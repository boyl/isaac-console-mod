param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('zh', 'en')]
    [string]$Language
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$sourceName = if ($Language -eq 'zh') { 'workshop-mod' } else { 'workshop-mod-en' }
$targetName = if ($Language -eq 'zh') { 'isaac_chinese_console_workshop' } else { 'console_ui_workshop' }
$sourceRoot = Join-Path $repositoryRoot $sourceName
$distRoot = Join-Path $repositoryRoot 'dist\workshop-candidates'
$targetRoot = Join-Path $distRoot $targetName

$commonFiles = @(
    'main.lua',
    'metadata.xml',
    'preview.png',
    'FONT-LICENSE-OFL.txt',
    'THIRD-PARTY-DATA.md',
    'THIRD-PARTY-FONTS.md',
    'resources/font/fusion/10.fnt',
    'resources/font/fusion/10_0.png',
    'resources/font/fusion/12.fnt',
    'resources/font/fusion/12_0.png',
    'resources/font/fusion/12_1.png',
    'resources/gfx/ui/isaac_console_pixel.anm2',
    'resources/gfx/ui/isaac_console_pixel.png',
    'scripts/data.lua',
    'scripts/official_objects.lua'
)

$languageFiles = if ($Language -eq 'zh') {
    @(
        'resources/font/fusion/LICENSE-OFL',
        'resources/font/isaac_console_fusion10.fnt',
        'resources/font/isaac_console_fusion10_0.png',
        'resources/font/isaac_console_fusion12.fnt',
        'resources/font/isaac_console_fusion12_0.png',
        'resources/font/isaac_console_fusion12_1.png',
        'resources/font/isaac_console_zh.fnt',
        'resources/font/isaac_console_zh_0.png',
        'scripts/object_pinyin_aliases.lua',
        'scripts/pinyin_aliases.lua',
        'scripts/search_aliases.lua'
    )
} else {
    @('scripts/english_aliases.lua')
}

$expectedPreview = if ($Language -eq 'zh') {
    'E187031C27C032EB11DBD2943BC75A4067E2FEA250A155B8DB3B08F06CFDB7C9'
} else {
    'D7378BB9951A72EFE3C112F30930719FB734E20D48C16A870E396326770BB26C'
}

$files = $commonFiles + $languageFiles
foreach ($relativePath in $files) {
    $sourcePath = Join-Path $sourceRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "缺少允许列表文件：$sourcePath"
    }
}

$resolvedDist = [IO.Path]::GetFullPath($distRoot)
$resolvedTarget = [IO.Path]::GetFullPath($targetRoot)
if (-not $resolvedTarget.StartsWith($resolvedDist + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "候选目录越过 dist 边界：$resolvedTarget"
}
if (Test-Path -LiteralPath $resolvedTarget) {
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
}

foreach ($relativePath in $files) {
    $destinationPath = Join-Path $resolvedTarget $relativePath
    New-Item -ItemType Directory -Path (Split-Path $destinationPath -Parent) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceRoot $relativePath) -Destination $destinationPath
}

$actualPreview = (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $resolvedTarget 'preview.png')).Hash
if ($actualPreview -ne $expectedPreview) {
    throw "预览图哈希不匹配：expected=$expectedPreview actual=$actualPreview"
}

Write-Output "WORKSHOP_CANDIDATE=$resolvedTarget"
Write-Output "FILE_COUNT=$($files.Count)"
Write-Output "PREVIEW_SHA256=$actualPreview"
