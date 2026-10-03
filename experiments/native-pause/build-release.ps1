#requires -Version 7.0
param([Parameter(Mandatory)][string]$PythonPath,[Parameter(Mandatory)][string]$OutputDirectory,
      [string]$GameDirectory=(Join-Path ${env:ProgramFiles(x86)} 'Steam/steamapps/common/The Binding of Isaac Rebirth'))
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'build-autoload-release.ps1') -PythonPath $PythonPath -OutputDirectory $OutputDirectory -GameDirectory $GameDirectory
