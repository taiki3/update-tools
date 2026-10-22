# Run from a normal (non-administrator) PowerShell window.
& {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false
    [Environment]::SetEnvironmentVariable('UV_SYSTEM_CERTS', 'true', 'User')
    $env:UV_SYSTEM_CERTS = 'true'
    if (!(Get-Command scoop.cmd -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-RestMethod https://get.scoop.sh | Invoke-Expression
    }
    if (!(Get-Command scoop.cmd -ErrorAction SilentlyContinue)) { throw 'Scoop installation failed.' }
    if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        scoop.cmd install main/winget
        if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'Winget installation failed.' }
    }
    $appPath = scoop.cmd prefix update-tools 2>$null
    if (!(Test-Path -LiteralPath $appPath)) {
        scoop.cmd install 'https://gitlab.example.com/api/v4/projects/1234/packages/generic/update-tools/latest/update-tools.json'
        if (!(Test-Path -LiteralPath (scoop.cmd prefix update-tools 2>$null))) { throw 'UpdateTools installation failed.' }
    }
}
