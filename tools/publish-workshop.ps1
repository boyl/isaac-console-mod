[CmdletBinding()]
param(
    [ValidateSet('zh', 'en')][string[]]$Language = @('zh', 'en'),
    [switch]$Publish, [switch]$SkipTests,
    [string]$ChineseChangeNotes = '', [string]$EnglishChangeNotes = '',
    [string]$UploaderPath = '', [string]$Proxy = 'http://127.0.0.1:7897',
    [ValidateRange(30, 300)][int]$UploadTimeoutSeconds = 150,
    [string]$ToolkitRoot = ''
)
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
if($PSVersionTable.PSVersion.Major -lt 7){throw 'publish-workshop.ps1 必须使用 PowerShell 7 或更高版本运行。'}

function Find-GameModdingToolkitRoot {
    if($ToolkitRoot){return (Resolve-Path -LiteralPath $ToolkitRoot -ErrorAction Stop).Path}
    if($env:GAME_MODDING_TOOLKIT_ROOT){return (Resolve-Path -LiteralPath $env:GAME_MODDING_TOOLKIT_ROOT -ErrorAction Stop).Path}
    $documents=[Environment]::GetFolderPath('MyDocuments')
    $moduleRoot=Join-Path $documents 'PowerShell\Modules\GameModdingToolkit'
    if(Test-Path -LiteralPath $moduleRoot -PathType Container){
        $installed=Get-ChildItem -LiteralPath $moduleRoot -Directory | Sort-Object {try{[version]$_.Name}catch{[version]'0.0.0'}} -Descending | Select-Object -First 1
        if($installed){return $installed.FullName}
    }
    $repositoryRoot=Split-Path $PSScriptRoot -Parent
    foreach($candidate in @(
        (Join-Path (Split-Path $repositoryRoot -Parent) 'game-modding-toolkit'),
        (Join-Path (Split-Path (Split-Path $repositoryRoot -Parent) -Parent) 'GitHub\game-modding-toolkit'),
        (Join-Path $documents 'GitHub\game-modding-toolkit')
    )){if(Test-Path -LiteralPath $candidate -PathType Container){return [IO.Path]::GetFullPath($candidate)}}
    throw '找不到 game-modding-toolkit。请通过 -ToolkitRoot、GAME_MODDING_TOOLKIT_ROOT 或当前用户安装提供工具；发布尚未开始。'
}

$root=Find-GameModdingToolkitRoot
$entry=Join-Path $root 'capabilities\publishing\steam-workshop\Invoke-WorkshopRelease.ps1'
if(-not (Test-Path -LiteralPath $entry -PathType Leaf)){throw "工具入口不存在：$entry"}
$arguments=@{ProjectProfile=(Join-Path $PSScriptRoot 'workshop-release-profile.json');Variant=$Language}
if($Proxy){$arguments.Proxy=[uri]$Proxy}; if($SkipTests){$arguments.SkipVerify=$true}; if($UploaderPath){$arguments.UploaderPath=$UploaderPath}; $arguments.UploadTimeoutSeconds=$UploadTimeoutSeconds
if($Publish){
    if(($Language -contains 'zh') -and [string]::IsNullOrWhiteSpace($ChineseChangeNotes)){throw '发布中文时必须提供 -ChineseChangeNotes。'}
    if(($Language -contains 'en') -and [string]::IsNullOrWhiteSpace($EnglishChangeNotes)){throw '发布英文时必须提供 -EnglishChangeNotes。'}
    $notesPath=Join-Path ([IO.Path]::GetTempPath()) ('isaac-workshop-notes-'+[guid]::NewGuid().ToString('N')+'.json')
    try{
        [ordered]@{zh=$ChineseChangeNotes;en=$EnglishChangeNotes}|ConvertTo-Json|Set-Content -LiteralPath $notesPath -Encoding utf8
        $arguments.Publish=$true; $arguments.ChangeNotesFile=$notesPath
        & $entry @arguments
    }finally{Remove-Item -LiteralPath $notesPath -Force -ErrorAction SilentlyContinue}
}else{& $entry @arguments}
