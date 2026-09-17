#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([switch]$IncludeGlobalScoop, [switch]$SkipSelfUpdate)

function Invoke-UpdateTools {
    [CmdletBinding(SupportsShouldProcess)]
    param([switch]$IncludeGlobalScoop)
    $results = @()
    $results += Invoke-UpdateStep 'Winget' 'winget.exe' @('upgrade', '--all', '--include-unknown', '--accept-source-agreements', '--accept-package-agreements')

    $scoopPath = Find-Tool 'scoop.cmd'
    if (!$scoopPath) {
        $results += Install-MissingTool 'Scoop'
        $scoopPath = Find-Tool 'scoop.cmd'
    }
    if ($scoopPath) {
        $results += Invoke-UpdateStep 'Scoop itself / buckets' $scoopPath @('update')
        $results += Invoke-UpdateStep 'Scoop apps' $scoopPath @('update', '*')
        if ($IncludeGlobalScoop) {
            $results += Invoke-UpdateStep 'Scoop global apps' $scoopPath @('update', '*', '--global')
        }
    }

    $uvPath = Find-Tool 'uv.exe'
    if (!$uvPath) {
        $results += Install-MissingTool 'uv' -ScoopPath $scoopPath
        $uvPath = Find-Tool 'uv.exe'
    }
    if ($uvPath) {
        switch (Get-UvInstallSource $uvPath) {
            'Scoop' { $results += New-StepResult 'uv itself' 'Managed by Scoop' }
            'Standalone' { $results += Invoke-UpdateStep 'uv itself' $uvPath @('self', 'update') }
            default {
                Write-Warning 'uv is not a recognized standalone or Scoop install; use its package manager to update uv itself.'
                $results += New-StepResult 'uv itself' 'Skipped (other / unknown installation)'
            }
        }
        $results += Invoke-UpdateStep 'uv tools' $uvPath @('tool', 'upgrade', '--all')
    }
    $results | Format-Table Manager, Result -AutoSize | Out-Host
    if ($results.Failed -contains $true) { return 1 }
    return 0
}

function Get-PowerShellPath {
    if ($PSVersionTable.PSVersion.Major -ge 6) { return (Join-Path $PSHOME 'pwsh.exe') }
    return (Join-Path $PSHOME 'powershell.exe')
}

function Invoke-Installer {
    param([string]$Name, [string]$Url, [string[]]$Arguments = @(), [string]$Sha256)
    $ErrorActionPreference = 'Stop'
    $path = Join-Path ([IO.Path]::GetTempPath()) ("update-tools-{0}.ps1" -f [guid]::NewGuid())
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $path -TimeoutSec 30 -ErrorAction Stop
        if ($Sha256 -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ine $Sha256) {
            throw 'Installer checksum mismatch.'
        }
        $parameters = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $path) + $Arguments
        return (Invoke-UpdateStep $Name (Get-PowerShellPath) $parameters)
    } finally {
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    }
}

function Invoke-ToolsSelfUpdate {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$InstallDir)
    $markerPath = Join-Path $InstallDir 'INSTALLATION.json'
    if (!(Test-Path -LiteralPath $markerPath) -or (Test-Path -LiteralPath (Join-Path $InstallDir '.git'))) {
        return $false
    }
    if (!$PSCmdlet.ShouldProcess('UpdateTools', 'Check for a new version and install it')) { return $false }
    try {
        $ErrorActionPreference = 'Stop'
        $marker = Get-Content -LiteralPath $markerPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($marker.Application -ne 'UpdateTools') { throw 'Invalid installation marker.' }
        $current = (Get-Content -LiteralPath (Join-Path $InstallDir 'VERSION') -Raw).Trim()
        if ($current -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid installed version.' }
        $packageBase = 'https://gitlab.example.com/api/v4/projects/1234/packages/generic/update-tools'
        Write-Host "`n=== UpdateTools self update ===" -ForegroundColor Cyan
        $release = Invoke-RestMethod -Uri "$packageBase/latest/release.json" -TimeoutSec 10 -ErrorAction Stop
        if ($release -is [string]) { $release = $release | ConvertFrom-Json }
        if ($release.Version -notmatch '^\d+\.\d+\.\d+$' -or $release.Sha256 -notmatch '^[a-fA-F0-9]{64}$') {
            throw 'Invalid release metadata.'
        }
        if ([version]$release.Version -le [version]$current) {
            Write-Host "UpdateTools $current is up to date."
            return $false
        }
        Write-Host "Updating UpdateTools $current -> $($release.Version)"
        # Pin both version and checksum so publishing latest cannot mix releases mid-update.
        $result = Invoke-Installer 'UpdateTools install' "$packageBase/$($release.Version)/install.ps1" @('-InstallDir', $InstallDir, '-NoPath') $release.Sha256
        if ($result.Failed) { throw $result.Result }
        $installed = (Get-Content -LiteralPath (Join-Path $InstallDir 'VERSION') -Raw).Trim()
        if ($installed -ne $release.Version) { throw 'Installed version does not match the release.' }
        return $true
    } catch {
        Write-Warning "UpdateTools self update failed; continuing with the installed version. $($_.Exception.Message)"
        return $false
    }
}

function Find-Tool {
    param([string]$Name)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { return $command.Source }
}

function Update-ProcessPath {
    # Keep the current ordering and add paths written by a child installer.
    $paths = @($env:PATH -split ';')
    foreach ($scope in @('User', 'Machine')) {
        foreach ($entry in ([Environment]::GetEnvironmentVariable('Path', $scope) -split ';')) {
            if ($entry) {
                $entry = [Environment]::ExpandEnvironmentVariables($entry)
                if ($paths -notcontains $entry) { $paths += $entry }
            }
        }
    }
    $env:PATH = $paths -join ';'
}

function New-StepResult {
    param([string]$Name, [string]$Status, [bool]$Failed = $false)
    [pscustomobject]@{ Manager = $Name; Result = $Status; Failed = $Failed }
}

function Invoke-UpdateStep {
    [CmdletBinding(SupportsShouldProcess)]
    param([string]$Name, [string]$Command, [string[]]$Arguments)
    Write-Host "`n=== $Name ===" -ForegroundColor Cyan
    if (!$PSCmdlet.ShouldProcess($Name, "$Command $($Arguments -join ' ')")) {
        return (New-StepResult $Name 'Skipped')
    }
    $savedEncoding = [Console]::OutputEncoding
    $isWinget = [IO.Path]::GetFileName($Command) -ieq 'winget.exe'
    try {
        $ErrorActionPreference = 'Stop'
        $PSNativeCommandUseErrorActionPreference = $false
        # WinGet writes UTF-8 to a pipe even when the terminal uses CP932.
        # PowerShell decodes native output using Console.OutputEncoding.
        if ($isWinget) { [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false) }
        # Scoop is invoked through its cmd shim to isolate its exit statements.
        & $Command @Arguments | Out-Host
        $code = $LASTEXITCODE
        if ($code -eq 0) { return (New-StepResult $Name 'OK') }
        if ($isWinget -and $code -eq -1978335189) {
            return (New-StepResult $Name 'Already up to date')
        }
        return (New-StepResult $Name "Failed (exit $code)" $true)
    } catch {
        Write-Warning $_.Exception.Message
        return (New-StepResult $Name "Failed: $($_.Exception.Message)" $true)
    } finally {
        if ($isWinget) { [Console]::OutputEncoding = $savedEncoding }
    }
}

function Install-MissingTool {
    [CmdletBinding(SupportsShouldProcess)]
    param([ValidateSet('Scoop', 'uv')][string]$Name, [string]$ScoopPath)
    $method = 'official installer'
    if ($Name -eq 'uv' -and $ScoopPath) { $method = 'Scoop (main/uv)' }
    if (!$PSCmdlet.ShouldProcess($Name, "Ask y/N, then install using $method")) {
        return (New-StepResult "$Name install" 'Skipped')
    }
    try {
        $answer = Read-Host "$Name が見つかりません。$method でインストールしますか？ [y/N]"
        if ($answer.Trim() -ine 'y') {
            return (New-StepResult "$Name install" 'Skipped (declined)')
        }
        if ($Name -eq 'uv' -and $ScoopPath) {
            $result = Invoke-UpdateStep 'uv install' $ScoopPath @('install', 'main/uv')
        } else {
            $url = 'https://astral.sh/uv/install.ps1'
            if ($Name -eq 'Scoop') { $url = 'https://get.scoop.sh' }
            $installerArguments = @()
            if ($Name -eq 'Scoop') {
                $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
                if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                    $installerArguments += '-RunAsAdmin'
                }
            }
            $result = Invoke-Installer "$Name install" $url $installerArguments
        }
        if ($result.Failed) { return $result }
        Update-ProcessPath
        $commandName = 'uv.exe'
        if ($Name -eq 'Scoop') { $commandName = 'scoop.cmd' }
        if (!(Find-Tool $commandName)) { throw "$Name is still unavailable after installation. Check the installer output and PATH." }
        return $result
    } catch {
        Write-Warning $_.Exception.Message
        return (New-StepResult "$Name install" "Failed: $($_.Exception.Message)" $true)
    }
}

function Get-UvInstallSource {
    param([string]$UvPath)
    # Inspect the active executable, not simply whether Scoop has another uv installed.
    $target = $UvPath
    $shim = [IO.Path]::ChangeExtension($UvPath, '.shim')
    if (Test-Path -LiteralPath $shim) {
        $shimText = Get-Content -LiteralPath $shim -Raw -Encoding UTF8
        if ($shimText -match '(?m)^path\s*=\s*"([^"]+)"') { $target = $Matches[1] }
    }
    $directory = Split-Path -Parent $target
    if ($directory -match '[\\/]apps[\\/]uv[\\/][^\\/]+$' -and
        (Test-Path -LiteralPath (Join-Path $directory 'manifest.json')) -and
        (Test-Path -LiteralPath (Join-Path $directory 'install.json'))) {
        return 'Scoop'
    }

    $receiptDirectories = @()
    if ($env:AXOUPDATER_CONFIG_WORKING_DIR) {
        $receiptDirectories += (Get-Location).Path
    } elseif ($env:AXOUPDATER_CONFIG_PATH) {
        $receiptDirectories += $env:AXOUPDATER_CONFIG_PATH
    } else {
        if ($env:XDG_CONFIG_HOME) { $receiptDirectories += Join-Path $env:XDG_CONFIG_HOME 'uv' }
        if ($env:LOCALAPPDATA) { $receiptDirectories += Join-Path $env:LOCALAPPDATA 'uv' }
    }
    foreach ($directory in $receiptDirectories) {
        $receiptPath = Join-Path $directory 'uv-receipt.json'
        if (!(Test-Path -LiteralPath $receiptPath)) { continue }
        try {
            $receipt = Get-Content -LiteralPath $receiptPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if (!$receipt.install_prefix -or $receipt.source.app_name -ne 'uv') { continue }
            $binDirectory = $receipt.install_prefix
            if ($receipt.install_layout -eq 'cargo-home') { $binDirectory = Join-Path $binDirectory 'bin' }
            $receiptExe = [IO.Path]::GetFullPath((Join-Path $binDirectory 'uv.exe'))
            if ($receiptExe -ieq [IO.Path]::GetFullPath($target)) { return 'Standalone' }
        } catch {
            Write-Warning "Cannot read uv install receipt: $receiptPath"
        }
    }
    return 'Other'
}

# Dot-sourcing loads helpers for offline verification without running any updates.
if ($MyInvocation.InvocationName -ne '.') {
    if (!$SkipSelfUpdate -and (Invoke-ToolsSelfUpdate -InstallDir $PSScriptRoot)) {
        # Start a fresh process to load the new code, with exactly one self-update check.
        $restartArguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-SkipSelfUpdate')
        if ($IncludeGlobalScoop) { $restartArguments += '-IncludeGlobalScoop' }
        & (Get-PowerShellPath) @restartArguments
        exit $LASTEXITCODE
    }
    exit (Invoke-UpdateTools -IncludeGlobalScoop:$IncludeGlobalScoop)
}
