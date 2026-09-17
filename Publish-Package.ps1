#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$GitLabHost = 'gitlab.example.com',
    [int]$ProjectId = 1234
)
$ErrorActionPreference = 'Stop'
Get-Command glab -ErrorAction Stop | Out-Null
& (Join-Path $PSScriptRoot 'Build-Installer.ps1')
$version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'VERSION') -Raw).Trim()
$baseEndpoint = "projects/$ProjectId/packages/generic/update-tools"
$existingJson = & glab api --hostname $GitLabHost "projects/$ProjectId/packages?package_type=generic&package_name=update-tools&package_version=$version"
if ($LASTEXITCODE -ne 0) { throw 'Cannot check existing package versions.' }
$existing = @($existingJson | ConvertFrom-Json | Where-Object { $_.name -eq 'update-tools' -and $_.version -eq $version })
if ($existing.Count -gt 0) { throw "Version $version is already published. Bump VERSION before publishing again." }
# Upload the immutable version before advancing the latest installer.
foreach ($packageVersion in @($version, 'latest')) {
    # Advance release.json only after all installer files are available.
    foreach ($file in @('install.ps1.sha256', 'install.ps1', 'release.json')) {
        $path = Join-Path $PSScriptRoot "dist\$file"
        $contentType = 'application/octet-stream'
        if ($file -eq 'release.json') { $contentType = 'application/json' }
        & glab api --hostname $GitLabHost --method PUT "$baseEndpoint/$packageVersion/$file" --header "Content-Type: $contentType" --input $path
        if ($LASTEXITCODE -ne 0) { throw "Failed to publish $packageVersion/$file" }
    }
}
Write-Host "Install: irm https://$GitLabHost/api/v4/$baseEndpoint/latest/install.ps1 | iex"
