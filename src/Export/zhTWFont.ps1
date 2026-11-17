# zhTW: builds the Chinese glyph atlases used by Modules/ZhTWText.lua
#
# PoB's bitmap fonts only contain ASCII (128 glyphs per size) and the engine draws every other
# character as "[U+xxxx]". ZhTWText.lua draws Chinese characters from these atlases instead.
#
# Usage (from the repository root, Windows PowerShell 5.1):
#   powershell -ExecutionPolicy Bypass -File src\Export\zhTWFont.ps1
#
# Characters included:
#   - every CJK character in src\Data\zhTW\*.lua (game data and UI translations)
#   - the Big5 level 1 common characters, so new translations are usually covered
# Re-run after adding translations that use characters outside this set.
#
# Output: src\Data\zhTW\Font16.png/.lua (normal UI text, drawn at native size so it stays sharp)
#         src\Data\zhTW\Font32.png/.lua (large text)
# Font: Noto Sans TC (SIL Open Font License), falls back to Microsoft JhengHei.

param(
	[string]$FontFile = "C:\Windows\Fonts\NotoSansTC-VF.ttf"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$dataDir = Join-Path $root "src\Data\zhTW"

# One atlas per common UI text size, so text is drawn at native size (scaled text looks blurry)
$sizes = @(
	@{ Cell = 12; EmSize = 11.25; Name = "Font12" },
	@{ Cell = 14; EmSize = 13.125; Name = "Font14" },
	@{ Cell = 16; EmSize = 15.0; Name = "Font16" },
	@{ Cell = 18; EmSize = 16.875; Name = "Font18" },
	@{ Cell = 20; EmSize = 18.75; Name = "Font20" },
	@{ Cell = 24; EmSize = 22.5; Name = "Font24" },
	@{ Cell = 32; EmSize = 30.0; Name = "Font32" }
)

function Test-Wide([int]$cp) {
	return ($cp -ge 0x3000 -and $cp -le 0x9FFF) -or ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or ($cp -ge 0xFF00 -and $cp -le 0xFFEF) -or ($cp -ge 0x2010 -and $cp -le 0x2027) -or ($cp -ge 0x2190 -and $cp -le 0x21FF) -or ($cp -ge 0x25A0 -and $cp -le 0x25FF)
}

# Collect characters
$set = New-Object 'System.Collections.Generic.SortedSet[int]'
# Every non-ASCII character the Chinese interface can draw: translations, game data, and the
# zhTW modules' own text (the engine shows any character missing here as "[U+xxxx]")
$sources = @(Get-ChildItem -Path $dataDir -Filter *.lua | Where-Object { $_.Name -notlike "Font*.lua" })
$sources += @(Get-ChildItem -Path (Join-Path $root "src\Data\StatDescriptions\zhTW\tc") -Filter *.lua)
$sources += @(Get-ChildItem -Path (Join-Path $root "src\Modules") -Filter "ZhTW*.lua")
$sources += @(Get-Item -Path (Join-Path $root "src\Classes\ImportTab.lua"))
foreach ($file in $sources) {
	$text = [System.IO.File]::ReadAllText($file.FullName, [System.Text.Encoding]::UTF8)
	foreach ($ch in $text.ToCharArray()) {
		$cp = [int]$ch
		# skip control characters and UTF-16 surrogate halves
		if ($cp -ge 0xA1 -and -not ($cp -ge 0xD800 -and $cp -le 0xDFFF)) { [void]$set.Add($cp) }
	}
}
$fromData = $set.Count
# Big5 level 1 common characters: lead bytes 0xA4-0xC6
$big5 = [System.Text.Encoding]::GetEncoding(950)
for ($lead = 0xA4; $lead -le 0xC6; $lead++) {
	foreach ($trail in (@(0x40..0x7E) + @(0xA1..0xFE))) {
		if ($lead -eq 0xC6 -and $trail -gt 0x7E) { continue }
		$s = $big5.GetString([byte[]]@($lead, $trail))
		if ($s.Length -eq 1) {
			$cp = [int]$s[0]
			if (Test-Wide $cp) { [void]$set.Add($cp) }
		}
	}
}
# Punctuation (as code points: Windows PowerShell reads this file in the system code page)
foreach ($cp in @(0xFF0C, 0x3002, 0x3001, 0xFF1B, 0xFF1A, 0xFF1F, 0xFF01, 0x300C, 0x300D, 0x300E, 0x300F, 0xFF08, 0xFF09, 0x300A, 0x300B, 0x3008, 0x3009, 0x2026, 0x2014, 0xFF0E, 0x00B7, 0xFF5E, 0xFF05, 0xFF0B, 0xFF0D, 0xFF1D, 0xFF0F, 0x00D7, 0x221E, 0x2027)) {
	[void]$set.Add([int]$cp)
}
$chars = @($set)
Write-Host ("Characters: {0} ({1} from data files)" -f $chars.Count, $fromData)

# Font
$pfc = New-Object System.Drawing.Text.PrivateFontCollection
$family = $null
if (Test-Path $FontFile) {
	$pfc.AddFontFile($FontFile)
	$family = $pfc.Families[0]
}
if (-not $family) {
	$family = New-Object System.Drawing.FontFamily("Microsoft JhengHei")
}
Write-Host ("Font: {0}" -f $family.Name)

foreach ($size in $sizes) {
	$cell = $size.Cell
	$font = New-Object System.Drawing.Font($family, [float]$size.EmSize, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
	$outPng = Join-Path $dataDir ($size.Name + ".png")
	$outLua = Join-Path $dataDir ($size.Name + ".lua")

	$cols = [int][Math]::Ceiling([Math]::Sqrt($chars.Count))
	$rows = [int][Math]::Ceiling($chars.Count / $cols)
	$width = $cols * $cell
	$height = $rows * $cell
	$bmp = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.Clear([System.Drawing.Color]::FromArgb(0, 255, 255, 255))
	$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
	$brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
	$fmt = [System.Drawing.StringFormat]::GenericTypographic
	$fmt.FormatFlags = $fmt.FormatFlags -bor [System.Drawing.StringFormatFlags]::NoClip
	# Vertical placement: centre the font's ascent+descent box in the cell
	$lineSpacing = $family.GetLineSpacing([System.Drawing.FontStyle]::Regular)
	$fontH = $size.EmSize * $lineSpacing / $family.GetEmHeight([System.Drawing.FontStyle]::Regular)

	$lua = New-Object System.Text.StringBuilder
	[void]$lua.AppendLine("-- This file is automatically generated by Export/zhTWFont.ps1, do not edit!")
	[void]$lua.AppendLine(("-- Font: {0} (SIL Open Font License)" -f $family.Name))
	[void]$lua.AppendLine("-- glyphs[codepoint] = { index (0-based cell), advance (fraction of cell) }")
	[void]$lua.AppendLine("return {")
	[void]$lua.AppendLine(("`tcell = {0}, cols = {1}, rows = {2}, width = {3}, height = {4}," -f $cell, $cols, $rows, $width, $height))
	[void]$lua.AppendLine("`tglyphs = {")
	for ($i = 0; $i -lt $chars.Count; $i++) {
		$cp = $chars[$i]
		$s = [string][char]$cp
		$x = ($i % $cols) * $cell
		$y = [Math]::Floor($i / $cols) * $cell
		$m = $g.MeasureString($s, $font, 1000, $fmt)
		$adv = [Math]::Min(1.0, [Math]::Max(0.3, $m.Width / $cell))
		$dx = [Math]::Round($x + ($cell - $m.Width) / 2)
		$dy = [Math]::Round($y + ($cell - $fontH) / 2)
		$g.DrawString($s, $font, $brush, [float]$dx, [float]$dy, $fmt)
		[void]$lua.AppendLine(("`t`t[{0}]={{{1},{2:0.###}}}," -f $cp, $i, $adv))
	}
	[void]$lua.AppendLine("`t},")
	[void]$lua.AppendLine("}")
	$g.Dispose()
	$bmp.Save($outPng, [System.Drawing.Imaging.ImageFormat]::Png)
	$bmp.Dispose()
	[System.IO.File]::WriteAllText($outLua, $lua.ToString(), (New-Object System.Text.UTF8Encoding($false)))
	Write-Host ("Atlas: {0} ({1}x{2})" -f $outPng, $width, $height)
}
