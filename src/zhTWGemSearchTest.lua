#@ SimpleGraphic
-- zhTW: headless test for 技能頁「複製名稱」與倉庫搜尋字串 (Modules/ZhTWGemSearch.lua)
-- Usage: Path{space}of{space}Building.exe <full path of src\zhTWGemSearchTest.lua>  → src/zhTWGemSearchTest.log

local realInflate, realDeflate = Inflate, Deflate
local logFile = io.open("zhTWGemSearchTest.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end
print = log
local failures = 0
local function check(cond, what)
	if not cond then
		failures = failures + 1
		log("FAIL", what)
	else
		log("ok", what)
	end
end

local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	Inflate, Deflate = realInflate, realDeflate
	local copied
	Copy = function(text) copied = text end
	ZhTWLocale.enabled = true
	local S = LoadModule("Modules/ZhTWGemSearch")

	-- 1. every gem in PoB has a Taiwan name
	local total, missing = 0, { }
	for _, gemData in pairs(data.gems) do
		if not gemData.name:match("^%[") then
			total = total + 1
			if not S.gemDataName(gemData) then
				table.insert(missing, gemData.name)
			end
		end
	end
	table.sort(missing)
	log(string.format("gems with Taiwan name: %d / %d", total - #missing, total))
	for i = 1, #missing do
		log("   missing: " .. missing[i])
	end

	-- 2. compression (the example from KAI)
	local example = "費爾羅巨獸|費爾羅巨人|初始之地費爾羅|初始之天斯卡沃|初始之潭奎爾珊|初始之夜菲恩絲|費爾羅猛虎幻獸|費爾羅惡狼幻獸|斯卡沃雛鳥|斯卡沃禿鷹|快速施放輔助|秘能波動輔助|暴擊傷害輔助|法術圖騰輔助"
	local names = { }
	for name in example:gmatch("[^|]+") do
		table.insert(names, name)
	end
	local plainLen = S.length(example) + 2
	local strings = S.buildStrings(names, 0)
	log("plain", plainLen, "compressed", S.length(strings[1]), strings[1])
	check(#strings == 1 and S.length(strings[1]) < plainLen, "compressed is shorter")
	-- 3. quality terms
	for _, q in ipairs({ 0, 1, 5, 10, 15, 20, 23 }) do
		log("quality", q, S.qualityTerm(q))
	end
	-- 4. chunks
	local chunks = S.buildStrings(names, 20, 60)
	for _, c in ipairs(chunks) do
		log("chunk", S.length(c), c)
		check(S.length(c) <= 60, "chunk within 60")
	end

	-- 5. the skills tab
	newBuild()
	local skillsTab = build.skillsTab
	local function addGroup(gems, enabled)
		local group = { label = "", enabled = enabled ~= false, gemList = { } }
		for _, g in ipairs(gems) do
			table.insert(group.gemList, { nameSpec = g[1], level = 20, quality = 0, enabled = g[2] ~= false, count = 1, enableGlobal1 = true, enableGlobal2 = true })
		end
		table.insert(skillsTab.socketGroupList, group)
		skillsTab:ProcessSocketGroup(group)
		return group
	end
	local g1 = addGroup({ { "Frostblink of Wintry Blast" }, { "Faster Casting" }, { "Arcanist Brand" }, { "Elemental Weakness" } })
	addGroup({ { "Spell Totem" }, { "Increased Critical Damage" }, { "Fireball", false } })
	addGroup({ { "Herald of Ice" } }, false)
	skillsTab:SetDisplayGroup(g1)
	skillsTab:UpdateGemSlots()
	local used = S.usedGemNames(skillsTab)
	log("used gems: " .. table.concat(used, "、"))
	check(#used == 6, "6 enabled gems (disabled gem and disabled group left out)")
	local slot = skillsTab.gemSlots[2]
	check(slot.zhTWCopyName ~= nil, "copy button on gem row")
	check(slot.zhTWCopyName:IsShown(), "copy button shown in Chinese interface")
	slot.zhTWCopyName.onClick()
	log("copied", copied)
	check(copied == "快速施放輔助", "copied Taiwan gem name")
	check(slot.count:GetProperty("x") == 86, "count moved right")
	local box = skillsTab.controls.zhTWGemSearchBox
	check(box:IsShown(), "search box shown")
	local x, y = box:GetPos()
	log("box", x, y, box:GetSize())
	skillsTab.controls.zhTWGemSearchQuality:SetText("18")
	skillsTab.controls.zhTWGemSearchQuality.changeFunc("18")
	local state = skillsTab.zhTWGemSearch
	box:GetSize() -- refresh
	log("info", skillsTab.controls.zhTWGemSearchInfo:GetProperty("label"))
	for i, c in ipairs(state.chunks) do
		log("tab chunk", i, S.length(c), c)
	end
	check(#state.chunks == 1 and state.chunks[1]:find("品質", 1, true), "tab string has quality term")
	skillsTab.controls.zhTWGemSearchCopy1.onClick()
	check(copied == state.chunks[1], "copy search string")
	-- English interface: nothing of ours
	ZhTWLocale.enabled = false
	check(not slot.zhTWCopyName:IsShown(), "copy button hidden in English")
	check(slot.count:GetProperty("x") == 18, "count back in English")
	check(not box:IsShown(), "search box hidden in English")
	ZhTWLocale.enabled = true
end)
if not ok then
	log("ERROR", err)
	failures = failures + 1
end
log(failures == 0 and "ALL PASSED" or ("FAILURES: " .. failures))
logFile:close()
if not os.getenv("ZHTW_NO_EXIT") then
	os.exit(failures == 0 and 0 or 1)
end
