#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$version = (Get-Content "$PSScriptRoot\VERSION" -Raw).Trim()
$endpoint = 'projects/1234/packages/generic/update-tools'
$baseUrl = "https://gitlab.example.com/api/v4/$endpoint"
$dist = New-Item -ItemType Directory -Path "$PSScriptRoot\dist" -Force
Compress-Archive -LiteralPath "$PSScriptRoot\Update-Tools.ps1", "$PSScriptRoot\update-tools.cmd" -DestinationPath "$dist\update-tools.zip" -Force
@{
    version = $version
    description = 'Update Winget, Scoop, and uv tools.'
    homepage = 'https://gitlab.example.com/taiki.yoshinaka/update-tools'
    url = "$baseUrl/$version/update-tools.zip"
    hash = (Get-FileHash "$dist\update-tools.zip" -Algorithm SHA256).Hash.ToLowerInvariant()
    bin = 'update-tools.cmd'
} | ConvertTo-Json | Set-Content "$dist\update-tools.json" -Encoding UTF8
Copy-Item "$PSScriptRoot\install.ps1" "$dist\install.ps1"
foreach ($file in @('update-tools.zip', 'update-tools.json', 'install.ps1')) {
    glab api --hostname gitlab.example.com -X PUT "$endpoint/$version/$file" -H 'Content-Type: application/octet-stream' --input "$dist\$file"
    if ($LASTEXITCODE -ne 0) { throw "Upload failed: $file" }
}
foreach ($file in @('update-tools.json', 'install.ps1')) {
    glab api --hostname gitlab.example.com -X PUT "$endpoint/latest/$file" -H 'Content-Type: application/octet-stream' --input "$dist\$file"
    if ($LASTEXITCODE -ne 0) { throw "Upload failed: latest/$file" }
}
