#requires -Version 7.0
param([Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$vswhere=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
$vsRoot=& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $vsRoot) { throw '需要已安装的 MSVC x86 构建工具。' }
$vcRoot=(Get-ChildItem -LiteralPath (Join-Path $vsRoot 'VC/Tools/MSVC') -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
$sdkRoot=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits/10'
$sdkVersion=(Get-ChildItem -LiteralPath (Join-Path $sdkRoot 'Include') -Directory | Sort-Object Name -Descending | Select-Object -First 1).Name
$oldInclude=$env:INCLUDE; $oldLib=$env:LIB
try {
    $env:INCLUDE="$vcRoot\include;$sdkRoot\Include\$sdkVersion\ucrt;$sdkRoot\Include\$sdkVersion\shared;$sdkRoot\Include\$sdkVersion\um"
    $env:LIB="$vcRoot\lib\x86;$sdkRoot\Lib\$sdkVersion\ucrt\x86;$sdkRoot\Lib\$sdkVersion\um\x86"
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    $dest=(Resolve-Path -LiteralPath $OutputDirectory).Path
    $compiler=Join-Path $vcRoot 'bin/Hostx64/x86/cl.exe'
    $sources=@('src/buffer.c','src/hook.c','src/trampoline.c','src/hde/hde32.c') | ForEach-Object { Join-Path $PSScriptRoot "vendor/minhook/$_" }
    & $compiler /nologo /utf-8 /MT /O2 /LD /Fo"$dest\" /Fe"$dest\native-pause.dll" (Join-Path $PSScriptRoot 'pause.c') @sources /link /Brepro bcrypt.lib /OUT:"$dest\native-pause.dll" '/EXPORT:NativePauseInitialize=_NativePauseInitialize@4'
    if($LASTEXITCODE -ne 0){throw 'DLL编译失败'}
    & $compiler /nologo /utf-8 /MT /O2 /DNATIVE_PAUSE_AUTO /LD /Fo"$dest\" /Fe"$dest\IsaacConsoleNativePause.asi" (Join-Path $PSScriptRoot 'pause.c') @sources /link /Brepro bcrypt.lib /OUT:"$dest\IsaacConsoleNativePause.asi" '/EXPORT:NativePauseInitialize=_NativePauseInitialize@4'
    if($LASTEXITCODE -ne 0){throw '自启动插件编译失败'}
    & $compiler /nologo /utf-8 /MT /O2 /Fo"$dest\" /Fe"$dest\inject.exe" (Join-Path $PSScriptRoot 'inject.c') /link /Brepro shell32.lib
    if($LASTEXITCODE -ne 0){throw '加载器编译失败'}
    & $compiler /nologo /utf-8 /MT /O2 /Fo"$dest\" /Fe"$dest\contract-test.exe" (Join-Path $PSScriptRoot 'test.c') @sources /link bcrypt.lib
    if($LASTEXITCODE -ne 0){throw '契约编译失败'}
    & $compiler /nologo /utf-8 /MT /O2 /DNATIVE_FIXTURE_DLL /LD /Fo"$dest\" /Fe"$dest\loader-fixture.dll" (Join-Path $PSScriptRoot 'loader-fixture.c') /link '/EXPORT:NativePauseInitialize=_NativePauseInitialize@4'
    if($LASTEXITCODE -ne 0){throw '加载测试DLL编译失败'}
    & $compiler /nologo /utf-8 /MT /O2 /Fo"$dest\" /Fe"$dest\loader-target.exe" (Join-Path $PSScriptRoot 'loader-fixture.c')
    if($LASTEXITCODE -ne 0){throw '加载测试进程编译失败'}
    & $compiler /nologo /utf-8 /MT /O2 /Fo"$dest\" /Fe"$dest\autoload-target.exe" (Join-Path $PSScriptRoot 'autoload-target.c') /link winmm.lib
    if($LASTEXITCODE -ne 0){throw '自启动测试进程编译失败'}
    Write-Output "NATIVE_BUILD_PASS compiler=$compiler runtime=static-x86"
} finally { $env:INCLUDE=$oldInclude; $env:LIB=$oldLib }
