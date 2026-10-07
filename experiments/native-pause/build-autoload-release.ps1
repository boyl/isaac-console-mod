#requires -Version 7.0
param([Parameter(Mandatory)][string]$PythonPath,[Parameter(Mandatory)][string]$OutputDirectory,
      [string]$GameDirectory=(Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/The Binding of Isaac Rebirth'))
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$sourceHead=(& git -C $repo rev-parse HEAD)
if($LASTEXITCODE -ne 0){throw '无法读取源码 HEAD。'}
$sourceChanges=(& git -C $repo status --porcelain)
if($sourceChanges){throw '正式发布要求源码工作树干净，请先提交改动。'}
if(Test-Path -LiteralPath $OutputDirectory){throw '输出目录已存在。'}
New-Item -ItemType Directory -Path $OutputDirectory | Out-Null
$out=(Resolve-Path -LiteralPath $OutputDirectory).Path
$build=Join-Path $out 'build-evidence'; $package=Join-Path $out 'native-pause-0.2.2'
& (Join-Path $PSScriptRoot 'build-native.ps1') -OutputDirectory $build
& (Join-Path $build 'contract-test.exe') (Join-Path $GameDirectory 'Lua5.3.3r.dll') | Tee-Object -FilePath (Join-Path $build 'native-tests.log')
if($LASTEXITCODE -ne 0){throw '原生测试失败'}
& (Join-Path $PSScriptRoot 'test-autoload.ps1') -BuildDirectory $build -GameDirectory $GameDirectory | Tee-Object -FilePath (Join-Path $build 'autoload-tests.log')
& $PythonPath (Join-Path $PSScriptRoot 'run-integration.py') | Tee-Object -FilePath (Join-Path $build 'integration.log')
if($LASTEXITCODE -ne 0){throw '双语暂停集成失败'}
& (Join-Path $repo 'tools/verify-workshop-candidates.ps1') -PythonPath $PythonPath | Tee-Object -FilePath (Join-Path $build 'source-gate.log')
$origin=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'vendor/asi-loader/origin.json') -Raw | ConvertFrom-Json
if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'vendor/asi-loader/winmm.dll')).Hash -ne $origin.binarySha256){throw '第三方加载器哈希不符'}
$gameFiles=Join-Path $package 'game-files'; $scripts=Join-Path $gameFiles 'scripts'
New-Item -ItemType Directory -Path $scripts -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'vendor/asi-loader/winmm.dll') -Destination $gameFiles
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'winmm.ini') -Destination $gameFiles
Copy-Item -LiteralPath (Join-Path $build 'IsaacConsoleNativePause.asi') -Destination $scripts
foreach($entry in @(@('install-autoload.ps1','install.ps1'),@('uninstall-autoload.ps1','uninstall.ps1'),@('installer-common.ps1','installer-common.ps1'),@('AUTOLOAD-RELEASE.md','README.md'),@('vendor/minhook/LICENSE.txt','LICENSE-MINHOOK.txt'),@('vendor/asi-loader/LICENSE.txt','LICENSE-ASI-LOADER.txt'))){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $entry[0]) -Destination (Join-Path $package $entry[1])}
foreach($action in @('install','uninstall')){
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
$files=[ordered]@{}
foreach($file in Get-ChildItem -LiteralPath $package -File -Recurse | Sort-Object FullName){$relative=[IO.Path]::GetRelativePath($package,$file.FullName).Replace('\','/');$files[$relative]=(Get-FileHash -LiteralPath $file.FullName).Hash}
$manifest=[ordered]@{version='0.2.2';sourceHead=$sourceHead;sourceDirty=$false;exeHashes=@('3BDFC8BAE0DC7E334B76009D0AD45DFBB16EE5F00C06FFBC3A0094E34D44616B','04469D0C3D3581936FCF85BEA5F9F4F3A65B2CCF96B36310456C9626BAC36DC6','CEB598B4E5E03DABBD2DA6EA322A9AA6FFC66FCC377AEEA4391F008403B7FAA4');runtimes=@('Repentance+ v1.9.7.17/J460/x86','Repentance v1.7.9b/x86','REPENTOGON+ fixed Rep+ executable/x86');installFiles=@('winmm.dll','winmm.ini','scripts/IsaacConsoleNativePause.asi');files=$files;loader=$origin}
$manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $package 'manifest.json') -Encoding utf8
& (Join-Path $PSScriptRoot 'test-autoload-installer.ps1') -PackageDirectory $package -TestDirectory $build -GameDirectory $GameDirectory | Tee-Object -FilePath (Join-Path $build 'installer-tests.log')
$zip=Join-Path $out 'native-pause-0.2.2.zip'
Compress-Archive -LiteralPath @(Get-ChildItem -LiteralPath $package | ForEach-Object FullName) -DestinationPath $zip
[ordered]@{status='AUTOMATIC_GATES_PASS';sourceHead=$manifest.sourceHead;package=$package;zip=$zip;zipSha256=(Get-FileHash -LiteralPath $zip).Hash;zipBytes=(Get-Item -LiteralPath $zip).Length} | ConvertTo-Json | Tee-Object -FilePath (Join-Path $out 'build-result.json')
