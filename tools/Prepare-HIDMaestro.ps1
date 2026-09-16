param(
    [string]$DestinationDir = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$version = '1.8.0'
$expectedSha256 = '1e5f5019c20e4be8f922c7aa5a86ee87eb01f7aa851fe38daea14d0ce4fd8240'
$url = "https://github.com/hifihedgehog/HIDMaestro/releases/download/v$version/HIDMaestro-v$version.zip"

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($DestinationDir)) {
    $DestinationDir = Join-Path $repoRoot 'src\virtual-gamepad-helper\deps'
}

New-Item -ItemType Directory -Path $DestinationDir -Force | Out-Null

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('mugen-hidmaestro-' + [Guid]::NewGuid().ToString('N'))
$zipPath = Join-Path $tempRoot 'HIDMaestro.zip'
$extractDir = Join-Path $tempRoot 'extract'

New-Item -ItemType Directory -Path $extractDir -Force | Out-Null

try {
    Write-Host "Downloading HIDMaestro v$version..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath

    $actualSha256 = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $expectedSha256) {
        throw "HIDMaestro archive hash mismatch. Expected $expectedSha256, got $actualSha256."
    }

    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractDir -Force

    $coreDll = Get-ChildItem -LiteralPath $extractDir -Recurse -File -Filter 'HIDMaestro.Core.dll' |
        Sort-Object Length -Descending |
        Select-Object -First 1

    if ($null -eq $coreDll) {
        throw 'HIDMaestro.Core.dll was not found in the verified release archive.'
    }

    Copy-Item -LiteralPath $coreDll.FullName -Destination (Join-Path $DestinationDir 'HIDMaestro.Core.dll') -Force

    $license = Get-ChildItem -LiteralPath $extractDir -Recurse -File |
        Where-Object { $_.Name -in @('LICENSE', 'LICENSE.txt', 'LICENSE.md') } |
        Select-Object -First 1

    if ($null -ne $license) {
        Copy-Item -LiteralPath $license.FullName -Destination (Join-Path $DestinationDir 'HIDMaestro-LICENSE.txt') -Force
    }
    else {
        throw 'HIDMaestro license file was not found in the verified release archive.'
    }

    Write-Host "Prepared HIDMaestro v$version dependency: $($coreDll.Length) bytes"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
