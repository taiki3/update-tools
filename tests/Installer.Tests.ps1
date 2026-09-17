#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
& (Join-Path $repoRoot 'Build-Installer.ps1')
$installerPath = Join-Path $repoRoot 'dist\install.ps1'
$installerText = [IO.File]::ReadAllText($installerPath)
$fixtureRoot = Join-Path $PSScriptRoot ('.fixtures-' + [guid]::NewGuid())
$installDir = Join-Path $fixtureRoot 'path with spaces\bin'
$previousPath = [Environment]::GetEnvironmentVariable('Path', 'User')
function Assert-True($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
try {
    & $installerPath -InstallDir $installDir -NoPath -WhatIf
    Assert-True (!(Test-Path -LiteralPath $installDir)) 'WhatIf must not create installation files'
    # IEX does not forward the caller's args. Override only the defaults in this test copy.
    $testInstallerText = $installerText.Replace("(Join-Path `$env:LOCALAPPDATA 'UpdateTools\bin')", ("'" + $installDir.Replace("'", "''") + "'"))
    $testInstallerText = $testInstallerText.Replace('[switch]$NoPath', '[switch]$NoPath = $true')
    Invoke-Expression $testInstallerText
    Assert-True ($ErrorActionPreference -eq 'Stop') 'Installer must preserve caller preferences'
    Assert-True ([Environment]::GetEnvironmentVariable('Path', 'User') -eq $previousPath) 'NoPath must leave user PATH unchanged'
    foreach ($file in @('Update-Tools.ps1', 'update-tools.cmd')) {
        $expected = (Get-FileHash -LiteralPath (Join-Path $repoRoot $file)).Hash
        $actual = (Get-FileHash -LiteralPath (Join-Path $installDir $file)).Hash
        Assert-True ($actual -eq $expected) "Installed payload differs: $file"
    }
    & (Join-Path $installDir 'update-tools.cmd') -WhatIf
    Assert-True ($LASTEXITCODE -eq 0) 'Installed launcher must run successfully'
    Set-Content -LiteralPath (Join-Path $installDir 'update-tools.cmd') -Value 'broken'
    & $installerPath -InstallDir $installDir -NoPath
    Assert-True ((Get-FileHash -LiteralPath (Join-Path $installDir 'update-tools.cmd')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $repoRoot 'update-tools.cmd')).Hash) 'Reinstall must restore payload'
    $badDir = Join-Path $fixtureRoot 'bad'
    $badInstaller = $testInstallerText.Replace($installDir, $badDir) -replace '"Sha256":"[A-F0-9]{64}"', '"Sha256":"BAD"'
    $rejected = $false
    try { Invoke-Expression $badInstaller }
    catch { $rejected = $_.Exception.Message -like '*Checksum mismatch*' }
    Assert-True ($rejected -and !(Test-Path -LiteralPath $badDir)) 'Bad checksum must fail before writing payload'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $allowedParent = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if (!$resolvedFixture.StartsWith($allowedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid fixture cleanup path' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
Write-Host 'All installer tests passed.' -ForegroundColor Green
