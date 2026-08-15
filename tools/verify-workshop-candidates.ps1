param(
    [string]$PythonPath = ''
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path $PSScriptRoot -Parent
$pythonCandidates = @()
if ($PythonPath) { $pythonCandidates += $PythonPath }
$pythonCandidates += (Join-Path $repositoryRoot '.venv\Scripts\python.exe')
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCommand -and $pythonCommand.Source -notlike '*\Microsoft\WindowsApps\python.exe') {
    $pythonCandidates += $pythonCommand.Source
}
$python = $pythonCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $python) {
    throw '找不到可用的 Python。请通过 -PythonPath 传入实际 python.exe，不要使用 WindowsApps 别名。'
}

& $python (Join-Path $repositoryRoot 'tests/workshop-mod/run_all_tests.py')
if ($LASTEXITCODE -ne 0) { throw "双语源码回归失败：$LASTEXITCODE" }

& (Join-Path $PSScriptRoot 'build-workshop-mod.ps1') -Language zh
& (Join-Path $PSScriptRoot 'build-workshop-mod.ps1') -Language en

$candidateRoot = Join-Path $repositoryRoot 'dist/workshop-candidates'
& $python (Join-Path $repositoryRoot 'tests/workshop-mod/validate_workshop_mod_zh.py') `
    (Join-Path $candidateRoot 'isaac_chinese_console_workshop')
if ($LASTEXITCODE -ne 0) { throw "中文候选包验证失败：$LASTEXITCODE" }

& $python (Join-Path $repositoryRoot 'tests/workshop-mod/validate_workshop_mod.py') `
    (Join-Path $candidateRoot 'console_ui_workshop')
if ($LASTEXITCODE -ne 0) { throw "英文候选包验证失败：$LASTEXITCODE" }

Write-Output 'BILINGUAL_WORKSHOP_GATE=OK'
