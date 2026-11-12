#Requires -Version 7.0
<#
.SYNOPSIS
    Builds a single file HTML dashboard from a Wagonmaster Manifest export.

.DESCRIPTION
    Wagonmaster Waypoint reads the JSON files in a Wagonmaster Manifest export folder and
    writes one self contained HTML report. The report needs no server, no internet access
    and no sign in: open it in any browser, email it, or put it on a file share.

    Waypoint never contacts Azure. It only reads the export folder and writes one file.

    The report covers migrations to Azure and to Azure Local. For Azure Local it works out
    readiness and a cluster sizing estimate from the discovery data, because Azure Migrate
    has no assessment type for Azure Local.

    The report embeds every dataset in the export, so it holds the same customer data as
    the export itself. Handle it the same way.

    Each setting is resolved in this order: parameter, environment variable, interactive
    prompt. In pipelines and with -NonInteractive it never prompts.

.PARAMETER ExportPath
    Folder written by Export-WagonmasterManifest.ps1 (the one that holds _Manifest.json
    and the json folder). If omitted, the newest export under .\WagonmasterManifest is
    used. Env: WAGONMASTER_EXPORT_PATH.

.PARAMETER OutputPath
    Path of the HTML file to write. Default: Waypoint.html inside the export folder.
    Env: WAGONMASTER_WAYPOINT_OUTPUT.

.PARAMETER Title
    Title shown at the top of the report. Default: "Wagonmaster Waypoint: <project>".

.PARAMETER ExcludeDataset
    Dataset names to leave out of the report, for example Discovery_SoftwareInventory on
    very large estates. Wildcards are allowed.

.PARAMETER Open
    Open the report in the default browser when done.

.PARAMETER NonInteractive
    Never prompt. A missing value is an error.

.EXAMPLE
    .\New-WagonmasterWaypoint.ps1
    Uses the newest export under .\WagonmasterManifest and writes Waypoint.html into it.

.EXAMPLE
    .\New-WagonmasterWaypoint.ps1 -ExportPath .\WagonmasterManifest\contoso-20261112-101500 -Open

.EXAMPLE
    .\New-WagonmasterWaypoint.ps1 -ExportPath ..\..\samples\manifest-export -OutputPath .\demo.html

.NOTES
    Author: Kristopher Turner
    Contact: kris@hybridsolutions.cloud
    Version: 0.2.0

    ScriptVersion    = "0.2.0"
    TaskReference    = "wagonmaster/waypoint"
    DocumentationRef = "docs/waypoint/index.md"
    LastUpdated      = "2026-11-12"
    UpdatedBy        = "Kristopher Turner"
    ChangeLog        = @(
        "0.2.0 - 2026-11-12 - Azure Local: readiness rules, cluster sizing estimate and replication tracking in the report"
        "0.1.0 - 2026-11-12 - Initial implementation, built against sample data"
    )
#>
[CmdletBinding()]
param(
    [string]$ExportPath = '',
    [string]$OutputPath = '',
    [string]$Title = '',
    [string[]]$ExcludeDataset = @(),
    [switch]$Open,
    [switch]$NonInteractive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# === Settings ===

$WaypointVersion = '0.2.0'
$TemplatePath    = Join-Path $PSScriptRoot 'template/waypoint.html'
$Placeholder     = '__WAGONMASTER_DATA__'
$WarnSizeMb      = 50

# === Functions ===

function Write-Status {
    param([string]$Message, [string]$Level = 'INFO')
    $color = switch ($Level) { 'PASS' { 'Green' } 'WARN' { 'Yellow' } 'FAIL' { 'Red' } 'HEADER' { 'Cyan' } default { 'Gray' } }
    Write-Host $Message -ForegroundColor $color
}

function Test-HCSInteractiveHost {
    if (-not [Environment]::UserInteractive) { return $false }
    if ([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-noni' }) { return $false }
    if ($env:TF_BUILD -or $env:GITHUB_ACTIONS -or $env:AUTOMATION_ASSET_ACCOUNTID) { return $false }
    return $true
}

function Find-HCSLatestExport {
    # Newest folder under .\WagonmasterManifest that looks like a Manifest export.
    $root = Join-Path (Get-Location).Path 'WagonmasterManifest'
    if (-not (Test-Path -Path $root)) { return $null }
    $candidate = Get-ChildItem -Path $root -Directory |
        Where-Object { Test-Path -Path (Join-Path $_.FullName 'json') } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
    return $null
}

function ConvertTo-HCSEmbeddedJson {
    # Makes JSON safe to place inside an HTML script element.
    param([Parameter(Mandatory)][string]$Json)
    return $Json.Replace('</', '<\/').Replace([string][char]0x2028, ' ').Replace([string][char]0x2029, ' ')
}

# === Main ===

Write-Status 'Wagonmaster Waypoint' 'HEADER'
$canPrompt = (-not $NonInteractive) -and (Test-HCSInteractiveHost)

# Export folder
$exportValue = $ExportPath
if ([string]::IsNullOrWhiteSpace($exportValue)) { $exportValue = $env:WAGONMASTER_EXPORT_PATH }
if ([string]::IsNullOrWhiteSpace($exportValue)) { $exportValue = Find-HCSLatestExport }
if ([string]::IsNullOrWhiteSpace($exportValue) -and $canPrompt) { $exportValue = Read-Host -Prompt 'Path to the Wagonmaster Manifest export folder' }
if ([string]::IsNullOrWhiteSpace($exportValue)) {
    throw "Missing required value 'ExportPath'. Provide it with -ExportPath or environment variable 'WAGONMASTER_EXPORT_PATH'."
}
if (-not (Test-Path -Path $exportValue -PathType Container)) { throw "Export folder not found: $exportValue" }
$exportFolder = (Resolve-Path -Path $exportValue).Path
$jsonFolder = Join-Path $exportFolder 'json'
if (-not (Test-Path -Path $jsonFolder -PathType Container)) {
    throw "'$exportFolder' does not look like a Wagonmaster Manifest export: it has no 'json' folder."
}
Write-Status "Export: $exportFolder"

# Output file
$outputValue = $OutputPath
if ([string]::IsNullOrWhiteSpace($outputValue)) { $outputValue = $env:WAGONMASTER_WAYPOINT_OUTPUT }
if ([string]::IsNullOrWhiteSpace($outputValue)) { $outputValue = Join-Path $exportFolder 'Waypoint.html' }
$outputFile = [System.IO.Path]::GetFullPath($outputValue, (Get-Location).Path)
$outputFolder = Split-Path -Path $outputFile -Parent

if (-not (Test-Path -Path $TemplatePath)) { throw "Report template not found: $TemplatePath" }

# Manifest and summary (both optional: an export without them still produces a report)
$manifestJson = '{}'
$projectName = ''
$manifestPath = Join-Path $exportFolder '_Manifest.json'
if (Test-Path -Path $manifestPath) {
    $manifestJson = (Get-Content -Path $manifestPath -Raw).Trim()
    try {
        $manifest = $manifestJson | ConvertFrom-Json -Depth 20
        if ($manifest.PSObject.Properties['Project']) { $projectName = [string]$manifest.Project }
    } catch {
        Write-Status "Could not read '_Manifest.json': $($_.Exception.Message)" 'WARN'
        $manifestJson = '{}'
    }
} else {
    Write-Status "No '_Manifest.json' in the export. Project details will be blank." 'WARN'
}
$summaryJson = '[]'
$summaryPath = Join-Path $exportFolder '_Summary.csv'
if (Test-Path -Path $summaryPath) {
    $summaryRows = @(Import-Csv -Path $summaryPath)
    $summaryJson = ConvertTo-Json -InputObject $summaryRows -Depth 5 -Compress
}

# Datasets. The JSON text is embedded as written by Manifest, without a round trip, so
# no value is reinterpreted on the way through.
$builder = [System.Text.StringBuilder]::new()
$included = 0
$skipped = 0
foreach ($file in Get-ChildItem -Path $jsonFolder -Filter '*.json' | Sort-Object Name) {
    $datasetName = $file.BaseName
    if ($ExcludeDataset | Where-Object { $datasetName -like $_ }) {
        Write-Status "Skipping '$datasetName' (excluded)."
        $skipped++
        continue
    }
    $text = (Get-Content -Path $file.FullName -Raw)
    if ([string]::IsNullOrWhiteSpace($text)) { continue }
    $text = $text.Trim().TrimStart([char]0xFEFF)
    if (-not $text.StartsWith('[')) {
        Write-Status "Skipping '$datasetName': the file is not a JSON list." 'WARN'
        $skipped++
        continue
    }
    if ($included -gt 0) { [void]$builder.Append(',') }
    [void]$builder.Append((ConvertTo-Json -InputObject $datasetName -Compress)).Append(':').Append($text)
    $included++
}
if ($included -eq 0) { throw "No datasets found in '$jsonFolder'." }

$titleValue = if ([string]::IsNullOrWhiteSpace($Title)) { if ($projectName) { "Wagonmaster Waypoint: $projectName" } else { 'Wagonmaster Waypoint' } } else { $Title }
$metaJson = ConvertTo-Json -Compress -InputObject ([ordered]@{
    title           = $titleValue
    waypointVersion = $WaypointVersion
    generatedAtUtc  = (Get-Date).ToUniversalTime().ToString('o')
    datasetCount    = $included
})
$dataJson = '{"meta":' + $metaJson + ',"manifest":' + $manifestJson + ',"summary":' + $summaryJson + ',"datasets":{' + $builder.ToString() + '}}'
$dataJson = ConvertTo-HCSEmbeddedJson -Json $dataJson

$template = Get-Content -Path $TemplatePath -Raw
if (-not $template.Contains($Placeholder)) { throw "The report template is missing the '$Placeholder' marker." }
$html = $template.Replace($Placeholder, $dataJson)

try {
    if (-not (Test-Path -Path $outputFolder)) { New-Item -ItemType Directory -Path $outputFolder -Force | Out-Null }
    [System.IO.File]::WriteAllText($outputFile, $html, [System.Text.UTF8Encoding]::new($false))
} catch {
    Write-Status "Could not write '$outputFile': $($_.Exception.Message)" 'FAIL'
    throw
}

$sizeMb = [math]::Round((Get-Item -Path $outputFile).Length / 1MB, 1)
Write-Status "Datasets included: $included$(if ($skipped) { ", skipped: $skipped" })"
if ($sizeMb -gt $WarnSizeMb) {
    Write-Status "The report is $sizeMb MB. Large reports open slowly. Consider -ExcludeDataset Discovery_SoftwareInventory." 'WARN'
}
Write-Status "Done. Report written to '$outputFile' ($sizeMb MB)." 'PASS'
Write-Status 'The report contains project data. Handle it as confidential.'

if ($Open -and $canPrompt) {
    try { Invoke-Item -Path $outputFile } catch { Write-Status "Could not open the report: $($_.Exception.Message)" 'WARN' }
}
