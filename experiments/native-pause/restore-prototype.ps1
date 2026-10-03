#requires -Version 7.0
$ErrorActionPreference = 'Stop'
if (Get-Process -Name isaac-ng -ErrorAction SilentlyContinue) { throw '先正常退出以撒，退出后 DLL 自动卸载。' }
$receiptPath = Join-Path $PSScriptRoot 'active-run.json'
if (-not (Test-Path -LiteralPath $receiptPath)) { Write-Output '没有本实验包的安装记录。'; return }
$receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
$hash = (Get-FileHash -LiteralPath $receipt.main).Hash
if ($hash -eq $receipt.originalHash) { Write-Output '安装副本已经恢复。'; return }
if ($hash -ne $receipt.installedHash) { throw '测试后安装副本发生其他修改，停止自动覆盖；备份路径见 active-run.json。' }
if ((Get-FileHash -LiteralPath $receipt.backup).Hash -ne $receipt.originalHash) { throw '备份校验失败。' }
Copy-Item -LiteralPath $receipt.backup -Destination $receipt.main
if ((Get-FileHash -LiteralPath $receipt.main).Hash -ne $receipt.originalHash) { throw '恢复后校验失败。' }
Write-Output '原安装 main.lua 已恢复；无需删除游戏目录 DLL，本原型没有向游戏目录写入 DLL。'
