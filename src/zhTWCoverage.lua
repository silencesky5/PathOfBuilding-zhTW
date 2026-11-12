#@ SimpleGraphic
-- zhTW: finds text that is drawn in English although the Chinese interface is on.
--
-- Imports the saved Taiwan characters (same inputs as zhTWTest.lua), draws every build tab,
-- and builds the tooltips of every item, allocated passive node and gem. Every line that
-- ZhTWLocale could not translate is counted. Results: src/zhTWCoverage.log
--
-- Usage:
--   set ZHTW_TEST_DIR=<folder with chars.json, items<N>.json, passive<N>.json>
--   set ZHTW_TEST_CHARS=1,2
--   runtime\Path{space}of{space}Building.exe src\zhTWCoverage.lua

local realSetMainObject, realExit = SetMainObject, Exit
local logFile = io.open("zhTWCoverage.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end
print = log

local misses = { }
local where = { }
local currentArea = "?"

local ok, err = xpcall(function()
	dofile("HeadlessWrapper.lua")
	local dkjson = require "dkjson"
	local ZhTW = LoadModule("Modules/ZhTWConverter")
	ZhTWLocale.enabled = true
	ZhTWLocale.onMiss = function(line)
		local core = StripEscapes(line):gsub("^%s+", ""):gsub("%s+$", "")
		-- Only text with real words; skip numbers, single letters and user/build names
		if not core:find("%a%a") then
			return
		end
		misses[core] = (misses[core] or 0) + 1
		where[core] = where[core] or currentArea
	end

	local dir = os.getenv("ZHTW_TEST_DIR") or "."
	local function readFile(name)
		local f = io.open(dir .. "/" .. name, "rb")
		if not f then return nil end
		local d = f:read("*a")
		f:close()
		return d
	end

	local function frames(n)
		for _ = 1, n or 2 do
			runCallback("OnFrame")
		end
	end

	-- Build list screen
	currentArea = "BuildList"
	frames(2)

	local charList = dkjson.decode(readFile("chars.json"))
	ZhTW.convertCharacterList(charList)
	local which = os.getenv("ZHTW_TEST_CHARS") or "1,2"
	for idx in which:gmatch("%d+") do
		local itemsResp = dkjson.decode(readFile("items" .. idx .. ".json"))
		local passiveResp = dkjson.decode(readFile("passive" .. idx .. ".json"))
		local charData
		for _, c in ipairs(charList) do
			if c.name == itemsResp.character.name then charData = copyTable(c) end
		end
		charData = charData or copyTable(itemsResp.character)
		ZhTW.convertPassiveResponse(passiveResp)
		ZhTW.convertItemsResponse(itemsResp)
		newBuild()
		local treeData = copyTable(charData)
		treeData.passives = passiveResp
		treeData.jewels = passiveResp.items
		build.importTab:ImportPassiveTreeAndJewels(treeData, true)
		local itemData = copyTable(charData)
		itemData.equipment = itemsResp.items
		build.importTab:ImportItemsAndSkills(itemData, true, true, false)
		frames(2)

		-- Every tab
		for _, mode in ipairs({ "IMPORT", "NOTES", "CONFIG", "TREE", "SKILLS", "ITEMS", "CALCS", "PARTY" }) do
			currentArea = "tab " .. mode
			build.viewMode = mode
			frames(3)
		end
		-- Gem name boxes on the skills tab (edit controls) must show Chinese too
		do
			local seen = { }
			ZhTWLocale.onDraw = function(text)
				if type(text) == "string" and text:find("%S") then
					seen[text] = true
				end
			end
			build.viewMode = "SKILLS"
			build.skillsTab:SetDisplayGroup(build.skillsTab.socketGroupList[1])
			frames(3)
			ZhTWLocale.onDraw = nil
			for k in pairs(seen) do
				log("[gem box] " .. k)
			end
		end
		-- Tooltips
		local tooltip = new("Tooltip"):Tooltip()
		local function drainTooltip(area)
			currentArea = area
			for _, line in ipairs(tooltip.lines) do
				if line.text then
					ZhTWLocale.tr(line.text)
				end
			end
			tooltip:Clear()
		end
		for _, item in pairs(build.itemsTab.items) do
			tooltip:Clear()
			local ok2, e2 = pcall(build.itemsTab.AddItemTooltip, build.itemsTab, tooltip, item)
			if not ok2 then log("item tooltip error: " .. tostring(e2)) end
			drainTooltip("item tooltip")
		end
		local viewer = build.treeTab.viewer
		for _, node in pairs(build.spec.allocNodes) do
			tooltip:Clear()
			local ok2, e2 = pcall(viewer.AddNodeTooltip, viewer, tooltip, node, build)
			if not ok2 then log("node tooltip error: " .. tostring(e2)) end
			drainTooltip("passive tooltip")
		end
		local GemTooltip = LoadModule("Classes/GemTooltip")
		for _, group in ipairs(build.skillsTab.socketGroupList) do
			for _, gem in ipairs(group.gemList) do
				if gem.gemData then
					tooltip:Clear()
					local ok2, e2 = pcall(GemTooltip.AddGemTooltip, tooltip, build, gem)
					if not ok2 then log("gem tooltip error: " .. tostring(e2)) end
					drainTooltip("gem tooltip")
				end
			end
		end
	end

	-- Frame time with the Chinese interface on and off (last imported build)
	for _, mode in ipairs({ "TREE", "CALCS", "ITEMS", "CONFIG" }) do
		build.viewMode = mode
		frames(3)
		local times = { }
		for _, enabled in ipairs({ true, false, true }) do
			ZhTWLocale.enabled = enabled
			local t0 = os.clock()
			frames(20)
			table.insert(times, string.format("%s %.1f ms/frame", enabled and "zh" or "en", (os.clock() - t0) * 1000 / 20))
		end
		log("== Frame time " .. mode .. ": " .. table.concat(times, ", "))
	end
	ZhTWLocale.enabled = true

	-- Report
	local list = { }
	for text, n in pairs(misses) do
		table.insert(list, { text = text, n = n })
	end
	table.sort(list, function(a, b)
		if where[a.text] ~= where[b.text] then return where[a.text] < where[b.text] end
		return a.text < b.text
	end)
	log(string.format("== Untranslated lines: %d", #list))
	for _, m in ipairs(list) do
		log(string.format("[%s] %s", where[m.text], m.text))
	end
end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
if not ok then
	log("ERROR: " .. tostring(err))
end
logFile:close()

realSetMainObject({
	OnInit = function() realExit() end,
	OnFrame = function() end,
})
