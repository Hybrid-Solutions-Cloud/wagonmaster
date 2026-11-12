#Requires -Version 7.0
<#
.SYNOPSIS
    Static checks for Export-WagonmasterManifest.ps1. No Azure access needed.
#>

BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot '../../src/manifest/Export-WagonmasterManifest.ps1'
    $tokens = $null
    $errors = $null
    $script:ast = [System.Management.Automation.Language.Parser]::ParseFile(
        (Resolve-Path $script:scriptPath).Path, [ref]$tokens, [ref]$errors)
    $script:parseErrors = $errors
    $script:source = Get-Content -Path $script:scriptPath -Raw
}

Describe 'Export-WagonmasterManifest.ps1 static checks' {
    It 'parses without errors' {
        $script:parseErrors | ForEach-Object { "$($_.Extent.StartLineNumber): $($_.Message)" } | Should -BeNullOrEmpty
    }

    It 'requires PowerShell 7' {
        $script:source | Should -Match '#Requires -Version 7\.0'
    }

    It 'sets strict mode and stops on errors' {
        $script:source | Should -Match 'Set-StrictMode -Version Latest'
        $script:source | Should -Match "\`$ErrorActionPreference = 'Stop'"
    }

    It 'only sends GET requests to Azure' {
        $methods = [regex]::Matches($script:source, 'Invoke-AzRestMethod[^\r\n]*-Method\s+(\w+)') | ForEach-Object { $_.Groups[1].Value }
        $methods | Should -Not -BeNullOrEmpty
        $methods | Where-Object { $_ -ne 'GET' } | Should -BeNullOrEmpty
    }

    It 'does not hardcode a subscription or tenant GUID' {
        $script:source | Should -Not -Match "'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'"
    }

    It 'exposes the documented parameters' {
        $names = $script:ast.ParamBlock.Parameters.Name.VariablePath.UserPath
        foreach ($expected in 'ConfigPath', 'AuthMethod', 'TenantId', 'SubscriptionId', 'ResourceGroupName', 'ProjectName',
            'OutputPath', 'ClientId', 'ClientSecret', 'CertificateThumbprint', 'ManagedIdentityClientId',
            'UseDeviceCode', 'IncludeSoftwareInventory', 'SkipResourceGraph', 'SkipMigrationStatus', 'NonInteractive', 'DryRun') {
            $names | Should -Contain $expected
        }
    }
}
