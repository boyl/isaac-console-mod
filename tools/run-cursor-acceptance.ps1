#requires -Version 7.0
param(
    [Parameter(Mandatory)][string]$PythonPath,
    [Parameter(Mandatory)][string]$NodePath,
    [string]$OutputDirectory = ''
)
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot ('dist/acceptance/' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
}
if (Test-Path -LiteralPath $OutputDirectory) { throw '验收输出目录已存在，请使用新目录。' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$result = [ordered]@{ status='FAIL'; sourceGate='NOT_RUN'; runnerTests='NOT_RUN'; frameTests='NOT_RUN'; liveGame='NOT_RUN'; output=[IO.Path]::GetFullPath($OutputDirectory) }
try {
    & (Join-Path $PSScriptRoot 'verify-workshop-candidates.ps1') -PythonPath $PythonPath *> (Join-Path $OutputDirectory 'source-and-package.log')
    $gateLog = Get-Content -LiteralPath (Join-Path $OutputDirectory 'source-and-package.log') -Raw
    if ($gateLog -notmatch 'BILINGUAL_WORKSHOP_GATE=OK') { throw '缺少实际源码/候选验收完成标记。' }
    $result.sourceGate = 'PASS'
    & $NodePath --test (Join-Path $repositoryRoot 'tests/acceptance/fullscreen-cursor.test.mjs') *> (Join-Path $OutputDirectory 'runner-tests.log')
    if ($LASTEXITCODE -ne 0) { throw '实机验收执行器的故障/恢复测试失败。' }
    $result.runnerTests = 'PASS'
    & $PythonPath (Join-Path $repositoryRoot 'tests/acceptance/test_cursor_frames.py') *> (Join-Path $OutputDirectory 'frame-tests.log')
    if ($LASTEXITCODE -ne 0) { throw '历史实机图片识别测试失败。' }
    $result.frameTests = 'PASS'
    $result.status = 'PASS'
} catch {
    $result.error = $_.Exception.Message
} finally {
    $result | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'result.json') -Encoding utf8
    $result | ConvertTo-Json
}
if ($result.status -ne 'PASS') { throw '验收失败，查看输出目录中的日志。' }
