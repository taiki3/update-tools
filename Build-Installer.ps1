#Requires -Version 5.1
[CmdletBinding()]
param([string]$OutputDir = (Join-Path $PSScriptRoot 'dist'))
$ErrorActionPreference = 'Stop'
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION must contain a semantic version such as 0.1.0.' }
$payload = foreach ($name in @('Update-Tools.ps1', 'update-tools.cmd')) {
    $bytes = [IO.File]::ReadAllBytes((Join-Path $PSScriptRoot $name))
    $sha256 = [Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha256.ComputeHash($bytes)).Replace('-', '') }
    finally { $sha256.Dispose() }
    [ordered]@{ Name = $name; Sha256 = $hash; Content = [Convert]::ToBase64String($bytes) }
}
$template = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'packaging\install.ps1.template'))
$installer = $template.Replace('__VERSION__', $version).Replace('__PAYLOAD__', (ConvertTo-Json -InputObject @($payload) -Compress))
[IO.Directory]::CreateDirectory($OutputDir) | Out-Null
$output = Join-Path $OutputDir 'install.ps1'
# ASCII source makes irm | iex work consistently in Windows PowerShell 5.1.
[IO.File]::WriteAllText($output, $installer, [Text.Encoding]::ASCII)
$checksum = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $OutputDir 'install.ps1.sha256'), "$checksum  install.ps1`n", [Text.Encoding]::ASCII)
Write-Host "Built UpdateTools $version : $output"
