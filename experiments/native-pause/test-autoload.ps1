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
foreach($expected in @('EXE path=', 'sha256=[A-F0-9]{64}', 'UNKNOWN_HASH compatibility_probe', 'candidate="Repentance\+ J460"', 'candidate="Repentance 1.7.9b"', 'check=paused', 'DISABLED no_compatible_runtime')) {
    if($after -notmatch $expected){throw "自加载诊断缺失：$expected`n$after"}
}
if($after -match 'DISABLED unsupported EXE hash'){throw '未知哈希仍被直接拒绝'}
Write-Output 'AUTOLOAD_PASS normal-exe-start winmm-forwarding unknown-hash-probed incompatible-target-diagnosed'
$lock=[IO.File]::Open($log,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
try {
    $target=Start-Process -FilePath (Join-Path $root 'autoload-target.exe') -ArgumentList ('"'+(Join-Path $GameDirectory 'Lua5.3.3r.dll')+'"') -WorkingDirectory $root -WindowStyle Hidden -PassThru
    if(-not $target.WaitForExit(15000)){Stop-Process -Id $target.Id;throw '日志回退测试进程超时'}
    if($target.ExitCode -ne 0){throw "日志回退测试异常：$($target.ExitCode)"}
    $fallback=Join-Path ([IO.Path]::GetTempPath()) "IsaacConsoleNativePause-$($target.Id).log"
    $fallbackText=Get-Content -LiteralPath $fallback -Raw
    foreach($expected in @('LOG_FALLBACK', 'EXE sha256=[A-F0-9]{64}', 'DISABLED no_compatible_runtime')) {
        if($fallbackText -notmatch $expected){throw "日志回退缺少诊断：$expected"}
    }
    Copy-Item -LiteralPath $fallback -Destination (Join-Path $BuildDirectory 'fallback-log-evidence.log') -Force
    Remove-Item -LiteralPath $fallback
    Write-Output 'LOG_FALLBACK_PASS locked-primary-log temp-log-contains-reason'
} finally {$lock.Dispose()}
