#requires -Version 7.0
param(
    [string]$GameDirectory = (Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/The Binding of Isaac Rebirth'),
    [ValidateSet('zh','en')][string]$Language = 'zh',
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
$gameRoot = (Resolve-Path -LiteralPath $GameDirectory).Path
$exe = Join-Path $gameRoot 'isaac-ng.exe'
$manifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $exe).Hash -ne $manifest.exeSha256) {
    throw '当前 EXE 不是已分析的忏悔+ v1.9.7.17 / J460，未安装或加载原型。'
}
if (Get-Process -Name isaac-ng -ErrorAction SilentlyContinue) { throw '先正常退出以撒，再启动原型。' }
foreach ($file in $manifest.files.PSObject.Properties) {
    if ((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $file.Name)).Hash -ne $file.Value) { throw "实验包校验失败：$($file.Name)" }
}
$id = if ($Language -eq 'zh') { '3776882944' } else { '3779128726' }
$installed = @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'mods') -Directory | Where-Object {
    $meta = Join-Path $_.FullName 'metadata.xml'
    (Test-Path -LiteralPath $meta) -and ((Get-Content -LiteralPath $meta -Raw) -match "<id>$id</id>")
})
if ($installed.Count -ne 1) { throw '未找到唯一的已安装控制台 Mod，未作修改。' }
$main = Join-Path $installed[0].FullName 'main.lua'
$currentHash=(Get-FileHash -LiteralPath $main).Hash
$experimental = Join-Path $PSScriptRoot "$Language-main.lua"
$experimentalHash=(Get-FileHash -LiteralPath $experimental).Hash
$existingReceipt=$null
if($currentHash -eq $experimentalHash) {
    $receiptPath=Join-Path $PSScriptRoot 'active-run.json'
    if(-not (Test-Path -LiteralPath $receiptPath)){throw '已安装暂停菜单但此包没有恢复记录，请从原安装包恢复后再启动。'}
    $existingReceipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if($existingReceipt.main -ne $main -or $existingReceipt.installedHash -ne $experimentalHash -or
       (Get-FileHash -LiteralPath $existingReceipt.backup).Hash -ne $existingReceipt.originalHash) {
        throw '已有恢复记录不匹配。'
    }
} elseif ($currentHash -notin @($manifest.baselines.$Language)) { throw '安装副本与兼容基线不同，未覆盖；需要重新核对版本。' }
if($ValidateOnly){Write-Output "NATIVE_PAUSE_PREFLIGHT_PASS language=$Language"; return}
$runRoot = Join-Path $PSScriptRoot ('runs/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
if($existingReceipt){$backup=$existingReceipt.backup; $originalHash=$existingReceipt.originalHash}
else { $backup=Join-Path $runRoot 'original-main.lua'; Copy-Item -LiteralPath $main -Destination $backup; $originalHash=$currentHash }
if((Get-FileHash -LiteralPath $main).Hash -ne $currentHash){throw '安装文件在预检后变化，停止覆盖。'}
$receipt = [ordered]@{ main=$main; backup=$backup; installedHash=$experimentalHash; originalHash=$originalHash; processId=$null }
try {
    Copy-Item -LiteralPath $experimental -Destination $main
    if((Get-FileHash -LiteralPath $main).Hash -ne $experimentalHash){throw '菜单安装后哈希验证失败。'}
    $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'active-run.json') -Encoding utf8
    Start-Process -FilePath $exe -WorkingDirectory $gameRoot
    $process = $null
    for ($attempt=0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 500
        $matches = @(Get-Process -Name isaac-ng -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe })
        if ($matches.Count -eq 1 -and $matches[0].MainWindowHandle -ne 0) { $process=$matches[0]; break }
    }
    if (-not $process) { throw '游戏窗口未出现。' }
    $receipt.processId=$process.Id
    $receipt | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'active-run.json') -Encoding utf8
    & (Join-Path $PSScriptRoot 'inject.exe') $process.Id (Join-Path $PSScriptRoot 'native-pause.dll')
    if ($LASTEXITCODE -ne 0) { throw "DLL 加载失败：$LASTEXITCODE" }
    $lastEvent = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'native-pause.log') -Tail 1
    if ($lastEvent -notmatch 'LOADED J460 native-pause 0.1.0$') { throw 'DLL 未完成初始化，请退出游戏；安装 main.lua 将恢复。' }
    Write-Output '原生暂停 0.1.0 已加载。进入一局后按原快捷键打开菜单；退出后可运行恢复脚本。'
} catch {
    Copy-Item -LiteralPath $receipt.backup -Destination $main
    if((Get-FileHash -LiteralPath $main).Hash -ne $receipt.originalHash){throw '启动失败且恢复校验失败，请使用 active-run.json 中的备份恢复。'}
    throw
}
