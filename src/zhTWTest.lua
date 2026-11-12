#@ SimpleGraphic
-- zhTW: headless test for the Taiwan server import.
--
-- Converts saved pathofexile.tw API responses with Modules/ZhTWConverter.lua, imports them
-- into a new build exactly like ImportTab does, and writes the resulting stats.
-- Optionally imports a PoB code for the same character and compares the numbers.
--
-- Usage:
--   set ZHTW_TEST_DIR=<folder with chars.json, items<N>.json, passive<N>.json, [pob<N>.txt]>
--   set ZHTW_TEST_CHARS=1,2          (which numbered files to test)
--   runtime\Path{space}of{space}Building.exe src\zhTWTest.lua
-- Results: src/zhTWTest.log

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local t_insert = table.insert
local logFile = io.open("zhTWTest.log", "w")
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
	local dkjson = require "dkjson"
	local ZhTW = LoadModule("Modules/ZhTWConverter")

	local dir = os.getenv("ZHTW_TEST_DIR") or "."
	local function readFile(name)
		local f = io.open(dir .. "/" .. name, "rb")
		if not f then return nil end
		local d = f:read("*a")
		f:close()
		return d
	end

	local charList = dkjson.decode(readFile("chars.json"))
	ZhTW.convertCharacterList(charList)
	log("== Character list (league converted)")
	for _, c in ipairs(charList) do
		log(c.name, c.class, c.level, c.league)
	end

	local function mainSkillName()
		local group = build.skillsTab.socketGroupList[build.mainSocketGroup]
		if not group or not group.displaySkillList then return "?" end
		local skill = group.displaySkillList[group.mainActiveSkill or 1]
		return skill and skill.activeEffect and skill.activeEffect.grantedEffect.name or "?"
	end
	local statKeys = { "TotalDPS", "CombinedDPS", "FullDPS", "Life", "EnergyShield", "Mana", "Armour", "Evasion",
		"FireResist", "ColdResist", "LightningResist", "ChaosResist", "BlockChance", "SpellBlockChance" }
	local function collectStats()
		build.buildFlag = true
		runCallback("OnFrame")
		local out = build.calcsTab.mainOutput or { }
		local res = { mainSkill = mainSkillName() }
		for _, k in ipairs(statKeys) do
			res[k] = out[k]
		end
		return res
	end
	local function dumpItems(label)
		local unparsed = 0
		log("== Items (" .. label .. ")")
		local slots = { }
		for name, slot in pairs(build.itemsTab.slots) do
			if slot.selItemId and slot.selItemId ~= 0 then
				t_insert(slots, name)
			end
		end
		table.sort(slots)
		for _, name in ipairs(slots) do
			local item = build.itemsTab.items[build.itemsTab.slots[name].selItemId]
			if item then
				log("-- [" .. name .. "] " .. (item.title or "") .. " / " .. (item.baseName or "?"))
				for _, kind in ipairs({ "enchantModLines", "implicitModLines", "explicitModLines" }) do
					for _, ml in ipairs(item[kind] or { }) do
						local bad = ml.extra or (ml.mods and #ml.mods == 0)
						if bad then unparsed = unparsed + 1 end
						log((bad and "   !! " or "      ") .. ml.line .. (ml.extra and ("   <extra: " .. ml.extra .. ">") or ""))
					end
				end
			end
		end
		log("Mod lines PoB did not parse: " .. unparsed)
		return unparsed
	end
	local function dumpSkills()
		log("== Skills")
		for i, group in ipairs(build.skillsTab.socketGroupList) do
			local names = { }
			for _, gem in ipairs(group.gemList) do
				t_insert(names, (gem.nameSpec or "?") .. " " .. tostring(gem.level) .. "/" .. tostring(gem.quality) .. (gem.gemData and "" or (" (UNKNOWN skillId=" .. tostring(gem.skillId) .. " source=" .. tostring(group.source) .. " label=" .. tostring(group.label) .. ")")))
			end
			log(string.format("%s%d [%s] %s", i == build.mainSocketGroup and "*" or " ", i, group.slot or "", table.concat(names, ", ")))
		end
	end

	local which = os.getenv("ZHTW_TEST_CHARS") or "1,2"
	for idx in which:gmatch("%d+") do
		local itemsResp = dkjson.decode(readFile("items" .. idx .. ".json"))
		local passiveResp = dkjson.decode(readFile("passive" .. idx .. ".json"))
		local charName = itemsResp.character and itemsResp.character.name
		local charData
		for _, c in ipairs(charList) do
			if c.name == charName then charData = copyTable(c) end
		end
		charData = charData or copyTable(itemsResp.character)
		log("")
		log("################ Character " .. idx .. ": " .. tostring(charName) .. " (" .. tostring(charData.class) .. " " .. tostring(charData.level) .. ")")

		local t0 = os.clock()
		ZhTW.convertPassiveResponse(passiveResp)
		local nPassive = ZhTW.printReport("passive " .. idx)
		local passiveFailures = copyTable(ZhTW.getReport().failures)
		ZhTW.convertItemsResponse(itemsResp)
		local nItems = ZhTW.printReport("items " .. idx)
		local itemFailures = copyTable(ZhTW.getReport().failures)
		log(string.format("Conversion time: %.2fs", os.clock() - t0))
		log("Conversion failures: passive/jewels " .. nPassive .. ", items " .. nItems)
		for _, f in ipairs(passiveFailures) do log("  FAIL " .. f.item .. " [" .. f.field .. "] " .. f.line) end
		for _, f in ipairs(itemFailures) do log("  FAIL " .. f.item .. " [" .. f.field .. "] " .. f.line) end

		newBuild()
		-- Same steps as ImportTab:DownloadPassiveTree / DownloadItems
		passiveResp.bandit_choice = passiveResp.bandit_choice or build.configTab.input.bandit
		passiveResp.pantheon_major = passiveResp.pantheon_major or build.configTab.input.pantheonMajorGod
		passiveResp.pantheon_minor = passiveResp.pantheon_minor or build.configTab.input.pantheonMinorGod
		local treeData = copyTable(charData)
		treeData.passives = passiveResp
		treeData.jewels = passiveResp.items
		build.importTab:ImportPassiveTreeAndJewels(treeData, true)
		local itemData = copyTable(charData)
		itemData.equipment = itemsResp.items
		itemData.guardian = itemsResp.guardian
		build.importTab:ImportItemsAndSkills(itemData, true, true, false)
		runCallback("OnFrame")
		dumpSkills()
		dumpItems("TW import")
		local twStats = collectStats()
		log("== Stats (TW import)")
		for _, k in ipairs(statKeys) do log(k, twStats[k]) end
		log("mainSkill", twStats.mainSkill)

		local code = readFile("pob" .. idx .. ".txt")
		if code then
			code = code:gsub("%s", "")
			local xml = Inflate(common.base64.decode(code:gsub("-", "+"):gsub("_", "/")))
			if xml and #xml > 0 then
				loadBuildFromXML(xml, "pob" .. idx)
				dumpSkills()
				dumpItems("PoB code")
				local refStats = collectStats()
				log("== Comparison (TW import vs PoB code)")
				for _, k in ipairs(statKeys) do
					local a, b = twStats[k], refStats[k]
					local same = (a == b) or (type(a) == "number" and type(b) == "number" and math.abs(a - b) <= math.max(1e-6, math.abs(b) * 1e-6))
					log(string.format("%-16s %-20s %-20s %s", k, tostring(a), tostring(b), same and "OK" or "DIFF"))
				end
				log(string.format("%-16s %-20s %-20s %s", "mainSkill", twStats.mainSkill, refStats.mainSkill, twStats.mainSkill == refStats.mainSkill and "OK" or "DIFF"))
			else
				log("Could not decode pob" .. idx .. ".txt")
			end
		end
	end
end)
if not ok then
	log("ERROR: " .. tostring(err))
	log(debug and debug.traceback and "" or "")
end
logFile:close()

realSetMainObject({
	OnInit = function() realExit() end,
	OnFrame = function() end,
})
