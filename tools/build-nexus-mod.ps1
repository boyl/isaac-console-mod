#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidateSet('zh', 'en')][string[]]$Language = @('zh', 'en'),
    [string]$OutputRoot = '',
    [switch]$SkipCandidateBuild,
    [switch]$AllowUnpushedHead
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'build-nexus-mod.ps1 requires PowerShell 7 or later.' }

$repositoryRoot = (Resolve-Path -LiteralPath (Split-Path $PSScriptRoot -Parent)).Path
if (-not $OutputRoot) { $OutputRoot = Join-Path $repositoryRoot 'dist\nexus-packages' }
$candidateRoot = Join-Path $repositoryRoot 'dist\workshop-candidates'

# A Nexus release archive is built from a pushed commit, so the record inside BUILD-INFO.json
# always names a commit that exists on origin/main.
$git = (Get-Command git -ErrorAction Stop).Source
$head = (& $git -C $repositoryRoot rev-parse HEAD).Trim()
$trackedChanges = @(& $git -C $repositoryRoot status --porcelain --untracked-files=no)
if ($trackedChanges.Count -gt 0) {
    throw "Tracked files have uncommitted changes; commit them before packaging:`n$($trackedChanges -join "`n")"
}
$divergence = @(((& $git -C $repositoryRoot rev-list --left-right --count origin/main...HEAD) -join ' ').Trim() -split '\s+')
if ($divergence.Count -ne 2) { throw 'Unable to read the origin/main...HEAD divergence.' }
$behind = [int]$divergence[0]
$ahead = [int]$divergence[1]
$headPushed = ($behind -eq 0 -and $ahead -eq 0)
if (-not $headPushed -and -not $AllowUnpushedHead) {
    throw "Local HEAD is not in sync with origin/main (behind=$behind ahead=$ahead). Push first or pass -AllowUnpushedHead."
}
if (-not $headPushed) { Write-Warning "Building from an unpushed HEAD ($head); BUILD-INFO.json records SourceCommitPushedToOriginMain=false." }

Write-Verbose "Building Nexus packages from commit $head"

New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null

$built = @()
foreach ($variant in $Language) {
    $slug = if ($variant -eq 'zh') { 'IsaacChineseConsole' } else { 'ConsoleUI' }
    $expectedDirectory = if ($variant -eq 'zh') { 'isaac_chinese_console_workshop' } else { 'console_ui_workshop' }

    if (-not $SkipCandidateBuild) {
        & (Join-Path $PSScriptRoot 'build-workshop-mod.ps1') -Language $variant | ForEach-Object { Write-Verbose $_ }
    }

    $candidateDirectory = Join-Path $candidateRoot $expectedDirectory
    if (-not (Test-Path -LiteralPath $candidateDirectory -PathType Container)) {
        throw "Missing Workshop candidate directory: $candidateDirectory"
    }

    [xml]$metadata = Get-Content -LiteralPath (Join-Path $candidateDirectory 'metadata.xml') -Raw
    $registerName = [string]$metadata.metadata.name
    $directory = [string]$metadata.metadata.directory
    $version = [string]$metadata.metadata.version
    $workshopFileId = [string]$metadata.metadata.id
    if ($directory -ne $expectedDirectory) { throw "Candidate directory '$directory' does not match '$expectedDirectory' for variant $variant." }
    if ([string]::IsNullOrWhiteSpace($version)) { throw "Candidate metadata.xml has no version: $candidateDirectory" }

    # The archive root is the Mod folder itself: Nexus expects a single top-level folder,
    # and the two existing candidate validators can then check the unpacked folder directly.
    $stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('nexus-stage-' + [guid]::NewGuid().ToString('N'))
    $verifyRoot = Join-Path ([IO.Path]::GetTempPath()) ('nexus-verify-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $stageRoot -Force | Out-Null
        Copy-Item -LiteralPath $candidateDirectory -Destination $stageRoot -Recurse -Force
        $stagedDirectory = Join-Path $stageRoot $directory

        $archiveName = "$slug-$version-Nexus.zip"
        $archivePath = Join-Path $OutputRoot $archiveName
        if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
        Compress-Archive -LiteralPath $stagedDirectory -DestinationPath $archivePath -CompressionLevel Optimal
        $archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $archivePath).Hash

        Expand-Archive -LiteralPath $archivePath -DestinationPath $verifyRoot -Force
        $rootEntries = @(Get-ChildItem -LiteralPath $verifyRoot)
        if ($rootEntries.Count -ne 1 -or -not $rootEntries[0].PSIsContainer -or $rootEntries[0].Name -ne $directory) {
            throw "Archive root must contain exactly one folder named '$directory'."
        }

        $candidateFiles = @(Get-ChildItem -LiteralPath $candidateDirectory -Recurse -File | Sort-Object FullName)
        $fileRecords = @()
        foreach ($file in $candidateFiles) {
            $relative = $file.FullName.Substring($candidateDirectory.Length + 1).Replace('\', '/')
            $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName).Hash
            $unpackedPath = Join-Path (Join-Path $verifyRoot $directory) $relative.Replace('/', '\')
            if (-not (Test-Path -LiteralPath $unpackedPath -PathType Leaf)) { throw "Archive is missing $relative" }
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $unpackedPath).Hash -ne $sourceHash) { throw "Archive content differs from the candidate at $relative" }
            $fileRecords += [ordered]@{ Path = $relative; Length = $file.Length; Sha256 = $sourceHash }
        }
        $unpackedCount = @(Get-ChildItem -LiteralPath (Join-Path $verifyRoot $directory) -Recurse -File).Count
        if ($unpackedCount -ne $candidateFiles.Count) { throw "Archive holds $unpackedCount files but the candidate holds $($candidateFiles.Count)." }

        $buildInfoPath = Join-Path $OutputRoot "$slug-$version-BUILD-INFO.json"
        $buildInfo = [ordered]@{
            SchemaVersion                   = 1
            Distribution                    = 'nexus'
            BuiltAtUtc                      = [DateTime]::UtcNow.ToString('o')
            SourceRepository                = (& $git -C $repositoryRoot remote get-url origin).Trim()
            SourceCommit                    = $head
            SourceCommitPushedToOriginMain  = $headPushed
            SourceBehindOriginMain          = $behind
            SourceAheadOfOriginMain         = $ahead
            Language                        = $variant
            RegisterName                    = $registerName
            Directory                       = $directory
            Version                         = $version
            WorkshopFileId                  = $workshopFileId
            CandidateDirectory              = $candidateDirectory
            CandidateFileCount              = $candidateFiles.Count
            Archive                         = [ordered]@{
                Name      = $archiveName
                Path      = $archivePath
                RootEntry = $directory
                Length    = (Get-Item -LiteralPath $archivePath).Length
                Sha256    = $archiveHash
            }
            Files                           = $fileRecords
        }
        $buildInfo | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $buildInfoPath -Encoding utf8
        $checksumPath = Join-Path $OutputRoot "$slug-$version.sha256"
        "$archiveHash  $archiveName" | Set-Content -LiteralPath $checksumPath -Encoding ascii

        Write-Output "NEXUS_PACKAGE=$archivePath"
        Write-Output "NEXUS_PACKAGE_SHA256=$archiveHash"
        Write-Output "NEXUS_PACKAGE_CHECKSUM=$checksumPath"
        Write-Output "NEXUS_BUILD_INFO=$buildInfoPath"
        Write-Output "NEXUS_FILES=$($fileRecords.Count)"
        Write-Output "SOURCE_COMMIT=$head"
        Write-Output "VERSION=$version"
        $built += [ordered]@{ Variant = $variant; Slug = $slug; Version = $version; Archive = $archivePath; Sha256 = $archiveHash; Files = $fileRecords.Count }
    }
    finally {
        foreach ($tempRoot in @($stageRoot, $verifyRoot)) {
            if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

Write-Output "NEXUS_BUILD_TOTAL=$($built.Count)"
Write-Output 'NEXUS_BUILD=OK'
