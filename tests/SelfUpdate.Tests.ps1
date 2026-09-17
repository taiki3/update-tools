#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repoRoot 'Update-Tools.ps1'
. $sourcePath
& (Join-Path $repoRoot 'Build-Installer.ps1')
$builtInstaller = Join-Path $repoRoot 'dist\install.ps1'
$release = Get-Content -LiteralPath (Join-Path $repoRoot 'dist\release.json') -Raw | ConvertFrom-Json
$fixtureRoot = Join-Path $PSScriptRoot ('.fixtures-' + [guid]::NewGuid())
$installDir = Join-Path $fixtureRoot 'installed tools\bin'
$shell = (Get-Process -Id $PID).Path
function Assert-True($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}
try {
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $installDir 'INSTALLATION.json') -Value '{"Application":"UpdateTools"}'
    Set-Content -LiteralPath (Join-Path $installDir 'VERSION') -Value '0.1.1'
    Set-Content -LiteralPath (Join-Path $installDir 'Update-Tools.ps1') -Value '# previous version'

    & {
        function Invoke-RestMethod { throw 'WhatIf and source checkout must not access the network' }
        Assert-True (!(Invoke-ToolsSelfUpdate -InstallDir $installDir -WhatIf)) 'WhatIf must skip self update'
        Assert-True (!(Invoke-ToolsSelfUpdate -InstallDir $repoRoot)) 'Source checkout must skip self update'
    }
    & {
        function Invoke-RestMethod { throw 'Simulated offline connection' }
        Assert-True (!(Invoke-ToolsSelfUpdate -InstallDir $installDir)) 'Offline self update must fall back'
        Assert-True ((Get-Content (Join-Path $installDir 'VERSION')).Trim() -eq '0.1.1') 'Offline check must preserve installed version'
    }
    & {
        function Invoke-RestMethod { @{ Version = '0.1.0'; Sha256 = $release.Sha256 } }
        function Invoke-WebRequest { throw 'Older versions must not download an installer' }
        Assert-True (!(Invoke-ToolsSelfUpdate -InstallDir $installDir)) 'Must never downgrade'
    }
    & {
        function Invoke-RestMethod { $release }
        function Invoke-WebRequest {
            param($Uri, $OutFile, $TimeoutSec, $ErrorAction, [switch]$UseBasicParsing)
            Set-Content -LiteralPath $OutFile -Value 'throw "Do not execute this corrupt installer"'
        }
        Assert-True (!(Invoke-ToolsSelfUpdate -InstallDir $installDir)) 'Checksum mismatch must reject update'
        Assert-True ((Get-Content (Join-Path $installDir 'VERSION')).Trim() -eq '0.1.1') 'Bad download must preserve installed version'
    }
    & {
        $script:downloadCount = 0
        function Invoke-RestMethod { $release }
        function Invoke-WebRequest {
            param($Uri, $OutFile, $TimeoutSec, $ErrorAction, [switch]$UseBasicParsing)
            Assert-True ($Uri.EndsWith('/' + $release.Version + '/install.ps1')) 'Download must use immutable version URL'
            $script:downloadCount++
            Copy-Item -LiteralPath $builtInstaller -Destination $OutFile
        }
        Assert-True (Invoke-ToolsSelfUpdate -InstallDir $installDir) 'Verified new version must install'
        Assert-True ((Get-FileHash (Join-Path $installDir 'Update-Tools.ps1')).Hash -eq (Get-FileHash $sourcePath).Hash) 'Updated code must match release payload'
        Assert-True (!(Invoke-ToolsSelfUpdate -InstallDir $installDir)) 'Same version must not reinstall'
        Assert-True ($script:downloadCount -eq 1) 'Only the first check should download installer'
    }
    & {
        function Invoke-RestMethod { $release | ConvertTo-Json }
        function Invoke-WebRequest { throw 'Same version must not download an installer' }
        Assert-True (!(Invoke-ToolsSelfUpdate -InstallDir $installDir)) 'JSON served as plain text must be supported'
    }

    # Force a write failure after the main script is replaced; verify rollback.
    $rollbackDir = Join-Path $fixtureRoot 'rollback'
    New-Item -ItemType Directory -Path (Join-Path $rollbackDir 'VERSION') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $rollbackDir 'Update-Tools.ps1') -Value '# original code'
    $beforeHash = (Get-FileHash (Join-Path $rollbackDir 'Update-Tools.ps1')).Hash
    $rollbackFailed = $false
    try { & $builtInstaller -InstallDir $rollbackDir -NoPath }
    catch { $rollbackFailed = $true }
    Assert-True ($rollbackFailed) 'Directory at VERSION should cause installer failure'
    Assert-True ((Get-FileHash (Join-Path $rollbackDir 'Update-Tools.ps1')).Hash -eq $beforeHash) 'Installer must restore previous code after partial failure'
    Assert-True (!(Test-Path (Join-Path $rollbackDir 'update-tools.cmd'))) 'Installer must roll back newly created files'

    # Execute the real entry point with a fake update, then a harmless replacement script.
    $entryPath = Join-Path $fixtureRoot 'Update-Tools.ps1'
    $replacement = @'
param([switch]$IncludeGlobalScoop, [switch]$SkipSelfUpdate)
if (!$IncludeGlobalScoop -or !$SkipSelfUpdate) { throw 'Missing restart flags' }
Write-Output 'Replacement code ran'
exit 23
'@
    $replacementEncoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($replacement))
    $fakeUpdate = @'
function Invoke-ToolsSelfUpdate {
    param($InstallDir)
    [IO.File]::WriteAllBytes((Join-Path $InstallDir 'Update-Tools.ps1'), [Convert]::FromBase64String('__REPLACEMENT__'))
    return $true
}
'@
    $fakeUpdate = $fakeUpdate.Replace('__REPLACEMENT__', $replacementEncoded)
    $entry = [IO.File]::ReadAllText($sourcePath).Replace('# Dot-sourcing loads helpers', ($fakeUpdate + "`r`n# Dot-sourcing loads helpers"))
    [IO.File]::WriteAllText($entryPath, $entry, (New-Object Text.UTF8Encoding($true)))
    $entryOutput = & $shell -NoProfile -ExecutionPolicy Bypass -File $entryPath -IncludeGlobalScoop
    Assert-True ($LASTEXITCODE -eq 23) 'Restart must propagate updated process exit code'
    Assert-True ($entryOutput -contains 'Replacement code ran') 'Same invocation must execute new code'
} finally {
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    $allowedParent = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
    if (!$resolvedFixture.StartsWith($allowedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid fixture cleanup path' }
    if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
Write-Host 'All self-update tests passed.' -ForegroundColor Green
