# PSScriptAnalyzer settings for the build check's step "Lint (warnings only)",
# issue #1343. Errors and warnings, no informational rules. The step reports
# counts and never fails the build.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @('PSAvoidUsingWriteHost')
}
