-- Path of Building
--
-- Module: zhTW Compare Items
-- 比較頁「裝備」檢視的中文介面版面（KAI 11/21）：勾選對方的裝備，試穿到我的 Build 上，看數值變化。
--   * 最上方固定：計算技能選單＋三格結果（總 DPS、有效生命、火／冰／雷抗性），綠色上升、紅色下降。
--   * 下方左右兩欄：左「我的配置」、右「對方配置」，同一個部位排在同一列。
--   * 對方每件裝備前有勾選框；勾起來的那列加橘色外框；最右邊標示「單換 DPS ±X%」（只換那一件）。
--   * 右上角「全選」「全取消」。
--   * 只換裝備：技能寶石、天賦樹、設定都用我自己的。天賦珠寶、守衛裝備不納入。
--   * 計算技能預設為我的 Build 裡傷害最高的那招（Modules/ZhTWBestSkill，召喚物技能也算），可手動切換；
--     只影響這一頁的數字，不會改到 Build 的主要技能。
--   * 不會更動 Build：要真的換上，還是用原本的「複製」功能或裝備頁。
-- 計算：POB 自己的 GetMiscCalculator（和物品提示「裝上後的變化」同一套）；
-- 一次換多件用 CalcSetup 的 override.repItems（標註 -- zhTW 的掛勾）。
--
-- Public API:
--   ZhTWCompareItems.draw(compareTab, vp, compareEntry, inputEvents) → true 表示已經畫好（中文介面）
--   ZhTWCompareItems.evaluate(primaryBuild, compareEntry, checked, cand) → 測試用，同步算出結果表
--
local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert
local t_concat = table.concat
local s_format = string.format
local m_max = math.max
local m_min = math.min
local m_floor = math.floor

local BestSkill = LoadModule("Modules/ZhTWBestSkill")

local M = { }

local FRAME_BUDGET = 25   -- 每個畫面最多計算幾毫秒

local HEADER_H = 78       -- CompareTab 原本的頂部（Build 名稱、物品配置選單），保留
local SKILL_ROW_H = 26
local CARD_H = 70
local COL_HEAD_H = 30
local ROW_H = 54
local ROW_GAP = 4
local LABEL_W = 64
local CHECK_W = 34
local SCROLLBAR_W = 22

local ORANGE = { 0.93, 0.58, 0.16 }

-- 比較的部位（天賦珠寶、守衛裝備不納入）
local SLOTS = {
	{ "Weapon 1", "武器" },
	{ "Weapon 2", "副手" },
	{ "Helmet", "頭盔" },
	{ "Body Armour", "胸甲" },
	{ "Gloves", "手套" },
	{ "Boots", "鞋子" },
	{ "Belt", "腰帶" },
	{ "Amulet", "項鍊" },
	{ "Ring 1", "戒指1" },
	{ "Ring 2", "戒指2" },
	{ "Ring 3", "戒指3" },
	{ "Flask 1", "藥劑1" },
	{ "Flask 2", "藥劑2" },
	{ "Flask 3", "藥劑3" },
	{ "Flask 4", "藥劑4" },
	{ "Flask 5", "藥劑5" },
}

local function enabled()
	return ZhTWLocale and ZhTWLocale.enabled
end

local function tr(text)
	if text and ZhTWLocale and ZhTWLocale.tr then
		return ZhTWLocale.tr(text) or text
	end
	return text
end

-- ===== 計算 =====

-- 暫時把 cand 設成主要技能來執行 f（算完一定還原）；cand 為 nil 時用 Build 目前的主要技能
local function withCand(build, cand, f, ...)
	if not cand then
		return f(...)
	end
	local group = build.skillsTab.socketGroupList[cand.groupIndex]
	local inst = cand.minionSkillIndex and cand.srcInstance
	local savedMain = build.mainSocketGroup
	local savedActive = group and group.mainActiveSkill
	local savedMinion = inst and inst.skillMinionSkill
	build.mainSocketGroup = cand.groupIndex
	if group then
		group.mainActiveSkill = cand.activeIndex
	end
	if inst then
		inst.skillMinionSkill = cand.minionSkillIndex
	end
	local ok, a, b = pcall(f, ...)
	build.mainSocketGroup = savedMain
	if group then
		group.mainActiveSkill = savedActive
	end
	if inst then
		inst.skillMinionSkill = savedMinion
	end
	if not ok then
		error(a, 0)
	end
	return a, b
end

-- 回傳 calc(override) → output，以及基準 output
local function makeCalculator(build, cand)
	local calcFunc, base = withCand(build, cand, build.calcsTab.calcs.getMiscCalculator, build)
	return function(override)
		return withCand(build, cand, calcFunc, override, false)
	end, base
end

local function isTwoHanded(item)
	local t = item and item.base and item.base.type
	return t == "Staff" or t == "Two Handed Sword" or t == "Two Handed Axe" or t == "Two Handed Mace" or t == "Bow"
end

-- 勾選的部位 → CalcSetup 用的 repItems（false = 該部位清空）
local function buildRepItems(primaryBuild, items, checked)
	local rep = { }
	local any = false
	for slotName in pairs(checked) do
		if items[slotName] then
			rep[slotName] = items[slotName]
			any = true
		end
	end
	if not any then
		return nil
	end
	-- 換上雙手武器（或弓）時，副手跟著清空（弓保留箭袋），和 POB 單件替換的規則相同
	local w1 = rep["Weapon 1"]
	if w1 and rep["Weapon 2"] == nil and isTwoHanded(w1) then
		local pSlot = primaryBuild.itemsTab.slots["Weapon 2"]
		local cur = pSlot and primaryBuild.itemsTab.items[pSlot.selItemId]
		if not (w1.base.type == "Bow" and cur and cur.base and cur.base.type == "Quiver") then
			rep["Weapon 2"] = false
		end
	end
	return rep
end

local function metrics(output)
	output = output or { }
	return {
		dps = BestSkill.dpsOf(output),
		ehp = output.TotalEHP or 0,
		fire = output.FireResist or 0,
		cold = output.ColdResist or 0,
		lightning = output.LightningResist or 0,
	}
end

local function pctChange(before, after)
	if not before or before <= 0 then
		return nil
	end
	return (after - before) / before * 100
end

-- 對方各部位的物品（新建一份，和「複製」按鈕相同的作法）
local function compareItems(compareEntry, slots)
	local items = { }
	local cTab = compareEntry.itemsTab
	for _, slot in ipairs(slots) do
		local cSlot = cTab and cTab.slots and cTab.slots[slot[1]]
		local cItem = cSlot and cTab.items and cTab.items[cSlot.selItemId]
		if cItem and cItem.raw then
			local newItem = new("Item"):Item(cItem.raw)
			newItem:NormaliseQuality()
			items[slot[1]] = newItem
		end
	end
	return items
end

local function activeSlots(compareTab, compareEntry)
	local list = { }
	local showRing3 = compareTab and compareTab.ShouldShowRing3 and compareTab:ShouldShowRing3(compareEntry)
	for _, slot in ipairs(SLOTS) do
		if slot[1] ~= "Ring 3" or showRing3 then
			t_insert(list, slot)
		end
	end
	return list
end

-- 同步計算（測試用）：checked = { [slotName] = true }，cand = 計算技能候選（nil = 主要技能）
function M.evaluate(primaryBuild, compareEntry, checked, cand)
	local slots = activeSlots(nil, compareEntry)
	local items = compareItems(compareEntry, slots)
	local calc, base = makeCalculator(primaryBuild, cand)
	local result = { base = metrics(base), single = { }, items = items }
	for _, slot in ipairs(slots) do
		local item = items[slot[1]]
		if item then
			local rep = buildRepItems(primaryBuild, items, { [slot[1]] = true })
			result.single[slot[1]] = metrics(calc({ repItems = rep }))
		end
	end
	local rep = buildRepItems(primaryBuild, items, checked or { })
	result.combined = rep and metrics(calc({ repItems = rep })) or result.base
	return result
end

-- ===== 狀態 =====

local function getState(compareTab)
	local st = compareTab.zhTWCompareItems
	if not st then
		st = { checked = { }, skillChoice = nil }
		compareTab.zhTWCompareItems = st
	end
	return st
end

local function itemSignature(compareEntry, slots)
	local parts = { }
	local cTab = compareEntry.itemsTab
	for _, slot in ipairs(slots) do
		local cSlot = cTab and cTab.slots and cTab.slots[slot[1]]
		t_insert(parts, tostring(cSlot and cSlot.selItemId or 0))
	end
	return t_concat(parts, ",")
end

local function candLabel(cand)
	local name = tr(cand.name) or "?"
	if cand.minionSkillName then
		name = name .. "／" .. (tr(cand.minionSkillName) or cand.minionSkillName)
	end
	return name
end

local function formatNumber(value)
	if value >= 100000000 then
		return s_format("%.2f億", value / 100000000)
	elseif value >= 10000 then
		return s_format("%.1f萬", value / 10000)
	end
	return s_format("%.1f", value)
end

-- 技能候選（Build 每次重算後重新排一次）
local function refreshCandidates(st, build)
	if st.candRevision == build.outputRevision and st.cands then
		return
	end
	local ok, cands = pcall(BestSkill.candidates, build)
	if not ok then
		ConPrintf("zhTW compare: %s", tostring(cands))
		cands = { }
	end
	-- 記住使用者手動選的那招（同一組、同一個主動技能、同一招召喚物技能）
	local keep = st.manualKey
	st.cands = cands
	st.candRevision = build.outputRevision
	st.skillChoice = 1
	if keep then
		for i, cand in ipairs(cands) do
			if (cand.groupIndex .. ":" .. cand.activeIndex .. ":" .. tostring(cand.minionSkillIndex)) == keep then
				st.skillChoice = i
				break
			end
		end
	end
	local list = { }
	local seen = { }
	for _, cand in ipairs(cands) do
		local key = candLabel(cand)
		seen[key] = (seen[key] or 0) + 1
	end
	for i, cand in ipairs(cands) do
		local text = candLabel(cand)
		if seen[text] > 1 then
			text = text .. s_format(" ^8（第 %d 組）^7", cand.groupIndex) -- 同名技能在不同插槽群組
		end
		text = text .. "  ^8" .. formatNumber(cand.dps or 0)
		if i == 1 and (cand.dps or 0) > 0 then
			text = text .. "^7（最高）"
		end
		t_insert(list, text)
	end
	if #list == 0 then
		list = { "主要技能" }
	end
	st.skillList = list
end

local function currentCand(st)
	local cand = st.cands and st.cands[st.skillChoice or 1]
	if cand and (cand.dps or 0) <= 0 and st.skillChoice == 1 then
		return nil -- 沒有任何技能有傷害：用 Build 的主要技能
	end
	return cand
end

-- 開始（或重新開始）計算：基準與每件單換，分散到每個畫面
local function startJob(st, build, compareEntry, slots, sig)
	st.sig = sig
	st.items = compareItems(compareEntry, slots)
	st.single = { }
	st.singleOutput = { }
	st.combined = nil
	st.combinedSig = nil
	st.calc = nil
	st.base = nil
	st.baseOutput = nil
	st.error = nil
	local cand = currentCand(st)
	st.co = coroutine.create(function()
		local calc, base = makeCalculator(build, cand)
		st.calc = calc
		st.baseOutput = base
		st.base = metrics(base)
		coroutine.yield()
		for _, slot in ipairs(slots) do
			local item = st.items[slot[1]]
			if item then
				local rep = buildRepItems(build, st.items, { [slot[1]] = true })
				local out = calc({ repItems = rep })
				st.singleOutput[slot[1]] = out
				st.single[slot[1]] = metrics(out)
				coroutine.yield()
			end
		end
	end)
end

local function runJob(st)
	if not st.co then
		return
	end
	local start = GetTime()
	repeat
		local ok, err = coroutine.resume(st.co)
		if not ok then
			st.error = tostring(err)
			ConPrintf("zhTW compare: %s", st.error)
			st.co = nil
			return
		end
		if coroutine.status(st.co) == "dead" then
			st.co = nil
			return
		end
	until GetTime() - start > FRAME_BUDGET
end

local function checkedSignature(st, slots)
	local parts = { }
	for _, slot in ipairs(slots) do
		if st.checked[slot[1]] and st.items and st.items[slot[1]] then
			t_insert(parts, slot[1])
		end
	end
	return t_concat(parts, ",")
end

local function updateCombined(st, build, slots)
	if not st.calc or not st.base then
		return
	end
	local csig = checkedSignature(st, slots)
	if st.combinedSig == csig then
		return
	end
	st.combinedSig = csig
	local rep = buildRepItems(build, st.items, st.checked)
	if not rep then
		st.combined = st.base
		return
	end
	local ok, out = pcall(st.calc, { repItems = rep })
	if ok then
		st.combined = metrics(out)
	else
		st.error = tostring(out)
		st.combined = nil
	end
end

-- ===== 控制項 =====

local function setupControls(compareTab)
	if compareTab.controls.zhTWCompareSkill then
		return
	end
	local controls = compareTab.controls
	local function itemsZh()
		return enabled() and compareTab.compareViewMode == "ITEMS" and compareTab:GetActiveCompare() ~= nil
	end
	-- 原本的「展開模式」與天賦配置選單在中文版面不顯示（天賦配置可在比較頁的天賦檢視切換）
	for _, name in ipairs({ "itemsExpandedCheck", "primaryTreeSetLabel", "primaryTreeSetSelect", "compareTreeSetLabel", "compareTreeSetSelect" }) do
		local ctrl = controls[name]
		if ctrl then
			local orig = ctrl.shown
			ctrl.shown = function(...)
				if enabled() then
					return false
				end
				if type(orig) == "function" then
					return orig(...)
				end
				return orig ~= false
			end
		end
	end
	local st = getState(compareTab)
	local dd = new("DropDownControl"):DropDownControl(nil, { 0, 0, 380, 20 }, { "主要技能" }, function(index)
		st.skillChoice = index
		local cand = st.cands and st.cands[index]
		st.manualKey = cand and (cand.groupIndex .. ":" .. cand.activeIndex .. ":" .. tostring(cand.minionSkillIndex)) or nil
		st.sig = nil -- 重新計算
	end)
	dd.shown = itemsZh
	dd.enabled = itemsZh
	dd.maxDroppedWidth = 600
	dd.enableDroppedWidth = true
	dd.tooltipText = "DPS 用哪一招技能計算。預設是我的 Build 裡傷害最高的那招（召喚物技能也算）。\n只影響這一頁的數字，不會改到 Build 的主要技能。"
	controls.zhTWCompareSkill = dd
end

-- ===== 繪製 =====

local function colorFor(value)
	if not value or math.abs(value) < 0.05 then
		return "^7"
	end
	return value > 0 and colorCodes.POSITIVE or colorCodes.NEGATIVE
end

local function pctText(value)
	if not value then
		return "^8—"
	end
	if math.abs(value) < 0.05 then
		return "^70%"
	end
	return colorFor(value) .. s_format("%+.1f%%", value)
end

local function resText(label, before, after)
	local diff = (after or 0) - (before or 0)
	local text
	if diff == 0 then
		text = "^70%"
	else
		text = colorFor(diff) .. s_format("%+d%%", diff)
	end
	return "^7" .. label .. " " .. text
end

local function drawBox(x, y, w, h, r, g, b)
	SetDrawColor(r, g, b)
	DrawImage(nil, x, y, w, h)
end

local function drawOutline(x, y, w, h, color, t)
	SetDrawColor(color[1], color[2], color[3])
	DrawImage(nil, x, y, w, t)
	DrawImage(nil, x, y + h - t, w, t)
	DrawImage(nil, x, y, t, h)
	DrawImage(nil, x + w - t, y, t, h)
end

local function inside(cx, cy, x, y, w, h)
	return cx >= x and cy >= y and cx < x + w and cy < y + h
end

-- 物品名稱＋前兩行詞綴（中文）
local function itemLines(item)
	if not item then
		return nil
	end
	local lines = { }
	for _, list in ipairs({ item.explicitModLines or { }, item.implicitModLines or { } }) do
		for _, modLine in ipairs(list) do
			if #lines >= 2 then
				break
			end
			if modLine.line and modLine.line ~= "" then
				local text = modLine.line
				if ZhTWMods and ZhTWMods.translate then
					text = ZhTWMods.translate(text) or text
				end
				t_insert(lines, text)
			end
		end
	end
	return lines
end

local function fitText(text, size, maxW)
	if DrawStringWidth(size, "VAR", text) <= maxW then
		return text
	end
	-- 逐字（UTF-8）縮短
	local chars = { }
	for ch in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		t_insert(chars, ch)
	end
	while #chars > 1 do
		chars[#chars] = nil
		local cut = t_concat(chars) .. "…"
		if DrawStringWidth(size, "VAR", cut) <= maxW then
			return cut
		end
	end
	return text
end

local function drawItemCell(x, y, w, h, item)
	drawBox(x, y, w, h, 0.11, 0.11, 0.12)
	if not item then
		SetDrawColor(1, 1, 1)
		DrawString(x + 10, y + h / 2 - 8, "LEFT", 16, "VAR", "^8（無）")
		return
	end
	local name = item.title or item.name or "?"
	local color = colorCodes[item.rarity] or "^7"
	SetDrawColor(1, 1, 1)
	DrawString(x + 10, y + 4, "LEFT", 16, "VAR", color .. fitText(tr(name) or name, 16, w - 20))
	local lines = itemLines(item)
	for i, line in ipairs(lines or { }) do
		DrawString(x + 12, y + 4 + 16 + (i - 1) * 15, "LEFT", 14, "VAR", "^7" .. fitText(line, 14, w - 24))
	end
end

local function drawButton(x, y, w, h, text, hover)
	drawBox(x, y, w, h, hover and 0.35 or 0.12, hover and 0.35 or 0.12, hover and 0.35 or 0.13)
	SetDrawColor(1, 1, 1)
	DrawString(x + w / 2, y + h / 2 - 8, "CENTER_X", 16, "VAR", "^7" .. text)
end

local function drawCheck(x, y, size, checked, hover)
	if checked then
		drawBox(x, y, size, size, ORANGE[1], ORANGE[2], ORANGE[3])
		SetDrawColor(0.08, 0.08, 0.08)
		main:DrawCheckMark(x + size / 2, y + size / 2, size * 0.8)
	else
		drawBox(x, y, size, size, hover and 0.9 or 0.6, hover and 0.9 or 0.6, hover and 0.9 or 0.6)
		drawBox(x + 2, y + 2, size - 4, size - 4, 0.06, 0.06, 0.06)
	end
end

local function drawCard(x, y, w, h, title)
	drawBox(x, y, w, h, 0.3, 0.3, 0.3)
	drawBox(x + 1, y + 1, w - 2, h - 2, 0.09, 0.09, 0.1)
	SetDrawColor(1, 1, 1)
	DrawString(x + 14, y + 6, "LEFT", 18, "VAR", "^7" .. title)
end

function M.draw(compareTab, vp, compareEntry, inputEvents)
	if not enabled() or not compareEntry then
		return false
	end
	setupControls(compareTab)
	local build = compareTab.primaryBuild
	local st = getState(compareTab)
	local slots = activeSlots(compareTab, compareEntry)

	-- 原本的水平捲軸不需要
	local hBar = compareTab.controls.itemsHScrollBar
	if hBar then
		hBar:SetContentDimension(vp.width, vp.width)
		compareTab.itemsScrollX = 0
	end

	-- 技能候選與計算
	refreshCandidates(st, build)
	local dd = compareTab.controls.zhTWCompareSkill
	dd.list = st.skillList
	dd.selIndex = m_min(st.skillChoice or 1, #st.skillList)
	local sig = tostring(build.outputRevision) .. "|" .. tostring(compareEntry) .. "|" .. itemSignature(compareEntry, slots)
		.. "|" .. tostring(st.skillChoice)
	if st.sig ~= sig then
		startJob(st, build, compareEntry, slots, sig)
	end
	runJob(st)
	updateCombined(st, build, slots)

	local cursorX, cursorY = GetCursorPos()
	local x0 = vp.x + 10
	local fullW = vp.width - 20 - SCROLLBAR_W
	local y = vp.y + HEADER_H + 4

	-- === 計算技能 ===
	SetDrawColor(1, 1, 1)
	DrawString(x0, y + 2, "LEFT", 16, "VAR", "^7計算技能：")
	local ddX = x0 + DrawStringWidth(16, "VAR", "^7計算技能：") + 4
	dd.x = ddX
	dd.y = y
	local status
	if st.error then
		status = colorCodes.NEGATIVE .. "計算失敗：" .. st.error
	elseif st.co then
		status = "^8計算中…"
	else
		status = "^8只換裝備，寶石、天賦、設定都用我自己的。天賦珠寶不納入。"
	end
	DrawString(ddX + dd.width + 12, y + 2, "LEFT", 14, "VAR", fitText(status, 14, m_max(40, x0 + fullW - (ddX + dd.width + 12))))
	y = y + SKILL_ROW_H

	-- === 結果卡片 ===
	local gap = 10
	local cardW = m_floor((fullW - gap * 2) / 3)
	local base, comb = st.base, st.combined
	drawCard(x0, y, cardW, CARD_H, "總 DPS")
	drawCard(x0 + cardW + gap, y, cardW, CARD_H, "有效生命")
	drawCard(x0 + (cardW + gap) * 2, y, cardW, CARD_H, "抗性")
	if base and comb then
		DrawString(x0 + 14, y + 30, "LEFT", 32, "VAR", pctText(pctChange(base.dps, comb.dps)))
		DrawString(x0 + cardW + gap + 14, y + 30, "LEFT", 32, "VAR", pctText(pctChange(base.ehp, comb.ehp)))
		local rx = x0 + (cardW + gap) * 2 + 14
		local resLine = resText("火", base.fire, comb.fire) .. "   " .. resText("冰", base.cold, comb.cold) .. "   " .. resText("雷", base.lightning, comb.lightning)
		local size = DrawStringWidth(24, "VAR", resLine) <= cardW - 24 and 24 or 18
		DrawString(rx, y + 34, "LEFT", size, "VAR", resLine)
	else
		DrawString(x0 + 14, y + 34, "LEFT", 20, "VAR", "^8計算中…")
	end
	local hoverCard = inside(cursorX, cursorY, x0, y, fullW, CARD_H)
	y = y + CARD_H + 8

	-- === 欄位標題 ===
	local colGap = 16
	local colW = m_floor((fullW - colGap) / 2)
	local leftX = x0
	local rightX = x0 + colW + colGap
	drawBox(leftX, y, colW, COL_HEAD_H, ORANGE[1], ORANGE[2], ORANGE[3])
	drawBox(rightX, y, colW, COL_HEAD_H, ORANGE[1], ORANGE[2], ORANGE[3])
	SetDrawColor(1, 1, 1)
	DrawString(leftX + 12, y + 5, "LEFT", 18, "VAR", "^0我的配置")
	DrawString(rightX + 12, y + 5, "LEFT", 18, "VAR", "^0對方配置")
	local btnW, btnH = 70, COL_HEAD_H - 6
	local clearX = rightX + colW - btnW - 3
	local allX = clearX - btnW - 4
	local btnY = y + 3
	local hoverAll = inside(cursorX, cursorY, allX, btnY, btnW, btnH)
	local hoverClear = inside(cursorX, cursorY, clearX, btnY, btnW, btnH)
	drawButton(allX, btnY, btnW, btnH, "全選", hoverAll)
	drawButton(clearX, btnY, btnW, btnH, "全取消", hoverClear)
	y = y + COL_HEAD_H + 6

	-- === 部位列（可捲動） ===
	local listTop = y
	local listH = m_max(vp.y + vp.height - listTop, 0)
	local rowsH = 0
	for _ in ipairs(slots) do
		rowsH = rowsH + ROW_H + ROW_GAP
	end
	-- 共用的垂直捲軸以 HEADER_H 為頂端計算，換算成我們的列表高度
	compareTab.itemsTotalContentHeight = rowsH + (listTop - vp.y - HEADER_H) + 8

	local pTab = build.itemsTab
	local cTab = compareEntry.itemsTab
	local primaryHasRing3 = build.calcsTab and build.calcsTab.mainEnv and build.calcsTab.mainEnv.modDB:Flag(nil, "AdditionalRingSlot")
	local hoverItem, hoverItemsTab, hoverRect
	local hoverSingle, hoverSingleSlot, hoverSingleRect
	local toggleSlot

	SetViewport(vp.x, listTop, vp.width, listH)
	local lcx, lcy = cursorX - vp.x, cursorY - listTop
	local inList = cursorY >= listTop and cursorY < listTop + listH
	local ry = -(compareTab.scrollY or 0)
	local lx, rxx = leftX - vp.x, rightX - vp.x
	for _, slot in ipairs(slots) do
		local slotName, label = slot[1], slot[2]
		local pSlot = pTab.slots[slotName]
		local pItem = pSlot and pTab.items[pSlot.selItemId]
		local cSlot = cTab and cTab.slots and cTab.slots[slotName]
		local cItem = cSlot and cTab.items and cTab.items[cSlot.selItemId]
		if ry + ROW_H >= 0 and ry < listH then
			-- 左：我的
			drawBox(lx, ry, LABEL_W, ROW_H, 0.14, 0.14, 0.15)
			SetDrawColor(1, 1, 1)
			DrawString(lx + 10, ry + ROW_H / 2 - 9, "LEFT", 18, "VAR", "^7" .. label)
			drawItemCell(lx + LABEL_W + 4, ry, colW - LABEL_W - 4, ROW_H, pItem)
			if pItem and inList and inside(lcx, lcy, lx + LABEL_W + 4, ry, colW - LABEL_W - 4, ROW_H) then
				hoverItem, hoverItemsTab = pItem, pTab
				hoverRect = { lx + LABEL_W + 4, ry, colW - LABEL_W - 4, ROW_H }
			end

			-- 右：對方
			local isChecked = cItem and st.checked[slotName]
			local disabled = slotName == "Ring 3" and not primaryHasRing3
			drawBox(rxx, ry, LABEL_W, ROW_H, 0.14, 0.14, 0.15)
			SetDrawColor(1, 1, 1)
			DrawString(rxx + 10, ry + ROW_H / 2 - 9, "LEFT", 18, "VAR", "^7" .. label)
			drawBox(rxx + LABEL_W + 2, ry, CHECK_W, ROW_H, 0.11, 0.11, 0.12)
			local checkRect = { rxx + LABEL_W + 2, ry, CHECK_W, ROW_H }
			local hoverCheck = inList and inside(lcx, lcy, checkRect[1], checkRect[2], checkRect[3], checkRect[4])
			if cItem and not disabled then
				drawCheck(rxx + LABEL_W + 2 + (CHECK_W - 20) / 2, ry + (ROW_H - 20) / 2, 20, isChecked, hoverCheck)
				if hoverCheck then
					toggleSlot = slotName
				end
			end
			local cellX = rxx + LABEL_W + 2 + CHECK_W + 2
			local cellW = colW - LABEL_W - 2 - CHECK_W - 2
			drawItemCell(cellX, ry, cellW, ROW_H, cItem)
			-- 單換 DPS
			if cItem and not disabled then
				local text
				local s = st.single[slotName]
				if s and st.base then
					local p = pctChange(st.base.dps, s.dps)
					text = p and (colorFor(p) .. "單換 DPS " .. (math.abs(p) < 0.05 and "0%" or s_format("%+.1f%%", p))) or "^8單換 DPS —"
				else
					text = "^8計算中…"
				end
				local tw = DrawStringWidth(16, "VAR", text)
				local tx = cellX + cellW - tw - 10
				SetDrawColor(1, 1, 1)
				DrawString(tx, ry + ROW_H / 2 - 8, "LEFT", 16, "VAR", text)
				if inList and inside(lcx, lcy, tx - 4, ry, tw + 14, ROW_H) and st.singleOutput[slotName] then
					hoverSingle, hoverSingleSlot = st.singleOutput[slotName], slotName
					hoverSingleRect = { tx - 4, ry, tw + 14, ROW_H }
				elseif inList and inside(lcx, lcy, cellX, ry, cellW, ROW_H) then
					hoverItem, hoverItemsTab = cItem, cTab
					hoverRect = { cellX, ry, cellW, ROW_H }
				end
			elseif disabled and cItem then
				SetDrawColor(1, 1, 1)
				DrawString(cellX + cellW - 10, ry + ROW_H / 2 - 8, "RIGHT", 14, "VAR", "^8我沒有第三戒指欄")
			end
			if isChecked then
				drawOutline(rxx, ry, colW, ROW_H, ORANGE, 2)
			end
		end
		ry = ry + ROW_H + ROW_GAP
	end

	-- === 點擊 ===
	if inputEvents and not main.popups[1] then
		for id, event in ipairs(inputEvents) do
			if event.type == "KeyUp" and event.key == "LEFTBUTTON" then
				if hoverAll then
					for _, slot in ipairs(slots) do
						if st.items and st.items[slot[1]] and not (slot[1] == "Ring 3" and not primaryHasRing3) then
							st.checked[slot[1]] = true
						end
					end
					inputEvents[id] = nil
				elseif hoverClear then
					wipeTable(st.checked)
					inputEvents[id] = nil
				elseif toggleSlot then
					st.checked[toggleSlot] = not st.checked[toggleSlot] or nil
					inputEvents[id] = nil
				end
			end
		end
	end

	-- === 提示框 ===
	local tooltip = compareTab.itemTooltip
	local maxTooltipWidth = m_min(600, m_max(260, vp.width - 24))
	if not main.popups[1] and tooltip then
		if hoverItem and hoverItemsTab then
			tooltip:Clear()
			hoverItemsTab:AddItemTooltip(tooltip, hoverItem, nil, nil, maxTooltipWidth)
			SetDrawLayer(nil, 100)
			tooltip:Draw(vp.x + hoverRect[1], listTop + hoverRect[2], hoverRect[3], hoverRect[4], vp)
			SetDrawLayer(nil, 0)
		elseif hoverSingle and st.baseOutput then
			tooltip:Clear()
			tooltip.maxWidth = maxTooltipWidth
			local cand = currentCand(st)
			local header = "^7只換這一件（" .. (cand and candLabel(cand) or "主要技能") .. "）："
			local count = build:AddStatComparesToTooltip(tooltip, st.baseOutput, hoverSingle, header)
			if count == 0 then
				tooltip:AddLine(14, header)
				tooltip:AddLine(14, "^7沒有變化。")
			end
			SetDrawLayer(nil, 100)
			tooltip:Draw(vp.x + hoverSingleRect[1], listTop + hoverSingleRect[2], vp.width, hoverSingleRect[4], vp)
			SetDrawLayer(nil, 0)
		end
	end
	SetViewport()

	if hoverCard and not main.popups[1] and tooltip and st.base and st.combined then
		tooltip:Clear()
		tooltip:AddLine(16, "^7勾選的裝備一起換上後，和我現在的配置相比。")
		local cand = currentCand(st)
		tooltip:AddLine(14, "^8計算技能：" .. (cand and candLabel(cand) or "主要技能"))
		tooltip:AddLine(14, s_format("^8DPS：%s → %s", formatNumber(st.base.dps), formatNumber(st.combined.dps)))
		tooltip:AddLine(14, s_format("^8有效生命：%s → %s", formatNumber(st.base.ehp), formatNumber(st.combined.ehp)))
		SetDrawLayer(nil, 100)
		tooltip:Draw(cursorX, cursorY, 0, 0, vp)
		SetDrawLayer(nil, 0)
	end
	return true
end

return M
