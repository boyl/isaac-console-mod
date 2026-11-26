#requires -Version 7.0
# 复用已成功发布的官方 API 流程；默认仅预检，不创建上传。
[CmdletBinding()]
param(
 [Parameter(Mandatory)][ValidateSet('zh','en')][string]$Language,
 [Parameter(Mandatory)][ValidatePattern('^[0-9]+$')][string]$PreviousVersionId,
 [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string]$ExpectedCommit,
 [Parameter(Mandatory)][string]$OutputDirectory,
 [Parameter(Mandatory)][ValidateLength(1,255)][string]$ChangeNotes,
 [string]$Proxy='http://127.0.0.1:7897',
 [switch]$Publish
)
$ErrorActionPreference='Stop'
$repo=(Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
if ((& git -C $repo rev-parse HEAD).Trim() -ne $ExpectedCommit) { throw 'HEAD differs from the approved package commit' }
if (@(& git -C $repo status --porcelain).Count) { throw 'Working tree must be clean before Nexus publication' }
if ($Proxy) { $env:HTTP_PROXY=$Proxy; $env:HTTPS_PROXY=$Proxy }
$key=(Get-Content -LiteralPath (Join-Path (Split-Path $repo -Parent) 'nexus-api-key.txt.txt') -Raw).Trim()
$headers=@{apikey=$key;'User-Agent'='IsaacConsoleRelease/1.0'}
$folder=if($Language -eq 'zh'){'workshop-mod'}else{'workshop-mod-en'}
[xml]$metadata=Get-Content -LiteralPath (Join-Path $repo ($folder+'/metadata.xml')) -Raw
$version=[string]$metadata.metadata.version
$profile=if($Language -eq 'zh'){
 @{id='8109348';old=$PreviousVersionId;version=$version;slug='IsaacChineseConsole';name="Isaac Chinese Console $version (Chinese)";primary=$false;update=$true;notes=$ChangeNotes}
}else{
 @{id='8109351';old=$PreviousVersionId;version=$version;slug='ConsoleUI';name="Console UI $version (English)";primary=$true;update=$false;notes=$ChangeNotes}
}
$null=New-Item -ItemType Directory -Path $OutputDirectory -Force
function Api([string]$Path,[string]$Method='GET',$Body=$null){
 $args=@{Uri=('https://api.nexusmods.com/v3'+$Path);Method=$Method;Headers=$headers;TimeoutSec=45}
 if($null -ne $Body){$args.ContentType='application/json';$args.Body=ConvertTo-Json -InputObject $Body -Depth 8 -Compress}
 try{Invoke-RestMethod @args}catch{throw ('Nexus API '+$Method+' '+$Path+' failed; HTTP '+[int]$_.Exception.Response.StatusCode)}
}
function PublicRequest([string]$Url,[string]$Method,[byte[]]$Body,[string]$ContentType){
 if(([uri]$Url).Scheme -ne 'https'){throw 'Non-HTTPS upload URL rejected'}
 try{Invoke-WebRequest -Uri $Url -Method $Method -Body $Body -ContentType $ContentType -TimeoutSec 60}catch{throw ('Upload transport failed; HTTP '+[int]$_.Exception.Response.StatusCode)}
}
$metaPath=Join-Path $repo ('dist/nexus-packages/'+$profile.slug+'-'+$profile.version+'-BUILD-INFO.json')
$info=Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json
$archive=[string]$info.Archive.Path
if($profile.notes.Length -gt 255){throw 'Description exceeds API limit'}
if(-not $info.SourceCommitPushedToOriginMain -or $info.SourceCommit -ne $ExpectedCommit){throw 'Unexpected source commit'}
$gateFile=Get-ChildItem -LiteralPath (Join-Path $repo 'dist/nexus-packages') -Filter 'NEXUS-GATE-*.json' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$gate=Get-Content -LiteralPath $gateFile.FullName -Raw | ConvertFrom-Json
if($gate.HeadCommit -ne $info.SourceCommit -or -not $gate.SourceTestsRun){throw 'Nexus gate source mismatch'}
$gatePackage=@($gate.Packages | Where-Object { $_.Variant -eq $Language -and $_.ArchiveSha256 -eq $info.Archive.Sha256 }); if($gatePackage.Count -ne 1){throw 'No matching package in successful gate'}

if((Get-FileHash -LiteralPath $archive).Hash -ne $info.Archive.Sha256){throw 'Archive hash differs from verified build'}
$mod=(Api '/games/thebindingofisaacrebirth/mods/140').data
if($mod.id -ne '5553392713868' -or $mod.name.Trim() -ne 'Isaac Console  UI'){throw 'Nexus Mod identity mismatch'}
$prior=(Api ('/games/thebindingofisaacrebirth/mod-file-versions/'+$profile.old)).data
if($prior.file.id -ne $profile.id){throw 'Nexus update chain mismatch'}
$versions=(Api ('/mod-files/'+$profile.id+'/versions')).data.versions
if(@($versions|Where-Object version -eq $profile.version).Count){throw 'Target version already exists; inspect instead of uploading again'}
Write-Output "NEXUS_PREFLIGHT_PASS language=$Language mod=$($mod.id) chain=$($profile.id) version=$($profile.version) sha256=$($info.Archive.Sha256)"
if(-not $Publish){exit 0}
$receiptPath=Join-Path $OutputDirectory ('nexus-'+$Language+'-receipt.json')
if(Test-Path -LiteralPath $receiptPath){throw 'Existing upload receipt; inspect remote state before retry'}
$receipt=[ordered]@{language=$Language;modId=$mod.id;fileId=$profile.id;version=$profile.version;archive=$archive;sha256=$info.Archive.Sha256;stage='creating-upload';uploadId=$null;versionId=$null}
function Save-Receipt { $receipt|ConvertTo-Json -Depth 6|Set-Content -LiteralPath $receiptPath -Encoding utf8NoBOM }
Save-Receipt
$bytes=[IO.File]::ReadAllBytes($archive)
$upload=(Api '/uploads/multipart' 'POST' @{filename=[IO.Path]::GetFileName($archive);size_bytes=[string]$bytes.Length}).data
$receipt.uploadId=$upload.id;$receipt.stage='uploading';Save-Receipt
$parts=@();$partSize=[int]$upload.part_size_bytes
for($i=0;$i -lt $upload.part_presigned_urls.Count;$i++){
 $offset=$i*$partSize;$length=[Math]::Min($partSize,$bytes.Length-$offset);$buffer=[byte[]]::new($length)
 [Array]::Copy($bytes,$offset,$buffer,0,$length)
 $response=PublicRequest $upload.part_presigned_urls[$i] 'PUT' $buffer 'application/octet-stream'
 $etag=([string]$response.Headers.ETag).Trim('"')
 if(-not $etag){throw 'Upload part returned no ETag'}
 $parts+='<Part><PartNumber>'+($i+1)+'</PartNumber><ETag>'+[Security.SecurityElement]::Escape($etag)+'</ETag></Part>'
 Write-Output "NEXUS_PART_PASS language=$Language part=$($i+1)/$($upload.part_presigned_urls.Count) bytes=$length"
}
$xml='<CompleteMultipartUpload>'+($parts -join '')+'</CompleteMultipartUpload>'
$null=PublicRequest $upload.complete_presigned_url 'POST' ([Text.Encoding]::UTF8.GetBytes($xml)) 'application/xml'
$null=Api ('/uploads/'+$upload.id+'/finalise') 'POST'
$receipt.stage='processing';Save-Receipt
$available=$false
for($i=0;$i -lt 30;$i++){
 $state=(Api ('/uploads/'+$upload.id)).data.state
 Write-Output "NEXUS_UPLOAD_STATE language=$Language state=$state"
 if($state -eq 'available'){$available=$true;break}
 if($state -in @('failed','rejected')){throw 'Nexus processing rejected upload'}
 Start-Sleep -Seconds 2
}
if(-not $available){throw 'Upload still processing; resume by inspecting receipt, do not create another upload'}
$receipt.stage='creating-file-version';Save-Receipt
$created=(Api ('/mod-files/'+$profile.id+'/versions') 'POST' @{
 upload_id=$upload.id;name=$profile.name;description=$profile.notes;version=$profile.version;file_category='main'
 archive_existing_file=$true;primary_mod_manager_download=$profile.primary;allow_mod_manager_download=$true
 show_requirements_pop_up=$false;update_mod_version=$profile.update;previous_version_id=$prior.id
}).data
$receipt.versionId=$created.version.id;$receipt.stage='created';Save-Receipt
$verified=(Api ('/mod-file-versions/'+$receipt.versionId)).data
if($verified.version -ne $profile.version -or $verified.file.id -ne $profile.id){throw 'Published version identity mismatch'}
$receipt.stage='verified';$receipt.remote=$verified;Save-Receipt
Write-Output "NEXUS_FILE_VERSION_VERIFIED language=$Language versionId=$($verified.id) version=$($verified.version) scan=$($verified.security_scan_status)"
