#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$PythonPath,
    [Parameter(Mandatory)][string]$OutputDirectory,
    [string]$GameDirectory=(Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/The Binding of Isaac Rebirth')
)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
if(Test-Path -LiteralPath $OutputDirectory){throw '发布目录已存在，请指定新目录。'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$out=(Resolve-Path -LiteralPath $OutputDirectory).Path
$build=Join-Path $out 'build-evidence'
& (Join-Path $PSScriptRoot 'build-native.ps1') -OutputDirectory $build
& (Join-Path $build 'contract-test.exe') (Join-Path $GameDirectory 'Lua5.3.3r.dll') | Tee-Object -FilePath (Join-Path $build 'native-tests.log')
if($LASTEXITCODE -ne 0){throw '原生测试失败'}
& (Join-Path $PSScriptRoot 'test-loader.ps1') -BuildDirectory $build | Tee-Object -FilePath (Join-Path $build 'loader-tests.log')
& (Join-Path $PSScriptRoot 'test-launcher.ps1') -TestDirectory $build -GameDirectory $GameDirectory | Tee-Object -FilePath (Join-Path $build 'launcher-tests.log')
& $PythonPath (Join-Path $PSScriptRoot 'run-integration.py') | Tee-Object -FilePath (Join-Path $build 'integration.log')
if($LASTEXITCODE -ne 0){throw '双语暂停集成失败'}
& (Join-Path $repo 'tools/verify-workshop-candidates.ps1') -PythonPath $PythonPath | Tee-Object -FilePath (Join-Path $build 'source-gate.log')
$package=Join-Path $out 'native-pause-0.1.0'
New-Item -ItemType Directory -Path $package | Out-Null
foreach($name in @('native-pause.dll','inject.exe')){Copy-Item -LiteralPath (Join-Path $build $name) -Destination $package}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-prototype.ps1') -Destination (Join-Path $package 'start.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'restore-prototype.ps1') -Destination (Join-Path $package 'restore.ps1')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RELEASE.md') -Destination (Join-Path $package 'README.md')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'vendor/minhook/LICENSE.txt') -Destination (Join-Path $package 'LICENSE-MINHOOK.txt')
foreach($action in @('start','restore')){
    $entry=@"
@echo off
setlocal
set "pwshExe="
for %%I in (pwsh.exe) do set "pwshExe=%%~`$PATH:I"
if not defined pwshExe (
  echo PowerShell 7 was not found on PATH.
  pause
  exit /b 1
)
"%pwshExe%" -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0$action.ps1"
set "rc=%errorlevel%"
if not "%rc%"=="0" pause
exit /b %rc%
"@
    [IO.File]::WriteAllText((Join-Path $package "$action.cmd"),$entry,[Text.ASCIIEncoding]::new())
}
$probe=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'probe.lua') -Raw
$baselines=[ordered]@{
    zh=@('34039902DEDD1114166896C9D91A43C2FAC2DA1577F974A2C109768A2065E534')
    en=@('64F268427163A8ABE19D43C037D1A580FB390E65C8C8175D87A65B592C7419BD')
}
foreach($language in @('zh','en')){
    $mod=if($language -eq 'zh'){'isaac_chinese_console_workshop'}else{'console_ui_workshop'}
    $candidate=Join-Path $repo "dist/workshop-candidates/$mod/main.lua"
    $baselines[$language]+=(Get-FileHash -LiteralPath $candidate).Hash
    $script=Get-Content -LiteralPath $candidate -Raw
    $languageProbe=if($language -eq 'en'){$probe.Replace('ChineseConsole:AddCallback','ConsoleUI:AddCallback')}else{$probe}
    [IO.File]::WriteAllText((Join-Path $package "$language-main.lua"),($script+"`n"+$languageProbe),[Text.UTF8Encoding]::new($false))
}
& $PythonPath (Join-Path $PSScriptRoot 'check-package.py') $package | Tee-Object -FilePath (Join-Path $build 'syntax.log')
if($LASTEXITCODE -ne 0){throw '最终菜单语法失败'}
$files=[ordered]@{}
foreach($file in Get-ChildItem -LiteralPath $package -File | Sort-Object Name){$files[$file.Name]=(Get-FileHash -LiteralPath $file.FullName).Hash}
$manifest=[ordered]@{
    version='0.1.0'; runtime='Repentance+ v1.9.7.17 / J460 / x86'
    exeSha256='3BDFC8BAE0DC7E334B76009D0AD45DFBB16EE5F00C06FFBC3A0094E34D44616B'
    sourceHead=(& git -C $repo rev-parse HEAD); sourceDirty=(@(& git -C $repo diff HEAD --name-only).Count -gt 0 -or @(& git -C $repo ls-files --others --exclude-standard).Count -gt 0)
    baselines=$baselines; files=$files
    validation='自动原生、并发、加载器、双语集成、完整源码回归、最终Lua编译通过；实机证据单独记录'
}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $package 'manifest.json') -Encoding utf8
$zip=Join-Path $out 'native-pause-0.1.0.zip'
Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $package -File | ForEach-Object FullName) -DestinationPath $zip
[ordered]@{status='BUILT_AND_AUTOMATIC_GATES_PASS'; package=$package; sourceHead=$manifest.sourceHead; sourceDirty=$manifest.sourceDirty; files=$files.Count+1; zipBytes=(Get-Item -LiteralPath $zip).Length; zipSha256=(Get-FileHash -LiteralPath $zip).Hash} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $out 'build-result.json')
if($manifest.sourceDirty){Write-Warning '源码尚未提交，此构建不能作为最终正式发布来源。'}
