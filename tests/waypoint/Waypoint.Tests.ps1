#Requires -Version 7.0
<#
.SYNOPSIS
    Tests for New-WagonmasterWaypoint.ps1 against the fictional sample export. No Azure access needed.
#>

BeforeAll {
    $script:scriptPath = (Resolve-Path (Join-Path $PSScriptRoot '../../src/waypoint/New-WagonmasterWaypoint.ps1')).Path
    $script:samplePath = (Resolve-Path (Join-Path $PSScriptRoot '../../samples/manifest-export')).Path
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($script:scriptPath, [ref]$tokens, [ref]$errors)
    $script:parseErrors = $errors
    $script:source = Get-Content -Path $script:scriptPath -Raw

    function Get-EmbeddedData {
        param([string]$Path)
        $html = Get-Content -Path $Path -Raw
        $match = [regex]::Match($html, '(?s)<script id="wm-data" type="application/json">(.*?)</script>')
        if (-not $match.Success) { throw 'Embedded data block not found.' }
        return $match.Groups[1].Value.Replace('<\/', '</') | ConvertFrom-Json -AsHashtable -Depth 100
    }
}

Describe 'New-WagonmasterWaypoint.ps1' {
    It 'parses without errors' {
        $script:parseErrors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" } | Should -BeNullOrEmpty
    }

    It 'never signs in to or calls Azure' {
        $script:source | Should -Not -Match 'Invoke-AzRestMethod|Connect-AzAccount|Search-AzGraph|Invoke-RestMethod|Invoke-WebRequest'
    }

    It 'builds a report from the sample export' {
        $out = Join-Path $TestDrive 'waypoint.html'
        & $script:scriptPath -ExportPath $script:samplePath -OutputPath $out -NonInteractive
        $out | Should -Exist
        $html = Get-Content -Path $out -Raw
        $html | Should -Not -Match '__WAGONMASTER_DATA__'
        $data = Get-EmbeddedData -Path $out
        $data.meta.title | Should -Be 'Wagonmaster Waypoint: iic-migrate'
        $data.manifest.Project | Should -Be 'iic-migrate'
        $data.datasets.Keys.Count | Should -Be 30
        $data.datasets['Discovery_VMware_Machines'].Count | Should -Be 160
        @($data.summary).Count | Should -BeGreaterThan 30
    }

    It 'builds a report from the Azure Local sample export' {
        $azureLocalSample = (Resolve-Path (Join-Path $PSScriptRoot '../../samples/manifest-export-azure-local')).Path
        $out = Join-Path $TestDrive 'waypoint-azure-local.html'
        & $script:scriptPath -ExportPath $azureLocalSample -OutputPath $out -NonInteractive
        $data = Get-EmbeddedData -Path $out
        $data.manifest.Target | Should -Be 'Azure Local'
        $data.datasets['Discovery_VMware_Machines'].Count | Should -Be 180
        $data.datasets['Migration_DataReplication_ProtectedItems'].Count | Should -Be 64
        $data.datasets.Keys | Should -Not -Contain 'Assessment_AzureVM'
    }

    It 'honors -ExcludeDataset with wildcards' {
        $out = Join-Path $TestDrive 'waypoint-excluded.html'
        & $script:scriptPath -ExportPath $script:samplePath -OutputPath $out -ExcludeDataset 'Discovery_SoftwareInventory', 'BusinessCase*' -NonInteractive
        $data = Get-EmbeddedData -Path $out
        $data.datasets.Keys | Should -Not -Contain 'Discovery_SoftwareInventory'
        $data.datasets.Keys | Should -Not -Contain 'BusinessCase'
        $data.datasets.Keys | Should -Contain 'Discovery_VMware_Machines'
    }

    It 'uses a custom title' {
        $out = Join-Path $TestDrive 'waypoint-title.html'
        & $script:scriptPath -ExportPath $script:samplePath -OutputPath $out -Title 'Wave 1 review' -NonInteractive
        (Get-EmbeddedData -Path $out).meta.title | Should -Be 'Wave 1 review'
    }

    It 'fails clearly for a folder that is not an export' {
        $empty = Join-Path $TestDrive 'not-an-export'
        New-Item -ItemType Directory -Path $empty | Out-Null
        { & $script:scriptPath -ExportPath $empty -NonInteractive } | Should -Throw '*does not look like a Wagonmaster Manifest export*'
    }

    It 'fails clearly when no export is given and it cannot prompt' {
        Push-Location $TestDrive
        try {
            $previous = $env:WAGONMASTER_EXPORT_PATH
            $env:WAGONMASTER_EXPORT_PATH = $null
            { & $script:scriptPath -NonInteractive } | Should -Throw "*Missing required value 'ExportPath'*"
        } finally {
            $env:WAGONMASTER_EXPORT_PATH = $previous
            Pop-Location
        }
    }
}
