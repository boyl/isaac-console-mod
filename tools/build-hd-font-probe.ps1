#Requires -Version 7.0
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Assets, [Parameter(Mandatory)][string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $OutputDirectory) { throw '请使用新的样板输出目录' }
$assetsRoot = (Resolve-Path -LiteralPath $Assets).Path
$spec = Get-Content -LiteralPath (Join-Path $assetsRoot 'manifest.json') -Raw | ConvertFrom-Json
foreach ($entry in $spec.files.psobject.Properties) {
    if ($entry.Name -ne [IO.Path]::GetFileName($entry.Name)) { throw '字形清单必须为直接文件名' }
    if ((Get-FileHash -LiteralPath (Join-Path $assetsRoot $entry.Name)).Hash -ne $entry.Value) { throw "字形资源校验失败：$($entry.Name)" }
}
New-Item -ItemType Directory -Path (Join-Path $OutputDirectory 'resources/hd') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $OutputDirectory 'resources/gfx/ui') -Force | Out-Null
foreach ($name in @('main.lua','metadata.xml')) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot "font-probe/$name") -Destination (Join-Path $OutputDirectory $name)
}
foreach ($entry in $spec.files.psobject.Properties) {
    Copy-Item -LiteralPath (Join-Path $assetsRoot $entry.Name) -Destination (Join-Path $OutputDirectory ('resources/hd/' + $entry.Name))
}
Copy-Item -LiteralPath (Join-Path $assetsRoot 'manifest.json') -Destination (Join-Path $OutputDirectory 'resources/hd/manifest.json')
$graphic = Join-Path $PSScriptRoot '../workshop-mod/resources/gfx/ui'
$anm = (Get-Content -LiteralPath (Join-Path $graphic 'isaac_console_pixel.anm2') -Raw).Replace('isaac_console_pixel.png','isaac_hd_probe_pixel.png')
$anm | Set-Content -LiteralPath (Join-Path $OutputDirectory 'resources/gfx/ui/isaac_hd_probe_pixel.anm2') -Encoding utf8NoBOM
Copy-Item -LiteralPath (Join-Path $graphic 'isaac_console_pixel.png') -Destination (Join-Path $OutputDirectory 'resources/gfx/ui/isaac_hd_probe_pixel.png')
$root = (Resolve-Path -LiteralPath $OutputDirectory).Path
$files = @(Get-ChildItem -LiteralPath $root -File -Recurse | ForEach-Object {
    @{path=[IO.Path]::GetRelativePath($root,$_.FullName);sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
})
@{schemaVersion=1;purpose='local-font-visual-gate-only';files=$files} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath ($root + '.manifest.json') -Encoding utf8NoBOM
Write-Output "PASS：独立样板已构建；$($files.Count) 个文件；正式控制台未修改"
