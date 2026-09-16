#Requires -Version 7.0
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot '../dist/hd-font-sources'))
$ErrorActionPreference = 'Stop'
$lock = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'hd-font-source.json') -Raw | ConvertFrom-Json
$base = 'https://raw.githubusercontent.com/adobe-fonts/source-han-sans/' + $lock.revision
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
foreach ($file in $lock.files) {
    $path = Join-Path $OutputDirectory $file.Path
    if (-not (Test-Path -LiteralPath $path)) { Invoke-WebRequest ($base + '/' + $file.remote) -OutFile $path }
    if ((Get-FileHash -LiteralPath $path).Hash -ne $file.Hash) { throw "源字体哈希不匹配：$($file.Path)" }
}
Invoke-WebRequest ($base + '/LICENSE.txt') -OutFile (Join-Path $OutputDirectory 'LICENSE-OFL.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'hd-font-source.json') -Destination (Join-Path $OutputDirectory 'source.json')
Write-Output 'PASS：锁定版本字体与 SHA-256 校验完成'
