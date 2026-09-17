#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'Update-Tools.ps1')
$winget = (Get-Command winget.exe -ErrorAction Stop).Source
$originalEncoding = [Console]::OutputEncoding
function Assert-True($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    $expected = @(& $winget upgrade --help) -join "`n"
    Assert-True ($LASTEXITCODE -eq 0) 'Winget help must succeed'

    # Capture the text at the actual native-output/Out-Host boundary.
    function Out-Host {
        param([Parameter(ValueFromPipeline)]$InputObject)
        process { $script:capturedLines.Add([string]$InputObject) }
    }
    foreach ($codePage in @(932, 65001)) {
        [Console]::OutputEncoding = [Text.Encoding]::GetEncoding($codePage)
        $script:capturedLines = New-Object 'Collections.Generic.List[string]'
        $result = Invoke-UpdateStep 'Winget help' $winget @('upgrade', '--help')
        Assert-True (!$result.Failed) 'Winget help step must succeed'
        Assert-True (($script:capturedLines -join "`n") -ceq $expected) "Winget text was corrupted with original encoding $codePage"
        Assert-True ([Console]::OutputEncoding.CodePage -eq $codePage) 'Must restore original output encoding after success'

        $result = Invoke-UpdateStep 'Winget invalid option' $winget @('--not-a-valid-update-tools-test-option')
        Assert-True ($result.Failed) 'Winget failure must remain a failure'
        Assert-True ([Console]::OutputEncoding.CodePage -eq $codePage) 'Must restore original output encoding after native failure'

        $missing = Join-Path $PSScriptRoot 'nonexistent\winget.exe'
        $result = Invoke-UpdateStep 'Winget launch failure' $missing @('--help')
        Assert-True ($result.Failed) 'Launch failure must remain a failure'
        Assert-True ([Console]::OutputEncoding.CodePage -eq $codePage) 'Must restore original output encoding after exception'
    }
} finally {
    [Console]::OutputEncoding = $originalEncoding
}
Write-Host 'All encoding tests passed (CP932 and UTF-8).' -ForegroundColor Green
