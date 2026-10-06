#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('inspect', 'fill', 'files', 'images', 'publish')][string]$Step = 'inspect',
    [string]$RepositoryRoot = '',
    [string]$PackageRoot = '',
    [string]$ProfileRoot = '',
    [string]$NodePath = '',
    [string]$BrowserPath = '',
    [int]$Port = 9222,
    [switch]$ConfirmPublish,
    [switch]$CloseBrowser
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'invoke-nexus-upload.ps1 requires PowerShell 7 or later.' }

$repositoryRoot = if ($RepositoryRoot) { (Resolve-Path -LiteralPath $RepositoryRoot).Path } else { (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if (-not $PackageRoot) { $PackageRoot = Join-Path $repositoryRoot 'dist\nexus-packages' }
if (-not $ProfileRoot) { $ProfileRoot = Join-Path $env:LOCALAPPDATA 'dsh\nexus-browser-profile' }
New-Item -ItemType Directory -Path $ProfileRoot -Force | Out-Null

if (-not $NodePath) {
    $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeCommand) { $NodePath = $nodeCommand.Source }
}
if (-not $NodePath -or -not (Test-Path -LiteralPath $NodePath -PathType Leaf)) {
    throw '找不到 node.exe。请通过 -NodePath 传入 Node 22 或更高版本的可执行文件。'
}

function Get-CdpVersion([int]$TargetPort) {
    try {
        return Invoke-RestMethod -Uri "http://127.0.0.1:$TargetPort/json/version" -TimeoutSec 3
    }
    catch {
        return $null
    }
}

if (-not $BrowserPath) {
    foreach ($candidate in @(
            (Join-Path ${env:ProgramFiles} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
            (Join-Path ${env:ProgramFiles} 'Microsoft\Edge\Application\msedge.exe')
        )) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $BrowserPath = $candidate; break }
    }
}

$existing = Get-CdpVersion -TargetPort $Port
$startedBrowser = $false
if ($existing) {
    Write-Output "CDP_REUSED=http://127.0.0.1:$Port ($($existing.Browser))"
    if (-not $BrowserPath) { $BrowserPath = 'unknown' }
}
else {
    if (-not $BrowserPath -or -not (Test-Path -LiteralPath $BrowserPath -PathType Leaf)) {
        throw "端口 $Port 上没有 CDP，且找不到 Chrome/Edge 可执行文件。请通过 -BrowserPath 指定。"
    }
    # A visible window is required: the logged-in Nexus session and any Cloudflare or two-factor
    # challenge are solved by the user, not by the script.
    $browserArguments = @(
        "--remote-debugging-port=$Port",
        "--user-data-dir=`"$ProfileRoot`"",
        '--no-first-run',
        '--no-default-browser-check',
        '--new-window',
        'about:blank'
    )
    Start-Process -FilePath $BrowserPath -ArgumentList $browserArguments | Out-Null
    $startedBrowser = $true
    Write-Output "BROWSER=$BrowserPath"
    Write-Output "PROFILE=$ProfileRoot"
    $deadline = [DateTime]::UtcNow.AddSeconds(45)
    while (-not (Get-CdpVersion -TargetPort $Port)) {
        if ([DateTime]::UtcNow -gt $deadline) { throw "浏览器启动后 45 秒内没有在端口 $Port 提供 CDP。若已有浏览器实例占用该配置目录，请先关闭它。" }
        Start-Sleep -Milliseconds 500
    }
    Write-Output "CDP_STARTED=http://127.0.0.1:$Port"
}

$nodeArguments = @(
    (Join-Path $PSScriptRoot 'nexus-upload.mjs'),
    '--step', $Step,
    '--port', $Port,
    '--repo', $repositoryRoot,
    '--packages', $PackageRoot
)
if ($ConfirmPublish) { $nodeArguments += '--confirm-publish' }
& $NodePath @nodeArguments
if ($LASTEXITCODE -ne 0) {
    Write-Output "NEXUS_UPLOAD_STEP=$Step FAILED (node exit $LASTEXITCODE)；浏览器保持打开，可人工继续。"
    exit $LASTEXITCODE
}

Write-Output "NEXUS_UPLOAD_STEP=$Step OK"
if ($startedBrowser -and $CloseBrowser) {
    Get-Process | Where-Object { $_.Path -eq $BrowserPath } | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Output 'BROWSER_CLOSED=1'
}
