#requires -Version 7.0
param([Parameter(Mandatory)][string]$BuildDirectory,[Parameter(Mandatory)][string]$GameDirectory)
$ErrorActionPreference='Stop'
$root=Join-Path $BuildDirectory 'autoload-fixture'
$scripts=Join-Path $root 'scripts'
New-Item -ItemType Directory -Path $scripts -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $BuildDirectory 'autoload-target.exe') -Destination $root
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'vendor/asi-loader/winmm.dll') -Destination $root
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'winmm.ini') -Destination $root
Copy-Item -LiteralPath (Join-Path $BuildDirectory 'IsaacConsoleNativePause.asi') -Destination $scripts
$log=Join-Path $scripts 'native-pause.log'
$before=if(Test-Path -LiteralPath $log){(Get-Content -LiteralPath $log -Raw).Length}else{0}
$target=Start-Process -FilePath (Join-Path $root 'autoload-target.exe') -ArgumentList ('"'+(Join-Path $GameDirectory 'Lua5.3.3r.dll')+'"') -WorkingDirectory $root -WindowStyle Hidden -PassThru
if(-not $target.WaitForExit(15000)){Stop-Process -Id $target.Id;throw '自加载测试进程超时'}
if($target.ExitCode -ne 0){throw "原始WINMM转发失败：$($target.ExitCode)"}
if(-not(Test-Path -LiteralPath $log)){throw '自加载器没有载入暂停插件'}
$after=(Get-Content -LiteralPath $log -Raw).Substring($before)
if($after -notmatch 'DISABLED unsupported EXE hash'){throw '自加载非游戏EXE未正确拒绝'}
Write-Output 'AUTOLOAD_PASS normal-exe-start winmm-forwarding plugin-auto-loaded unsupported-exe-rejected'
