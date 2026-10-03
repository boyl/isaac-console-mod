#requires -Version 7.0
param([Parameter(Mandatory)][string]$BuildDirectory)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $BuildDirectory).Path
$unicode=Join-Path $root '中文路径 加载验证'
New-Item -ItemType Directory -Path $unicode -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $root 'loader-fixture.dll') -Destination $unicode
$target=Start-Process -FilePath (Join-Path $root 'loader-target.exe') -WindowStyle Hidden -PassThru
try {
    & (Join-Path $root 'inject.exe') $target.Id (Join-Path $unicode 'loader-fixture.dll')
    if($LASTEXITCODE -ne 0){throw '中文路径加载失败'}
    if((Get-Content -LiteralPath (Join-Path $unicode 'fixture-ready.txt') -Raw) -ne 'EXPLICIT_INITIALIZATION_PASS'){throw '显式初始化未执行'}
    $target.Refresh(); if($target.HasExited){throw '测试目标意外退出'}
    Write-Output 'LOADER_PASS unicode-path explicit-initialization target-alive'
    & (Join-Path $root 'inject.exe') $target.Id (Join-Path $root 'native-pause.dll')
    if($LASTEXITCODE -eq 0){throw '非游戏目标未被拒绝'}
    $target.Refresh(); if($target.HasExited){throw '拒绝加载后目标退出'}
    Write-Output 'LOADER_PASS unsupported-target-rejected target-alive'
} finally { if(-not $target.HasExited){Stop-Process -Id $target.Id}; $target.Dispose() }
