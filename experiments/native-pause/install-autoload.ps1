#requires -Version 7.0
param(
    [string]$GameDirectory=(Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/The Binding of Isaac Rebirth'),
    [switch]$NoPause,[switch]$Elevated,[switch]$ValidateOnly
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'installer-common.ps1')
function Invoke-AutoloadInstall {
    $gameRoot=(Resolve-Path -LiteralPath $GameDirectory).Path
    if(Get-Process -Name isaac-ng -ErrorAction SilentlyContinue){throw '先正常退出游戏再安装。'}
    $manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
    $exeHash=(Get-FileHash -LiteralPath (Join-Path $gameRoot 'isaac-ng.exe')).Hash
    if($exeHash -notin @($manifest.exeHashes)){throw '当前游戏EXE不在支持清单，未修改。'}
    foreach($file in $manifest.files.PSObject.Properties){
        if((Get-InstallHash (Resolve-InstallFile $PSScriptRoot $file.Name)) -ne $file.Value){throw "包校验失败：$($file.Name)"}
    }
    $names=@($manifest.installFiles)
    $source=Join-Path $PSScriptRoot 'game-files'
    $plan=@(Get-InstallPlan $source $gameRoot $names)
    $receiptPath=Join-Path $gameRoot '.isaac-native-pause-install.json'
    if(Test-Path -LiteralPath $receiptPath){
        $receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
        foreach($file in $plan){if((Get-InstallHash $file.Target) -ne $file.SourceHash){throw '已有安装发生变化，请先卸载或核对，未覆盖。'}}
        Write-Output 'AUTOLOAD_ALREADY_INSTALLED_AND_VERIFIED'; return
    }
    foreach($file in $plan){if($file.PreviousHash){throw "目标已有文件，避免覆盖其他加载器：$($file.Name)"}}
    if($ValidateOnly){Write-Output "AUTOLOAD_PREFLIGHT_PASS exe=$exeHash";return}
    try{Test-InstallAccess $plan $gameRoot}
    catch [UnauthorizedAccessException]{
        if($Elevated){throw '提权后仍无写入权限。'}
        $pwsh=(Get-Command pwsh.exe -CommandType Application | Select-Object -First 1).Source
        $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -GameDirectory "{1}" -Elevated -NoPause' -f $PSCommandPath,$gameRoot
        $child=Start-Process -FilePath $pwsh -Verb RunAs -WindowStyle Hidden -ArgumentList $args -Wait -PassThru
        if($child.ExitCode -ne 0){throw "提权安装失败：$($child.ExitCode)"}
        foreach($file in $plan){if((Get-InstallHash $file.Target) -ne $file.SourceHash){throw '提权后独立哈希验证失败'}}
        Write-Output 'AUTOLOAD_INSTALLED_AND_VERIFIED';return
    }
    Invoke-InstallTransaction $plan $gameRoot
    $receipt=[ordered]@{version=$manifest.version;gameRoot=$gameRoot;files=@($plan | ForEach-Object {[ordered]@{name=$_.Name;hash=$_.SourceHash}})}
    try{$receipt | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $receiptPath -Encoding utf8}
    catch{foreach($file in $plan){if((Get-InstallHash $file.Target) -eq $file.SourceHash){Remove-Item -LiteralPath $file.Target}};throw}
    Write-Output 'AUTOLOAD_INSTALLED_AND_VERIFIED：以后从Steam正常启动，无需运行脚本。'
}
if($MyInvocation.InvocationName -ne '.') {
    try{Invoke-AutoloadInstall; $code=0}catch{Write-Warning $_.Exception.Message; $code=1}
    if(-not $NoPause){[void](Read-Host '按Enter关闭')}
    exit $code
}
