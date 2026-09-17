#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
function Assert($condition, $message) { if (!$condition) { throw $message } }

# Exercise the real scripts with harmless replacements for package managers.
& {
    $state = @{ Calls = @() }
    $state.UvPresent = $true
    $state.WingetExit = 7
    function Get-Command { param($Name) if ($Name -eq 'uv.exe' -and $state.UvPresent) { 'uv.exe' } }
    function winget.exe {
        Assert ([Console]::OutputEncoding.CodePage -eq 65001) 'Use UTF-8 for Winget'
        $state.Calls += 'winget'
        $global:LASTEXITCODE = $state.WingetExit
    }
    function scoop.cmd { $state.Calls += "scoop $args"; $global:LASTEXITCODE = 0 }
    function uv.exe { $state.Calls += "uv $args"; $global:LASTEXITCODE = 0 }
    $originalEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(932)
        & "$root\Update-Tools.ps1" -IncludeGlobalScoop
        Assert ($LASTEXITCODE -eq 1) 'Report a failed update'
        Assert ([Console]::OutputEncoding.CodePage -eq 932) 'Restore encoding'
        Assert (($state.Calls -join '|') -eq 'winget|scoop update|scoop update *|scoop update * --global|uv tool upgrade --all') "Continue in order after failure: $($state.Calls -join '|')"
        $state.Calls = @()
        & "$root\Update-Tools.ps1" -WhatIf
        Assert ($state.Calls.Count -eq 0) 'WhatIf must execute nothing'
        $state.WingetExit = -1978335189
        $state.UvPresent = $false
        & "$root\Update-Tools.ps1"
        Assert ($LASTEXITCODE -eq 0) 'No Winget upgrades is success'
        Assert (($state.Calls -join '|') -eq 'winget|scoop update|scoop update *') 'Missing uv must be skipped'
    } finally { [Console]::OutputEncoding = $originalEncoding }
}

foreach ($alreadyInstalled in @($true, $false)) {
    & {
        $state = @{ Calls = @(); ScoopPresent = $alreadyInstalled }
        function Get-Command {
            param($Name)
            if (($Name -eq 'scoop.cmd' -and $state.ScoopPresent) -or ($Name -eq 'winget.exe' -and $alreadyInstalled)) { $Name }
        }
        function Set-ExecutionPolicy {}
        function Invoke-RestMethod { 'mock installer' }
        function Invoke-Expression { $state.Calls += 'install scoop'; $state.ScoopPresent = $true }
        function scoop.cmd {
            param($action, $package)
            $global:LASTEXITCODE = 0
            if ($action -eq 'prefix') { if (!$alreadyInstalled) { $global:LASTEXITCODE = 1 }; return }
            $state.Calls += "$action $package"
        }
        & "$root\install.ps1"
        if ($alreadyInstalled) { Assert ($state.Calls.Count -eq 0) 'Existing tools must be untouched' }
        else {
            Assert ($state.Calls.Count -eq 3) 'Install only missing Scoop, Winget, and UpdateTools'
            Assert ($state.Calls[1] -eq 'install main/winget') 'Install Winget through Scoop'
            Assert ($state.Calls[2] -like 'install https://*/latest/update-tools.json') 'Install UpdateTools from its Scoop manifest'
        }
    }
}
Write-Host 'All smoke tests passed.'
