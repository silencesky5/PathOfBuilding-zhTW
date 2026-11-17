# zhTW: packs the Chinese (Taiwan) PoB into a zip to give to other people.
#
# The zip is a portable PoB in one folder with automatic updates turned on: it follows the
# GitHub repository and branch in src\Export\zhTWRelease.ini (never the official PoB).
# Built from the current commit by src\Export\zhTWRelease.py; only files under version control
# are included, so src\Settings.xml (account, login tokens) and src\Builds\ never are.
#
# Usage (Windows PowerShell, Python 3.10+ installed):
#   powershell -ExecutionPolicy Bypass -File src\Export\zhTWPackage.ps1
#   optional: -OutDir <folder>   (default: the folder that contains the PathOfBuilding folder)
#
# Releasing an update to everyone who has the zip: see zhTWRelease.py (publish, then git push).
param(
	[string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

$dirty = & git -C $root status --porcelain --untracked-files=no
if ($dirty) {
	Write-Host "Warning: uncommitted changes are NOT in the zip (it is built from the last commit):"
	$dirty | ForEach-Object { Write-Host ("  " + $_) }
}

$pyArgs = @((Join-Path $PSScriptRoot "zhTWRelease.py"), "package")
if ($OutDir -ne "") {
	$pyArgs += @("--out", $OutDir)
}
& python @pyArgs
if ($LASTEXITCODE -ne 0) {
	exit $LASTEXITCODE
}
