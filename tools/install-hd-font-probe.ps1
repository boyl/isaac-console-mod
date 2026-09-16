#Requires -Version 7.0
<# 仅安装独立样板，不覆盖正式控制台。默认预览；-Apply 执行。 #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Candidate, [Parameter(Mandatory)][string]$GameDirectory,
      [Parameter(Mandatory)][string]$RecoveryDirectory, [switch]$Apply)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$source = (Resolve-Path -LiteralPath $Candidate).Path
$game = (Resolve-Path -LiteralPath $GameDirectory).Path
if (-not (Test-Path -LiteralPath (Join-Path $game 'isaac-ng.exe') -PathType Leaf)) { throw '不是以撒安装目录' }
$name = 'isaac_console_hd_font_probe'
$target = Join-Path $game ('mods/' + $name)
if ((Test-Path -LiteralPath $target) -and @(Get-ChildItem -LiteralPath $target -Recurse -File -Force).Count) { throw '样板目录包含文件，先用上次清单回退，避免覆盖' }
$spec = Get-Content -LiteralPath ($source + '.manifest.json') -Raw | ConvertFrom-Json
if ($spec.schemaVersion -ne 1 -or $spec.purpose -ne 'local-font-visual-gate-only') { throw '候选身份不符' }
foreach ($entry in $spec.files) {
    if ([IO.Path]::IsPathRooted($entry.path) -or $entry.path.Contains(':') -or $entry.path -match '(^|[/\\])\.\.([/\\]|$)') { throw '候选包含非法路径' }
    if ((Get-FileHash -LiteralPath (Join-Path $source $entry.path)).Hash -ne $entry.sha256) { throw "候选文件被修改：$($entry.path)" }
}
[xml]$xml = Get-Content -LiteralPath (Join-Path $source 'metadata.xml') -Raw
if ($xml.metadata.name -ne 'Isaac Console HD Font Probe' -or $xml.metadata.directory -ne $name -or [string]$xml.metadata.id -ne '') { throw '样板 metadata 身份不符' }
Write-Output "独立样板目标：$target；文件数：$($spec.files.Count)；正式控制台保持不变"
if (-not $Apply) { Write-Output 'PREVIEW：未修改文件'; exit 0 }
if (Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue) { throw '安装样板前请正常退出以撒' }
if (Test-Path -LiteralPath $RecoveryDirectory) { throw '恢复目录必须是新目录' }
# 目标父目录不允许链接，避免操作超出真实游戏目录。
$cursor = Join-Path $game 'mods'
while ($cursor) {
    if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "目标路径含链接：$cursor" }
    $cursor = Split-Path $cursor -Parent
}
New-Item -ItemType Directory -Path $RecoveryDirectory -Force | Out-Null
$rollback = @{schemaVersion=1;target=$target;name='Isaac Console HD Font Probe';directory=$name;workshopId='';files=@(
    $spec.files | ForEach-Object { @{path=$_.path;beforeHash=$null;afterHash=$_.sha256} }
)}
$rollback | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $RecoveryDirectory 'rollback.json') -Encoding utf8NoBOM
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'restore-hd-menu.ps1') -Destination $RecoveryDirectory
$written = [Collections.Generic.List[object]]::new()
try {
    foreach ($entry in $spec.files) {
        $dest = Join-Path $target $entry.path
        if (Test-Path -LiteralPath $dest) { throw '目标被并发创建，停止' }
        if ((Get-FileHash -LiteralPath (Join-Path $source $entry.path)).Hash -ne $entry.sha256) { throw '源资源发生变化' }
        New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
        $written.Add(@{path=$dest;hash=$entry.sha256})
        Copy-Item -LiteralPath (Join-Path $source $entry.path) -Destination $dest
        if ((Get-FileHash -LiteralPath $dest).Hash -ne $entry.sha256) { throw "写入验证失败：$($entry.path)" }
    }
} catch {
    foreach ($item in $written) {
        if ((Test-Path -LiteralPath $item.path -PathType Leaf) -and (Get-FileHash -LiteralPath $item.path).Hash -eq $item.hash) {
            Remove-Item -LiteralPath $item.path -Force
        }
    }
    throw
}
Write-Output 'PASS：样板安装及哈希验证完成；安全房间按 F8 显示。'
