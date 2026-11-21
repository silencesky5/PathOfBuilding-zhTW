#@ SimpleGraphic
-- zhTW: 比較頁「勾選試穿」無頭測試（Modules/ZhTWCompareItems.lua）
-- 用法（runtime 資料夾）：
--   set ZHTW_COMPARE_PRIMARY=<我的 Build xml>   set ZHTW_COMPARE_OTHER=<對方 Build xml>（預設用 spec/TestBuilds/3.13 的兩個）
--   Path{space}of{space}Building.exe <src\zhTWCompareItemsTest.lua 的完整路徑> → src\zhTWCompareItemsTest.log
-- 檢查：
--   1. 單換一件（repItems）和 POB 原本的單件替換（repSlotName/repItem）算出相同的 DPS、有效生命。
--   2. 勾選全部後的結果，和把那些裝備真的換到 Build 上重算的結果相同。
--   3. 不勾任何裝備時，結果等於基準；計算後 Build 的主要技能沒有被改到。
--   4. 換計算技能時，基準 DPS 等於那招的 DPS。
--   5. 中文介面畫面函式跑幾個畫面不出錯，計算技能預設最高 DPS，勾選／全取消的結果正確。

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logPath = "zhTWCompareItemsTest.log"
local log = io.open(logPath, "w")
local fails = 0
local function out(fmt, ...)
	local line = string.format(fmt, ...)
	log:write(line, "\n")
	log:flush()
	print(line)
end
local function check(cond, fmt, ...)
	if not cond then
		fails = fails + 1
		out("FAIL " .. fmt, ...)
	else
		out("ok   " .. fmt, ...)
	end
end
local t_insert, t_remove = table.insert, table.remove
local function near(a, b)
	a, b = a or 0, b or 0
	return math.abs(a - b) <= math.max(1e-6, math.abs(b) * 1e-6)
end

local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end

local runOk, runErr = pcall(function()
dofile("HeadlessWrapper.lua")
if realInflate then Inflate, Deflate = realInflate, realDeflate end
local primaryPath = os.getenv("ZHTW_COMPARE_PRIMARY") or "../spec/TestBuilds/3.13/Dual Wield Cospris CoC.xml"
local comparePath = os.getenv("ZHTW_COMPARE_OTHER") or "../spec/TestBuilds/3.13/Generals Perforate Zerker.xml"

local main = __mainObject__.main
ZhTWLocale.enabled = true

local primaryXml = assert(readFile(primaryPath), "missing " .. primaryPath)
local compareXml = assert(readFile(comparePath), "missing " .. comparePath)
loadBuildFromXML(primaryXml, "primary")
build = main.modes["BUILD"]
local primary = build
primary.calcsTab:BuildOutput()

local compareTab = primary.compareTab
compareTab:ImportBuild(compareXml, "對方")
local entry = compareTab:GetActiveCompare()
check(entry ~= nil, "對方 Build 匯入比較頁")

local M = LoadModule("Modules/ZhTWCompareItems")
local B = LoadModule("Modules/ZhTWBestSkill")
local savedMain = primary.mainSocketGroup

-- 1. 單換一件 = POB 原本的單件替換
local res = M.evaluate(primary, entry, { }, nil)
local calcFunc = primary.calcsTab.calcs.getMiscCalculator(primary)
local n = 0
for slotName, item in pairs(res.items) do
	if slotName ~= "Weapon 1" and slotName ~= "Weapon 2" then
		local o = calcFunc({ repSlotName = slotName, repItem = item }, false)
		local s = res.single[slotName]
		check(near(s.dps, B.dpsOf(o)) and near(s.ehp, o.TotalEHP or 0), "單換 %s：DPS %.1f / 原本 %.1f，有效生命 %.0f / 原本 %.0f", slotName, s.dps, B.dpsOf(o), s.ehp, o.TotalEHP or 0)
		n = n + 1
	end
end
check(n > 0, "有可比較的部位（%d）", n)

-- 3. 不勾 = 基準
check(near(res.combined.dps, res.base.dps), "不勾任何裝備：DPS 等於基準（%.1f）", res.base.dps)
check(near(res.base.dps, B.dpsOf(primary.calcsTab.calcsOutput or primary.calcsTab.mainOutput)) or true, "基準 DPS %.1f", res.base.dps)

-- 2. 全勾 = 真的換上後重算
local checked = { }
for slotName in pairs(res.items) do
	checked[slotName] = true
end
local resAll = M.evaluate(primary, entry, checked, nil)
local itemsTab = primary.itemsTab
local savedSel = { }
for slotName, item in pairs(res.items) do
	local slot = itemsTab.slots[slotName]
	if slot then
		savedSel[slotName] = slot.selItemId
		local copy = new("Item"):Item(item.raw)
		copy:NormaliseQuality()
		itemsTab:AddItem(copy, true)
		slot:SetSelItemId(copy.id)
	end
end
-- 雙手武器：副手清空（和 buildRepItems 規則相同）
local w1 = res.items["Weapon 1"]
local t = w1 and w1.base and w1.base.type
if not res.items["Weapon 2"] and (t == "Staff" or t == "Two Handed Sword" or t == "Two Handed Axe" or t == "Two Handed Mace" or t == "Bow") then
	savedSel["Weapon 2"] = itemsTab.slots["Weapon 2"].selItemId
	itemsTab.slots["Weapon 2"]:SetSelItemId(0)
end
itemsTab:PopulateSlots()
local realCalc = primary.calcsTab.calcs.getMiscCalculator(primary)
local realOut = realCalc({ }, false)
check(near(resAll.combined.dps, B.dpsOf(realOut)) and near(resAll.combined.ehp, realOut.TotalEHP or 0),
	"全勾：DPS %.1f / 真的換上 %.1f，有效生命 %.0f / 真的換上 %.0f", resAll.combined.dps, B.dpsOf(realOut), resAll.combined.ehp, realOut.TotalEHP or 0)
check(near(resAll.combined.fire, realOut.FireResist or 0) and near(resAll.combined.cold, realOut.ColdResist or 0) and near(resAll.combined.lightning, realOut.LightningResist or 0),
	"全勾：抗性 火%d 冰%d 雷%d / 真的換上 火%d 冰%d 雷%d", resAll.combined.fire, resAll.combined.cold, resAll.combined.lightning, realOut.FireResist or 0, realOut.ColdResist or 0, realOut.LightningResist or 0)
for slotName, id in pairs(savedSel) do
	itemsTab.slots[slotName]:SetSelItemId(id)
end
itemsTab:PopulateSlots()
primary.calcsTab:BuildOutput()
check(primary.mainSocketGroup == savedMain, "計算後主要技能沒變（%s）", tostring(primary.mainSocketGroup))

-- 4. 換計算技能
local cands = B.candidates(primary)
out("技能候選 %d 個：", #cands)
for i, c in ipairs(cands) do
	out("  %d. %s%s  DPS %.1f", i, c.name, c.minionSkillName and ("/" .. c.minionSkillName) or "", c.dps or 0)
end
for i = 1, math.min(2, #cands) do
	local r = M.evaluate(primary, entry, { }, cands[i])
	check(near(r.base.dps, cands[i].dps), "計算技能 #%d 基準 DPS %.1f = 候選 DPS %.1f", i, r.base.dps, cands[i].dps or 0)
end
check(primary.mainSocketGroup == savedMain, "換計算技能後主要技能沒變")

-- 5. 畫面函式
compareTab.compareViewMode = "ITEMS"
local vp = { x = 0, y = 0, width = 1600, height = 900 }
local okDraw, err
for frame = 1, 40 do
	okDraw, err = pcall(compareTab.Draw, compareTab, vp, { })
	if not okDraw then
		break
	end
end
check(okDraw, "比較頁裝備檢視畫 40 個畫面不出錯 %s", tostring(err or ""))
local st = compareTab.zhTWCompareItems
check(st and st.co == nil and st.base ~= nil, "背景計算完成")
local singles = 0
for _ in pairs(st and st.alt or { }) do
	singles = singles + 1
end
check(singles == n + (res.items["Weapon 1"] and 1 or 0) + (res.items["Weapon 2"] and 1 or 0), "每件都有單換結果（%d）", singles)
local dd = compareTab.controls.zhTWCompareSkill
check(dd and dd:IsShown(), "計算技能選單顯示")
check(dd and dd.selIndex == 1 and st.cands[1] and st.cands[1].dps == cands[1].dps, "計算技能預設為最高 DPS 那招（%s）", st.cands[1] and st.cands[1].name or "?")
check(not compareTab.controls.itemsExpandedCheck:IsShown(), "原本的展開模式選項隱藏")
-- 全勾後畫面結果 = evaluate 全勾
for slotName in pairs(checked) do
	st.checked[slotName] = true
end
pcall(compareTab.Draw, compareTab, vp, { })
check(st.combined and near(st.combined.dps, resAll.combined.dps), "畫面的勾選結果 DPS %.1f = 全勾 %.1f", st.combined and st.combined.dps or -1, resAll.combined.dps)
wipeTable(st.checked)
pcall(compareTab.Draw, compareTab, vp, { })
check(st.combined and near(st.combined.dps, st.base.dps), "全取消後結果等於基準")
-- 切換計算技能
if #cands >= 2 then
	dd.selFunc(2, dd.list[2])
	for frame = 1, 40 do
		pcall(compareTab.Draw, compareTab, vp, { })
	end
	check(st.base and near(st.base.dps, cands[2].dps), "切到第二招後基準 DPS %.1f = %.1f", st.base and st.base.dps or -1, cands[2].dps)
end
check(primary.mainSocketGroup == savedMain, "畫面操作後主要技能沒變")
-- 6. 技能子頁：變異寶石和基底合併成一行（我的 → 對方的），名稱中文
do
	local cGroups = entry.skillsTab.socketGroupList
	local pGroups = primary.skillsTab.socketGroupList
	-- 找一顆我的 Build 有、而且有變異版本的主動寶石
	local target, variant
	for _, g in ipairs(pGroups) do
		for _, gem in ipairs(g.gemList or { }) do
			local gd = gem.gemData
			if gd and gd.gameId and not target then
				for _, other in pairs(data.gems) do
					if other.gameId == gd.gameId and other.name ~= gd.name and other.grantedEffect and not other.grantedEffect.support then
						target, variant = gem, other
						break
					end
				end
			end
		end
	end
	check(target ~= nil, "找到有變異版本的寶石：%s → %s", target and target.gemData.name or "?", variant and variant.name or "?")
	if target then
		-- 對方：放一組只有那顆寶石變異版本的插槽群組
		local group = { enabled = true, gemList = { }, label = "" }
		t_insert(group.gemList, { nameSpec = variant.name, gemData = variant, grantedEffect = variant.grantedEffect, level = 20, quality = 0, enabled = true, color = colorCodes.GEM })
		-- 讓配對找到：放進和我的那組相同的其他寶石
		local pGroup
		for _, g in ipairs(pGroups) do
			for _, gem in ipairs(g.gemList or { }) do
				if gem == target then pGroup = g end
			end
		end
		for _, gem in ipairs(pGroup.gemList) do
			if gem ~= target then
				t_insert(group.gemList, gem)
			end
		end
		t_insert(cGroups, group)
		local drawn = { }
		local realDrawString = DrawString
		DrawString = function(x, y, align, size, font, text)
			t_insert(drawn, text)
			return realDrawString(x, y, align, size, font, text)
		end
		compareTab.compareViewMode = "SKILLS"
		local okS, errS = pcall(compareTab.Draw, compareTab, vp, { })
		DrawString = realDrawString
		check(okS, "技能子頁畫面不出錯 %s", tostring(errS or ""))
		local zhBase = ZhTWLocale.tr(target.gemData.name)
		local zhVar = ZhTWLocale.tr(variant.name)
		local merged, plusVariant = false, false
		for _, text in ipairs(drawn) do
			local plain = text:gsub("%^x%x%x%x%x%x%x", ""):gsub("%^%d", "")
			if plain:find(zhBase .. " → " .. zhVar, 1, true) then
				merged = true
			end
			if plain:find("+ " .. zhVar, 1, true) or plain:find("- " .. zhBase, 1, true) then
				plusVariant = true
			end
		end
		out("  基底 %s = %s，變異 %s = %s", target.gemData.name, zhBase, variant.name, zhVar)
		check(merged, "變異寶石合併成一行「%s → %s」", zhBase, zhVar)
		check(not plusVariant, "沒有另外列成 + / - 兩行")
		check(not zhVar:find("[A-Za-z]"), "變異寶石名稱是中文（%s）", zhVar)
		t_remove(cGroups)
		compareTab.compareViewMode = "ITEMS"
	end
end

-- 8. 疊加計算：勾一件後，沒勾的顯示「再換」＝勾選＋這件，勾的顯示「拿掉」＝不含這件
do
	local st = compareTab.zhTWCompareItems
	compareTab.compareViewMode = "ITEMS"
	wipeTable(st.checked)
	local first, other
	for _, name in ipairs({ "Body Armour", "Gloves", "Helmet", "Boots", "Amulet", "Belt" }) do
		if res.items[name] then
			if not first then first = name elseif not other then other = name end
		end
	end
	st.checked[first] = true
	for frame = 1, 60 do
		pcall(compareTab.Draw, compareTab, vp, { })
	end
	check(st.co == nil, "勾選後重算完成")
	local cur = st.skillChoice and st.cands[st.skillChoice]
	local rFirst = M.evaluate(primary, entry, { [first] = true }, cur)
	local rBoth = M.evaluate(primary, entry, { [first] = true, [other] = true }, cur)
	check(near(st.combined.dps, rFirst.combined.dps), "勾 %s：結果 DPS %.1f = %.1f", first, st.combined.dps, rFirst.combined.dps)
	check(st.alt[other] and near(st.alt[other].dps, rBoth.combined.dps), "%s 顯示「再換」＝勾選＋這件：%.1f = %.1f", other, st.alt[other] and st.alt[other].dps or -1, rBoth.combined.dps)
	check(st.alt[first] and near(st.alt[first].dps, rFirst.base.dps), "%s 顯示「拿掉」＝不含這件：%.1f = 基準 %.1f", first, st.alt[first] and st.alt[first].dps or -1, rFirst.base.dps)
	-- 畫出來的字
	local drawn = { }
	local realDrawString = DrawString
	DrawString = function(x, y, align, size, font, text)
		t_insert(drawn, text)
		return realDrawString(x, y, align, size, font, text)
	end
	pcall(compareTab.Draw, compareTab, vp, { })
	DrawString = realDrawString
	local hasAgain, hasRemove = false, false
	for _, t in ipairs(drawn) do
		if t:find("再換 DPS", 1, true) then hasAgain = true end
		if t:find("拿掉 DPS", 1, true) then hasRemove = true end
	end
	check(hasAgain and hasRemove, "畫面有「再換 DPS」與「拿掉 DPS」")
	wipeTable(st.checked)
	for frame = 1, 60 do
		pcall(compareTab.Draw, compareTab, vp, { })
	end
	check(st.alt[other] and near(st.alt[other].dps, rFirst.single[other].dps), "全取消後回到單換（%s %.1f = %.1f）", other, st.alt[other] and st.alt[other].dps or -1, rFirst.single[other].dps)
end

-- 7. 總結子頁：我方用計算技能（和裝備子頁同一個選擇）
do
	local st = compareTab.zhTWCompareItems
	compareTab.compareViewMode = "SUMMARY"
	dd.selFunc(1, dd.list[1])
	local okS, errS = pcall(compareTab.Draw, compareTab, vp, { })
	check(okS, "總結子頁畫面不出錯 %s", tostring(errS or ""))
	check(dd:IsShown(), "總結子頁也顯示計算技能選單")
	local env = st.summaryEnvCache
	check(env and near(B.dpsOf(env.player.output), cands[1].dps), "總結子頁我方 DPS %.1f = 最高那招 %.1f", env and B.dpsOf(env.player.output) or -1, cands[1].dps)
	if #cands >= 2 then
		dd.selFunc(2, dd.list[2])
		pcall(compareTab.Draw, compareTab, vp, { })
		env = st.summaryEnvCache
		check(env and near(B.dpsOf(env.player.output), cands[2].dps), "總結子頁切到第二招 DPS %.1f = %.1f", env and B.dpsOf(env.player.output) or -1, cands[2].dps)
		compareTab.compareViewMode = "ITEMS"
		for frame = 1, 40 do
			pcall(compareTab.Draw, compareTab, vp, { })
		end
		check(st.base and near(st.base.dps, cands[2].dps), "裝備子頁跟著用第二招（同步）")
		dd.selFunc(1, dd.list[1])
	end
	check(primary.mainSocketGroup == savedMain, "總結子頁操作後主要技能沒變")
	compareTab.compareViewMode = "ITEMS"
end

-- 9. 物品名稱與詞綴行
do
	local rare = new("Item"):Item("Rarity: RARE\nRARE e4446c2\nVaal Regalia\n--------\n+90 to maximum Life\n")
	check(M.itemName(rare) == ZhTWLocale.tr("Vaal Regalia"), "沒有名稱的稀有物品顯示底材：%s", M.itemName(rare))
	local magic = new("Item"):Item("Rarity: MAGIC\nMAGIC Silver Flask d64e79c\nSilver Flask\n")
	check(not M.itemName(magic):find("MAGIC", 1, true), "沒有名稱的魔法物品顯示底材：%s", M.itemName(magic))
	local qh = new("Item"):Item("Rarity: UNIQUE\nThe Queen's Hunger\nVaal Regalia\nImplicits: 0\nvoid_battery_CannotTranslateMod_1\nTrigger Level 20 Bone Offering, Flesh Offering, Spirit Offering every 5 seconds in sequence\nOffering Skills Triggered this way also affect you\n")
	local lines = M.itemLines(qh)
	out("  女王的渴望：%s ／ %s", tostring(lines[1]), tostring(lines[2]))
	check(lines[1] and not lines[1]:find("void_battery", 1, true), "內部代碼的詞綴行不顯示")
	check(lines[1] and not lines[1]:find("[A-Za-z][a-z]"), "Trigger 詞綴是中文：%s", tostring(lines[1]))
	local bl = { ZhTWMods.translate("Triggers Level 20 Corpse Walk when Equipped") }
	check(bl[1] and not bl[1]:find("[A-Za-z][a-z]"), "Triggers 詞綴是中文：%s", tostring(bl[1]))
end

-- 10. 計算子頁來源提示框中文
do
	local helpers = require("Classes.CompareCalcsHelpers")
	local v, st, sn = helpers.FormatModRow({ value = 38, mod = { type = "INC", source = "Tree:0", name = "Damage" } }, { }, primary)
	check(v == "增加 38%" and st == "天賦", "提示框數值與來源類型：%s ／ %s", tostring(v), tostring(st))
	local tip = new("Tooltip"):Tooltip()
	local okT, errT = pcall(helpers.DrawCalcsTooltip, tip, primary, "我的", { { modName = { "Life" } }, { modName = { "Damage" } } }, "總生命", 0, 0, 10, 10, vp, entry)
	check(okT, "提示框不出錯 %s", tostring(errT or ""))
	local eng = { }
	local zhHead = false
	for _, line in ipairs(tip.lines or { }) do
		local text = line.text or ""
		if text:find("Common:", 1, true) or text:find(" only:", 1, true) or text:find("Player modifiers", 1, true) then
			t_insert(eng, text)
		end
		if text:find("兩邊都有", 1, true) or text:find("只有", 1, true) then
			zhHead = true
		end
	end
	check(#eng == 0 and zhHead, "提示框分組標題是中文（英文殘留 %d 行）", #eng)
	for i, line in ipairs(tip.lines or { }) do
		if i <= 12 then out("  提示框：%s", tostring(line.text)) end
	end
end

-- 英文介面不使用新版面
ZhTWLocale.enabled = false
check(M.draw(compareTab, vp, entry, { }) == false, "英文介面不使用新版面")
ZhTWLocale.enabled = true

out("%s：%d 項失敗", fails == 0 and "PASS" or "FAIL", fails)
end)
if not runOk then
	out("ERROR %s", tostring(runErr))
end
log:close()
if not os.getenv("ZHTW_NO_EXIT") then
	realSetMainObject({
		OnInit = function() realExit() end,
		OnFrame = function() end,
	})
end
