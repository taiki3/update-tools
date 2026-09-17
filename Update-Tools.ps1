#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess)]
param([switch]$IncludeGlobalScoop)
$PSNativeCommandUseErrorActionPreference = $false
$commands = @(
    @('winget.exe', 'upgrade', '--all', '--include-unknown', '--accept-source-agreements', '--accept-package-agreements'),
    @('scoop.cmd', 'update'),
    @('scoop.cmd', 'update', '*')
)
if ($IncludeGlobalScoop) { $commands += ,@('scoop.cmd', 'update', '*', '--global') }
if (Get-Command uv.exe -ErrorAction SilentlyContinue) { $commands += ,@('uv.exe', 'tool', 'upgrade', '--all') }
$encoding = [Console]::OutputEncoding
$failed = $false
try {
    [Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
    foreach ($command in $commands) {
        $tool = $command[0]
        [string[]]$arguments = $command[1..($command.Count - 1)]
        if (!$PSCmdlet.ShouldProcess(($command -join ' '), 'Run')) { continue }
        try {
            & $tool @arguments
            if ($LASTEXITCODE -ne 0 -and !($tool -eq 'winget.exe' -and $LASTEXITCODE -eq -1978335189)) { $failed = $true }
        } catch { Write-Warning $_.Exception.Message; $failed = $true }
    }
} finally { [Console]::OutputEncoding = $encoding }
exit [int]$failed
