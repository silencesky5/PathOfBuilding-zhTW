#@ SimpleGraphic
-- zhTW: headless test for 稀有裝備傷害最佳化 (Modules/ZhTWOptimize.lua)
--
-- Usage (from the runtime folder):
--   set ZHTW_OPT_BUILDS=<build xml>;<build xml>   (default: two of spec/TestBuilds/3.13)
--   Path{space}of{space}Building.exe <full path of src\zhTWOptimizeTest.lua>
-- Results: src/zhTWOptimizeTest.log

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logFile = io.open("zhTWOptimizeTest.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end
print = log

local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	Inflate, Deflate = realInflate, realDeflate
	local Opt = LoadModule("Modules/ZhTWOptimize")
	local builds = os.getenv("ZHTW_OPT_BUILDS") or "../spec/TestBuilds/3.13/Generals Perforate Zerker.xml;../spec/TestBuilds/3.13/Mirage Archer Toxic Rain.xml"
	for path in builds:gmatch("[^;]+") do
		local f = io.open(path, "rb")
		local xml = f:read("*a")
		f:close()
		loadBuildFromXML(xml, path)
		local itemsTab = build.itemsTab
		log("== " .. path)
		local _, calcBase = build.calcsTab:GetMiscCalculator()
		log("base CombinedDPS", calcBase.CombinedDPS)
		for _, keepRes in ipairs({ false, true }) do
			log("-- keepRes", keepRes)
			for _, slot in ipairs(Opt.listSlots(itemsTab)) do
				local t0 = os.clock() * 1000
				local r = Opt.optimizeSlot(itemsTab, slot, keepRes)
				local ms = os.clock() * 1000 - t0
				if r.skip then
					log(slot.slotName, "skip", r.skip)
				else
					log(string.format("%s  ilvl=%s  base=%s  cands=%d evals=%d  %.0fms  DPS %.1f -> %.1f (%+.1f%%)",
						slot.slotName, tostring(r.orig.itemLevel), r.orig.baseName, r.candidateCount, r.evals, ms,
						r.before, r.after, r.before > 0 and (r.after / r.before - 1) * 100 or 0))
					for _, k in ipairs(r.kept) do
						log("   kept " .. k.type .. ": " .. k.modLine.line)
					end
					if r.need then
						local got = { }
						for _, ml in ipairs(r.item.explicitModLines) do
							local v, target = ml.line:lower():match("^%+([%d%.]+)%% to ([%a ]-) resistances?$")
							if v and not target:match("maximum") then
								local names = target == "all elemental" and { "fire", "cold", "lightning" } or { }
								if target ~= "all elemental" then
									for n in (target .. " and "):gmatch("(%a+) and ") do names[#names + 1] = n end
								end
								for _, n in ipairs(names) do got[n] = (got[n] or 0) + tonumber(v) end
							end
						end
						local parts = { }
						for _, e in ipairs({ "fire", "cold", "lightning", "chaos" }) do
							parts[#parts + 1] = string.format("%s %d/%d", e, got[e] or 0, r.need[e] or 0)
							if not r.resistFallback then
								assert((got[e] or 0) >= (r.need[e] or 0), "resistance below the original: " .. e)
							end
						end
						log("   resist got/need: " .. table.concat(parts, ", ") .. (r.resistFallback and "  (fallback: kept lines)" or "") .. "  fixed=" .. #r.fixed)
					end
					for _, c in ipairs(r.chosen) do
						log(string.format("   %s %s (lvl %d, group %s): %s", c.type, c.id, c.mod.level, c.group, table.concat(c.mod, " / ")))
					end
					-- sanity: limits and unique groups
					local n, groups, keptN = { Prefix = 0, Suffix = 0 }, { }, { Prefix = 0, Suffix = 0 }
					for _, k in ipairs(r.kept) do n[k.type] = n[k.type] + 1; keptN[k.type] = keptN[k.type] + 1 end
					for _, c in ipairs(r.chosen) do
						n[c.type] = n[c.type] + 1
						assert(not groups[c.group], "duplicate group " .. c.group)
						groups[c.group] = true
						assert(c.mod.level <= (r.orig.itemLevel or 100), "mod level above item level")
					end
					assert(n.Prefix <= math.max(3, keptN.Prefix) and n.Suffix <= math.max(3, keptN.Suffix), "too many affixes")
					assert(n.Prefix - keptN.Prefix == 0 or n.Prefix <= 3, "too many prefixes")
					assert(n.Suffix - keptN.Suffix == 0 or n.Suffix <= 3, "too many suffixes")
					for _, ml in ipairs(r.item.explicitModLines) do
						log("     line: " .. ml.line .. (ml.extra and "  (UNSUPPORTED)" or ""))
					end
				end
			end
		end
	end
	-- the popup: run 全部稀有裝備 the way the button does, drawing frames until it finishes
	log("== popup")
	local before = #build.itemsTab.itemOrderList
	Opt.openPopup(build.itemsTab)
	local popup = main.popups[1]
	local controls = popup.controls
	controls.go.onClick()
	local drawn = { }
	local realDrawString = DrawString
	DrawString = function(x, y, align, size, font, text)
		drawn[#drawn + 1] = text
	end
	local frames = 0
	repeat
		wipeTable(drawn)
		controls.results:Draw({ x = 0, y = 0, width = 1920, height = 1080 })
		frames = frames + 1
	until controls.go:GetProperty("label") ~= "計算中…" or frames > 100000
	DrawString = realDrawString
	log("frames", frames, "items added", #build.itemsTab.itemOrderList - before)
	for _, t in ipairs(drawn) do log("  " .. t) end
	controls.close.onClick()
	log("DONE")
end)
if not ok then
	log("ERROR", err)
end
logFile:close()

realSetMainObject({
	OnInit = function() realExit() end,
	OnFrame = function() end,
})
