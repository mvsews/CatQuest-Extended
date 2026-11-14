$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $PSScriptRoot
$python = (Get-Command python -ErrorAction Stop).Source
$buildRoot = Join-Path $root '.tmp\hybrid-client-build'
$workPath = Join-Path $buildRoot 'pyinstaller'
$specPath = Join-Path $buildRoot 'spec'
$stagePath = Join-Path $buildRoot 'CatQuest-Hybrid-Windows'
$exePath = Join-Path $root 'dist\CatQuest-Hybrid.exe'
$zipPath = Join-Path $root 'dist\CatQuest-Hybrid-Windows.zip'

& $python -m pip install -r (Join-Path $root 'client\requirements.txt') pyinstaller
if ($LASTEXITCODE -ne 0) { throw 'Could not install the standalone build dependencies.' }

New-Item -ItemType Directory -Force -Path $buildRoot, $workPath, $specPath, $stagePath | Out-Null

& $python -m PyInstaller `
    --noconfirm `
    --clean `
    --onefile `
    --console `
    --name CatQuest-Hybrid `
    --paths (Join-Path $root 'client') `
    --hidden-import mss `
    --hidden-import pygame `
    --distpath (Join-Path $root 'dist') `
    --workpath $workPath `
    --specpath $specPath `
    (Join-Path $root 'client\catquest_hybrid.py')
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller failed.' }

Copy-Item -LiteralPath (Join-Path $root 'CatQuest-Hybrid.cmd') -Destination $stagePath -Force
Copy-Item -LiteralPath (Join-Path $root 'client\CatQuest-Hybrid-Windows.txt') -Destination $stagePath -Force
Copy-Item -LiteralPath $exePath -Destination $stagePath -Force
Compress-Archive -Path (Join-Path $stagePath '*') -DestinationPath $zipPath -Force

Write-Host "Built $exePath"
Write-Host "Built $zipPath"
