#Requires -Version 7.0
<#
.SYNOPSIS
    Exports all available data from an Azure Migrate project to CSV and JSON.

.DESCRIPTION
    Pulls discovery, assessment, business case, and migration data from an Azure Migrate
    project through the Azure Resource Manager REST APIs and Azure Resource Graph. Every
    dataset is written twice: a flattened CSV (one row per record, ready for Excel or
    Power BI) and a JSON file that keeps the full nested structure.

    Each setting is resolved in this order:
        1. Parameter passed on the command line
        2. Config file (YAML, snake_case keys). Default: .\config\wagonmaster-manifest.yml
        3. Environment variable
        4. Interactive prompt (only when a person is at the keyboard)
    If a required value is still missing and prompting is not possible, the script stops
    with an error that names the parameter, config key, and environment variable to set.

    Supported sign-in methods:
        Interactive       Browser or device code sign-in. Reuses an existing Az session.
        ManagedIdentity   System-assigned, or user-assigned via -ManagedIdentityClientId.
        ServicePrincipal  Client secret or certificate thumbprint.
    Prompts only appear when a person is at the keyboard. Pipelines (Azure DevOps,
    GitHub Actions), Azure Automation, scheduled tasks, pwsh -NonInteractive, and
    -NonInteractive runs never prompt; a missing value stops the run with a clear error
    instead of hanging.

    What is collected (best effort; anything the project does not use is skipped):
        Project      Migrate project, solutions (tools registered to the project)
        Discovery    VMware, Hyper-V, physical/other-cloud and import sites, vCenters,
                     Hyper-V hosts and clusters, discovered machines, SQL Server instances,
                     databases and availability groups, IIS and Tomcat web servers and apps,
                     optional per-machine software inventory
        Assessments  Assessment projects, groups, Azure VM, AVS, SQL and web app
                     assessments, assessed machines, SQL instances and databases
        Business     Business cases and their evaluated machines and workloads
        Migration    Replication and migration items in linked Recovery Services vaults
        Graph        Every Azure Migrate record in the MigrateResources Resource Graph table

    Not collected: agentless dependency data. Microsoft does not expose a documented API
    for it; export it from the portal (Manage Dependencies > Export dependencies).

    The script is read-only. It never changes anything in Azure, and each run writes to a
    new timestamped folder, so it is safe to run as often as needed.

.PARAMETER ConfigPath
    Path to a YAML config file. If omitted, .\config\wagonmaster-manifest.yml next to the script
    is used when it exists. If a path is given but the file is missing, it is created from
    the bundled example and the script stops so the values can be filled in.

.PARAMETER AuthMethod
    Interactive, ManagedIdentity, or ServicePrincipal.
    Config: auth_method. Env: WAGONMASTER_AUTH_METHOD.

.PARAMETER TenantId
    Entra ID tenant. Required for ServicePrincipal, optional otherwise.
    Config: tenant_id. Env: AZURE_TENANT_ID.

.PARAMETER SubscriptionId
    Subscription that holds the Azure Migrate project. Interactive runs show a picker.
    Config: subscription_id. Env: AZURE_SUBSCRIPTION_ID.

.PARAMETER ResourceGroupName
    Resource group of the Azure Migrate project. Interactive runs show a picker.
    Config: resource_group_name. Env: WAGONMASTER_RESOURCE_GROUP.

.PARAMETER ProjectName
    Azure Migrate project name. Interactive runs show a picker.
    Config: project_name. Env: WAGONMASTER_PROJECT_NAME.

.PARAMETER OutputPath
    Folder for the export. A timestamped subfolder is created per run. Default: .\WagonmasterManifest
    Config: output_path. Env: WAGONMASTER_OUTPUT_PATH.

.PARAMETER ClientId
    Application (client) ID of the service principal.
    Config: client_id. Env: AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Service principal secret as a SecureString. Never put this in the config file.
    Env: AZURE_CLIENT_SECRET.

.PARAMETER CertificateThumbprint
    Thumbprint of a service principal certificate in the local certificate store.
    Used instead of a secret when set. Config: certificate_thumbprint.
    Env: AZURE_CLIENT_CERTIFICATE_THUMBPRINT.

.PARAMETER ManagedIdentityClientId
    Client ID of a user-assigned managed identity. Leave empty for system-assigned.
    Config: managed_identity_client_id. Env: WAGONMASTER_MI_CLIENT_ID.

.PARAMETER UseDeviceCode
    Interactive sign-in with a device code instead of a browser (useful over SSH or RDP).

.PARAMETER IncludeSoftwareInventory
    Also pull installed software for every discovered machine. One API call per machine,
    so this is slow on large estates.

.PARAMETER SkipResourceGraph
    Do not query the Azure Resource Graph MigrateResources table.

.PARAMETER SkipMigrationStatus
    Do not query Recovery Services vaults for replication and migration status.

.PARAMETER NonInteractive
    Never prompt. Missing values cause an error. Detected automatically in pipelines,
    Azure Automation and pwsh -NonInteractive sessions.

.PARAMETER DryRun
    Sign in, resolve the project and list the linked resources that would be exported,
    then stop without calling the data APIs or writing any files.

.EXAMPLE
    .\Export-WagonmasterManifest.ps1
    Fully guided: prompts for sign-in method, then pick subscription and project from a list.

.EXAMPLE
    .\Export-WagonmasterManifest.ps1 -SubscriptionId <sub-id> -ResourceGroupName rg-migrate -ProjectName SA-Migrate

.EXAMPLE
    .\Export-WagonmasterManifest.ps1 -AuthMethod ManagedIdentity -ConfigPath .\config\wagonmaster-manifest.yml

.EXAMPLE
    $env:AZURE_CLIENT_SECRET = '<from your secret store>'
    .\Export-WagonmasterManifest.ps1 -AuthMethod ServicePrincipal -TenantId <tenant-id> -ClientId <app-id> `
        -SubscriptionId <sub-id> -ResourceGroupName rg-migrate -ProjectName SA-Migrate -IncludeSoftwareInventory

.NOTES
    Author: Kristopher Turner
    Contact: kris@hybridsolutions.cloud
    Version: 1.2.0

    ScriptVersion    = "1.2.0"
    TaskReference    = "wagonmaster/manifest"
    DocumentationRef = "docs/manifest/usage.md"
    LastUpdated      = "2026-11-12"
    UpdatedBy        = "Kristopher Turner"
    ChangeLog        = @(
        "1.2.0 - 2026-11-12 - Renamed to Wagonmaster Manifest (Export-WagonmasterManifest.ps1); config file, environment variables and output folder renamed to match"
        "1.1.0 - 2026-11-12 - Review fixes: fail when project is unreadable; prompt for service principal values; process-scoped sign-in for MI and SPN; CSV formula guard, BOM and column collision fix; input validation"
        "1.0.0 - 2026-11-12 - Initial implementation"
    )

    Required permissions: Reader on the resource group that holds the Azure Migrate
    project (and on any linked Recovery Services vault if it lives elsewhere).

    Parameters are intentionally not marked Mandatory. Mandatory would force PowerShell's
    own prompt before the config file and environment variables are read, which breaks
    the parameter > config > environment > prompt order and unattended runs.

    Modules: Az.Accounts, Az.Resources, Az.ResourceGraph, and powershell-yaml (only when a
    config file is used). Missing modules are installed for the current user.
#>
[CmdletBinding()]
param(
    [string]$ConfigPath = '',

    [ValidateSet('Interactive', 'ManagedIdentity', 'ServicePrincipal')]
    [string]$AuthMethod,

    [string]$TenantId = '',
    [string]$SubscriptionId = '',
    [string]$ResourceGroupName = '',
    [string]$ProjectName = '',
    [string]$OutputPath = '',
    [string]$ClientId = '',
    [securestring]$ClientSecret,
    [string]$CertificateThumbprint = '',
    [string]$ManagedIdentityClientId = '',

    [switch]$UseDeviceCode,
    [switch]$IncludeSoftwareInventory,
    [switch]$SkipResourceGraph,
    [switch]$SkipMigrationStatus,
    [switch]$NonInteractive,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# === Settings ===

# API versions per resource provider. Adjust here if Microsoft retires a version.
$ApiVersions = @{
    MigrateProject   = '2018-09-01-preview'
    OffAzure         = '2023-06-06'
    Assessment       = '2023-03-15'
    AssessmentPreview = '2023-04-01-preview'
    RecoveryServices = '2024-04-01'
    DataReplication  = '2021-02-16-preview'
}

$DefaultConfigPath = Join-Path $PSScriptRoot 'config/wagonmaster-manifest.yml'
$DefaultOutputPath = Join-Path (Get-Location).Path 'WagonmasterManifest'
$ExcelCellLimit    = 32000

$script:logFile  = Join-Path ([System.IO.Path]::GetTempPath()) "hcs-Export-WagonmasterManifest-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
$script:config   = @{}
$script:canPrompt = $false
$script:datasets = [ordered]@{}
$script:manifest = [System.Collections.Generic.List[object]]::new()

# === Functions ===

function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $ts   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [$Level] $Message"
    $line | Out-File -FilePath $script:logFile -Append -Encoding utf8
    switch ($Level) {
        'PASS'    { Write-Host $line -ForegroundColor Green }
        'FAIL'    { Write-Host $line -ForegroundColor Red }
        'WARN'    { Write-Host $line -ForegroundColor Yellow }
        'HEADER'  { Write-Host $line -ForegroundColor Cyan }
        'VERBOSE' { Write-Verbose $line }
        'DEBUG'   { Write-Debug $line }
        default   { Write-Host $line }
    }
}

function Install-HCSModuleIfMissing {
    param([Parameter(Mandatory)][string]$Name)
    if (-not (Get-Module -Name $Name -ListAvailable)) {
        Write-Log "Installing PowerShell module '$Name' for the current user..." 'HEADER'
        try {
            Install-Module -Name $Name -Force -Scope CurrentUser -AllowClobber -Repository PSGallery
        } catch {
            Write-Log "Could not install module '$Name': $($_.Exception.Message)" 'FAIL'
            throw
        }
    }
    Import-Module $Name -ErrorAction Stop
}

function Test-HCSInteractiveHost {
    # A person can answer prompts only in an interactive user session that was not
    # started with pwsh -NonInteractive (pipelines, Automation, scheduled tasks).
    if (-not [Environment]::UserInteractive) { return $false }
    $startedNonInteractive = [Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-noni' }
    if ($startedNonInteractive) { return $false }
    if ($env:TF_BUILD -or $env:GITHUB_ACTIONS -or $env:AUTOMATION_ASSET_ACCOUNTID) { return $false }
    return $true
}

function Import-HCSConfig {
    param([string]$Path, [bool]$WasRequested)
    if (-not (Test-Path -Path $Path)) {
        if (-not $WasRequested) { return @{} }
        $examplePath = $Path -replace '\.ya?ml$', '.example.yml'
        $bundledExample = Join-Path $PSScriptRoot 'config/wagonmaster-manifest.example.yml'
        $source = if (Test-Path $examplePath) { $examplePath } elseif (Test-Path $bundledExample) { $bundledExample } else { $null }
        if ($source) {
            $parent = Split-Path -Path $Path -Parent
            if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -Path $source -Destination $Path
            Write-Log "Created '$Path' from the example. Fill in your values and run again." 'WARN'
        }
        throw "Config file not found: $Path"
    }
    Install-HCSModuleIfMissing -Name 'powershell-yaml'
    try {
        $parsed = Get-Content -Path $Path -Raw | ConvertFrom-Yaml
    } catch {
        Write-Log "Config file '$Path' is not valid YAML: $($_.Exception.Message)" 'FAIL'
        throw
    }
    if ($null -eq $parsed) { return @{} }
    if ($parsed -isnot [System.Collections.IDictionary]) { throw "Config file '$Path' must contain key: value pairs." }
    # Accept either flat keys or keys nested under wagonmaster_manifest:
    if ($parsed.Contains('wagonmaster_manifest') -and $parsed['wagonmaster_manifest'] -is [System.Collections.IDictionary]) {
        $parsed = $parsed['wagonmaster_manifest']
    }
    $clean = @{}
    foreach ($key in $parsed.Keys) {
        if ([string]$key -eq 'client_secret') {
            Write-Log "Ignoring 'client_secret' in the config file. Use -ClientSecret or AZURE_CLIENT_SECRET instead." 'WARN'
            continue
        }
        $clean[[string]$key] = $parsed[$key]
    }
    Write-Log "Loaded config file '$Path'." 'PASS'
    return $clean
}

function Resolve-HCSSetting {
    <#
        Returns the first non-empty value from: parameter, config key, environment variable,
        interactive prompt, default. Throws if required and nothing is found.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [string]$ParameterValue,
        [string]$ConfigKey,
        [string]$EnvVarName,
        [string]$PromptText,
        [string]$DefaultValue,
        [switch]$Optional
    )
    if (-not [string]::IsNullOrWhiteSpace($ParameterValue)) {
        Write-Log "$Name set from parameter." 'VERBOSE'
        return $ParameterValue.Trim()
    }
    if ($ConfigKey -and $script:config.ContainsKey($ConfigKey) -and -not [string]::IsNullOrWhiteSpace([string]$script:config[$ConfigKey])) {
        Write-Log "$Name set from config key '$ConfigKey'." 'VERBOSE'
        return ([string]$script:config[$ConfigKey]).Trim()
    }
    if ($EnvVarName) {
        $envValue = [Environment]::GetEnvironmentVariable($EnvVarName)
        if (-not [string]::IsNullOrWhiteSpace($envValue)) {
            Write-Log "$Name set from environment variable '$EnvVarName'." 'VERBOSE'
            return $envValue.Trim()
        }
    }
    if ($script:canPrompt -and $PromptText) {
        $suffix = if ($DefaultValue) { " [$DefaultValue]" } else { '' }
        $answer = Read-Host -Prompt "$PromptText$suffix"
        if (-not [string]::IsNullOrWhiteSpace($answer)) { return $answer.Trim() }
    }
    if ($DefaultValue) { return $DefaultValue }
    if ($Optional) { return '' }

    $hints = @("-$Name")
    if ($ConfigKey)  { $hints += "config key '$ConfigKey'" }
    if ($EnvVarName) { $hints += "environment variable '$EnvVarName'" }
    throw "Missing required value '$Name'. Provide it with $($hints -join ', or ')."
}

function Select-HCSFromList {
    param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][object[]]$Items,
        [Parameter(Mandatory)][scriptblock]$Label
    )
    if ($Items.Count -eq 1) { return $Items[0] }
    Write-Host ''
    Write-Host $Title -ForegroundColor Cyan
    for ($i = 0; $i -lt $Items.Count; $i++) {
        Write-Host ('  [{0}] {1}' -f ($i + 1), (& $Label $Items[$i]))
    }
    while ($true) {
        $answer = Read-Host -Prompt "Enter a number (1-$($Items.Count))"
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Items.Count) {
            return $Items[$number - 1]
        }
        Write-Host 'Invalid selection, try again.' -ForegroundColor Yellow
    }
}

function Connect-HCSAzure {
    param(
        [Parameter(Mandatory)][string]$Method,
        [string]$Tenant,
        [string]$AppId,
        [securestring]$Secret,
        [string]$Thumbprint,
        [string]$IdentityClientId,
        [string]$Subscription,
        [switch]$DeviceCode
    )
    try {
        switch ($Method) {
            'Interactive' {
                $context = Get-AzContext -ErrorAction SilentlyContinue
                $reuse = $context -and $context.Account -and ([string]::IsNullOrWhiteSpace($Tenant) -or $context.Tenant.Id -eq $Tenant)
                if ($reuse) {
                    Write-Log "Reusing existing Azure session for '$($context.Account.Id)'." 'PASS'
                    return
                }
                if (-not $script:canPrompt) {
                    throw 'No existing Azure session to reuse and this run cannot prompt. Sign in first (Connect-AzAccount, or the pipeline Azure PowerShell task), or use -AuthMethod ManagedIdentity or ServicePrincipal.'
                }
                $connectParams = @{ ErrorAction = 'Stop' }
                if ($Tenant)       { $connectParams['Tenant'] = $Tenant }
                if ($Subscription) { $connectParams['Subscription'] = $Subscription }
                if ($DeviceCode)   { $connectParams['UseDeviceAuthentication'] = $true }
                Write-Log 'Signing in interactively...' 'HEADER'
                Connect-AzAccount @connectParams | Out-Null
            }
            'ManagedIdentity' {
                # Scope Process: do not overwrite the saved Azure context of whoever runs this.
                $connectParams = @{ Identity = $true; Scope = 'Process'; ErrorAction = 'Stop' }
                if ($IdentityClientId) { $connectParams['AccountId'] = $IdentityClientId }
                if ($Tenant)           { $connectParams['Tenant'] = $Tenant }
                $label = if ($IdentityClientId) { "user-assigned identity '$IdentityClientId'" } else { 'system-assigned identity' }
                Write-Log "Signing in with managed $label..." 'HEADER'
                Connect-AzAccount @connectParams | Out-Null
            }
            'ServicePrincipal' {
                if ($Thumbprint) {
                    Write-Log "Signing in as service principal '$AppId' with certificate..." 'HEADER'
                    Connect-AzAccount -ServicePrincipal -ApplicationId $AppId -CertificateThumbprint $Thumbprint -Tenant $Tenant -Scope Process -ErrorAction Stop | Out-Null
                } else {
                    Write-Log "Signing in as service principal '$AppId' with client secret..." 'HEADER'
                    $credential = [pscredential]::new($AppId, $Secret)
                    Connect-AzAccount -ServicePrincipal -Credential $credential -Tenant $Tenant -Scope Process -ErrorAction Stop | Out-Null
                }
            }
        }
    } catch {
        Write-Log "Azure sign-in failed ($Method): $($_.Exception.Message)" 'FAIL'
        throw
    }
    $context = Get-AzContext
    Write-Log "Signed in as '$($context.Account.Id)' in tenant '$($context.Tenant.Id)'." 'PASS'
}

function Invoke-HCSArmRequest {
    # GET against ARM with retry on throttling and transient errors. Accepts a path or a full URI.
    param([Parameter(Mandatory)][string]$Path)
    $attempt = 0
    while ($true) {
        $attempt++
        $requestParams = if ($Path -match '^https://') { @{ Uri = $Path } } else { @{ Path = $Path } }
        $response = Invoke-AzRestMethod @requestParams -Method GET
        $status = [int]$response.StatusCode
        if ($status -ge 200 -and $status -lt 300) {
            if ([string]::IsNullOrWhiteSpace($response.Content)) { return $null }
            return ($response.Content | ConvertFrom-Json -Depth 100)
        }
        if (($status -in @(429, 500, 502, 503, 504)) -and ($attempt -lt 6)) {
            $delay = [math]::Min(60, [math]::Pow(2, $attempt) * 2)
            Write-Log "HTTP $status, retrying in $delay seconds (attempt $attempt)..." 'WARN'
            Start-Sleep -Seconds $delay
            continue
        }
        $detail = $response.Content
        try {
            $errorBody = $response.Content | ConvertFrom-Json -Depth 20
            if ($errorBody.PSObject.Properties['error']) { $detail = "$($errorBody.error.code): $($errorBody.error.message)" }
        } catch { Write-Log 'Error response body was not JSON.' 'DEBUG' }
        if ($detail -and $detail.Length -gt 400) { $detail = $detail.Substring(0, 400) + '...' }
        $exception = [System.Exception]::new("HTTP $status $detail")
        $exception.Data['StatusCode'] = $status
        throw $exception
    }
}

function Get-HCSArmCollection {
    # Returns every item of a list endpoint, following nextLink. A single-object response is returned as one item.
    param([Parameter(Mandatory)][string]$Path)
    $items = [System.Collections.Generic.List[object]]::new()
    $next = $Path
    while ($next) {
        $page = Invoke-HCSArmRequest -Path $next
        $next = $null
        if ($null -eq $page) { break }
        $valueProperty = $page.PSObject.Properties['value']
        if ($valueProperty) {
            foreach ($entry in @($valueProperty.Value)) {
                if ($null -ne $entry) { $items.Add($entry) }
            }
            $nextProperty = $page.PSObject.Properties['nextLink']
            if ($nextProperty -and -not [string]::IsNullOrWhiteSpace([string]$nextProperty.Value)) {
                $next = [string]$nextProperty.Value
            }
        } else {
            $items.Add($page)
        }
    }
    return , $items
}

function Add-HCSDataset {
    <#
        Calls an ARM endpoint, tags each record with context columns, and stores it under
        a dataset name. Failures are logged and recorded in the manifest, never fatal.
    #>
    param(
        [Parameter(Mandatory)][string]$DatasetName,
        [Parameter(Mandatory)][string]$Path,
        [System.Collections.Specialized.OrderedDictionary]$Context = [ordered]@{}
    )
    $records = [System.Collections.Generic.List[object]]::new()
    $status = 'OK'
    $message = ''
    try {
        $items = Get-HCSArmCollection -Path $Path
        foreach ($item in $items) {
            $records.Add((Join-HCSContext -Item $item -Context $Context))
        }
    } catch {
        $statusCode = if ($_.Exception.Data.Contains('StatusCode')) { [int]$_.Exception.Data['StatusCode'] } else { 0 }
        if ($statusCode -in @(400, 404)) {
            $status = 'NotAvailable'
            Write-Log "$DatasetName not available for this project ($($_.Exception.Message))." 'VERBOSE'
        } else {
            $status = 'Error'
            Write-Log "$DatasetName failed: $($_.Exception.Message)" 'WARN'
        }
        $message = $_.Exception.Message
    }
    if (-not $script:datasets.Contains($DatasetName)) {
        $script:datasets[$DatasetName] = [System.Collections.Generic.List[object]]::new()
    }
    foreach ($record in $records) { $script:datasets[$DatasetName].Add($record) }
    $script:manifest.Add([pscustomobject]@{
        Dataset = $DatasetName
        Source  = ($Path -replace '\?.*$', '')
        Records = $records.Count
        Status  = $status
        Message = $message
    })
    return , $records
}

function Add-HCSDatasetRecords {
    # Stores records that were already retrieved (for example from Resource Graph).
    param(
        [Parameter(Mandatory)][string]$DatasetName,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items,
        [string]$Source = '',
        [System.Collections.Specialized.OrderedDictionary]$Context = [ordered]@{}
    )
    if (-not $script:datasets.Contains($DatasetName)) {
        $script:datasets[$DatasetName] = [System.Collections.Generic.List[object]]::new()
    }
    foreach ($item in $Items) { $script:datasets[$DatasetName].Add((Join-HCSContext -Item $item -Context $Context)) }
    $script:manifest.Add([pscustomobject]@{ Dataset = $DatasetName; Source = $Source; Records = $Items.Count; Status = 'OK'; Message = '' })
}

function Join-HCSContext {
    # Puts context columns (project, site, group, assessment) in front of the API record.
    param($Item, [System.Collections.Specialized.OrderedDictionary]$Context)
    $combined = [ordered]@{}
    foreach ($key in $Context.Keys) { $combined["_$key"] = $Context[$key] }
    if ($Item -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $Item.PSObject.Properties) {
            if (-not $combined.Contains($property.Name)) { $combined[$property.Name] = $property.Value }
        }
    } elseif ($Item -is [System.Collections.IDictionary]) {
        foreach ($key in $Item.Keys) { if (-not $combined.Contains([string]$key)) { $combined[[string]$key] = $Item[$key] } }
    } else {
        $combined['value'] = $Item
    }
    return [pscustomobject]$combined
}

function Get-HCSPropertyValue {
    # Safe property read under StrictMode. Supports dotted paths like 'properties.sites'.
    param($InputObject, [Parameter(Mandatory)][string]$Name)
    $current = $InputObject
    foreach ($segment in $Name.Split('.')) {
        if ($null -eq $current) { return $null }
        if ($current -is [System.Collections.IDictionary]) {
            $current = if ($current.Contains($segment)) { $current[$segment] } else { $null }
            continue
        }
        $property = $current.PSObject.Properties[$segment]
        $current = if ($property) { $property.Value } else { $null }
    }
    return $current
}

function ConvertTo-HCSFlatRecord {
    # Flattens nested objects into dotted column names for CSV. Lists of simple values are
    # joined with '; ', lists of objects are kept as compact JSON in a single cell.
    param($InputObject, [string]$Prefix = '', [Parameter(Mandatory)][System.Collections.IDictionary]$Target, [int]$Depth = 0)

    if ($null -eq $InputObject) {
        if ($Prefix) { $Target[$Prefix] = $null }
        return
    }
    $isObject = ($InputObject -is [System.Management.Automation.PSCustomObject]) -or ($InputObject -is [System.Collections.IDictionary])
    if ($isObject -and $Depth -ge 8) {
        $Target[$Prefix] = ($InputObject | ConvertTo-Json -Depth 50 -Compress)
        return
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $childName = if ($Prefix) { "$Prefix.$key" } else { [string]$key }
            ConvertTo-HCSFlatRecord -InputObject $InputObject[$key] -Prefix $childName -Target $Target -Depth ($Depth + 1)
        }
        return
    }
    if ($InputObject -is [System.Management.Automation.PSCustomObject]) {
        foreach ($property in $InputObject.PSObject.Properties) {
            $childName = if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name }
            ConvertTo-HCSFlatRecord -InputObject $property.Value -Prefix $childName -Target $Target -Depth ($Depth + 1)
        }
        return
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and $InputObject -isnot [string]) {
        $elements = @($InputObject)
        $allSimple = $true
        foreach ($element in $elements) {
            if ($null -ne $element -and -not ($element -is [string] -or $element -is [ValueType])) { $allSimple = $false; break }
        }
        $Target[$Prefix] = if ($elements.Count -eq 0) { '' }
                           elseif ($allSimple) { ($elements | ForEach-Object { [string]$_ }) -join '; ' }
                           else { ConvertTo-Json -InputObject $elements -Depth 50 -Compress }
        return
    }
    if ($InputObject -is [datetime]) {
        $Target[$Prefix] = $InputObject.ToUniversalTime().ToString('o')
        return
    }
    $Target[$Prefix] = $InputObject
}

function Export-HCSDataset {
    param(
        [Parameter(Mandatory)][string]$DatasetName,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Records,
        [Parameter(Mandatory)][string]$CsvFolder,
        [Parameter(Mandatory)][string]$JsonFolder
    )
    $safeName = $DatasetName -replace '[^\w\-]', '_'
    $jsonPath = Join-Path $JsonFolder "$safeName.json"
    $csvPath  = Join-Path $CsvFolder "$safeName.csv"

    ConvertTo-Json -InputObject @($Records) -Depth 100 | Set-Content -Path $jsonPath -Encoding utf8

    $rows = foreach ($record in $Records) {
        $flat = [ordered]@{}
        ConvertTo-HCSFlatRecord -InputObject $record -Target $flat
        # Drop the 'properties.' prefix ARM puts on everything, unless it would collide.
        $renamed = [ordered]@{}
        foreach ($key in $flat.Keys) {
            $shortKey = $key
            if ($key -like 'properties.*') {
                $candidate = $key.Substring(11)
                # Keep the long name when a top-level column already uses the short one.
                if (-not $flat.Contains($candidate)) { $shortKey = $candidate }
            }
            $value = $flat[$key]
            if ($value -is [string]) {
                if ($value.Length -gt $ExcelCellLimit) {
                    $value = $value.Substring(0, $ExcelCellLimit) + ' ...[truncated, see JSON]'
                }
                # Discovered data comes from customer servers. Stop Excel from running a
                # cell as a formula (CSV injection). The JSON copy keeps the raw value.
                if ($value -match '^[=+\-@\t\r]') { $value = "'" + $value }
            }
            $renamed[$shortKey] = $value
        }
        $renamed
    }

    $columns = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($row in @($rows)) {
        foreach ($key in $row.Keys) { if ($seen.Add([string]$key)) { $columns.Add([string]$key) } }
    }

    if ($columns.Count -eq 0) {
        Set-Content -Path $csvPath -Value '' -Encoding utf8
    } else {
        @($rows) | ForEach-Object {
            $row = $_
            $line = [ordered]@{}
            foreach ($column in $columns) { $line[$column] = if ($row.Contains($column)) { $row[$column] } else { $null } }
            [pscustomobject]$line
        } | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8BOM
    }
}

function Get-HCSLinkedResourceIds {
    <#
        Finds the discovery sites, assessment projects and vaults that belong to the Migrate
        project by reading the resource IDs registered in its solutions. Falls back to every
        Azure Migrate resource in the resource group when none are found.
    #>
    param([Parameter(Mandatory)][string]$ProjectId, [object[]]$Solutions, [Parameter(Mandatory)][string]$ResourceGroup)

    $pattern = '(?i)/subscriptions/[0-9a-f\-]{36}/resourceGroups/[^/"\\]+/providers/(Microsoft\.OffAzure/[A-Za-z]+Sites|Microsoft\.Migrate/assessmentProjects|Microsoft\.RecoveryServices/vaults|Microsoft\.DataReplication/replicationVaults)/[^/"\\?]+'
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    if ($Solutions -and $Solutions.Count -gt 0) {
        $solutionJson = ConvertTo-Json -InputObject @($Solutions) -Depth 50 -Compress
        foreach ($match in [regex]::Matches($solutionJson, $pattern)) { [void]$ids.Add($match.Value) }
    }

    if ($ids.Count -gt 0) {
        Write-Log "Found $($ids.Count) resources linked to the project through its solutions." 'PASS'
    } else {
        Write-Log "No linked resource IDs in the project solutions. Using all Azure Migrate resources in '$ResourceGroup'." 'WARN'
        $typePattern = '^(Microsoft\.OffAzure/[A-Za-z]+Sites|Microsoft\.Migrate/assessmentProjects|Microsoft\.RecoveryServices/vaults|Microsoft\.DataReplication/replicationVaults)$'
        try {
            Get-AzResource -ResourceGroupName $ResourceGroup -ErrorAction Stop |
                Where-Object { $_.ResourceType -match $typePattern } |
                ForEach-Object { [void]$ids.Add($_.ResourceId) }
        } catch {
            Write-Log "Could not list resources in '$ResourceGroup': $($_.Exception.Message)" 'FAIL'
            throw
        }
        Write-Log "Found $($ids.Count) Azure Migrate resources in the resource group." 'PASS'
    }

    # Master sites list the VMware, Hyper-V and server sites they aggregate.
    foreach ($masterSiteId in @($ids | Where-Object { $_ -match '/MasterSites/' })) {
        try {
            $masterSite = Invoke-HCSArmRequest -Path "$($masterSiteId)?api-version=$($ApiVersions.OffAzure)"
            foreach ($siteId in @(Get-HCSPropertyValue -InputObject $masterSite -Name 'properties.sites')) {
                if ($siteId) { [void]$ids.Add([string]$siteId) }
            }
        } catch {
            Write-Log "Could not read master site '$masterSiteId': $($_.Exception.Message)" 'WARN'
        }
    }
    return , @($ids)
}

function Get-HCSResourceName {
    param([string]$ResourceId)
    return ($ResourceId -split '/')[-1]
}

function Export-HCSDiscoveryData {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ResourceIds, [string]$Project)
    $api = "api-version=$($ApiVersions.OffAzure)"
    $machineCollections = [System.Collections.Generic.List[object]]::new()

    foreach ($siteId in $ResourceIds | Where-Object { $_ -match '/providers/Microsoft\.OffAzure/' }) {
        $siteName = Get-HCSResourceName $siteId
        $context = [ordered]@{ Project = $Project; Site = $siteName }

        switch -Regex ($siteId) {
            '/VMwareSites/' {
                Write-Log "Discovery: VMware site '$siteName'" 'HEADER'
                [void](Add-HCSDataset -DatasetName 'Discovery_Sites' -Path "$($siteId)?$api" -Context $context)
                [void](Add-HCSDataset -DatasetName 'Discovery_VMware_vCenters' -Path "$siteId/vCenters?$api" -Context $context)
                $machines = Add-HCSDataset -DatasetName 'Discovery_VMware_Machines' -Path "$siteId/machines?$api" -Context $context
                $machineCollections.Add(@{ Records = $machines; Context = $context })
            }
            '/HyperVSites/' {
                Write-Log "Discovery: Hyper-V site '$siteName'" 'HEADER'
                [void](Add-HCSDataset -DatasetName 'Discovery_Sites' -Path "$($siteId)?$api" -Context $context)
                [void](Add-HCSDataset -DatasetName 'Discovery_HyperV_Hosts' -Path "$siteId/hosts?$api" -Context $context)
                [void](Add-HCSDataset -DatasetName 'Discovery_HyperV_Clusters' -Path "$siteId/clusters?$api" -Context $context)
                $machines = Add-HCSDataset -DatasetName 'Discovery_HyperV_Machines' -Path "$siteId/machines?$api" -Context $context
                $machineCollections.Add(@{ Records = $machines; Context = $context })
            }
            '/ServerSites/' {
                Write-Log "Discovery: physical/other-cloud site '$siteName'" 'HEADER'
                [void](Add-HCSDataset -DatasetName 'Discovery_Sites' -Path "$($siteId)?$api" -Context $context)
                $machines = Add-HCSDataset -DatasetName 'Discovery_Physical_Machines' -Path "$siteId/machines?$api" -Context $context
                $machineCollections.Add(@{ Records = $machines; Context = $context })
            }
            '/ImportSites/' {
                Write-Log "Discovery: import site '$siteName'" 'HEADER'
                [void](Add-HCSDataset -DatasetName 'Discovery_Sites' -Path "$($siteId)?$api" -Context $context)
                [void](Add-HCSDataset -DatasetName 'Discovery_Imported_Machines' -Path "$siteId/machines?$api" -Context $context)
            }
            '/MasterSites/' {
                Write-Log "Discovery: master site '$siteName' (SQL and web apps)" 'HEADER'
                [void](Add-HCSDataset -DatasetName 'Discovery_Sites' -Path "$($siteId)?$api" -Context $context)
                $sqlSites = Add-HCSDataset -DatasetName 'Discovery_SqlSites' -Path "$siteId/sqlSites?$api" -Context $context
                foreach ($sqlSite in $sqlSites) {
                    $sqlSiteId = [string](Get-HCSPropertyValue -InputObject $sqlSite -Name 'id')
                    if (-not $sqlSiteId) { continue }
                    $sqlContext = [ordered]@{ Project = $Project; Site = $siteName; SqlSite = (Get-HCSResourceName $sqlSiteId) }
                    [void](Add-HCSDataset -DatasetName 'Discovery_Sql_Servers' -Path "$sqlSiteId/sqlServers?$api" -Context $sqlContext)
                    [void](Add-HCSDataset -DatasetName 'Discovery_Sql_Databases' -Path "$sqlSiteId/sqlDatabases?$api" -Context $sqlContext)
                    [void](Add-HCSDataset -DatasetName 'Discovery_Sql_AvailabilityGroups' -Path "$sqlSiteId/sqlAvailabilityGroups?$api" -Context $sqlContext)
                }
                $webAppSites = Add-HCSDataset -DatasetName 'Discovery_WebAppSites' -Path "$siteId/webAppSites?$api" -Context $context
                foreach ($webAppSite in $webAppSites) {
                    $webAppSiteId = [string](Get-HCSPropertyValue -InputObject $webAppSite -Name 'id')
                    if (-not $webAppSiteId) { continue }
                    $webContext = [ordered]@{ Project = $Project; Site = $siteName; WebAppSite = (Get-HCSResourceName $webAppSiteId) }
                    [void](Add-HCSDataset -DatasetName 'Discovery_IIS_WebServers' -Path "$webAppSiteId/iisWebServers?$api" -Context $webContext)
                    [void](Add-HCSDataset -DatasetName 'Discovery_IIS_WebApps' -Path "$webAppSiteId/iisWebApplications?$api" -Context $webContext)
                    [void](Add-HCSDataset -DatasetName 'Discovery_Tomcat_WebServers' -Path "$webAppSiteId/tomcatWebServers?$api" -Context $webContext)
                    [void](Add-HCSDataset -DatasetName 'Discovery_Tomcat_WebApps' -Path "$webAppSiteId/tomcatWebApplications?$api" -Context $webContext)
                }
            }
            default { Write-Log "Skipping unrecognized site type: $siteId" 'VERBOSE' }
        }
    }

    if ($IncludeSoftwareInventory) {
        $total = ($machineCollections | ForEach-Object { $_.Records.Count } | Measure-Object -Sum).Sum
        Write-Log "Software inventory: querying $total machines (one call each)..." 'HEADER'
        $done = 0
        foreach ($collection in $machineCollections) {
            foreach ($machine in $collection.Records) {
                $done++
                $machineId = [string](Get-HCSPropertyValue -InputObject $machine -Name 'id')
                if (-not $machineId) { continue }
                $machineName = Get-HCSPropertyValue -InputObject $machine -Name 'properties.displayName'
                if (-not $machineName) { $machineName = Get-HCSResourceName $machineId }
                $context = [ordered]@{ Project = $Project; Site = $collection.Context['Site']; Machine = $machineName; MachineId = $machineId }
                [void](Add-HCSDataset -DatasetName 'Discovery_SoftwareInventory' -Path "$machineId/softwareInventories?$api" -Context $context)
                if ($done % 50 -eq 0) { Write-Log "Software inventory: $done of $total machines done." 'INFO' }
            }
        }
    }
}

function Export-HCSAssessmentData {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ResourceIds, [string]$Project)
    $api = "api-version=$($ApiVersions.Assessment)"
    $previewApi = "api-version=$($ApiVersions.AssessmentPreview)"

    foreach ($assessmentProjectId in $ResourceIds | Where-Object { $_ -match '/providers/Microsoft\.Migrate/assessmentProjects/' }) {
        $assessmentProjectName = Get-HCSResourceName $assessmentProjectId
        Write-Log "Assessments: assessment project '$assessmentProjectName'" 'HEADER'
        $context = [ordered]@{ Project = $Project; AssessmentProject = $assessmentProjectName }

        [void](Add-HCSDataset -DatasetName 'Assessment_Projects' -Path "$($assessmentProjectId)?$api" -Context $context)
        [void](Add-HCSDataset -DatasetName 'Assessment_ProjectMachines' -Path "$assessmentProjectId/machines?$api" -Context $context)
        $groups = Add-HCSDataset -DatasetName 'Assessment_Groups' -Path "$assessmentProjectId/groups?$api" -Context $context

        foreach ($group in $groups) {
            $groupId = [string](Get-HCSPropertyValue -InputObject $group -Name 'id')
            if (-not $groupId) { continue }
            $groupName = Get-HCSResourceName $groupId
            $groupContext = [ordered]@{ Project = $Project; AssessmentProject = $assessmentProjectName; Group = $groupName }

            # Azure VM assessments
            foreach ($assessment in (Add-HCSDataset -DatasetName 'Assessment_AzureVM' -Path "$groupId/assessments?$api" -Context $groupContext)) {
                $assessmentId = [string](Get-HCSPropertyValue -InputObject $assessment -Name 'id')
                if (-not $assessmentId) { continue }
                $ctx = [ordered]@{ Project = $Project; AssessmentProject = $assessmentProjectName; Group = $groupName; Assessment = (Get-HCSResourceName $assessmentId) }
                [void](Add-HCSDataset -DatasetName 'Assessment_AzureVM_AssessedMachines' -Path "$assessmentId/assessedMachines?$api" -Context $ctx)
            }

            # Azure VMware Solution assessments
            foreach ($assessment in (Add-HCSDataset -DatasetName 'Assessment_AVS' -Path "$groupId/avsAssessments?$api" -Context $groupContext)) {
                $assessmentId = [string](Get-HCSPropertyValue -InputObject $assessment -Name 'id')
                if (-not $assessmentId) { continue }
                $ctx = [ordered]@{ Project = $Project; AssessmentProject = $assessmentProjectName; Group = $groupName; Assessment = (Get-HCSResourceName $assessmentId) }
                [void](Add-HCSDataset -DatasetName 'Assessment_AVS_AssessedMachines' -Path "$assessmentId/avsAssessedMachines?$api" -Context $ctx)
            }

            # SQL assessments
            foreach ($assessment in (Add-HCSDataset -DatasetName 'Assessment_SQL' -Path "$groupId/sqlAssessments?$api" -Context $groupContext)) {
                $assessmentId = [string](Get-HCSPropertyValue -InputObject $assessment -Name 'id')
                if (-not $assessmentId) { continue }
                $ctx = [ordered]@{ Project = $Project; AssessmentProject = $assessmentProjectName; Group = $groupName; Assessment = (Get-HCSResourceName $assessmentId) }
                [void](Add-HCSDataset -DatasetName 'Assessment_SQL_AssessedMachines' -Path "$assessmentId/assessedSqlMachines?$api" -Context $ctx)
                [void](Add-HCSDataset -DatasetName 'Assessment_SQL_AssessedInstances' -Path "$assessmentId/assessedSqlInstances?$api" -Context $ctx)
                [void](Add-HCSDataset -DatasetName 'Assessment_SQL_AssessedDatabases' -Path "$assessmentId/assessedSqlDatabases?$api" -Context $ctx)
                [void](Add-HCSDataset -DatasetName 'Assessment_SQL_RecommendedEntities' -Path "$assessmentId/recommendedAssessedEntities?$api" -Context $ctx)
                [void](Add-HCSDataset -DatasetName 'Assessment_SQL_Summaries' -Path "$assessmentId/summaries?$api" -Context $ctx)
            }

            # Web app assessments (preview API)
            foreach ($assessment in (Add-HCSDataset -DatasetName 'Assessment_WebApp' -Path "$groupId/webAppAssessments?$previewApi" -Context $groupContext)) {
                $assessmentId = [string](Get-HCSPropertyValue -InputObject $assessment -Name 'id')
                if (-not $assessmentId) { continue }
                $ctx = [ordered]@{ Project = $Project; AssessmentProject = $assessmentProjectName; Group = $groupName; Assessment = (Get-HCSResourceName $assessmentId) }
                [void](Add-HCSDataset -DatasetName 'Assessment_WebApp_AssessedWebApps' -Path "$assessmentId/assessedWebApps?$previewApi" -Context $ctx)
                [void](Add-HCSDataset -DatasetName 'Assessment_WebApp_Summaries' -Path "$assessmentId/summaries?$previewApi" -Context $ctx)
            }
        }

        # Business cases (preview API)
        foreach ($businessCase in (Add-HCSDataset -DatasetName 'BusinessCase' -Path "$assessmentProjectId/businessCases?$previewApi" -Context $context)) {
            $businessCaseId = [string](Get-HCSPropertyValue -InputObject $businessCase -Name 'id')
            if (-not $businessCaseId) { continue }
            $ctx = [ordered]@{ Project = $Project; AssessmentProject = $assessmentProjectName; BusinessCase = (Get-HCSResourceName $businessCaseId) }
            [void](Add-HCSDataset -DatasetName 'BusinessCase_EvaluatedMachines' -Path "$businessCaseId/evaluatedMachines?$previewApi" -Context $ctx)
            [void](Add-HCSDataset -DatasetName 'BusinessCase_EvaluatedAvsMachines' -Path "$businessCaseId/evaluatedAvsMachines?$previewApi" -Context $ctx)
            [void](Add-HCSDataset -DatasetName 'BusinessCase_EvaluatedSqlEntities' -Path "$businessCaseId/evaluatedSqlEntities?$previewApi" -Context $ctx)
            [void](Add-HCSDataset -DatasetName 'BusinessCase_EvaluatedWebApps' -Path "$businessCaseId/evaluatedWebApps?$previewApi" -Context $ctx)
        }
    }
}

function Export-HCSMigrationData {
    param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ResourceIds, [string]$Project)
    foreach ($vaultId in $ResourceIds | Where-Object { $_ -match '/providers/Microsoft\.RecoveryServices/vaults/' }) {
        $vaultName = Get-HCSResourceName $vaultId
        Write-Log "Migration: Recovery Services vault '$vaultName'" 'HEADER'
        $api = "api-version=$($ApiVersions.RecoveryServices)"
        $context = [ordered]@{ Project = $Project; Vault = $vaultName }
        [void](Add-HCSDataset -DatasetName 'Migration_ReplicationMigrationItems' -Path "$vaultId/replicationMigrationItems?$api" -Context $context)
        [void](Add-HCSDataset -DatasetName 'Migration_ReplicationProtectedItems' -Path "$vaultId/replicationProtectedItems?$api" -Context $context)
        [void](Add-HCSDataset -DatasetName 'Migration_ReplicationJobs' -Path "$vaultId/replicationJobs?$api" -Context $context)
    }
    foreach ($vaultId in $ResourceIds | Where-Object { $_ -match '/providers/Microsoft\.DataReplication/replicationVaults/' }) {
        $vaultName = Get-HCSResourceName $vaultId
        Write-Log "Migration: replication vault '$vaultName'" 'HEADER'
        $api = "api-version=$($ApiVersions.DataReplication)"
        $context = [ordered]@{ Project = $Project; Vault = $vaultName }
        [void](Add-HCSDataset -DatasetName 'Migration_DataReplication_ProtectedItems' -Path "$vaultId/protectedItems?$api" -Context $context)
        [void](Add-HCSDataset -DatasetName 'Migration_DataReplication_Jobs' -Path "$vaultId/jobs?$api" -Context $context)
    }
}

function Export-HCSResourceGraphData {
    param([Parameter(Mandatory)][string]$Subscription, [Parameter(Mandatory)][string]$ResourceGroup, [string]$Project)
    Write-Log 'Resource Graph: querying MigrateResources table...' 'HEADER'
    $query = "migrateresources | where subscriptionId =~ '$Subscription' and resourceGroup =~ '$ResourceGroup'"
    $all = [System.Collections.Generic.List[object]]::new()
    try {
        $skipToken = $null
        do {
            $graphParams = @{ Query = $query; Subscription = $Subscription; First = 1000; ErrorAction = 'Stop' }
            if ($skipToken) { $graphParams['SkipToken'] = $skipToken }
            $result = Search-AzGraph @graphParams
            $page = if ($result.PSObject.Properties['Data']) { $result.Data } else { $result }
            foreach ($row in @($page)) { if ($null -ne $row) { $all.Add($row) } }
            $skipToken = if ($result.PSObject.Properties['SkipToken']) { $result.SkipToken } else { $null }
        } while ($skipToken)
    } catch {
        Write-Log "Resource Graph query failed: $($_.Exception.Message)" 'WARN'
        $script:manifest.Add([pscustomobject]@{ Dataset = 'ResourceGraph'; Source = 'migrateresources'; Records = 0; Status = 'Error'; Message = $_.Exception.Message })
        return
    }
    $context = [ordered]@{ Project = $Project }
    $byType = $all | Group-Object -Property { [string](Get-HCSPropertyValue -InputObject $_ -Name 'type') }
    foreach ($typeGroup in $byType) {
        $typeTail = (($typeGroup.Name -replace '^microsoft\.offazure/', '') -replace '^microsoft\.migrate/', '') -replace '/', '_'
        if (-not $typeTail) { $typeTail = 'unknown' }
        Add-HCSDatasetRecords -DatasetName "ResourceGraph_$typeTail" -Items @($typeGroup.Group) -Source "migrateresources type '$($typeGroup.Name)'" -Context $context
    }
    Write-Log "Resource Graph: $($all.Count) records across $(@($byType).Count) types." 'PASS'
}

# === Main ===

Write-Log 'Azure Migrate project export' 'HEADER'

# Modules
foreach ($moduleName in @('Az.Accounts', 'Az.Resources')) { Install-HCSModuleIfMissing -Name $moduleName }
if (-not $SkipResourceGraph) { Install-HCSModuleIfMissing -Name 'Az.ResourceGraph' }

# Config file (optional)
$configRequested = -not [string]::IsNullOrWhiteSpace($ConfigPath)
$resolvedConfigPath = if ($configRequested) { $ConfigPath } else { $DefaultConfigPath }
$script:config = Import-HCSConfig -Path $resolvedConfigPath -WasRequested $configRequested

# Sign-in method decides whether prompting is allowed
$script:canPrompt = (-not $NonInteractive) -and (Test-HCSInteractiveHost)
$authMethodValue = Resolve-HCSSetting -Name 'AuthMethod' -ParameterValue $AuthMethod -ConfigKey 'auth_method' -EnvVarName 'WAGONMASTER_AUTH_METHOD' -Optional
if (-not $authMethodValue) {
    if (-not $script:canPrompt) {
        throw "Missing required value 'AuthMethod'. Use -AuthMethod, config key 'auth_method', or environment variable 'WAGONMASTER_AUTH_METHOD' (Interactive, ManagedIdentity, ServicePrincipal)."
    }
    $authMethodValue = Select-HCSFromList -Title 'How do you want to sign in to Azure?' -Items @('Interactive', 'ManagedIdentity', 'ServicePrincipal') -Label { param($item) $item }
}
$validMethods = @('Interactive', 'ManagedIdentity', 'ServicePrincipal')
$authMethodValue = $validMethods | Where-Object { $_ -eq $authMethodValue } | Select-Object -First 1
if (-not $authMethodValue) { throw "AuthMethod must be one of: $($validMethods -join ', ')." }
if (-not $script:canPrompt) {
    Write-Log 'Non-interactive run: prompts are disabled, all values must come from parameters, config or environment.' 'INFO'
}

# Sign-in values
$isServicePrincipal = $authMethodValue -eq 'ServicePrincipal'
$tenantPrompt = if ($isServicePrincipal) { 'Tenant ID of the service principal' } else { '' }
$tenantIdValue = Resolve-HCSSetting -Name 'TenantId' -ParameterValue $TenantId -ConfigKey 'tenant_id' -EnvVarName 'AZURE_TENANT_ID' -PromptText $tenantPrompt -Optional:(-not $isServicePrincipal)
$clientIdValue = ''
$clientSecretValue = $null
$thumbprintValue = ''
$miClientIdValue = ''
switch ($authMethodValue) {
    'ServicePrincipal' {
        $clientIdValue   = Resolve-HCSSetting -Name 'ClientId' -ParameterValue $ClientId -ConfigKey 'client_id' -EnvVarName 'AZURE_CLIENT_ID' -PromptText 'Application (client) ID of the service principal'
        $thumbprintValue = Resolve-HCSSetting -Name 'CertificateThumbprint' -ParameterValue $CertificateThumbprint -ConfigKey 'certificate_thumbprint' -EnvVarName 'AZURE_CLIENT_CERTIFICATE_THUMBPRINT' -Optional
        if (-not $thumbprintValue) {
            if ($ClientSecret) {
                $clientSecretValue = $ClientSecret
            } elseif (-not [string]::IsNullOrWhiteSpace($env:AZURE_CLIENT_SECRET)) {
                $clientSecretValue = ConvertTo-SecureString -String $env:AZURE_CLIENT_SECRET -AsPlainText -Force
            } elseif ($script:canPrompt) {
                $clientSecretValue = Read-Host -Prompt "Client secret for service principal '$clientIdValue'" -AsSecureString
            } else {
                throw "Service principal sign-in needs -ClientSecret, the AZURE_CLIENT_SECRET environment variable, or a certificate thumbprint (-CertificateThumbprint / AZURE_CLIENT_CERTIFICATE_THUMBPRINT)."
            }
        }
    }
    'ManagedIdentity' {
        $miClientIdValue = Resolve-HCSSetting -Name 'ManagedIdentityClientId' -ParameterValue $ManagedIdentityClientId -ConfigKey 'managed_identity_client_id' -EnvVarName 'WAGONMASTER_MI_CLIENT_ID' -Optional
    }
}

# Subscription (if already known, it is passed to sign-in so Az does not show its own picker)
$subscriptionIdValue = Resolve-HCSSetting -Name 'SubscriptionId' -ParameterValue $SubscriptionId -ConfigKey 'subscription_id' -EnvVarName 'AZURE_SUBSCRIPTION_ID' -Optional
if ($subscriptionIdValue -and $subscriptionIdValue -notmatch '^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$') {
    throw "SubscriptionId '$subscriptionIdValue' is not a valid subscription GUID."
}

Connect-HCSAzure -Method $authMethodValue -Tenant $tenantIdValue -AppId $clientIdValue -Secret $clientSecretValue `
    -Thumbprint $thumbprintValue -IdentityClientId $miClientIdValue -Subscription $subscriptionIdValue -DeviceCode:$UseDeviceCode

if (-not $subscriptionIdValue) {
    $subscriptionParams = @{ ErrorAction = 'Stop' }
    if ($tenantIdValue) { $subscriptionParams['TenantId'] = $tenantIdValue }
    $subscriptions = @(Get-AzSubscription @subscriptionParams | Where-Object { $_.State -eq 'Enabled' } | Sort-Object Name)
    if ($subscriptions.Count -eq 0) { throw 'The signed-in account cannot see any enabled subscriptions.' }
    if ($subscriptions.Count -eq 1) {
        $subscriptionIdValue = $subscriptions[0].Id
    } elseif ($script:canPrompt) {
        $chosen = Select-HCSFromList -Title 'Select the subscription that holds the Azure Migrate project:' -Items $subscriptions -Label { param($s) "$($s.Name)  ($($s.Id))" }
        $subscriptionIdValue = $chosen.Id
    } else {
        throw "Missing required value 'SubscriptionId'. Use -SubscriptionId, config key 'subscription_id', or environment variable 'AZURE_SUBSCRIPTION_ID'."
    }
}
try {
    Set-AzContext -Subscription $subscriptionIdValue -ErrorAction Stop | Out-Null
} catch {
    Write-Log "Cannot switch to subscription '$subscriptionIdValue': $($_.Exception.Message)" 'FAIL'
    throw
}
Write-Log "Subscription: $subscriptionIdValue" 'PASS'

# Resource group and project
$resourceGroupValue = Resolve-HCSSetting -Name 'ResourceGroupName' -ParameterValue $ResourceGroupName -ConfigKey 'resource_group_name' -EnvVarName 'WAGONMASTER_RESOURCE_GROUP' -Optional
$projectNameValue   = Resolve-HCSSetting -Name 'ProjectName' -ParameterValue $ProjectName -ConfigKey 'project_name' -EnvVarName 'WAGONMASTER_PROJECT_NAME' -Optional
if (-not ($resourceGroupValue -and $projectNameValue)) {
    $projectQuery = @{ ResourceType = 'Microsoft.Migrate/migrateProjects'; ErrorAction = 'Stop' }
    if ($resourceGroupValue) { $projectQuery['ResourceGroupName'] = $resourceGroupValue }
    $projects = @(Get-AzResource @projectQuery | Sort-Object ResourceGroupName, Name)
    if ($projectNameValue) { $projects = @($projects | Where-Object { $_.Name -eq $projectNameValue }) }
    if ($projects.Count -eq 0) {
        throw "No Azure Migrate project found in subscription '$subscriptionIdValue'$(if ($resourceGroupValue) { " resource group '$resourceGroupValue'" })$(if ($projectNameValue) { " named '$projectNameValue'" })."
    }
    if ($projects.Count -gt 1 -and -not $script:canPrompt) {
        throw "Found $($projects.Count) Azure Migrate projects. Set -ProjectName and -ResourceGroupName (or config/environment values) to choose one."
    }
    $chosenProject = Select-HCSFromList -Title 'Select the Azure Migrate project:' -Items $projects -Label { param($p) "$($p.Name)  (resource group: $($p.ResourceGroupName))" }
    $resourceGroupValue = $chosenProject.ResourceGroupName
    $projectNameValue = $chosenProject.Name
}
# These values go into REST paths and a Resource Graph query, so reject anything unexpected.
if ($resourceGroupValue -notmatch '^[\w\-\.\(\)]{1,90}$') { throw "ResourceGroupName '$resourceGroupValue' contains characters that are not valid in a resource group name." }
if ($projectNameValue -notmatch '^[\w\-\.]{1,260}$') { throw "ProjectName '$projectNameValue' contains characters that are not valid in a project name." }
Write-Log "Project: $projectNameValue (resource group: $resourceGroupValue)" 'PASS'

$outputRoot = Resolve-HCSSetting -Name 'OutputPath' -ParameterValue $OutputPath -ConfigKey 'output_path' -EnvVarName 'WAGONMASTER_OUTPUT_PATH' -PromptText 'Output folder' -DefaultValue $DefaultOutputPath

# Read the project and find what is linked to it
$projectId = "/subscriptions/$subscriptionIdValue/resourceGroups/$resourceGroupValue/providers/Microsoft.Migrate/migrateProjects/$projectNameValue"
$projectApi = "api-version=$($ApiVersions.MigrateProject)"
$projectRecords = Add-HCSDataset -DatasetName 'Project' -Path "$($projectId)?$projectApi" -Context ([ordered]@{ Project = $projectNameValue })
if ($projectRecords.Count -eq 0) {
    $reason = ($script:manifest | Where-Object Dataset -eq 'Project' | Select-Object -Last 1).Message
    throw "Cannot read Azure Migrate project '$projectNameValue' in resource group '$resourceGroupValue'. Check the names and that this identity has Reader on the resource group. Detail: $reason"
}
$solutions = Add-HCSDataset -DatasetName 'Project_Solutions' -Path "$projectId/solutions?$projectApi" -Context ([ordered]@{ Project = $projectNameValue })
$linkedIds = Get-HCSLinkedResourceIds -ProjectId $projectId -Solutions @($solutions) -ResourceGroup $resourceGroupValue

if ($DryRun) {
    Write-Host ''
    Write-Host 'DRY RUN: these resources would be exported:' -ForegroundColor Yellow
    foreach ($id in ($linkedIds | Sort-Object)) { Write-Host "  $id" -ForegroundColor Yellow }
    if (-not $SkipResourceGraph) { Write-Host "  Resource Graph: migrateresources in '$resourceGroupValue'" -ForegroundColor Yellow }
    Write-Host "DRY RUN: output would be written under '$outputRoot'. No data APIs called, no files written." -ForegroundColor Yellow
    Write-Log "Log file: $script:logFile" 'INFO'
    return
}

# Collect
Export-HCSDiscoveryData -ResourceIds $linkedIds -Project $projectNameValue
Export-HCSAssessmentData -ResourceIds $linkedIds -Project $projectNameValue
if (-not $SkipMigrationStatus) { Export-HCSMigrationData -ResourceIds $linkedIds -Project $projectNameValue }
if (-not $SkipResourceGraph) { Export-HCSResourceGraphData -Subscription $subscriptionIdValue -ResourceGroup $resourceGroupValue -Project $projectNameValue }

# Write files
$safeProject = $projectNameValue -replace '[^\w\-]', '_'
$runFolder  = Join-Path $outputRoot "$safeProject-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
$csvFolder  = Join-Path $runFolder 'csv'
$jsonFolder = Join-Path $runFolder 'json'
try {
    New-Item -ItemType Directory -Path $csvFolder -Force | Out-Null
    New-Item -ItemType Directory -Path $jsonFolder -Force | Out-Null
} catch {
    Write-Log "Cannot create output folder '$runFolder': $($_.Exception.Message)" 'FAIL'
    throw
}

Write-Log "Writing files to '$runFolder'..." 'HEADER'
$exported = 0
foreach ($datasetName in $script:datasets.Keys) {
    $records = @($script:datasets[$datasetName])
    if ($records.Count -eq 0) { continue }
    try {
        Export-HCSDataset -DatasetName $datasetName -Records $records -CsvFolder $csvFolder -JsonFolder $jsonFolder
        $exported++
    } catch {
        Write-Log "Failed to write '$datasetName': $($_.Exception.Message)" 'FAIL'
    }
}

# Manifest: one row per dataset, so a PM can see what was found at a glance
$summary = $script:manifest | Group-Object Dataset | ForEach-Object {
    $statuses = @($_.Group | Select-Object -ExpandProperty Status -Unique)
    $overall = if ($statuses -contains 'OK') { if ($statuses -contains 'Error') { 'Partial' } else { 'OK' } }
               elseif ($statuses -contains 'Error') { 'Error' } else { 'NotAvailable' }
    $errorMessages = @($_.Group | Where-Object Status -eq 'Error' | Select-Object -ExpandProperty Message -Unique)
    [pscustomobject]@{
        Dataset   = $_.Name
        Records   = ($_.Group | Measure-Object -Property Records -Sum).Sum
        Status    = $overall
        Calls     = $_.Count
        Errors    = ($errorMessages -join ' | ')
        CsvFile   = if (($_.Group | Measure-Object -Property Records -Sum).Sum -gt 0) { "csv/$($_.Name -replace '[^\w\-]', '_').csv" } else { '' }
    }
} | Sort-Object Dataset

$summary | Export-Csv -Path (Join-Path $runFolder '_Summary.csv') -NoTypeInformation -Encoding utf8BOM
$script:manifest | Export-Csv -Path (Join-Path $runFolder '_CallLog.csv') -NoTypeInformation -Encoding utf8BOM
[pscustomobject]@{
    ExportedAtUtc   = (Get-Date).ToUniversalTime().ToString('o')
    ScriptVersion   = '1.2.0'
    SubscriptionId  = $subscriptionIdValue
    ResourceGroup   = $resourceGroupValue
    Project         = $projectNameValue
    AuthMethod      = $authMethodValue
    SignedInAs      = (Get-AzContext).Account.Id
    LinkedResources = @($linkedIds | Sort-Object)
    ApiVersions     = $ApiVersions
    Datasets        = @($summary)
    Notes           = 'Agentless dependency data is not available through a documented API. Export it from the portal: Manage Dependencies > Export dependencies.'
} | ConvertTo-Json -Depth 10 | Set-Content -Path (Join-Path $runFolder '_Manifest.json') -Encoding utf8

Copy-Item -Path $script:logFile -Destination (Join-Path $runFolder 'export.log') -ErrorAction SilentlyContinue

Write-Host ''
$summary | Where-Object Records -gt 0 | Format-Table Dataset, Records, Status -AutoSize | Out-String | Write-Host
$errorCount = @($summary | Where-Object Status -in 'Error', 'Partial').Count
if ($errorCount -gt 0) {
    Write-Log "$errorCount datasets had errors. See _Summary.csv for details." 'WARN'
}
Write-Log "Done. $exported datasets exported to '$runFolder'." 'PASS'
Write-Log 'Reminder: export dependency data from the portal (Manage Dependencies > Export dependencies); it has no public API.' 'INFO'
