#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$scriptPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'Update-Tools.ps1'
function Assert-True($Condition, [string]$Message) {
    if (!$Condition) { throw $Message }
}

# No real downloads, installations, or package updates are performed.
& {
    . $scriptPath
    function Invoke-WebRequest { throw 'Unexpected download' }
    function Invoke-UpdateStep { throw 'Unexpected command' }
    foreach ($reply in @('', 'n', 'N', 'yes', 'invalid')) {
        function Read-Host { return $reply }
        $result = Install-MissingTool 'Scoop'
        Assert-True ($result.Result -eq 'Skipped (declined)' -and !$result.Failed) "Must decline: '$reply'"
    }
    function Read-Host { throw 'Unexpected prompt in WhatIf' }
    $result = Install-MissingTool 'uv' -WhatIf
    Assert-True ($result.Result -eq 'Skipped' -and !$result.Failed) 'WhatIf must skip all install actions'
}

& {
    . $scriptPath
    $script:installCall = $null
    $script:pathRefreshed = $false
    function Read-Host { 'Y' }
    function Invoke-WebRequest { throw 'Scoop installation must not download the standalone installer' }
    function Invoke-UpdateStep {
        param($Name, $Command, $Arguments)
        $script:installCall = @($Command) + $Arguments
        New-StepResult $Name 'OK'
    }
    function Update-ProcessPath { $script:pathRefreshed = $true }
    function Find-Tool { 'C:\fake\uv.exe' }
    $result = Install-MissingTool 'uv' -ScoopPath 'C:\fake\scoop.cmd'
    Assert-True (($script:installCall -join '|') -eq 'C:\fake\scoop.cmd|install|main/uv') 'uv must install via Scoop when available'
    Assert-True (!$result.Failed -and $script:pathRefreshed) 'Install must refresh PATH'
}

& {
    . $scriptPath
    $script:downloadUrls = @()
    $script:installerFiles = @()
    function Read-Host { 'y' }
    function Invoke-WebRequest {
        param($Uri, $OutFile, [switch]$UseBasicParsing, $ErrorAction)
        $script:downloadUrls += $Uri
        $script:installerFiles += $OutFile
        Set-Content -LiteralPath $OutFile -Value '# fake installer'
    }
    function Invoke-UpdateStep {
        param($Name, $Command, $Arguments)
        Assert-True ($Arguments -contains '-File') 'Installer must run in a child process'
        New-StepResult $Name 'OK'
    }
    function Update-ProcessPath {}
    function Find-Tool { 'C:\fake\installed.exe' }
    Assert-True (!(Install-MissingTool 'Scoop').Failed) 'Scoop install should succeed'
    Assert-True (!(Install-MissingTool 'uv').Failed) 'Standalone uv install should succeed'
    Assert-True (($script:downloadUrls -join '|') -eq 'https://get.scoop.sh|https://astral.sh/uv/install.ps1') 'Use official installers'
    foreach ($path in $script:installerFiles) {
        Assert-True (!(Test-Path -LiteralPath $path)) 'Temporary installer must be removed'
    }
    function Invoke-WebRequest { throw 'Simulated network failure' }
    Assert-True ((Install-MissingTool 'uv').Failed) 'Download failure must be reported'
}

& {
    . $scriptPath
    $fixtureRoot = Join-Path $PSScriptRoot ('.fixtures-' + [guid]::NewGuid())
    $previousConfig = $env:AXOUPDATER_CONFIG_PATH
    $previousWorkingDir = $env:AXOUPDATER_CONFIG_WORKING_DIR
    try {
        $env:AXOUPDATER_CONFIG_PATH = $fixtureRoot
        $env:AXOUPDATER_CONFIG_WORKING_DIR = $null
        $scoopBin = Join-Path $fixtureRoot 'custom scoop\apps\uv\current'
        $standaloneBin = Join-Path $fixtureRoot 'custom standalone'
        $shimDir = Join-Path $fixtureRoot 'custom scoop\shims'
        New-Item -ItemType Directory -Path $scoopBin, $standaloneBin, $shimDir -Force | Out-Null
        Set-Content (Join-Path $scoopBin 'manifest.json') '{}'
        Set-Content (Join-Path $scoopBin 'install.json') '{}'
        Set-Content (Join-Path $shimDir 'uv.shim') ('path = "' + (Join-Path $scoopBin 'uv.exe') + '"')
        $receiptPath = Join-Path $fixtureRoot 'uv-receipt.json'
        @{ install_prefix = $standaloneBin; install_layout = 'flat'; source = @{ app_name = 'uv' } } |
            ConvertTo-Json | Set-Content -LiteralPath $receiptPath
        Assert-True ((Get-UvInstallSource (Join-Path $shimDir 'uv.exe')) -eq 'Scoop') 'Scoop shim must take precedence over another standalone receipt'
        Assert-True ((Get-UvInstallSource (Join-Path $scoopBin 'uv.exe')) -eq 'Scoop') 'Direct Scoop binary must be detected'
        Assert-True ((Get-UvInstallSource (Join-Path $standaloneBin 'uv.exe')) -eq 'Standalone') 'Matching standalone receipt must be detected'
        Assert-True ((Get-UvInstallSource (Join-Path $fixtureRoot 'other\uv.exe')) -eq 'Other') 'Stale receipt must not classify a different binary as standalone'
        Set-Content -LiteralPath $receiptPath -Value 'broken json'
        Assert-True ((Get-UvInstallSource (Join-Path $standaloneBin 'uv.exe')) -eq 'Other') 'Corrupt receipt must not enable self update'
    } finally {
        $env:AXOUPDATER_CONFIG_PATH = $previousConfig
        $env:AXOUPDATER_CONFIG_WORKING_DIR = $previousWorkingDir
        $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
        $allowedParent = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') + '\'
        if (!$resolvedFixture.StartsWith($allowedParent, [StringComparison]::OrdinalIgnoreCase)) { throw 'Invalid fixture cleanup path' }
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}

foreach ($source in @('Scoop', 'Standalone', 'Other')) {
    & {
        . $scriptPath
        $script:commands = @()
        function Find-Tool { param($Name) "C:\fake\$Name" }
        function Get-UvInstallSource { $source }
        function Install-MissingTool { throw 'Existing tools must not prompt for installation' }
        function Invoke-UpdateStep {
            param($Name, $Command, $Arguments)
            $script:commands += $Arguments -join ' '
            New-StepResult $Name 'Simulated result' ($Name -eq 'Winget')
        }
        $code = Invoke-UpdateTools -IncludeGlobalScoop
        Assert-True ($code -eq 1) 'A failed step must produce a nonzero exit code'
        Assert-True ($script:commands[-1] -eq 'tool upgrade --all') 'Must continue to uv tools after earlier failures'
        Assert-True ($script:commands -contains 'update * --global') 'Global Scoop updates must remain supported'
        Assert-True (($script:commands -contains 'self update') -eq ($source -eq 'Standalone')) 'Only standalone uv must self update'
    }
}

& {
    . $scriptPath
    function Find-Tool { return $null }
    function Read-Host { '' }
    function Invoke-UpdateStep { param($Name) New-StepResult $Name 'OK' }
    function Invoke-WebRequest { throw 'Declining must not download anything' }
    Assert-True ((Invoke-UpdateTools) -eq 0) 'Declining missing tools must not fail the run'
}

& {
    . $scriptPath
    $shell = (Get-Process -Id $PID).Path
    Assert-True ((Invoke-UpdateStep 'Simulated failure' $shell @('-NoProfile', '-Command', 'exit 7')).Failed) 'Native failures must be detected'
    Assert-True (!(Invoke-UpdateStep 'Simulated success' $shell @('-NoProfile', '-Command', 'exit 0')).Failed) 'Native success must be detected'
}
Write-Host 'All offline tests passed.' -ForegroundColor Green
