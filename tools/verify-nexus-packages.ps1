#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$PythonPath = '',
    [ValidateSet('zh', 'en')][string[]]$Language = @('zh', 'en'),
    [switch]$SkipSourceTests
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'verify-nexus-packages.ps1 requires PowerShell 7 or later.' }

$repositoryRoot = (Resolve-Path -LiteralPath (Split-Path $PSScriptRoot -Parent)).Path

$pythonCandidates = @()
if ($PythonPath) { $pythonCandidates += $PythonPath }
$pythonCandidates += (Join-Path $repositoryRoot '.venv\Scripts\python.exe')
$pythonCommand = Get-Command python -ErrorAction SilentlyContinue
if ($pythonCommand -and $pythonCommand.Source -notlike '*\Microsoft\WindowsApps\python.exe') {
    $pythonCandidates += $pythonCommand.Source
}
$python = $pythonCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $python) {
    throw 'No usable Python found. Pass -PythonPath with a real python.exe; the WindowsApps alias is not accepted.'
}

$packageRoot = Join-Path $repositoryRoot 'dist\nexus-packages'
$logRoot = Join-Path $packageRoot 'logs'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $logRoot "verify-$stamp.log"
$recordPath = Join-Path $packageRoot "NEXUS-GATE-$stamp.json"

$verified = @()
try {
    Start-Transcript -LiteralPath $logPath -Force | Out-Null

    Write-Output "PYTHON=$python"

    if (-not $SkipSourceTests) {
        & (Join-Path $PSScriptRoot 'verify-workshop-candidates.ps1') -PythonPath $python
    }
    else {
        Write-Output 'SKIPPED_SOURCE_TESTS=1'
    }

    & (Join-Path $PSScriptRoot 'build-nexus-mod.ps1') -Language $Language -ErrorAction Stop

    foreach ($variant in $Language) {
        $expectedDirectory = if ($variant -eq 'zh') { 'isaac_chinese_console_workshop' } else { 'console_ui_workshop' }
        $validator = if ($variant -eq 'zh') { 'validate_workshop_mod_zh.py' } else { 'validate_workshop_mod.py' }

        $buildInfoFile = Get-ChildItem -LiteralPath $packageRoot -Filter '*-BUILD-INFO.json' |
            Where-Object { (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).Directory -eq $expectedDirectory } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $buildInfoFile) { throw "No BUILD-INFO.json found for variant $variant." }

        $buildInfo = Get-Content -LiteralPath $buildInfoFile.FullName -Raw | ConvertFrom-Json
        $archivePath = [string]$buildInfo.Archive.Path
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) { throw "Archive recorded in $($buildInfoFile.Name) is missing: $archivePath" }

        $archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash
        if ($archiveHash -ne [string]$buildInfo.Archive.Sha256) { throw "Archive hash changed since packaging: $archivePath" }

        # The unpacked archive is validated by the same candidates validators used for the
        # Workshop candidates, so a Nexus release package can never drift from a checked candidate.
        $unpackRoot = Join-Path ([IO.Path]::GetTempPath()) ('nexus-gate-' + [guid]::NewGuid().ToString('N'))
        try {
            Expand-Archive -LiteralPath $archivePath -DestinationPath $unpackRoot -Force
            $rootEntries = @(Get-ChildItem -LiteralPath $unpackRoot)
            if ($rootEntries.Count -ne 1 -or -not $rootEntries[0].PSIsContainer -or $rootEntries[0].Name -ne $expectedDirectory) {
                throw "Archive root must hold exactly one folder named '$expectedDirectory': $archivePath"
            }
            $modDirectory = Join-Path $unpackRoot $expectedDirectory

            foreach ($record in $buildInfo.Files) {
                $relative = [string]$record.Path
                $unpackedPath = Join-Path $modDirectory $relative.Replace('/', '\')
                if (-not (Test-Path -LiteralPath $unpackedPath -PathType Leaf)) { throw "Archive is missing $relative" }
                if ((Get-FileHash -Algorithm SHA256 -LiteralPath $unpackedPath).Hash -ne [string]$record.Sha256) { throw "Archive content differs from BUILD-INFO.json at $relative" }
            }
            $unpackedCount = @(Get-ChildItem -LiteralPath $modDirectory -Recurse -File).Count
            if ($unpackedCount -ne $buildInfo.Files.Count) { throw "Archive holds $unpackedCount files but BUILD-INFO.json lists $($buildInfo.Files.Count)." }

            & $python (Join-Path $repositoryRoot "tests\workshop-mod\$validator") $modDirectory
            if ($LASTEXITCODE -ne 0) { throw "$validator rejected the unpacked $variant package: exit $LASTEXITCODE" }

            Write-Output "NEXUS_UNPACKED_VALID=$variant files=$unpackedCount validator=$validator sha256=$archiveHash"
            $verified += [ordered]@{
                Variant           = $variant
                Directory         = $expectedDirectory
                Version           = [string]$buildInfo.Version
                RegisterName      = [string]$buildInfo.RegisterName
                Archive           = $archivePath
                ArchiveSha256     = $archiveHash
                FileCount         = $unpackedCount
                Validator         = $validator
                SourceCommit      = [string]$buildInfo.SourceCommit
                SourceCommitPushedToOriginMain = [bool]$buildInfo.SourceCommitPushedToOriginMain
            }
        }
        finally {
            if (Test-Path -LiteralPath $unpackRoot) { Remove-Item -LiteralPath $unpackRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }

    $git = (Get-Command git -ErrorAction Stop).Source
    $record = [ordered]@{
        SchemaVersion     = 1
        VerifiedAtUtc     = [DateTime]::UtcNow.ToString('o')
        Repository        = $repositoryRoot
        HeadCommit        = (& $git -C $repositoryRoot rev-parse HEAD).Trim()
        Python            = $python
        SourceTestsRun    = (-not $SkipSourceTests)
        LogPath           = $logPath
        Packages          = $verified
    }
    $record | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $recordPath -Encoding utf8
    Write-Output "NEXUS_GATE_RECORD=$recordPath"
    Write-Output 'NEXUS_PACKAGE_GATE=OK'
}
finally {
    Stop-Transcript | Out-Null
}
