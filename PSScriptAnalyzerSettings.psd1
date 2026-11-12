@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Status output uses Write-Host with colors by design, through the Write-Log helper.
        'PSAvoidUsingWriteHost',
        # Write-Log is a local helper defined in each script.
        'PSAvoidOverwritingBuiltInCmdlets',
        # Script level switches are read inside helper functions through script scope.
        'PSReviewUnusedParameter',
        'PSUseSingularNouns'
    )
}
