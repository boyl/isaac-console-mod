[CmdletBinding()]
param(
    [ValidateSet('zh', 'en')]
    [string[]]$Language = @('zh', 'en'),
    [switch]$Publish,
    [switch]$SkipTests,
    [string]$ChineseChangeNotes = '',
    [string]$EnglishChangeNotes = '',
    [string]$UploaderPath = '',
    [string]$Proxy = 'http://127.0.0.1:7897',
    [ValidateRange(30, 300)]
    [int]$UploadTimeoutSeconds = 150
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if ($PSVersionTable.PSVersion.Major -lt 7) {
    throw 'publish-workshop.ps1 必须使用 PowerShell 7 或更高版本运行。'
}

$repositoryRoot = Split-Path $PSScriptRoot -Parent
$gitPath = 'C:\Program Files\Git\cmd\git.exe'
$steamApi = 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/'
$evidenceRoot = Join-Path $repositoryRoot ('dist\workshop-publish\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$script:clipboardBackup = $null
$script:foundWindow = $null

$variants = @{
    zh = [ordered]@{
        Language = 'zh'
        SourceDirectory = 'workshop-mod'
        CandidateDirectory = 'isaac_chinese_console_workshop'
        PublishedFileId = '3776882944'
        ExpectedTitle = 'Isaac Chinese Console'
        DescriptionMarker = '可选 Mod 集成（均非前置）'
        ChangeNotes = $ChineseChangeNotes
    }
    en = [ordered]@{
        Language = 'en'
        SourceDirectory = 'workshop-mod-en'
        CandidateDirectory = 'console_ui_workshop'
        PublishedFileId = '3779128726'
        ExpectedTitle = 'Console UI'
        DescriptionMarker = 'Optional Mod Integrations — Not Required'
        ChangeNotes = $EnglishChangeNotes
    }
}

function Write-Checkpoint {
    param([string]$Name, [string]$Detail = '')
    $suffix = if ($Detail) { " | $Detail" } else { '' }
    Write-Host ('[{0:HH:mm:ss}] {1}{2}' -f (Get-Date), $Name, $suffix)
}

function Invoke-Git {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    if (-not (Test-Path -LiteralPath $gitPath -PathType Leaf)) {
        throw "找不到 Git：$gitPath"
    }
    $output = & $gitPath -C $repositoryRoot @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Git 命令失败：git $($Arguments -join ' ')`n$($output -join "`n")"
    }
    return $output
}

function Assert-CleanPushedHead {
    $status = Invoke-Git status --porcelain
    if ($status) {
        throw "Git 工作树不干净，拒绝发布：`n$($status -join "`n")"
    }
    $head = (Invoke-Git rev-parse HEAD | Select-Object -First 1).Trim()
    $branch = (Invoke-Git branch --show-current | Select-Object -First 1).Trim()
    if (-not $branch) { throw '当前处于 detached HEAD，拒绝发布。' }
    $remoteArgs = @(
        '-c', "http.proxy=$Proxy",
        '-c', 'http.sslBackend=openssl',
        '-c', 'http.sslCAInfo=C:/Program Files/Git/mingw64/etc/ssl/certs/ca-bundle.crt',
        'ls-remote', 'origin', "refs/heads/$branch"
    )
    $remoteLine = (Invoke-Git @remoteArgs | Select-Object -First 1)
    $remoteHead = if ($remoteLine) { ($remoteLine -split "`t")[0] } else { '' }
    if ($remoteHead -ne $head) {
        throw "本地 HEAD 尚未与 origin/$branch 同步：local=$head remote=$remoteHead"
    }
    return [ordered]@{ Head = $head; Branch = $branch }
}

function Get-WorkshopDetails {
    param([string]$PublishedFileId)
    $response = Invoke-RestMethod -Method Post -Uri $steamApi -Proxy $Proxy -TimeoutSec 20 `
        -Body "itemcount=1&publishedfileids[0]=$PublishedFileId"
    $details = $response.response.publishedfiledetails | Select-Object -First 1
    if (-not $details -or $details.result -ne 1) {
        throw "Steam API 未返回有效项目：$PublishedFileId"
    }
    return $details
}

function Get-RemotePreview {
    param([object]$Details, [string]$TargetPath)
    Invoke-WebRequest -Uri $Details.preview_url -Proxy $Proxy -TimeoutSec 30 -OutFile $TargetPath
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $TargetPath).Hash
}

function Get-MetadataFacts {
    param([System.Collections.IDictionary]$Variant)
    $sourceRoot = Join-Path $repositoryRoot $Variant.SourceDirectory
    $candidateRoot = Join-Path $repositoryRoot ('dist\workshop-candidates\' + $Variant.CandidateDirectory)
    $metadataPath = Join-Path $candidateRoot 'metadata.xml'
    $previewPath = Join-Path $candidateRoot 'preview.png'
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) { throw "缺少候选 metadata：$metadataPath" }
    if (-not (Test-Path -LiteralPath $previewPath -PathType Leaf)) { throw "缺少候选预览图：$previewPath" }
    [xml]$metadata = Get-Content -Raw -LiteralPath $metadataPath
    $id = [string]$metadata.metadata.id
    if ($id -ne $Variant.PublishedFileId) {
        throw "Workshop ID 不匹配：expected=$($Variant.PublishedFileId) actual=$id"
    }
    return [ordered]@{
        SourceRoot = $sourceRoot
        CandidateRoot = $candidateRoot
        MetadataPath = $metadataPath
        PreviewPath = $previewPath
        Name = [string]$metadata.metadata.name
        Version = [string]$metadata.metadata.version
        PreviewSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $previewPath).Hash
    }
}

function Resolve-UploaderPath {
    if ($UploaderPath) {
        $resolved = (Resolve-Path -LiteralPath $UploaderPath -ErrorAction Stop).Path
        if ([IO.Path]::GetFileName($resolved) -ne 'ModUploader.exe') { throw "不是 ModUploader.exe：$resolved" }
        return $resolved
    }
    $roots = New-Object Collections.Generic.List[string]
    $steam = Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue
    if ($steam.SteamPath) { $roots.Add(($steam.SteamPath -replace '/', '\')) }
    $libraryFiles = @($roots | ForEach-Object { Join-Path $_ 'steamapps\libraryfolders.vdf' })
    foreach ($file in $libraryFiles) {
        if (-not (Test-Path -LiteralPath $file)) { continue }
        foreach ($match in [regex]::Matches((Get-Content -Raw -LiteralPath $file), '"path"\s+"([^"]+)"')) {
            $root = $match.Groups[1].Value -replace '\\\\', '\'
            if (-not $roots.Contains($root)) { $roots.Add($root) }
        }
    }
    foreach ($root in $roots) {
        $gameRoot = Join-Path $root 'steamapps\common\The Binding of Isaac Rebirth'
        if (-not (Test-Path -LiteralPath $gameRoot -PathType Container)) { continue }
        $found = Get-ChildItem -LiteralPath $gameRoot -Filter ModUploader.exe -File -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }
    throw '找不到 ModUploader.exe，请通过 -UploaderPath 指定。'
}

function Initialize-WindowAutomation {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    if ('WorkshopWindow' -as [type]) { return }
    Add-Type @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class WorkshopWindow {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
    [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int command);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    public static void Click(int x, int y) {
        SetCursorPos(x, y); mouse_event(2, 0, 0, 0, UIntPtr.Zero); mouse_event(4, 0, 0, 0, UIntPtr.Zero);
    }
}
'@
    [WorkshopWindow]::SetProcessDPIAware() | Out-Null
}

function Find-Window {
    param([int]$ProcessId, [string]$ExactTitle)
    $script:foundWindow = $null
    $result = [IntPtr]::Zero
    [WorkshopWindow]::EnumWindows({
        param($hwnd, $unused)
        if (-not [WorkshopWindow]::IsWindowVisible($hwnd)) { return $true }
        $owner = 0
        [WorkshopWindow]::GetWindowThreadProcessId($hwnd, [ref]$owner) | Out-Null
        if ($owner -ne $ProcessId) { return $true }
        $text = New-Object Text.StringBuilder 512
        [WorkshopWindow]::GetWindowText($hwnd, $text, 512) | Out-Null
        if ($text.ToString() -eq $ExactTitle) { $script:foundWindow = $hwnd }
        return $true
    }, [IntPtr]::Zero) | Out-Null
    if ($script:foundWindow) {
        $result = $script:foundWindow
        $script:foundWindow = $null
    }
    return $result
}

function Wait-Window {
    param([int]$ProcessId, [string]$ExactTitle, [int]$TimeoutSeconds = 15, [switch]$Disappear)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $window = Find-Window -ProcessId $ProcessId -ExactTitle $ExactTitle
        if ($Disappear) {
            if ($window -eq [IntPtr]::Zero) { return [IntPtr]::Zero }
        } elseif ($window -ne [IntPtr]::Zero) {
            return $window
        }
        Start-Sleep -Milliseconds 150
    } while ((Get-Date) -lt $deadline)
    $verb = if ($Disappear) { '消失' } else { '出现' }
    throw "等待窗口$verb超时：$ExactTitle"
}

function Focus-VerifiedWindow {
    param([int]$ProcessId, [string]$ExactTitle)
    $window = Wait-Window -ProcessId $ProcessId -ExactTitle $ExactTitle
    [WorkshopWindow]::ShowWindow($window, 9) | Out-Null
    [WorkshopWindow]::BringWindowToTop($window) | Out-Null
    [WorkshopWindow]::SetForegroundWindow($window) | Out-Null
    $deadline = (Get-Date).AddSeconds(3)
    while ([WorkshopWindow]::GetForegroundWindow() -ne $window -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 100
        [WorkshopWindow]::SetForegroundWindow($window) | Out-Null
    }
    if ([WorkshopWindow]::GetForegroundWindow() -ne $window) {
        throw "无法取得窗口焦点：$ExactTitle"
    }
    return $window
}

function Get-WindowRectObject {
    param([IntPtr]$Window)
    $rect = New-Object WorkshopWindow+RECT
    if (-not [WorkshopWindow]::GetWindowRect($Window, [ref]$rect)) { throw '读取窗口矩形失败。' }
    return [ordered]@{ Left=$rect.Left; Top=$rect.Top; Width=$rect.Right-$rect.Left; Height=$rect.Bottom-$rect.Top }
}

function Click-Relative {
    param([IntPtr]$Window, [double]$X, [double]$Y)
    $rect = Get-WindowRectObject $Window
    [WorkshopWindow]::Click([int]($rect.Left + $rect.Width * $X), [int]($rect.Top + $rect.Height * $Y))
}

function Save-WindowEvidence {
    param([IntPtr]$Window, [string]$Name)
    $rect = Get-WindowRectObject $Window
    $bitmap = New-Object Drawing.Bitmap $rect.Width, $rect.Height
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, $bitmap.Size)
    $path = Join-Path $evidenceRoot ($Name + '.png')
    $bitmap.Save($path)
    $graphics.Dispose(); $bitmap.Dispose()
    return $path
}

function Submit-FileDialog {
    param([int]$ProcessId, [string]$DialogTitle, [string]$FilePath)
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { throw "待选择文件不存在：$FilePath" }
    $dialog = Focus-VerifiedWindow -ProcessId $ProcessId -ExactTitle $DialogTitle
    $shell = New-Object -ComObject WScript.Shell
    $previous = [Windows.Forms.Clipboard]::GetText()
    try {
        $shell.SendKeys('%n'); Start-Sleep -Milliseconds 250
        [Windows.Forms.Clipboard]::SetText($FilePath)
        $shell.SendKeys('^a'); $shell.SendKeys('^v'); Start-Sleep -Milliseconds 750
        Save-WindowEvidence -Window $dialog -Name ("dialog-" + ($DialogTitle -replace '\W+', '-')) | Out-Null
        $shell.SendKeys('{ENTER}')
        Wait-Window -ProcessId $ProcessId -ExactTitle $DialogTitle -TimeoutSeconds 15 -Disappear | Out-Null
    } finally {
        if ($previous) { [Windows.Forms.Clipboard]::SetText($previous) } else { [Windows.Forms.Clipboard]::Clear() }
    }
}

function Set-TextByClipboard {
    param([string]$Text)
    $shell = New-Object -ComObject WScript.Shell
    $previous = [Windows.Forms.Clipboard]::GetText()
    try {
        [Windows.Forms.Clipboard]::SetText($Text)
        $shell.SendKeys('^a'); $shell.SendKeys('^v'); Start-Sleep -Milliseconds 500
    } finally {
        if ($previous) { [Windows.Forms.Clipboard]::SetText($previous) } else { [Windows.Forms.Clipboard]::Clear() }
    }
}

function Start-Uploader {
    param([string]$Path)
    $existing = Get-Process ModUploader -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($existing) { $process = $existing } else { $process = Start-Process -FilePath $Path -PassThru }
    Wait-Window -ProcessId $process.Id -ExactTitle 'The Binding of Isaac: Afterbirth+ Mod Uploader' -TimeoutSeconds 20 | Out-Null
    return $process
}

function Load-UploaderProject {
    param([Diagnostics.Process]$Process, [System.Collections.IDictionary]$Facts, [string]$LanguageCode)
    $title = 'The Binding of Isaac: Afterbirth+ Mod Uploader'
    $main = Focus-VerifiedWindow -ProcessId $Process.Id -ExactTitle $title
    Click-Relative -Window $main -X 0.09 -Y 0.16
    Wait-Window -ProcessId $Process.Id -ExactTitle 'Choose Metadata' -TimeoutSeconds 10 | Out-Null
    Submit-FileDialog -ProcessId $Process.Id -DialogTitle 'Choose Metadata' -FilePath $Facts.MetadataPath
    $main = Focus-VerifiedWindow -ProcessId $Process.Id -ExactTitle $title
    Start-Sleep -Seconds 1
    Save-WindowEvidence -Window $main -Name "$LanguageCode-metadata-loaded" | Out-Null
    Click-Relative -Window $main -X 0.39 -Y 0.55
    Wait-Window -ProcessId $Process.Id -ExactTitle 'Choose Preview' -TimeoutSeconds 10 | Out-Null
    Submit-FileDialog -ProcessId $Process.Id -DialogTitle 'Choose Preview' -FilePath $Facts.RemotePreviewPath
    $main = Focus-VerifiedWindow -ProcessId $Process.Id -ExactTitle $title
    Start-Sleep -Seconds 1
    Save-WindowEvidence -Window $main -Name "$LanguageCode-preview-loaded" | Out-Null
}

function Invoke-UploaderUploadOnce {
    param(
        [Diagnostics.Process]$Process,
        [System.Collections.IDictionary]$Variant,
        [System.Collections.IDictionary]$Facts,
        [object]$Before
    )
    $title = 'The Binding of Isaac: Afterbirth+ Mod Uploader'
    $main = Focus-VerifiedWindow -ProcessId $Process.Id -ExactTitle $title
    Click-Relative -Window $main -X 0.70 -Y 0.12
    Set-TextByClipboard -Text $Variant.ChangeNotes
    $main = Focus-VerifiedWindow -ProcessId $Process.Id -ExactTitle $title
    Save-WindowEvidence -Window $main -Name "$($Variant.Language)-before-upload" | Out-Null
    Click-Relative -Window $main -X 0.26 -Y 0.16
    Write-Checkpoint "$($Variant.Language) 上传按钮已点击一次" '之后只轮询远端，不重复点击'
    $deadline = (Get-Date).AddSeconds($UploadTimeoutSeconds)
    do {
        Start-Sleep -Seconds 2
        try { $after = Get-WorkshopDetails -PublishedFileId $Variant.PublishedFileId } catch { continue }
        if ([long]$after.time_updated -gt [long]$Before.time_updated) { return $after }
    } while ((Get-Date) -lt $deadline)
    $main = Focus-VerifiedWindow -ProcessId $Process.Id -ExactTitle $title
    $evidence = Save-WindowEvidence -Window $main -Name "$($Variant.Language)-upload-timeout"
    throw "上传后远端更新时间未变化；没有重复点击上传。证据：$evidence"
}

function Assert-RemoteResult {
    param(
        [System.Collections.IDictionary]$Variant,
        [System.Collections.IDictionary]$Facts,
        [object]$Details
    )
    if ($Details.title -ne $Variant.ExpectedTitle) {
        throw "远端标题不匹配：expected=$($Variant.ExpectedTitle) actual=$($Details.title)"
    }
    if ([string]$Details.description -notlike ('*' + $Variant.DescriptionMarker + '*')) {
        throw "远端描述缺少标记：$($Variant.DescriptionMarker)"
    }
    $remotePath = Join-Path $evidenceRoot "$($Variant.Language)-preview-after.png"
    $remoteHash = Get-RemotePreview -Details $Details -TargetPath $remotePath
    if ($remoteHash -ne $Facts.RemotePreviewSha256) {
        throw "远端预览图被改变：before=$($Facts.RemotePreviewSha256) after=$remoteHash"
    }
    return $remoteHash
}

New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
Write-Checkpoint '发布预检开始' "languages=$($Language -join ',') publish=$Publish"
$gitFacts = Assert-CleanPushedHead
if (-not $SkipTests) {
    & (Join-Path $PSScriptRoot 'verify-workshop-candidates.ps1')
    if ($LASTEXITCODE -ne 0) { throw "双语候选门禁失败：$LASTEXITCODE" }
} else {
    foreach ($code in $Language) { & (Join-Path $PSScriptRoot 'build-workshop-mod.ps1') -Language $code }
}

$releaseFacts = [ordered]@{}
foreach ($code in $Language) {
    $variant = $variants[$code]
    if ($Publish -and [string]::IsNullOrWhiteSpace($variant.ChangeNotes)) {
        throw "发布 $code 时必须提供对应更新说明。"
    }
    $facts = Get-MetadataFacts -Variant $variant
    $before = Get-WorkshopDetails -PublishedFileId $variant.PublishedFileId
    if ($before.title -ne $variant.ExpectedTitle) {
        throw "Workshop 项目身份不匹配：expected=$($variant.ExpectedTitle) actual=$($before.title)"
    }
    $remotePreviewPath = Join-Path $evidenceRoot "$code-preview-before.png"
    $remoteHash = Get-RemotePreview -Details $before -TargetPath $remotePreviewPath
    if ($remoteHash -ne $facts.PreviewSha256) {
        throw "候选预览图与远端不一致，拒绝自动发布：local=$($facts.PreviewSha256) remote=$remoteHash"
    }
    $facts.RemotePreviewPath = $remotePreviewPath
    $facts.RemotePreviewSha256 = $remoteHash
    $releaseFacts[$code] = [ordered]@{ Variant=$variant; Facts=$facts; Before=$before }
    Write-Checkpoint "$code 预检完成" "id=$($variant.PublishedFileId) version=$($facts.Version) preview=$remoteHash"
}

$manifest = [ordered]@{
    GeneratedAt = (Get-Date).ToString('o')
    Publish = [bool]$Publish
    Git = $gitFacts
    Items = $releaseFacts
}
$manifestPath = Join-Path $evidenceRoot 'release-manifest.json'
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding utf8

if (-not $Publish) {
    Write-Checkpoint '只读预检完成' "manifest=$manifestPath"
    Write-Output 'WORKSHOP_PUBLISH_PREFLIGHT=OK'
    exit 0
}

Initialize-WindowAutomation
$resolvedUploader = Resolve-UploaderPath
$uploader = Start-Uploader -Path $resolvedUploader
try {
    foreach ($code in $Language) {
        $item = $releaseFacts[$code]
        Write-Checkpoint "$code 上传器自动化开始"
        Load-UploaderProject -Process $uploader -Facts $item.Facts -LanguageCode $code
        $after = Invoke-UploaderUploadOnce -Process $uploader -Variant $item.Variant -Facts $item.Facts -Before $item.Before
        $afterHash = Assert-RemoteResult -Variant $item.Variant -Facts $item.Facts -Details $after
        Write-Checkpoint "$code 远端复核完成" "updated=$($after.time_updated) preview=$afterHash"
    }
} finally {
    if ($uploader -and -not $uploader.HasExited) { $uploader.CloseMainWindow() | Out-Null }
    foreach ($code in $Language) { & (Join-Path $PSScriptRoot 'build-workshop-mod.ps1') -Language $code }
}

$finalStatus = Invoke-Git status --porcelain
if ($finalStatus) { throw "发布后源码工作树发生变化：`n$($finalStatus -join "`n")" }
Write-Checkpoint 'Workshop 自动发布完成' "evidence=$evidenceRoot"
Write-Output 'WORKSHOP_PUBLISH=OK'
