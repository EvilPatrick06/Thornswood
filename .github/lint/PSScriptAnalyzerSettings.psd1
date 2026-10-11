# PSScriptAnalyzer settings for the build check's step "Lint (warnings only)",
# issue #1343. Errors and warnings, no informational rules. The step reports
# counts and never fails the build.
# PSAvoidUsingConvertToSecureStringWithPlainText: the 4 hits (Setup-Discord.ps1:137,
# Discord-Hook.ps1:78, test-prove-secret.ps1:98, test-secret-channel.ps1:212) wrap
# values already plain in memory or test fixtures, kept off the command line per #1069.
@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSAvoidUsingConvertToSecureStringWithPlainText'
    )
}
