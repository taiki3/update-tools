#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$version = (Get-Content "$PSScriptRoot\VERSION" -Raw).Trim()
$repository = 'taiki3/update-tools'
$baseUrl = "https://github.com/$repository"
$tag = "v$version"
$dist = New-Item -ItemType Directory -Path "$PSScriptRoot\dist" -Force
Compress-Archive -LiteralPath "$PSScriptRoot\Update-Tools.ps1", "$PSScriptRoot\update-tools.cmd" -DestinationPath "$dist\update-tools.zip" -Force
@{
    version = $version
    description = 'Update Winget, Scoop, and uv tools.'
    homepage = $baseUrl
    url = "$baseUrl/releases/download/$tag/update-tools.zip"
    hash = (Get-FileHash "$dist\update-tools.zip" -Algorithm SHA256).Hash.ToLowerInvariant()
    bin = 'update-tools.cmd'
} | ConvertTo-Json | Set-Content "$dist\update-tools.json" -Encoding UTF8
Copy-Item "$PSScriptRoot\install.ps1" "$dist\install.ps1"
$commit = git -C $PSScriptRoot rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'Cannot identify the release commit.' }
gh release create $tag "$dist\update-tools.zip" "$dist\update-tools.json" "$dist\install.ps1" --repo $repository --target $commit --title $tag --notes 'Install UpdateTools with Scoop from GitHub Releases.' --latest
if ($LASTEXITCODE -ne 0) { throw "Release failed: $tag" }
