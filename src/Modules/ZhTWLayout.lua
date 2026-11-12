-- Path of Building
--
-- Module: zhTW Layout
-- Layout changes for the Chinese interface (only while ZhTWLocale.enabled is on).
--
-- Kept out of PoB's own files: Build.lua / ItemsTab.lua only call into this module, so the
-- upstream layout code stays untouched and the original layout returns when the Chinese
-- interface is switched off.
--
local t_insert = table.insert
local s_format = string.format
local m_floor = math.floor

local ZhTWLayout = { }

local function enabled()
	return ZhTWLocale and ZhTWLocale.enabled
end
ZhTWLayout.enabled = enabled

local GOLD = "^xC8A45A"

local function rect(x, y, w, h, r, g, b, a)
	SetDrawColor(r, g, b, a or 1)
	DrawImage(nil, x, y, w, h)
end

local function formatValue(v, decimals)
	if type(v) ~= "number" then
		return "-"
	end
	if v == math.huge then
		return "∞"
	end
	return formatNumSep(s_format("%." .. (decimals or 0) .. "f", v))
end

---------------------------------------------------------------------------
-- Sidebar: summary cards above the stat list
---------------------------------------------------------------------------

local CARD_H = 40
local CARD_GAP = 4

-- The four numbers people look for first
local function summaryCards(build)
	local output = build.calcsTab and build.calcsTab.mainOutput or { }
	local dpsLabel, dps = "合計 DPS", output.CombinedDPS
	if output.FullDPS and output.FullDPS > 0 then
		dpsLabel, dps = "完整 DPS", output.FullDPS
	elseif not dps or dps == 0 then
		dpsLabel, dps = "總 DPS", output.TotalDPS
	end
	return {
		{ label = dpsLabel, value = formatValue(dps, dps and dps < 100 and 1 or 0), color = "^xE0D0A0" },
		{ label = "有效生命池", value = formatValue(output.TotalEHP), color = "^7" },
		{ label = "總生命", value = formatValue(output.Life), color = colorCodes.LIFE },
		{ label = "能量護盾", value = formatValue(output.EnergyShield), color = colorCodes.ES },
	}
end

function ZhTWLayout.setupSidebar(build)
	local controls = build.controls
	local cards = new("Control"):Control({ "TOPLEFT", controls.statBoxAnchor, "BOTTOMLEFT" }, { 0, 2, 300, 0 })
	cards.height = function()
		return enabled() and (CARD_H * 2 + CARD_GAP) or 0
	end
	cards.shown = function()
		return enabled()
	end
	cards.Draw = function(control)
		local x, y = control:GetPos()
		local width = control:GetSize()
		local cardW = m_floor((width - CARD_GAP) / 2)
		for i, card in ipairs(summaryCards(build)) do
			local cx = x + ((i - 1) % 2) * (cardW + CARD_GAP)
			local cy = y + m_floor((i - 1) / 2) * (CARD_H + CARD_GAP)
			rect(cx, cy, cardW, CARD_H, 0.23, 0.2, 0.15)
			rect(cx + 1, cy + 1, cardW - 2, CARD_H - 2, 0.11, 0.1, 0.08)
			DrawString(cx + 8, cy + 3, "LEFT", 12, "VAR", card.color .. card.label)
			DrawString(cx + 8, cy + 17, "LEFT", 20, "VAR BOLD", "^7" .. card.value)
		end
		SetDrawColor(1, 1, 1)
	end
	controls.zhTWSummary = cards
	controls.statBox:SetAnchor("TOPLEFT", cards, "BOTTOMLEFT", 0, 2)
	-- Original sidebar columns, restored when the Chinese interface is off
	ZhTWLayout.originalColumns = controls.statBox.columns
end

---------------------------------------------------------------------------
-- Sidebar: group headings, labels left and values right
---------------------------------------------------------------------------

-- Group heading from the first stat label of each group (BuildDisplayStats.lua order)
local groupByFirstLabel = {
	["Strength"] = "屬性", ["Strength Required"] = "屬性", ["Dexterity"] = "屬性", ["Intelligence"] = "屬性",
	["Devotion"] = "奉獻",
	["Effective Hit Pool"] = "承受能力", ["PvP Hit Taken"] = "承受能力",
	["MH Accuracy"] = "命中與生命", ["OH Accuracy"] = "命中與生命", ["Total Life"] = "生命",
	["Total Mana"] = "魔力",
	["Energy Shield"] = "能量護盾",
	["Ward"] = "保護",
	["Rage"] = "盛怒",
	["Total Degen"] = "回復與流失", ["Total Net Recovery"] = "回復與流失", ["Net Life Recovery"] = "回復與流失",
	["Evasion rating"] = "閃避",
	["Armour"] = "護甲",
	["Block Chance"] = "格擋與抑制", ["Spell Block Chance"] = "格擋與抑制", ["Spell Suppression Chance"] = "格擋與抑制",
	["Fire Resistance"] = "抗性",
	["Movement Speed Modifier"] = "其他",
	["Full DPS"] = "完整 DPS", ["Full Dot DPS"] = "完整 DPS",
	["Skill DPS"] = "技能 DPS",
}

local function labelOf(line)
	local text = line[1]
	if type(text) ~= "string" or line.x or line.align then
		return nil
	end
	return (StripEscapes(text):gsub(":%s*$", ""))
end

function ZhTWLayout.refreshSidebar(build)
	local statBox = build.controls.statBox
	if not enabled() then
		statBox.columns = ZhTWLayout.originalColumns or statBox.columns
		return
	end
	local width = statBox:GetSize()
	statBox.columns = { { x = 4, align = "LEFT" }, { x = width - 24, align = "RIGHT_X" } }
	local list = statBox.list
	local out = { }
	local needHeading = true
	local first = true
	for _, line in ipairs(list) do
		local label = labelOf(line)
		if label == "Minion" or label == "Player" or label == "Skill disabled" then
			-- section titles of their own
			needHeading = true
			first = true
			t_insert(out, line)
		elseif not line[1] and not line[2] then
			-- separator between groups
			needHeading = true
			t_insert(out, line)
		elseif label and needHeading then
			local heading = groupByFirstLabel[label] or (first and "攻擊") or nil
			if heading then
				t_insert(out, { height = 18, GOLD .. heading })
			end
			needHeading = false
			first = false
			t_insert(out, line)
		else
			if label then
				first = false
			end
			t_insert(out, line)
		end
	end
	wipeTable(list)
	for i, line in ipairs(out) do
		list[i] = line
	end
end

---------------------------------------------------------------------------
-- Items tab: group headings above the equipped item slots
---------------------------------------------------------------------------

local HEADING_SPACE = 20
local slotGroups = {
	["Weapon 1"] = "武器",
	["Helmet"] = "防具",
	["Amulet"] = "飾品",
	["Flask 1"] = "藥劑",
}

function ZhTWLayout.setupItemsTab(itemsTab)
	for _, slot in ipairs(itemsTab.orderedSlots or { }) do
		local heading = slotGroups[slot.slotName]
		if heading then
			-- Push the slot (and everything anchored below it) down to make room.
			-- Done on GetPos so it also works when the slot above is hidden (collapsed anchors).
			local origGetPos = slot.GetPos
			slot.GetPos = function(self)
				local x, y = origGetPos(self)
				if enabled() then
					y = y + HEADING_SPACE
				end
				return x, y
			end
			local label = new("LabelControl"):LabelControl({ "BOTTOMLEFT", slot, "TOPLEFT" }, { -88, -3, 0, 14 }, GOLD .. heading)
			label.shown = enabled
			itemsTab.controls["zhTWHeading_" .. slot.slotName] = label
		end
	end
end

return ZhTWLayout
