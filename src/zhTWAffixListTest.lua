#@ SimpleGraphic
-- zhTW: headless test for the crafting affix lists (前綴/後綴 drop-downs of a crafted item).
-- ItemsTab:UpdateAffixControl shows a tier group with "#" for the numbers ("+# to Intelligence")
-- and hybrid modifiers joined by "/"; ZhTWLocale translates them (translateAffixGroup).
-- Builds the labels of every item type the same way and lists the lines left in English.
--
-- Usage (from the runtime folder):
--   Path{space}of{space}Building.exe <full path of src\zhTWAffixListTest.lua>
-- Results: src/zhTWAffixListTest.log

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logFile = io.open("zhTWAffixListTest.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end
print = log

local pass, fail = 0, 0
local function check(ok, name, detail)
	if ok then
		pass = pass + 1
	else
		fail = fail + 1
	end
	log((ok and "OK" or "FAIL") .. "\t" .. name .. (detail and ("\t" .. detail) or ""))
end

local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	Inflate, Deflate = realInflate, realDeflate
	ZhTWLocale.enabled = true
	ZhTWLocale.clearCache()

	-- Lines from the report (screenshot 11/26)
	local expect = {
		["+# to Intelligence"] = "+# 智慧",
		["+# to Dexterity"] = "+# 敏捷",
		["#% reduced Attribute Requirements"] = "減少 #% 能力值需求",
		["+# to Accuracy Rating"] = "+# 命中值",
		["+#% to Fire Resistance"] = "+#% 火焰抗性",
		["+# to Armour/+# to maximum Life"] = "+# 點護甲/+# 最大生命",
	}
	for en, zh in pairs(expect) do
		local got = ZhTWLocale.tr(en)
		check(got == zh, en, got)
		check(not got:find("情報"), "no Syndicate intelligence text: " .. en, got)
	end
	-- Measuring first (quick mode) must not cache a wrong text
	ZhTWLocale.clearCache()
	ZhTWLocale.tr("+# to Strength", true)
	check(ZhTWLocale.tr("+# to Strength") == "+# 力量", "measure then draw", ZhTWLocale.tr("+# to Strength"))
	-- English interface: unchanged
	ZhTWLocale.enabled = false
	check(ZhTWLocale.tr("+# to Intelligence") == "+# to Intelligence", "English interface unchanged")
	ZhTWLocale.enabled = true

	-- Every item type: tier groups ("#") and single tiers (ranges), as ItemsTab builds them
	local labels, seenType = { }, { }
	for name, base in pairs(data.itemBases) do
		local key = (base.type or "") .. "|" .. (base.subType or "")
		if not seenType[key] then
			seenType[key] = true
			local okItem, item = pcall(function()
				return new("Item"):Item("Rarity: RARE\nTest\n" .. name)
			end)
			if okItem and item and item.affixes then
				for _, mod in pairs(item.affixes) do
					if (mod.type == "Prefix" or mod.type == "Suffix") and item:CanHaveMod(mod, { }) and not item:CheckIfModIsDelve(mod) then
						local text = table.concat(mod, "/")
						labels[text] = true
						labels[(text:gsub("%(%-?[%d%.]+%-%-?[%d%.]+%)", "#"):gsub("%-?%d+%.?%d*", "#"))] = true
					end
				end
			end
		end
	end
	local list = { }
	for label in pairs(labels) do
		table.insert(list, label)
	end
	table.sort(list)
	local english = 0
	for _, label in ipairs(list) do
		local zh = ZhTWLocale.tr(label)
		if zh:find("%a%a%a") then
			english = english + 1
			log("EN", label, zh)
		end
	end
	log("LABELS", #list, "ENGLISH", english)
	-- 11/26: 10 left (fishing rod lure/hook, "If you've ... Recently" block lines, ranged two-line lines)
	check(english <= 12, "affix labels left in English: " .. english .. " / " .. #list)
end)
if not ok then
	fail = fail + 1
	log("ERROR\t" .. tostring(err))
end
log(string.format("RESULT pass %d fail %d", pass, fail))
logFile:close()
if not os.getenv("ZHTW_NO_EXIT") then
	realSetMainObject({ OnInit = function() realExit() end, OnFrame = function() end })
end
