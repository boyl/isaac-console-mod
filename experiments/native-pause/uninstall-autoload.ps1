#requires -Version 7.0
param([string]$GameDirectory=(Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/The Binding of Isaac Rebirth'),[switch]$NoPause,[switch]$Elevated)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'installer-common.ps1')
try {
    if(Get-Process -Name isaac-ng -ErrorAction SilentlyContinue){throw '先正常退出游戏再卸载。'}
    $root=(Resolve-Path -LiteralPath $GameDirectory).Path
    $receiptPath=Join-Path $root '.isaac-native-pause-install.json'
    if(-not(Test-Path -LiteralPath $receiptPath)){throw '无本组件安装记录；手动安装请按README的文件清单移除。'}
    $receipt=Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    if($receipt.gameRoot -ne $root){throw '安装记录的目录不符。'}
    $manifest=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'manifest.json') -Raw | ConvertFrom-Json
    if($receipt.files.Count -ne $manifest.installFiles.Count){throw '安装记录文件清单不符。'}
    foreach($file in $receipt.files){if($file.name -notin @($manifest.installFiles) -or $file.hash -ne $manifest.files.('game-files/'+$file.name)){throw '安装记录不属于本包，停止卸载。'}}
    foreach($file in $receipt.files){$target=Resolve-InstallFile $root $file.name;if((Get-InstallHash $target) -ne $file.hash){throw "安装文件已变更，停止卸载：$($file.name)"}}
    $plan=@(Get-InstallPlan (Join-Path $PSScriptRoot 'game-files') $root @($manifest.installFiles))
    try{Test-InstallAccess $plan $root}
    catch [UnauthorizedAccessException]{
        if($Elevated){throw '提权后仍不能卸载。'}
        $pwsh=(Get-Command pwsh.exe -CommandType Application | Select-Object -First 1).Source
        $args='-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -GameDirectory "{1}" -NoPause -Elevated' -f $PSCommandPath,$root
        $child=Start-Process -FilePath $pwsh -Verb RunAs -WindowStyle Hidden -ArgumentList $args -Wait -PassThru
        if($child.ExitCode -ne 0){throw "提权卸载失败：$($child.ExitCode)"}
        foreach($file in $receipt.files){if(Test-Path -LiteralPath (Resolve-InstallFile $root $file.name)){throw '提权后仍存在组件文件'}}
        Write-Output 'AUTOLOAD_UNINSTALLED_AND_VERIFIED';exit 0
    }
    foreach($file in $receipt.files){Remove-Item -LiteralPath (Resolve-InstallFile $root $file.name)}
    Remove-Item -LiteralPath $receiptPath
    Write-Output 'AUTOLOAD_UNINSTALLED：已移除加载器、配置和暂停插件，存档与Mod未修改。'; $code=0
}catch{Write-Warning $_.Exception.Message;$code=1}
if(-not $NoPause){[void](Read-Host '按Enter关闭')}
exit $code
