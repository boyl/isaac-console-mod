#requires -Version 7.0
[CmdletBinding()]
param([string]$GameDirectory)
$ErrorActionPreference = 'Stop'
if (-not $GameDirectory) {
    $steamPath = (Get-ItemProperty -LiteralPath 'HKCU:\Software\Valve\Steam').SteamPath
    $libraries = @($steamPath)
    $vdf = Join-Path $steamPath 'steamapps/libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) {
        $libraries += [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"') |
            ForEach-Object { $_.Groups[1].Value.Replace('\\', '\') }
    }
    $gameCandidates = @($libraries | ForEach-Object {
        Join-Path $_ 'steamapps/common/The Binding of Isaac Rebirth'
    } | Where-Object { Test-Path -LiteralPath (Join-Path $_ 'isaac-ng.exe') } |
        ForEach-Object { (Resolve-Path -LiteralPath $_).Path } | Sort-Object -Unique)
    if ($gameCandidates.Count -ne 1) { throw '无法唯一定位以撒，请传入 -GameDirectory。' }
    $GameDirectory = $gameCandidates[0]
}
$gameExe = (Resolve-Path -LiteralPath (Join-Path $GameDirectory 'isaac-ng.exe')).Path
$running = @(Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue)
if ($running.Count) {
    if ($running.Count -ne 1 -or $running[0].Path -ne $gameExe) { throw '已运行的以撒进程与目标不唯一或不匹配。' }
    Write-Output "REUSED: $gameExe"
    exit 0
}
# 用户需要看见和操作的游戏窗口。此入口只负责启动，不注入按键或修改配置。
Start-Process -FilePath $gameExe -WorkingDirectory $GameDirectory | Out-Null
$deadline = [DateTime]::UtcNow.AddSeconds(25)
do {
    Start-Sleep -Milliseconds 500
    # Steam 可能接管启动并替换最初 PID；验证实际目标窗口，不绑定引导进程。
    $gameWindows = @(Get-Process -Name 'isaac-ng' -ErrorAction SilentlyContinue |
        Where-Object { $_.Path -eq $gameExe -and $_.MainWindowHandle -ne 0 })
    if ($gameWindows.Count -gt 1) { throw '出现多个游戏窗口，停止自动启动检查。' }
    if ($gameWindows.Count -eq 1) {
        Write-Output "OPENED: $($gameWindows[0].MainWindowTitle)"
        exit 0
    }
} while ([DateTime]::UtcNow -lt $deadline)
throw '25 秒内没有出现游戏窗口；请检查游戏启动日志。'
