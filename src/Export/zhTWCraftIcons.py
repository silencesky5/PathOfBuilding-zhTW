"""zhTW: builds src/Assets/zhTW/currency.png for the 製作 tab's buttons from the crafting site's
currency icons (Poe-tool/img/craft/items, the game's own art as the site uses it).

Cells of 32 px, 6 per row: the ten currencies in Modules/ZhTWCraftEngine.lua's order, then an
essence and a resonator.

usage: python src/Export/zhTWCraftIcons.py <Poe-tool folder>
"""
import json
import pathlib
import sys

from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "src" / "Assets" / "zhTW" / "currency.png"
ORDER = ["transmute", "alt", "aug", "regal", "alch", "chaos", "exalt", "annul", "scour", "divine"]
CELL, COLS = 32, 6


def main():
	site = pathlib.Path(sys.argv[1])
	text = (site / "craft-data.js").read_text(encoding="utf-8")
	data = json.loads(text[text.index("{"):text.rstrip().rstrip(";").rindex("}") + 1])
	files = [data["curIcons"][k] for k in ORDER]
	files.append(data["essences"][0].get("ic") or "")
	files.append(next(r["ic"] for r in data["resonators"] if r["kind"] == "c" and r["s"] == 1))
	rows = (len(files) + COLS - 1) // COLS
	sheet = Image.new("RGBA", (COLS * CELL, rows * CELL), (0, 0, 0, 0))
	for i, name in enumerate(files):
		path = site / "img" / "craft" / "items" / name
		if not name or not path.exists():
			print("missing", name)
			continue
		icon = Image.open(path).convert("RGBA")
		box = icon.getbbox() or (0, 0, icon.width, icon.height)
		icon = icon.crop(box)
		side = max(icon.width, icon.height)
		square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
		square.alpha_composite(icon, ((side - icon.width) // 2, (side - icon.height) // 2))
		square = square.resize((CELL - 2, CELL - 2), Image.LANCZOS)
		r, c = divmod(i, COLS)
		sheet.alpha_composite(square, (c * CELL + 1, r * CELL + 1))
	OUT.parent.mkdir(parents=True, exist_ok=True)
	sheet.save(OUT)
	print(OUT, sheet.size, len(files), "icons")


main()
