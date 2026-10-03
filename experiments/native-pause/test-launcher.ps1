#requires -Version 7.0
param([Parameter(Mandatory)][string]$TestDirectory,[Parameter(Mandatory)][string]$GameDirectory)
$ErrorActionPreference='Stop'
$root=Join-Path $TestDirectory 'launcher-fixture'
$package=Join-Path $root 'package'; $gameRoot=Join-Path $root 'game'; $mod=Join-Path $gameRoot 'mods/console'
New-Item -ItemType Directory -Path $package,$mod -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $GameDirectory 'isaac-ng.exe') -Destination $gameRoot
$main=Join-Path $mod 'main.lua'
Set-Content -LiteralPath (Join-Path $mod 'metadata.xml') -Value '<metadata><id>3776882944</id></metadata>'
[IO.File]::WriteAllText($main,'original-menu')
$originalHash=(Get-FileHash -LiteralPath $main).Hash
[IO.File]::WriteAllText((Join-Path $package 'zh-main.lua'),'pause-menu')
$newHash=(Get-FileHash -LiteralPath (Join-Path $package 'zh-main.lua')).Hash
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-prototype.ps1') -Destination (Join-Path $package 'start.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'restore-prototype.ps1') -Destination (Join-Path $package 'restore.ps1')
$manifest=[ordered]@{exeSha256=(Get-FileHash -LiteralPath (Join-Path $gameRoot 'isaac-ng.exe')).Hash; baselines=@{zh=@($originalHash)}; files=@{'zh-main.lua'=$newHash}}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $package 'manifest.json')
# 只替换进程边界，安装、备份、哈希和恢复执行真实文件操作；不启动游戏。
function Get-Process { param($Name,$ErrorAction) return $null }
function Start-Process { throw 'TEST_START_FAILURE' }
$checks=0
function Assert-Test($ok,$name){if(-not $ok){throw "FAIL $name"}; $script:checks++; Write-Output "PASS $name"}
& (Join-Path $package 'start.ps1') -GameDirectory $gameRoot -ValidateOnly
Assert-Test ((Get-FileHash -LiteralPath $main).Hash -eq $originalHash) 'preflight leaves installed menu unchanged'
try { & (Join-Path $package 'start.ps1') -GameDirectory $gameRoot; throw 'EXPECTED_FAILURE_MISSING' }
catch { if($_.Exception.Message -notmatch 'TEST_START_FAILURE'){throw} }
Assert-Test ((Get-FileHash -LiteralPath $main).Hash -eq $originalHash) 'startup failure restores installed hash'
$receipt=Get-Content -LiteralPath (Join-Path $package 'active-run.json') -Raw | ConvertFrom-Json
Assert-Test ((Get-FileHash -LiteralPath $receipt.backup).Hash -eq $originalHash) 'original backup survives failure'
Copy-Item -LiteralPath (Join-Path $package 'zh-main.lua') -Destination $main
& (Join-Path $package 'start.ps1') -GameDirectory $gameRoot -ValidateOnly
Assert-Test ((Get-FileHash -LiteralPath $main).Hash -eq $newHash) 'repeat startup accepts its own installed version'
try { & (Join-Path $package 'start.ps1') -GameDirectory $gameRoot; throw 'EXPECTED_FAILURE_MISSING' }
catch { if($_.Exception.Message -notmatch 'TEST_START_FAILURE'){throw} }
$again=Get-Content -LiteralPath (Join-Path $package 'active-run.json') -Raw | ConvertFrom-Json
Assert-Test ($again.backup -eq $receipt.backup -and $again.originalHash -eq $originalHash) 'repeat startup preserves original restoration identity'
Copy-Item -LiteralPath (Join-Path $package 'zh-main.lua') -Destination $main
& (Join-Path $package 'restore.ps1')
Assert-Test ((Get-FileHash -LiteralPath $main).Hash -eq $originalHash) 'restore verifies original hash'
[IO.File]::WriteAllText($main,'user-edited-menu')
try { & (Join-Path $package 'start.ps1') -GameDirectory $gameRoot -ValidateOnly; throw 'EXPECTED_FAILURE_MISSING' }
catch { if($_.Exception.Message -notmatch '兼容基线'){throw} }
Assert-Test ((Get-Content -LiteralPath $main -Raw) -eq 'user-edited-menu') 'unknown installed revision is preserved'
try { & (Join-Path $package 'restore.ps1'); throw 'EXPECTED_FAILURE_MISSING' }
catch { if($_.Exception.Message -notmatch '其他修改'){throw} }
Assert-Test ((Get-Content -LiteralPath $main -Raw) -eq 'user-edited-menu') 'restore refuses concurrent user changes'
[IO.File]::WriteAllText((Join-Path $package 'zh-main.lua'),'tampered-payload')
try { & (Join-Path $package 'start.ps1') -GameDirectory $gameRoot -ValidateOnly; throw 'EXPECTED_FAILURE_MISSING' }
catch { if($_.Exception.Message -notmatch '校验失败'){throw} }
Assert-Test ((Get-Content -LiteralPath $main -Raw) -eq 'user-edited-menu') 'tampered payload rejected before install'
Write-Output "LAUNCHER_TRANSACTION_PASS assertions=$checks"
