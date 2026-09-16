#Requires -Version 7.0
<#
按候选安装清单回退。默认仅预览；-Apply 执行。只接收已审计的本地清单。
恢复过程中不修改任何 SaveData；manifest 所在目录的 before/ 保存原文件。
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Manifest, [switch]$Apply)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-SafeFile([string]$Root, [string]$Relative) {
    if ([IO.Path]::IsPathRooted($Relative) -or $Relative.Contains(':')) { throw "非法相对路径：$Relative" }
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $file = [IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (-not $file.StartsWith($base + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw "路径超出目标：$Relative" }
    $cursor = $file
    while ($cursor) {
        if ((Test-Path -LiteralPath $cursor) -and ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "路径包含链接：$cursor" }
        $cursor = Split-Path $cursor -Parent
    }
    return $file
}
function Get-HashOrNull([string]$Path) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
    if (Test-Path -LiteralPath $Path) { throw "文件路径被目录占用：$Path" }
    return $null
}

$manifestPath = (Resolve-Path -LiteralPath $Manifest).Path
$bundle = Split-Path $manifestPath -Parent
$spec = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($spec.schemaVersion -ne 1 -or -not $spec.files.Count) { throw '安装清单版本不支持或文件为空' }
$target = [IO.Path]::GetFullPath($spec.target)
$targetDirectory = if ($spec.PSObject.Properties.Name -contains 'targetDirectory') { $spec.targetDirectory } else { $spec.directory }
if ((Split-Path $target -Leaf) -ne $targetDirectory) { throw '目标目录身份不匹配' }
$metadata = Resolve-SafeFile $target 'metadata.xml'
$plan = @()
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$drift = [Collections.Generic.List[string]]::new()
foreach ($entry in $spec.files) {
    if (-not $seen.Add($entry.path)) { throw "重复文件：$($entry.path)" }
    if ($entry.path -match '(^|[/\\])(save[^/\\]*\.dat|data|\.git)([/\\]|$)') { throw '回退清单不得包含存档或 Git 数据' }
    $dest = Resolve-SafeFile $target $entry.path
    $source = Resolve-SafeFile (Join-Path $bundle 'before') $entry.path
    if ($entry.beforeHash -and (Get-HashOrNull $source) -ne $entry.beforeHash) { throw "备份校验失败：$($entry.path)" }
    $current = Get-HashOrNull $dest
    if ($current -ne $entry.afterHash -and $current -ne $entry.beforeHash) { $drift.Add($entry.path) }
    $plan += [pscustomobject]@{ Name=$entry.path; Target=$dest; Source=$source; Before=$entry.beforeHash; After=$entry.afterHash; Current=$current }
}
if ($drift.Count) { throw ('安装后文件被修改，已停止：' + ($drift -join ', ')) }
if ($plan.Where({$_.Current -ne $_.Before}).Count -eq 0) { Write-Output 'PASS：已经处于备份状态，无需回退'; exit 0 }
$progressPath = Join-Path $bundle 'restore-progress.json'
$manifestHash = (Get-FileHash -LiteralPath $manifestPath).Hash
$restoredPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
if (Test-Path -LiteralPath $progressPath) {
    $progress = Get-Content -LiteralPath $progressPath -Raw | ConvertFrom-Json
    if ($progress.manifestHash -ne $manifestHash) { throw '恢复进度与当前清单不匹配' }
    foreach ($name in $progress.paths) { [void]$restoredPaths.Add($name) }
}
# 首次恢复要求完整候选哈希；只有本工具记录过的恢复步骤才允许处于旧状态。
foreach ($item in $plan) {
    if ($item.Current -ne $item.After -and -not $restoredPaths.Contains($item.Name)) { $drift.Add($item.Name) }
}
if ($drift.Count) { throw ('候选文件已被修改或移除，已停止：' + ($drift -join ', ')) }
if (-not (Test-Path -LiteralPath $metadata -PathType Leaf)) { throw '目标 Mod 缺少 metadata.xml' }
[xml]$xml = Get-Content -LiteralPath $metadata -Raw
if ($xml.metadata.name -ne $spec.name -or $xml.metadata.directory -ne $spec.directory -or [string]$xml.metadata.id -ne [string]$spec.workshopId) { throw '目标 Mod 身份校验失败' }
$plan | ForEach-Object { '{0} {1}' -f $(if($_.Current -eq $_.Before){'保留'}elseif($_.Before){'恢复'}else{'移除新增'}), $_.Name }
if (-not $Apply) { Write-Output 'PREVIEW：未修改文件。确认清单后加 -Apply 执行。'; exit 0 }
if (Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue) { throw '请先正常退出以撒，再执行回退' }

# 先验证写权限，再保存候选现场。恢复失败时保留可重试的清单状态。
foreach ($item in $plan.Where({$_.Current -ne $_.Before})) {
    if ($item.Current) {
        $stream = [IO.File]::Open($item.Target, 'Open', 'Write', 'Read')
        $stream.Dispose()
    }
}
$recovery = Join-Path $bundle ('rollback-attempt-' + [guid]::NewGuid().ToString('N'))
foreach ($item in $plan.Where({$_.Current -ne $_.Before})) {
    if ($item.Current) {
        $copy = Resolve-SafeFile $recovery $item.Name
        New-Item -ItemType Directory -Path (Split-Path $copy -Parent) -Force | Out-Null
        Copy-Item -LiteralPath $item.Target -Destination $copy
        if ((Get-HashOrNull $copy) -ne $item.Current) { throw '候选现场备份失败，尚未开始回退' }
    }
}
foreach ($item in $plan.Where({$_.Current -ne $_.Before})) {
    if (Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue) { throw '游戏已启动，暂停回退；退出后可重新执行' }
    if ((Get-HashOrNull $item.Target) -ne $item.Current) { throw "回退期间文件发生变化：$($item.Name)" }
    [void]$restoredPaths.Add($item.Name)
    @{manifestHash=$manifestHash;paths=@($restoredPaths)} | ConvertTo-Json -Depth 3 |
        Set-Content -LiteralPath $progressPath -Encoding utf8NoBOM
    if ($item.Before) {
        if ((Get-HashOrNull $item.Source) -ne $item.Before) { throw '备份内容发生变化' }
        Copy-Item -LiteralPath $item.Source -Destination $item.Target -Force
    } else {
        Remove-Item -LiteralPath $item.Target -Force
    }
    if ((Get-HashOrNull $item.Target) -ne $item.Before) { throw "恢复后校验失败：$($item.Name)" }
}
foreach ($item in $plan) {
    if ((Get-HashOrNull $item.Target) -ne $item.Before) { throw "最终校验失败：$($item.Name)" }
}
Write-Output 'PASS：回退完成，文件哈希与备份一致；存档和游戏配置未修改。'
