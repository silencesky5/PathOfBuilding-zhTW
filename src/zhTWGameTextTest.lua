#@ SimpleGraphic
-- zhTW: headless test for gem descriptions, anoint oils on tree tooltips and search synonyms
-- (writes zhTWGameTextTest.log)
--
-- Usage: runtime\Path{space}of{space}Building.exe <full path of src\zhTWGameTextTest.lua>
local realSetMainObject, realExit = SetMainObject, Exit
local logFile = io.open("zhTWGameTextTest.log", "w")
local function log(...)
	local p = { }
	for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
	logFile:write(table.concat(p, "\t"), "\n")
	logFile:flush()
end
local pass, fail = 0, 0
local function check(cond, label, detail)
	if cond then pass = pass + 1 else fail = fail + 1 end
	log(cond and "OK" or "FAIL", label, detail or "")
end
local function hasChinese(s)
	return type(s) == "string" and s:find("[\228-\233][\128-\191][\128-\191]") ~= nil
end
local function tooltipText(tooltip)
	local lines = { }
	for _, line in ipairs(tooltip.lines) do
		if line.text then table.insert(lines, line.text) end
	end
	return table.concat(lines, "\n")
end

local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	ZhTWLocale.enabled = true
	local GameText = LoadModule("Modules/ZhTWGameText")
	ZhTWGameText = GameText

	-- 1. Gem descriptions
	local total, byId, byText, none, noneList = 0, 0, 0, 0, { }
	for _, gem in pairs(build.data.gems) do
		local ge = gem.grantedEffect
		if ge and ge.description then
			total = total + 1
			if GameText.gemDescription(ge) then
				byId = byId + 1
			elseif hasChinese(ZhTWLocale.translate(ge.description)) then
				byText = byText + 1
			else
				none = none + 1
				if #noneList < 10 then table.insert(noneList, ge.id) end
			end
		end
	end
	check(none == 0, "gem descriptions", string.format("%d gems: %d by id, %d by English text, %d none %s", total, byId, byText, none, table.concat(noneList, ",")))
	-- The ones the English-text lookup missed before (multi-line or different English)
	for _, id in ipairs({ "SupportEclipse", "SupportSecondWind", "SupportTransfusion", "SupportGuardiansBlessing", "SmokeMine", "DarkPact", "EtherealKnivesAltX", "PerforateAltY" }) do
		local zh = GameText.gemDescription({ id = id })
		check(hasChinese(zh), "gem description " .. id, zh and zh:gsub("\n", " / "):sub(1, 90))
	end
	-- Through the real gem tooltip
	local gemTooltip = LoadModule("Classes/GemTooltip")
	local gemByEffect = { }
	for _, gem in pairs(build.data.gems) do
		if gem.grantedEffect then gemByEffect[gem.grantedEffect.id] = gem end
	end
	for _, effectId in ipairs({ "Fireball", "SupportEclipse", "SupportSecondWind", "SupportGuardiansBlessing" }) do
		local gemId = effectId
		local gemData = gemByEffect[effectId]
		if gemData then
			local tooltip = new("Tooltip"):Tooltip()
			local okT, errT = pcall(gemTooltip.AddGemTooltip, tooltip, build, { gemData = gemData, level = 1, quality = 0, enabled = true, enableGlobal1 = true })
			local text = tooltipText(tooltip)
			local want = GameText.gemDescription(gemData.grantedEffect)
			local first = want and want:match("^[^\n]+")
			check(okT and first and text:find(first, 1, true) ~= nil, "gem tooltip " .. gemData.name, okT and (first or "no description") or tostring(errT))
		else
			log("skip", gemId)
		end
	end
	-- Gem stat lines: unsupported lines, multi-line descriptions, PoB English outside its value range
	local function gemTooltipText(name, level)
		for _, gem in pairs(build.data.gems) do
			if gem.name == name then
				local tooltip = new("Tooltip"):Tooltip()
				pcall(gemTooltip.AddGemTooltip, tooltip, build, { gemData = gem, level = level, quality = 0, enabled = true, enableGlobal1 = true })
				local lines = { }
				for _, line in ipairs(tooltip.lines) do
					if line.text then table.insert(lines, StripEscapes(ZhTWLocale.tr(line.text))) end
				end
				return table.concat(lines, "\n")
			end
		end
		return ""
	end
	for _, case in ipairs({
		{ "Animate Guardian", 10, "最高可使用物品需求等級 58" },
		{ "Animate Guardian", 10, "(PoB 尚未支援)" },
		{ "Vaal Animate Weapon", 1, "幻化武器轉化至物品需求等級" },
		{ "Spellblade", 20, "附加法術傷害" },
		{ "Summon Phantasm", 1, "召喚幻影上限" },
	}) do
		local text = gemTooltipText(case[1], case[2])
		local hit = text:find(case[3], 1, true)
		local line = hit and text:sub(1, hit):match("([^\n]*)$") .. text:sub(hit + 1):match("^([^\n]*)") or ""
		check(hit ~= nil and not line:find("Can use Items") and not line:find("Not supported"), "gem stat " .. case[1] .. " " .. case[3], line)
	end
	-- Every gem tooltip line (levels 1 and 20): kinds of lines still showing English words
	local leftKinds, leftSample = 0, { }
	local seenKinds = { }
	for _, gem in pairs(build.data.gems) do
		for _, level in ipairs({ 1, 20 }) do
			local tooltip = new("Tooltip"):Tooltip()
			if pcall(gemTooltip.AddGemTooltip, tooltip, build, { gemData = gem, level = level, quality = 0, enabled = true, enableGlobal1 = true }) then
				for _, line in ipairs(tooltip.lines) do
					if line.text and line.font ~= "FONTIN SC ITALIC" then
						local zh = StripEscapes(ZhTWLocale.tr(line.text))
						local isFlavour = zh:find('^"') or zh:find('"$')
						if zh:find("%a%a%a%a") and not isFlavour then
							local key = zh:gsub("%d+%.?%d*", "#")
							if not seenKinds[key] then
								seenKinds[key] = true
								leftKinds = leftKinds + 1
								if #leftSample < 8 then table.insert(leftSample, gem.name .. ": " .. zh) end
							end
						end
					end
				end
			end
		end
	end
	log("gem tooltip lines still in English (incl. flavour text)", leftKinds, table.concat(leftSample, " | "))

	-- 2. Anoint oils
	local tree = build.spec.tree
	local oils, oilMissing = { }, { }
	local recipeNodes = 0
	for _, node in pairs(tree.nodes) do
		if node.recipe then
			recipeNodes = recipeNodes + 1
			for _, id in ipairs(node.recipe) do
				oils[id] = GameText.oilName(id)
			end
		end
	end
	local oilList = { }
	for id, zh in pairs(oils) do
		table.insert(oilList, id .. "=" .. zh)
		if not hasChinese(zh) then table.insert(oilMissing, id) end
	end
	table.sort(oilList)
	check(recipeNodes > 0 and #oilMissing == 0, "oil names", string.format("%d anointable nodes; %s", recipeNodes, table.concat(oilList, " ")))
	-- Tooltip line on a real notable
	local sample
	for _, node in pairs(tree.nodes) do
		if node.recipe and node.dn == "Whispers of Doom" then sample = node end
	end
	for _, node in pairs(tree.nodes) do
		if not sample and node.recipe then sample = node end
	end
	local viewer = build.treeTab and build.treeTab.viewer
	if sample and viewer then
		local tooltip = new("Tooltip"):Tooltip()
		viewer:AddNodeName(tooltip, build.spec.nodes[sample.id] or sample, build)
		local text = tooltipText(tooltip)
		check(text:find("塗油：", 1, true) ~= nil, "tree tooltip " .. sample.dn, text:gsub("\n", " / "))
		ZhTWLocale.enabled = false
		local tooltipEn = new("Tooltip"):Tooltip()
		viewer:AddNodeName(tooltipEn, build.spec.nodes[sample.id] or sample, build)
		check(not tooltipText(tooltipEn):find("塗油", 1, true), "tree tooltip English interface has no oil line")
		ZhTWLocale.enabled = true
	else
		check(false, "tree tooltip", "no recipe node or viewer")
	end

	-- 4. Search synonyms
	local N = ZhTWLocale.normalizeSearch
	check(N("提高攻速") == N("增加攻擊速度"), "normalize 提高攻速", N("提高攻速"))
	check(N("降低") == "減少", "normalize 降低", N("降低"))
	check(N("火焰與冰冷") == N("火焰和冰冷"), "normalize 與/和", N("火焰與冰冷"))
	check(N("Fire 與") == N("Fire 和"), "normalize keeps English", N("Fire 與"))
	check(ZhTWLocale.searchMatch("Fireball", "火球") == true, "searchMatch still finds 火球")
	check(ZhTWLocale.searchMatch("Fireball", "冰球") == false, "searchMatch no false match")
	-- A gem or unique whose Chinese name has 和/與/增加/減少, found with the other word
	local swaps = { { "和", "與" }, { "與", "和" }, { "增加", "提高" }, { "減少", "降低" } }
	local candidates = { }
	for _, gem in pairs(build.data.gems) do table.insert(candidates, gem.name) end
	for name in pairs(build.data.uniques or { }) do table.insert(candidates, name) end
	for _, list in pairs(data.uniques or { }) do
		for _, raw in ipairs(list) do
			local name = raw:match("^%s*([^\n]+)")
			if name then table.insert(candidates, name) end
		end
	end
	for _, sw in ipairs(swaps) do
		local found
		for _, en in ipairs(candidates) do
			local zh = ZhTWLocale.translate(en)
			if zh:find(sw[1], 1, true) then
				found = { en, zh }
				break
			end
		end
		if found then
			local q = found[2]:gsub(sw[1], sw[2])
			check(ZhTWLocale.searchMatch(found[1], q) == true, "search " .. sw[2] .. " finds " .. sw[1], found[2] .. " <- " .. q)
		else
			log("skip", "no name with " .. sw[1])
		end
	end
	-- Unique database search box (same check as zhTWSearchTest)
	local db = build.itemsTab.controls.uniqueDB
	local counts = { }
	for _, q in ipairs({ "全部元素抗性", "全抗" }) do
		db.controls.search:SetText(q)
		db:BuildSortOrder()
		db:ListBuilder()
		counts[q] = #db.list
	end
	check(counts["全抗"] > 0 and counts["全抗"] == counts["全部元素抗性"], "unique search 全抗 = 全部元素抗性", string.format("%d / %d", counts["全抗"], counts["全部元素抗性"]))
	db.controls.search:SetText("")
end)
if not ok then
	fail = fail + 1
	log("ERROR: " .. tostring(err))
end
log(string.format("RESULT pass %d fail %d", pass, fail))
logFile:close()
realSetMainObject({ OnInit = function() realExit() end, OnFrame = function() end })
