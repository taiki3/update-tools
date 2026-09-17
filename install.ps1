# Run from a normal (non-administrator) PowerShell window.
& {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $false
    if (!(Get-Command scoop.cmd -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        Invoke-RestMethod https://get.scoop.sh | Invoke-Expression
    }
    if (!(Get-Command scoop.cmd -ErrorAction SilentlyContinue)) { throw 'Scoop installation failed.' }
    if (!(Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        scoop.cmd install main/winget
        if ($LASTEXITCODE -ne 0) { throw 'Winget installation failed.' }
    }
    scoop.cmd prefix update-tools *> $null
    if ($LASTEXITCODE -ne 0) {
        scoop.cmd install 'https://gitlab.example.com/api/v4/projects/1234/packages/generic/update-tools/latest/update-tools.json'
        if ($LASTEXITCODE -ne 0) { throw 'UpdateTools installation failed.' }
    }
}
