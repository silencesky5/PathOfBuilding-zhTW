# zhTW: packs the Chinese (Taiwan) PoB into a zip to give to other people.
#
# Takes only files under version control (git ls-files), so personal files are never included:
#   src\Settings.xml (account name, login tokens), src\Builds\ (your builds) are not tracked.
# Also left out: src\Export\ (data export tools and extracted game files), zhTW test scripts,
# GitHub / test / docs files, and the reports.
#
# Usage (Windows PowerShell):
#   powershell -ExecutionPolicy Bypass -File src\Export\zhTWPackage.ps1
#   optional: -OutDir <folder>   (default: the folder that contains the PathOfBuilding folder)
param(
	[string]$OutDir = ""
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if ($OutDir -eq "") {
	$OutDir = Split-Path -Parent $root
}
$name = "POB台服版_" + (Get-Date -Format "yyyyMMdd")
$zipPath = Join-Path $OutDir ($name + ".zip")

# Uncommitted changes would be packed as they are on disk; warn so the zip matches a commit
$dirty = & git -C $root status --porcelain -- src runtime
if ($dirty) {
	Write-Host "Warning: uncommitted changes under src or runtime:"
	$dirty | ForEach-Object { Write-Host ("  " + $_) }
}

$rootFiles = @("manifest.xml", "changelog.txt", "help.txt", "LICENSE.md", "README.md")
$files = & git -C $root ls-files -- runtime src | Where-Object {
	-not $_.StartsWith("src/Export/") -and
	-not ($_ -match "^src/zhTW(Test|Coverage|LocaleTest|Probe)\.lua$")
}
$files = @($files) + $rootFiles
Write-Host ("Files: {0}" -f $files.Count)

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("pob_zhtw_package\" + $name)
if (Test-Path -LiteralPath $stage) {
	Remove-Item -LiteralPath $stage -Recurse -Force
}
foreach ($f in $files) {
	$src = Join-Path $root $f
	$dst = Join-Path $stage $f
	$dir = Split-Path -Parent $dst
	if (-not (Test-Path -LiteralPath $dir)) {
		[void](New-Item -ItemType Directory -Force -Path $dir)
	}
	Copy-Item -LiteralPath $src -Destination $dst
}

# Start file (the program must run from the runtime folder)
$bat = "@echo off`r`ncd /d `"%~dp0runtime`"`r`nstart `"`" `"Path{space}of{space}Building.exe`"`r`n"
[System.IO.File]::WriteAllText((Join-Path $stage "開啟POB台服版.bat"), $bat, (New-Object System.Text.ASCIIEncoding))

$readme = @"
POB 台服版（Path of Building Community 非官方繁體中文版）

【開啟】
  雙擊「開啟POB台服版.bat」，或執行 runtime\Path{space}of{space}Building.exe。
  解壓縮的路徑可以有中文。不要只把 runtime 資料夾拿出來執行，它需要旁邊的 src 資料夾。

【匯入台服角色】
  1. 進入一個 Build，到「匯入/匯出」分頁。
  2. 在「依帳號名稱匯入」輸入台服帳號名稱（要包含 # 後面的數字，例如 名稱#1234），按「開始」。
     台服帳號的角色資料要設為公開。
  3. 選聯盟和角色，按「全部匯入」。
  4. 台服資料不含盜賊任務的選擇，請到「設定」分頁手動選擇。

【語言】
  按「選項」按鈕，可以在選項視窗切回英文介面。

【注意】
  - 這個版本不會自動更新。台服或 POB 改版後，需要拿新的打包版本。
  - 你的 Build 和設定存在這個資料夾裡（src\Builds、src\Settings.xml），換資料夾時請一起搬。
  - Path of Building Community 為 MIT 授權（見 LICENSE.md）；中文字型 Noto Sans TC 為 SIL Open Font License。
    遊戲文字與資料版權屬於 Grinding Gear Games。本版本與官方無關。

打包日期：$(Get-Date -Format "yyyy-MM-dd")
"@
[System.IO.File]::WriteAllText((Join-Path $stage "使用說明.txt"), $readme.Replace("`n", "`r`n"), (New-Object System.Text.UTF8Encoding($true)))

if (Test-Path -LiteralPath $zipPath) {
	Remove-Item -LiteralPath $zipPath -Force
}
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true, [System.Text.Encoding]::UTF8)
Remove-Item -LiteralPath (Split-Path -Parent $stage) -Recurse -Force

$size = (Get-Item -LiteralPath $zipPath).Length / 1MB
Write-Host ("Zip: {0} ({1:0} MB)" -f $zipPath, $size)
