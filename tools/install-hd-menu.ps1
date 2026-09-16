#requires -Version 7.0
<# 本地测试安装；默认预览。保留既有文件与 SaveData，逐文件保存本次回退信息。 #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate,
      [Parameter(Mandatory)][string]$Target,
      [Parameter(Mandatory)][string]$Baseline,
      [Parameter(Mandatory)][ValidateSet('installed-zh','installed-en')][string]$BaselineSet,
      [Parameter(Mandatory)][string]$RecoveryDirectory,
      [switch]$Apply)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $Candidate).Path
$targetRoot = (Resolve-Path -LiteralPath $Target).Path
$game = Split-Path (Split-Path $targetRoot -Parent) -Parent
if (-not (Test-Path -LiteralPath (Join-Path $game 'isaac-ng.exe'))) { throw '目标不在以撒 mods 目录中' }
if ((Split-Path (Split-Path $targetRoot -Parent) -Leaf) -ne 'mods') { throw '目标父目录必须是 mods' }
[xml]$current = Get-Content -LiteralPath (Join-Path $targetRoot 'metadata.xml') -Raw
[xml]$next = Get-Content -LiteralPath (Join-Path $source 'metadata.xml') -Raw
foreach ($field in @('name','directory','id')) {
    if ([string]$current.metadata.$field -ne [string]$next.metadata.$field) { throw "候选 Mod 身份不同：$field" }
}
$baselinePath = (Resolve-Path -LiteralPath $Baseline).Path
$baseRoot = Split-Path $baselinePath -Parent
$base = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
$set = @($base.sets | Where-Object name -eq $BaselineSet)
if ($set.Count -ne 1 -or [IO.Path]::GetFullPath($set[0].path) -ne $targetRoot) { throw '基线目标不匹配' }
$known = @{}
foreach ($file in @($base.files | Where-Object set -eq $BaselineSet)) { $known[$file.path.Replace('\','/')] = $file }
$files = @()
foreach ($file in Get-ChildItem -LiteralPath $source -Recurse -File) {
    $relative = [IO.Path]::GetRelativePath($source, $file.FullName).Replace('\','/')
    if ($relative -match '(^|/)(save[^/]*\.dat|data|\.git)(/|$)') { throw '候选包含存档或开发数据' }
    $dest = Join-Path $targetRoot $relative
    $cursor = $dest
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "目标包含链接：$cursor" }
        $cursor = Split-Path $cursor -Parent
    }
    $after = (Get-FileHash -LiteralPath $file.FullName).Hash
    $before = if (Test-Path -LiteralPath $dest -PathType Leaf) { (Get-FileHash -LiteralPath $dest).Hash } else { $null }
    if ($before -eq $after) { continue }
    if ($known.ContainsKey($relative)) {
        $backupFile = Join-Path (Join-Path $baseRoot $BaselineSet) $relative
        $backupHash = (Get-FileHash -LiteralPath $backupFile).Hash
        if ($before -ne $backupHash -or $backupHash -ne $known[$relative].sha256) { throw "基线后文件发生变化：$relative" }
    } elseif ($before) { throw "新增文件已被占用：$relative" }
    $files += [pscustomobject]@{path=$relative;beforeHash=$before;afterHash=$after}
}
Write-Output "LOCAL TEST ONLY：$targetRoot；将变更 $($files.Count) 个文件，保留其他文件与存档。"
if (-not $Apply) { $files | Select-Object path,beforeHash,afterHash; Write-Output 'PREVIEW：未修改文件'; exit 0 }
if (Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue) { throw '安装前请正常退出以撒' }
if (Test-Path -LiteralPath $RecoveryDirectory) { throw '恢复目录必须是新目录' }
New-Item -ItemType Directory -Path $RecoveryDirectory | Out-Null
foreach ($file in $files) {
    if ($file.beforeHash) {
        $backup = Join-Path (Join-Path $RecoveryDirectory 'before') $file.path
        New-Item -ItemType Directory -Path (Split-Path $backup -Parent) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $targetRoot $file.path) -Destination $backup
        if ((Get-FileHash -LiteralPath $backup).Hash -ne $file.beforeHash) { throw '安装前备份失败，未开始安装' }
    }
}
$manifest = @{schemaVersion=1;target=$targetRoot;targetDirectory=(Split-Path $targetRoot -Leaf);
    name=[string]$current.metadata.name;directory=[string]$current.metadata.directory;
    workshopId=[string]$current.metadata.id;files=$files}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $RecoveryDirectory 'rollback.json') -Encoding utf8NoBOM
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'restore-hd-menu.ps1') -Destination $RecoveryDirectory
foreach ($file in $files) {
    if (Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue) { throw '游戏已启动，停止安装；保留恢复清单' }
    $dest = Join-Path $targetRoot $file.path
    $now = if (Test-Path -LiteralPath $dest) { (Get-FileHash -LiteralPath $dest).Hash } else { $null }
    if ($now -ne $file.beforeHash) { throw "安装期间目标变化：$($file.path)" }
    $from = Join-Path $source $file.path
    if ((Get-FileHash -LiteralPath $from).Hash -ne $file.afterHash) { throw '候选发生变化' }
    New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
    Copy-Item -LiteralPath $from -Destination $dest -Force
    if ((Get-FileHash -LiteralPath $dest).Hash -ne $file.afterHash) { throw "写入验证失败：$($file.path)" }
}
Write-Output "PASS：测试版安装完成；回退清单 $RecoveryDirectory/rollback.json"
