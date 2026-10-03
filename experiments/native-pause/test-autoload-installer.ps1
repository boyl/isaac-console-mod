#requires -Version 7.0
param([Parameter(Mandatory)][string]$PackageDirectory,[Parameter(Mandatory)][string]$TestDirectory,[Parameter(Mandatory)][string]$GameDirectory)
$ErrorActionPreference='Stop'
$root=Join-Path $TestDirectory 'autoload-install-fixture'; $package=Join-Path $root 'package'; $gameRoot=Join-Path $root 'game'
New-Item -ItemType Directory -Path $package,$gameRoot -Force | Out-Null
Get-ChildItem -LiteralPath $PackageDirectory | ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $package -Recurse -Force}
Copy-Item -LiteralPath (Join-Path $GameDirectory 'isaac-ng.exe') -Destination $gameRoot
$saved=Join-Path $gameRoot 'user-save.dat'; [IO.File]::WriteAllText($saved,'keep-user-data')
function Get-Process {param($Name,$ErrorAction)return $null}
. (Join-Path $package 'install.ps1') -GameDirectory $gameRoot -NoPause -ValidateOnly
$checks=0
function Check($ok,$name){if(-not $ok){throw "FAIL $name"};$script:checks++;Write-Output "PASS $name"}
Invoke-AutoloadInstall
Check (-not(Test-Path -LiteralPath (Join-Path $gameRoot 'winmm.dll'))) 'preflight performs no install'
$ValidateOnly=$false
Invoke-AutoloadInstall
Check (Test-Path -LiteralPath (Join-Path $gameRoot '.isaac-native-pause-install.json')) 'install writes restoration receipt'
$manifest=Get-Content -LiteralPath (Join-Path $package 'manifest.json') -Raw | ConvertFrom-Json
foreach($name in $manifest.installFiles){Check ((Get-FileHash -LiteralPath (Join-Path $gameRoot $name)).Hash -eq $manifest.files.('game-files/'+$name)) "installed hash $name"}
Invoke-AutoloadInstall
Check ((Get-Content -LiteralPath $saved -Raw) -eq 'keep-user-data') 'repeat install preserves unrelated data'
& (Join-Path $package 'uninstall.ps1') -GameDirectory $gameRoot -NoPause
if($LASTEXITCODE -ne 0){throw '卸载失败'}
Check (-not(Test-Path -LiteralPath (Join-Path $gameRoot 'winmm.dll')) -and -not(Test-Path -LiteralPath (Join-Path $gameRoot 'scripts/IsaacConsoleNativePause.asi'))) 'uninstall removes only owned component files'
Check ((Get-Content -LiteralPath $saved -Raw) -eq 'keep-user-data') 'uninstall preserves unrelated data'
[IO.File]::WriteAllText((Join-Path $gameRoot 'winmm.dll'),'other-loader')
try{Invoke-AutoloadInstall;throw 'EXPECTED_CONFLICT_MISSING'}catch{if($_.Exception.Message -notmatch '其他加载器'){throw}}
Check ((Get-Content -LiteralPath (Join-Path $gameRoot 'winmm.dll') -Raw) -eq 'other-loader') 'conflicting loader is not overwritten'
Write-Output "AUTOLOAD_INSTALLER_PASS assertions=$checks"
