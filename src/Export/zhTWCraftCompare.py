"""zhTW: compares the crafting site's engine (JS) with the 製作 tab's (Lua).

  node src/Export/zhTWCraftCompare.js <Poe-tool folder> 20000 > js.txt
  (runtime) set ZHTW_CRAFT_SCRIPT=<full path of src/zhTWCraftCompare.lua>
            set ZHTW_CRAFT_OUT=<full path of lua.txt>  &  set ZHTW_CRAFT_N=20000
            Path{space}of{space}Building.exe <full path of src/zhTWCraftTest.lua>
  python src/Export/zhTWCraftCompare.py js.txt lua.txt 20000

Text, tiers and error messages must be equal; mod frequencies must agree within random noise.
"""
import collections
import math
import sys


def load(path):
	d = {}
	for line in open(path, encoding="utf-8"):
		a, b, c = line.rstrip("\n").split("\t")
		d[(a, b)] = c
	return d


js, lua, n = load(sys.argv[1]), load(sys.argv[2]), int(sys.argv[3])
bad, worst = 0, collections.defaultdict(float)
for k in sorted(set(js) | set(lua)):
	a, b = js.get(k), lua.get(k)
	if k[0] in ("meta", "check", "text", "tier", "implicit"):
		if a != b:
			print("DIFF", k, a, b)
			bad += 1
		continue
	pa, pb = float(a or 0), float(b or 0)
	p = max((pa + pb) / 2, 1 / n)
	z = abs(pa - pb) / (math.sqrt(p / n) * math.sqrt(2))
	worst[k[0]] = max(worst[k[0]], z)
	if z > 4.5:
		print("FLAG", k, pa, pb, round(z, 1))
		bad += 1
for c in sorted(worst):
	print(c, "max z", round(worst[c], 2))
print("problems", bad)
