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
local m_min = math.min
local m_max = math.max

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

-- The four summary cards above the stat list; off since the group cards show the same
-- numbers (攻擊 DPS and skill, 承受能力 EHP, 生命, 能量護盾). true brings them back.
local SHOW_SUMMARY = false
local CARD_H = 40
local CARD_H_TOP = 54 -- the top row has a second line: which skill the DPS is for
local CARD_GAP = 4

-- Name of the skill the side bar DPS is calculated for (chosen in the 技能 tab)
local function mainSkillName(build)
	local group = build.skillsTab and build.skillsTab.socketGroupList[build.mainSocketGroup]
	local list = group and group.displaySkillList
	local skill = list and list[group.mainActiveSkill or 1]
	local effect = skill and skill.activeEffect
	if not (effect and effect.grantedEffect) then
		return "未選擇技能"
	end
	local name = effect.grantedEffect.name or "?"
	return ZhTWLocale.tr and ZhTWLocale.tr(name) or name
end

-- Cuts a UTF-8 string until it fits in width pixels
local function fitText(text, size, width)
	if DrawStringWidth(size, "VAR", text) <= width then
		return text
	end
	while #text > 0 and DrawStringWidth(size, "VAR", text .. "…") > width do
		text = text:gsub("[%z\1-\127\194-\244][\128-\191]*$", "")
	end
	return text .. "…"
end

-- The four numbers people look for first
local function summaryCards(build)
	local output = build.calcsTab and build.calcsTab.mainOutput or { }
	local dpsLabel, dps = "合計 DPS", output.CombinedDPS
	local skillName = mainSkillName(build)
	if output.FullDPS and output.FullDPS > 0 then
		dpsLabel, dps = "完整 DPS", output.FullDPS
		skillName = "所有納入的技能"
	elseif not dps or dps == 0 then
		dpsLabel, dps = "總 DPS", output.TotalDPS
	end
	return {
		{ label = dpsLabel, value = formatValue(dps, dps and dps < 100 and 1 or 0), color = "^xE0D0A0", sub = skillName },
		{ label = "有效生命池", value = formatValue(output.TotalEHP), color = "^7" },
		{ label = "總生命", value = formatValue(output.Life), color = colorCodes.LIFE },
		{ label = "能量護盾", value = formatValue(output.EnergyShield), color = colorCodes.ES },
	}
end

function ZhTWLayout.setupSidebar(build)
	local controls = build.controls
	local cards = new("Control"):Control({ "TOPLEFT", controls.statBoxAnchor, "BOTTOMLEFT" }, { 0, 2, 300, 0 })
	cards.height = function()
		return enabled() and SHOW_SUMMARY and (CARD_H_TOP + CARD_H + CARD_GAP) or 0
	end
	cards.shown = function()
		return enabled()
	end
	-- The skill selection moved to the 技能 tab, so the cards start right under the buttons
	local baseGetPos = cards.GetPos
	cards.GetPos = function(self)
		if enabled() then
			local x, y = build.anchorSideBar:GetPos()
			return x, y + 30
		end
		return baseGetPos(self)
	end
	cards.Draw = function(control)
		if not SHOW_SUMMARY then
			return
		end
		local x, y = control:GetPos()
		local width = control:GetSize()
		local cardW = m_floor((width - CARD_GAP) / 2)
		for i, card in ipairs(summaryCards(build)) do
			local top = i <= 2
			local cardH = top and CARD_H_TOP or CARD_H
			local cx = x + ((i - 1) % 2) * (cardW + CARD_GAP)
			local cy = top and y or (y + CARD_H_TOP + CARD_GAP)
			rect(cx, cy, cardW, cardH, 0.23, 0.2, 0.15)
			rect(cx + 1, cy + 1, cardW - 2, cardH - 2, 0.11, 0.1, 0.08)
			DrawString(cx + 8, cy + 3, "LEFT", 12, "VAR", card.color .. card.label)
			if card.sub then
				DrawString(cx + 8, cy + 17, "LEFT", 12, "VAR", "^x8C8478" .. fitText(card.sub, 12, cardW - 14))
			end
			DrawString(cx + 8, cy + cardH - 23, "LEFT", 20, "VAR BOLD", "^7" .. card.value)
		end
		SetDrawColor(1, 1, 1)
	end
	controls.zhTWSummary = cards
	controls.statBox:SetAnchor("TOPLEFT", cards, "BOTTOMLEFT", 0, 2)
	ZhTWLayout.setupGroupCards(build)
	ZhTWLayout.setupTopBar(build)
	ZhTWLayout.setupModeButtons(build)
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

---------------------------------------------------------------------------
-- Icons: one sprite sheet (Assets/zhTW/icons.png, 6 x 5 cells of 32 px, row by row in
-- the order below). Set SHOW_ICONS to false to turn every icon off; without the file
-- nothing is drawn either.
---------------------------------------------------------------------------

local SHOW_ICONS = true
local ICON_CELL, ICON_COLS, ICON_ROWS = 32, 6, 5
local iconIndex = {
	["攻擊"] = 1, ["屬性"] = 2, ["奉獻"] = 3, ["承受能力"] = 4, ["命中與生命"] = 5, ["生命"] = 6,
	["魔力"] = 7, ["能量護盾"] = 8, ["保護"] = 9, ["盛怒"] = 10, ["回復與流失"] = 11, ["閃避"] = 12,
	["護甲"] = 13, ["格擋與抑制"] = 14, ["抗性"] = 15, ["其他"] = 16, ["完整 DPS"] = 17, ["技能 DPS"] = 18,
	["裝備"] = 19, ["技能"] = 20, ["天賦"] = 21, ["計算"] = 22, ["匯入/匯出"] = 23, ["角色配置"] = 24,
	["設定"] = 25, ["儲存"] = 26, ["另存新檔"] = 27,
}
local iconSheet
local function loadIcons()
	if iconSheet ~= nil then
		return iconSheet
	end
	iconSheet = false
	if SHOW_ICONS then
		local f = io.open("Assets/zhTW/icons.png", "rb")
		if f then
			f:close()
			iconSheet = NewImageHandle()
			iconSheet:Load("Assets/zhTW/icons.png", "CLAMP")
		end
	end
	return iconSheet
end

-- Draws the icon for name at x, y (size px square); false when there is none
function ZhTWLayout.drawIcon(name, x, y, size, alpha)
	local index = iconIndex[name]
	local sheet = enabled() and index and loadIcons()
	if not sheet then
		return false
	end
	local col, row = (index - 1) % ICON_COLS, m_floor((index - 1) / ICON_COLS)
	local w, h = ICON_COLS * ICON_CELL, ICON_ROWS * ICON_CELL
	SetDrawColor(1, 1, 1, alpha or 1)
	DrawImage(sheet, x, y, size, size, col * ICON_CELL / w, row * ICON_CELL / h, (col + 1) * ICON_CELL / w, (row + 1) * ICON_CELL / h)
	SetDrawColor(1, 1, 1)
	return true
end
function ZhTWLayout.hasIcons()
	return enabled() and loadIcons() and true or false
end

-- Group cards in the side bar: the value shown on the right of each heading
local headingValueLabel = {
	["攻擊"] = { "Combined DPS", "Hit DPS", "Total DPS", "Average Damage", "Average Hit" },
	["奉獻"] = { "Devotion" },
	["承受能力"] = { "Effective Hit Pool" },
	["命中與生命"] = { "Total Life" },
	["生命"] = { "Total Life" },
	["魔力"] = { "Total Mana" },
	["能量護盾"] = { "Energy Shield" },
	["保護"] = { "Ward" },
	["盛怒"] = { "Rage" },
	["回復與流失"] = { "Total Net Recovery", "Net Life Recovery" },
	["閃避"] = { "Evasion rating" },
	["護甲"] = { "Armour" },
	["格擋與抑制"] = { "Block Chance" },
	["其他"] = { "Movement Speed Modifier" },
	["完整 DPS"] = { "Full DPS" },
	["技能 DPS"] = { },
}
local HEADING_H = 24
ZhTWLayout.collapsedGroups = { } -- key -> true (folded) / false (open); unset uses defaultCollapsed
local defaultCollapsed = { ["奉獻"] = true, ["保護"] = true, ["盛怒"] = true, ["命中與生命"] = true }

local function labelOf(line)
	local text = line[1]
	if type(text) ~= "string" or line.x or line.align then
		return nil
	end
	return (StripEscapes(text):gsub(":%s*$", ""))
end

-- Group cards: framed heading rows with icon, name and key value; click to fold the group
function ZhTWLayout.setupGroupCards(build)
	local statBox = build.controls.statBox
	local baseDraw = statBox.Draw
	statBox.Draw = function(self, viewPort)
		baseDraw(self, viewPort)
		if not enabled() then
			return
		end
		local x, y = self:GetPos()
		local width, height = self:GetSize()
		local hovered = self.hoveredLine and self.hoveredLine.line
		SetViewport(x + 2, y + 2, width - 20, height - 4)
		local w = width - 24
		local lineY = -self.controls.scrollBar.offset
		for _, line in ipairs(self.list) do
			if line.zhTWHeading and lineY + line.height > 0 and lineY < height then
				local cy, ch = lineY + 2, line.height - 3
				rect(0, cy, w, ch, 0.42, 0.34, 0.2)
				if line == hovered then
					rect(1, cy + 1, w - 2, ch - 2, 0.2, 0.16, 0.1)
				else
					rect(1, cy + 1, w - 2, ch - 2, 0.12, 0.1, 0.07)
				end
				rect(1, cy + 1, 3, ch - 2, 0.78, 0.64, 0.35) -- gold edge on the left
				-- fold arrow: right when folded, down when open
				local ax, ay = w - 12, cy + ch / 2
				SetDrawColor(0.78, 0.64, 0.35)
				if line.empty then
					-- nothing to fold
				elseif line.collapsed then
					DrawImageQuad(nil, ax - 2, ay - 4, ax + 3, ay, ax + 3, ay, ax - 2, ay + 4)
				else
					DrawImageQuad(nil, ax - 4, ay - 2, ax + 4, ay - 2, ax, ay + 3, ax, ay + 3)
				end
				SetDrawColor(1, 1, 1)
				local tx = 10
				if ZhTWLayout.drawIcon(line.zhTWHeading, 8, cy + (ch - 16) / 2, 16) then
					tx = 30
				end
				DrawString(tx, cy + (ch - 16) / 2, "LEFT", 16, "VAR BOLD", GOLD .. line.zhTWHeading)
				local valueW = 0
				if line.value then
					DrawString(w - 22, cy + (ch - 14) / 2, "RIGHT_X", 14, "VAR", "^7" .. line.value)
					valueW = DrawStringWidth(14, "VAR", line.value)
				end
				if line.zhTWSkill then
					local nx = tx + DrawStringWidth(16, "VAR BOLD", line.zhTWHeading) + 8
					local room = w - 30 - valueW - nx
					if room > 30 then
						DrawString(nx, cy + (ch - 12) / 2, "LEFT", 12, "VAR", "^x8C8478" .. fitText(line.zhTWSkill, 12, room))
					end
				end
			end
			lineY = lineY + line.height
		end
		SetViewport()
	end
	local baseClick = statBox.onClick
	statBox.onClick = function(hoveredLine)
		local line = hoveredLine and hoveredLine.line
		if enabled() and line and line.zhTWKey then
			if line.empty then
				return
			end
			ZhTWLayout.collapsedGroups[line.zhTWKey] = not line.collapsed
			build:RefreshStatList()
			return
		end
		if baseClick then
			return baseClick(hoveredLine)
		end
	end
end

-- Order of the group cards in the side bar (KAI 11/17); groups not listed keep PoB's order after them
local groupOrder = {
	"屬性", "攻擊", "完整 DPS", "技能 DPS", "生命", "回復與流失", "能量護盾", "魔力",
	"抗性", "護甲", "閃避", "格擋與抑制", "其他", "承受能力",
}
local groupRank = { }
for i, name in ipairs(groupOrder) do
	groupRank[name] = i
end

-- Cards always shown for the player (KAI 11/17), with the value used when PoB hides the group
local fixedGroups = {
	{ "屬性" }, { "攻擊", "0" }, { "生命", "0" }, { "能量護盾", "0" }, { "魔力", "0" },
	{ "抗性" }, { "護甲", "0" }, { "閃避", "0" }, { "格擋與抑制", "0%" }, { "其他", "+0%" }, { "承受能力", "0" },
}

local function sectionOf(line)
	local label = labelOf(line)
	if label == "Minion" or label == "Player" then
		return label
	end
end

-- Moves whole groups (card, its stat lines and the gap after them) into groupOrder,
-- separately inside the player and minion sections
local function orderGroups(lines, build)
	local result = { }
	local blocks, pending = { }, nil
	local section = ""
	local function flush()
		if section ~= "Minion" and #blocks > 0 then
			local have = { }
			for _, block in ipairs(blocks) do
				have[block[1].zhTWHeading] = true
			end
			for _, fixed in ipairs(fixedGroups) do
				local heading = fixed[1]
				if not have[heading] then
					local card = { height = HEADING_H, zhTWHeading = heading, zhTWKey = section .. "/" .. heading, value = fixed[2], empty = true }
					if heading == "攻擊" then
						card.zhTWSkill = mainSkillName(build)
					end
					t_insert(blocks, { card })
				end
			end
		end
		for i, block in ipairs(blocks) do
			block.rank = groupRank[block[1].zhTWHeading] or (#groupOrder + i)
			block.index = i
		end
		table.sort(blocks, function(a, b)
			if a.rank ~= b.rank then
				return a.rank < b.rank
			end
			return a.index < b.index
		end)
		for _, block in ipairs(blocks) do
			local last = block[#block]
			if last[1] or last[2] or last.zhTWHeading then
				t_insert(block, { height = 6 }) -- keep a gap after a moved group
			end
			for _, line in ipairs(block) do
				t_insert(result, line)
			end
		end
		blocks = { }
	end
	for _, line in ipairs(lines) do
		if sectionOf(line) then
			flush()
			section = sectionOf(line)
			pending = nil
			t_insert(result, line)
		elseif line.zhTWHeading then
			pending = { line }
			t_insert(blocks, pending)
		elseif pending then
			t_insert(pending, line)
		else
			t_insert(result, line) -- lines before the first card stay on top
		end
	end
	flush()
	return result
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
	local section = ""
	local card, hidden -- current group card; true while its group is collapsed
	-- the card shows the first wanted stat of its group on the right
	local function takeValue(label, line)
		if not card or not label or not line[2] then
			return
		end
		local wanted = headingValueLabel[card.zhTWHeading]
		if not wanted then
			return
		end
		if #wanted == 0 then
			card.value = card.value or line[2]
			return
		end
		-- earlier names in the list win over later ones
		for rank, name in ipairs(wanted) do
			if name == label and rank < (card.valueRank or math.huge) then
				card.value, card.valueRank = line[2], rank
				return
			end
		end
	end
	for _, line in ipairs(list) do
		local label = labelOf(line)
		if label == "Minion" or label == "Player" or label == "Skill disabled" then
			-- section titles of their own
			needHeading = true
			first = true
			section = label
			card, hidden = nil, false
			t_insert(out, line)
		elseif not line[1] and not line[2] then
			-- separator between groups
			needHeading = true
			card, hidden = nil, false
			t_insert(out, line)
		elseif label and needHeading then
			local heading = groupByFirstLabel[label] or (first and "攻擊") or nil
			if heading then
				local key = section .. "/" .. heading
				card = { height = HEADING_H, zhTWHeading = heading, zhTWKey = key }
				if heading == "攻擊" and section ~= "Minion" then
					-- which skill the numbers are for (chosen in the 技能 tab)
					card.zhTWSkill = mainSkillName(build)
				end
				hidden = ZhTWLayout.collapsedGroups[key]
				if hidden == nil then
					hidden = defaultCollapsed[heading] or false
				end
				card.collapsed = hidden
				t_insert(out, card)
			end
			needHeading = false
			first = false
			takeValue(label, line)
			if not hidden then
				t_insert(out, line)
			end
		else
			if label then
				first = false
			end
			takeValue(label, line)
			if not hidden then
				t_insert(out, line)
			end
		end
	end
	out = orderGroups(out, build)
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
	ZhTWLayout.setupJewelSockets(itemsTab)
	-- Docked item details: drawn after the tab itself (instance override, the class stays as it is)
	local origDraw = itemsTab.Draw
	itemsTab.Draw = function(self, viewPort, inputEvents)
		ZhTWLayout.detailsFrame = (ZhTWLayout.detailsFrame or 0) + 1
		ZhTWLayout.detailsViewPort = viewPort
		ZhTWLayout.hookItemLists(self)
		origDraw(self, viewPort, inputEvents)
		ZhTWLayout.drawDetails(self, viewPort)
	end
end

---------------------------------------------------------------------------
-- Items tab: passive tree jewel sockets, collapsed into a row of chips
---------------------------------------------------------------------------

ZhTWLayout.jewelsExpanded = false
local JEWEL_TOGGLE_SPACE = 30

local function jewelsCollapsed()
	return enabled() and not ZhTWLayout.jewelsExpanded
end

-- Chips: unique jewels by name, other jewels grouped by kind
local function jewelChips(itemsTab)
	local chips, byKey = { }, { }
	local empty = 0
	for _, slot in ipairs(itemsTab.orderedSlots) do
		if slot.nodeId and not slot.inactive then
			local item = itemsTab.items[slot.selItemId]
			if not item then
				empty = empty + 1
			else
				local key, text
				if item.rarity == "UNIQUE" or item.rarity == "RELIC" then
					key, text = "U:" .. (item.title or item.name), item.title or item.name
				elseif item.baseName and item.baseName:match("Cluster Jewel") then
					key, text = "C:" .. item.baseName, item.baseName
				elseif item.rarity == "RARE" then
					key, text = "R", "稀有珠寶"
				else
					key, text = "M", "魔法珠寶"
				end
				local chip = byKey[key]
				if not chip then
					chip = { text = text, color = colorCodes[item.rarity] or "^7", count = 0 }
					byKey[key] = chip
					t_insert(chips, chip)
				end
				chip.count = chip.count + 1
			end
		end
	end
	if empty > 0 then
		t_insert(chips, { text = "空插槽", color = "^x8C8478", count = empty })
	end
	return chips
end

local function activeSocketCount(itemsTab)
	local n = 0
	for _, slot in ipairs(itemsTab.orderedSlots) do
		if slot.nodeId and not slot.inactive then
			n = n + 1
		end
	end
	return n
end

local CHIP_H = 20
local CHIP_GAP = 6

-- Lays out the chips in rows; returns the rows' total height (draws them when draw is true)
local function layoutChips(itemsTab, x, y, width, draw)
	local cx, cy = x, y
	for _, chip in ipairs(jewelChips(itemsTab)) do
		local label = ZhTWLocale.tr(chip.text) .. (chip.count > 1 and (" ×" .. chip.count) or "")
		local w = DrawStringWidth(14, "VAR", label) + 16
		if cx > x and cx + w > x + width then
			cx = x
			cy = cy + CHIP_H + CHIP_GAP
		end
		if draw then
			rect(cx, cy, w, CHIP_H, 0.23, 0.2, 0.15)
			rect(cx + 1, cy + 1, w - 2, CHIP_H - 2, 0.1, 0.09, 0.07)
			DrawString(cx + 8, cy + 3, "LEFT", 14, "VAR", chip.color .. label)
		end
		cx = cx + w + CHIP_GAP
	end
	return cy - y + CHIP_H
end

function ZhTWLayout.setupJewelSockets(itemsTab)
	local controls = itemsTab.controls
	local specSelect = controls.specSelect
	local firstSocket
	for _, slot in ipairs(itemsTab.orderedSlots) do
		if slot.nodeId then
			firstSocket = firstSocket or slot
			-- Hidden while collapsed; zhTWShownExpanded keeps "is this socket usable" for ItemsTab logic
			local origShown = slot.shown
			slot.zhTWShownExpanded = function()
				return not slot.inactive
			end
			slot.shown = function(self)
				if jewelsCollapsed() then
					return false
				end
				if type(origShown) == "function" then
					return origShown(self)
				end
				return origShown ~= false
			end
		end
	end
	if not firstSocket or not specSelect then
		return
	end
	local toggle = new("ButtonControl"):ButtonControl({ "TOPLEFT", specSelect, "BOTTOMLEFT" }, { 0, 8, 160, 20 }, function()
		if ZhTWLayout.jewelsExpanded then
			return "收合珠寶插槽"
		end
		return "展開珠寶插槽 (" .. activeSocketCount(itemsTab) .. ")"
	end, function()
		ZhTWLayout.jewelsExpanded = not ZhTWLayout.jewelsExpanded
	end)
	toggle.shown = enabled
	controls.zhTWJewelToggle = toggle
	local heading = new("LabelControl"):LabelControl({ "TOPLEFT", toggle, "TOPLEFT" }, { -88, 3, 0, 14 }, GOLD .. "天賦樹珠寶")
	heading.shown = enabled
	controls.zhTWJewelHeading = heading
	local chips = new("Control"):Control({ "TOPLEFT", toggle, "BOTTOMLEFT" }, { -88, 6, 398, 0 })
	chips.shown = jewelsCollapsed
	chips.height = function()
		local x, y = toggle:GetPos()
		return layoutChips(itemsTab, x - 88, y, 398, false)
	end
	chips.Draw = function(control)
		local x, y = control:GetPos()
		local width = control:GetSize()
		layoutChips(itemsTab, x, y, width, true)
		SetDrawColor(1, 1, 1)
	end
	controls.zhTWJewelChips = chips
	-- Room for the toggle button above the first socket
	local origGetPos = firstSocket.GetPos
	firstSocket.GetPos = function(self)
		local x, y = origGetPos(self)
		if enabled() then
			y = y + JEWEL_TOGGLE_SPACE
		end
		return x, y
	end
end

---------------------------------------------------------------------------
-- Items tab: unique / rare template databases behind two toggle buttons
---------------------------------------------------------------------------

function ZhTWLayout.setupItemDBs(itemsTab)
	local controls = itemsTab.controls
	local itemList, selectDB = controls.itemList, controls.selectDB
	local uniqueDB, rareDB, label = controls.uniqueDB, controls.rareDB, controls.selectDBLabel
	if not (itemList and selectDB and uniqueDB and rareDB and label) then
		return
	end
	local function wrap(control, key, zhValue)
		local orig = control[key]
		control[key] = function(...)
			if enabled() then
				return zhValue(...)
			end
			if type(orig) == "function" then
				return orig(...)
			end
			return orig
		end
	end
	-- POB's own "Import from:" drop-down is replaced by the buttons
	wrap(label, "shown", function() return false end)
	wrap(uniqueDB, "shown", function() return selectDB.selIndex == 1 end)
	wrap(rareDB, "shown", function() return selectDB.selIndex == 2 end)
	-- same places as POB's compact layout, but the list runs down to the bottom
	wrap(uniqueDB, "y", function() return 118 end)
	wrap(rareDB, "y", function() return 78 end)
	local function fillHeight(c)
		local _, y = c:GetPos()
		return m_max(120, (itemsTab.maxY or 1000) - y - 4)
	end
	wrap(uniqueDB, "height", fillHeight)
	wrap(rareDB, "height", fillHeight)
	local function sourceButton(index, text, anchor, x, y)
		local button = new("ButtonControl"):ButtonControl(anchor, { x, y, 110, 22 }, function()
			return (selectDB.selIndex == index and GOLD or "^7") .. text
		end, function()
			selectDB.selIndex = index
		end)
		button.shown = enabled
		return button
	end
	local unique = sourceButton(1, "傳奇資料庫", { "TOPLEFT", itemList, "BOTTOMLEFT" }, 0, 12)
	local rare = sourceButton(2, "稀有範本", { "LEFT", unique, "RIGHT" }, 6, 0)
	controls.zhTWSourceUnique = unique
	controls.zhTWSourceRare = rare
	-- gold underline under the chosen one
	local mark = new("Control"):Control({ "TOPLEFT", unique, "BOTTOMLEFT" }, { 0, 1, 226, 2 })
	mark.shown = enabled
	mark.Draw = function(control)
		local chosen = selectDB.selIndex == 2 and rare or unique
		local x, y = chosen:GetPos()
		local w, h = chosen:GetSize()
		rect(x, y + h + 1, w, 2, 0.78, 0.64, 0.35)
		SetDrawColor(1, 1, 1)
	end
	controls.zhTWSourceMark = mark
end

---------------------------------------------------------------------------
-- Top bar: labelled passive point counts, gold Save button with unsaved changes
---------------------------------------------------------------------------

-- "^7123 / 123   ^78 / 8" (colours are ^7 or ^xRRGGBB)
local function splitPoints(str)
	local parts = { }
	-- "^7" has no fixed length against the digits after it, so make it a 6-digit colour first
	str = (str or ""):gsub("%^7", "^xFFFFFF")
	for color, a, b in str:gmatch("(%^x%x%x%x%x%x%x)%s*(%d+) / (%d+)") do
		t_insert(parts, { color = color, used = a, max = b })
	end
	return parts
end
ZhTWLayout.splitPoints = splitPoints

local function pointsText(str)
	local parts = splitPoints(str)
	if #parts < 2 then
		return str
	end
	local gray = "^x8C8478"
	return s_format("%s天賦點 %s%s / %s  %s|  昇華 %s%s / %s", gray, parts[1].color, parts[1].used, parts[1].max, gray, parts[2].color, parts[2].used, parts[2].max)
end
ZhTWLayout.pointsText = pointsText

function ZhTWLayout.setupTopBar(build)
	local controls = build.controls
	local points = controls.pointDisplay
	if points then
		local origWidth, origDraw = points.width, points.Draw
		points.width = function(control)
			if enabled() and control.str then
				return DrawStringWidth(16, "VAR", pointsText(control.str)) + 12
			end
			return origWidth(control)
		end
		points.Draw = function(control, ...)
			if not enabled() or not control.str then
				return origDraw(control, ...)
			end
			-- POB draws str with the fixed-width font; in Chinese draw the labelled text instead
			local x, y = control:GetPos()
			local width, height = control:GetSize()
			SetDrawColor(1, 1, 1)
			if not ZhTWLayout.drawPanelPoints(build, control) then
				rect(x, y, width + 2, height, 0.35, 0.29, 0.19)
				rect(x + 1, y + 1, width, height - 2, 0.08, 0.07, 0.05)
				SetDrawColor(1, 1, 1)
				DrawString(x + 6, y + 2, "LEFT", 16, "VAR", pointsText(control.str))
			end
			if control:IsMouseInBounds() and control.req then
				SetDrawLayer(nil, 10)
				local tip = ZhTWLayout.pointsTooltip or new("Tooltip"):Tooltip()
				ZhTWLayout.pointsTooltip = tip
				tip:Clear()
				tip:AddLine(16, control.req)
				tip:Draw(x, y, width, height, main.viewPort)
				SetDrawLayer(nil, 0)
			end
			SetDrawColor(1, 1, 1)
		end
	end
	local save = controls.save
	if save then
		local origLabel = save.label
		save.label = function()
			if enabled() and build.unsaved then
				return GOLD .. "Save"
			end
			return origLabel
		end
	end
end

---------------------------------------------------------------------------
-- Side bar buttons: only Import/Export, Build and Configuration; the build
-- sheets (Items / Skills / Tree / Calcs) become tabs above the main view.
-- Notes, Party and Compare are hidden but their tabs and saved data stay.
---------------------------------------------------------------------------

local SHEET_STRIP = 30
local sheetTabs = {
	{ label = "裝備", mode = "ITEMS" },
	{ label = "技能", mode = "SKILLS" },
	{ label = "天賦", mode = "TREE" },
	{ label = "計算", mode = "CALCS" },
}
local isSheet = { ITEMS = true, SKILLS = true, TREE = true, CALCS = true }
local hiddenModes = { NOTES = true, PARTY = true, COMPARE = true }

local function hideWhenEnabled(control)
	if not control then
		return
	end
	local orig = control.shown
	control.shown = function(self)
		if enabled() then
			return false
		end
		if type(orig) == "function" then
			return orig(self)
		end
		return orig ~= false
	end
end

function ZhTWLayout.setupModeButtons(build)
	local controls = build.controls
	-- buildName: "Current build:" box; Save on an unnamed build already asks for a name
	for _, name in ipairs({ "modeNotes", "modeTree", "modeSkills", "modeItems", "modeCalcs", "modeParty", "modeCompare", "buildName" }) do
		hideWhenEnabled(controls[name])
	end
	-- On narrow screens PoB moves the build name into the side bar and pushes the side bar down
	local sideBar = build.anchorSideBar
	local origSideY = sideBar.y
	sideBar.y = function(self)
		if enabled() then
			return 36
		end
		return type(origSideY) == "function" and origSideY(self) or origSideY
	end
	local import = controls.modeImport
	import.width = function()
		return enabled() and 96 or 134
	end
	local sheetButton = new("ButtonControl"):ButtonControl({ "LEFT", import, "RIGHT" }, { 4, 0, 96, 20 }, "角色配置", function()
		build.viewMode = build.zhTWLastSheet or "ITEMS"
	end)
	sheetButton.shown = function()
		return enabled()
	end
	sheetButton.locked = function()
		return isSheet[build.viewMode]
	end
	controls.zhTWModeSheets = sheetButton
	-- Main skill selection moves into the 技能 tab (setupSkillsTab); the side bar keeps only
	-- the character sheet. mainSocketGroup / mainSkill hide with the label they hang from;
	-- the others use collapsing anchors and get their shown flag rewritten every frame by
	-- RefreshSkillSelectControls, so they are hidden through IsShown instead.
	hideWhenEnabled(controls.mainSkillLabel)
	for _, name in ipairs({ "mainSkillPart", "mainSkillStageCount", "mainSkillMineCount", "mainSkillMinion", "mainSkillMinionSkill" }) do
		local control = controls[name]
		if control then
			local baseIsShown = control.IsShown
			control.IsShown = function(self)
				if enabled() then
					return false
				end
				return baseIsShown(self)
			end
		end
	end

	-- Tabs across the top of the main view
	local strip = new("Control"):Control(nil, { 312, 32, 0, SHEET_STRIP })
	strip.width = function()
		return main.screenW - 312
	end
	strip.shown = function()
		return enabled() and isSheet[build.viewMode]
	end
	strip.Draw = function(control)
		local x, y = control:GetPos()
		local width, height = control:GetSize()
		SetDrawLayer(nil, -10) -- below the buttons and dropdowns drawn on top of it
		rect(x, y + height - 2, width, 1, 0.47, 0.39, 0.22)
		SetDrawColor(1, 1, 1)
		SetDrawLayer(nil, 0)
	end
	controls.zhTWSheetStrip = strip
	for i, tab in ipairs(sheetTabs) do
		local button = new("ButtonControl"):ButtonControl({ "TOPLEFT", strip, "TOPLEFT" }, { 4 + (i - 1) * 94, 3, 90, 22 }, tab.label, function()
			build.viewMode = tab.mode
		end)
		button.locked = function()
			return build.viewMode == tab.mode
		end
		controls["zhTWSheet" .. tab.mode] = button
		ZhTWLayout.addButtonIcon(button, tab.label)
	end
	ZhTWLayout.addButtonIcon(import, "匯入/匯出")
	ZhTWLayout.addButtonIcon(sheetButton, "角色配置")
	ZhTWLayout.addButtonIcon(controls.modeConfig, "設定")

	ZhTWLayout.setupTreePanel(build)
end

-- Icon before a button's text (Chinese interface with the icon sheet only)
function ZhTWLayout.addButtonIcon(button, iconName)
	if not button then
		return
	end
	local baseDraw = button.Draw
	button.Draw = function(self, viewPort, noTooltip)
		if not ZhTWLayout.hasIcons() or not iconIndex[iconName] then
			return baseDraw(self, viewPort, noTooltip)
		end
		local label = self:GetProperty("label")
		local origLabel = self.label
		self.label = "" -- frame and hover from PoB, icon and text drawn here
		baseDraw(self, viewPort, noTooltip)
		self.label = origLabel
		local x, y = self:GetPos()
		local width, height = self:GetSize()
		local textH = height - 4
		local size = height - 4
		local textW = DrawStringWidth(textH, "VAR", label)
		local startX = m_floor(x + (width - size - 4 - textW) / 2)
		local on = self:IsEnabled()
		ZhTWLayout.drawIcon(iconName, startX, y + 2, size, on and 1 or 0.4)
		if on then
			SetDrawColor(1, 1, 1)
		else
			SetDrawColor(0.33, 0.33, 0.33)
		end
		DrawString(startX + size + 4, y + 2, "LEFT", textH, "VAR", label)
		SetDrawColor(1, 1, 1)
	end
end

---------------------------------------------------------------------------
-- 天賦 tab: the top bar's right half (level, points, class, ascendancies, loadout)
-- becomes a vertical panel in the top-left corner of the tree view. Everything in
-- that row is anchored to pointDisplay, so hiding pointDisplay hides all of it.
---------------------------------------------------------------------------

local PANEL_X, PANEL_Y = 318, 32 + SHEET_STRIP + 4
local PANEL_PAD, PANEL_ROW, LABEL_W, FIELD_W = 8, 24, 64, 176
local PANEL_W = PANEL_PAD * 2 + LABEL_W + FIELD_W
-- rows top to bottom; points takes two rows (天賦 and 昇華)
local panelRows = {
	{ name = "characterLevel", row = 1, x = 0, w = FIELD_W + LABEL_W - 54 },
	{ name = "levelScalingButton", row = 1, x = FIELD_W + LABEL_W - 50, w = 50 },
	{ name = "pointDisplay", row = 2, x = LABEL_W, w = FIELD_W, rows = 2 },
	{ name = "classDrop", row = 4, x = LABEL_W, w = FIELD_W, label = "職業" },
	{ name = "ascendDrop", row = 5, x = LABEL_W, w = FIELD_W, label = "昇華職業" },
	{ name = "secondaryAscendDrop", row = 6, x = LABEL_W, w = FIELD_W, label = "血液昇華" },
	{ name = "buildLoadouts", row = 7, x = LABEL_W, w = FIELD_W, label = "天賦配置" },
}
local PANEL_H = PANEL_PAD * 2 + 7 * PANEL_ROW - 4

local function rowTop(row)
	return PANEL_Y + PANEL_PAD + (row - 1) * PANEL_ROW
end

function ZhTWLayout.inTreePanel(build)
	if not (enabled() and build.viewMode == "TREE") then
		return false
	end
	local cx, cy = GetCursorPos()
	return cx >= PANEL_X and cy >= PANEL_Y and cx < PANEL_X + PANEL_W and cy < PANEL_Y + PANEL_H
end

function ZhTWLayout.setupTreePanel(build)
	local controls = build.controls
	local points = controls.pointDisplay
	if not points then
		return
	end
	local function treePanel()
		return enabled() and build.viewMode == "TREE"
	end
	for _, entry in ipairs(panelRows) do
		local control = controls[entry.name]
		if control then
			local baseGetPos = control.GetPos
			control.GetPos = function(self)
				if treePanel() then
					return PANEL_X + PANEL_PAD + entry.x, rowTop(entry.row)
				end
				return baseGetPos(self)
			end
			-- Size through GetSize: DropDownControl does arithmetic on its width/height fields
			local baseGetSize = control.GetSize
			control.GetSize = function(self)
				if treePanel() then
					return entry.w, (entry.rows or 1) * PANEL_ROW - 4
				end
				return baseGetSize(self)
			end
		end
	end
	local origShown = points.shown
	points.shown = function(self)
		if enabled() and build.viewMode ~= "TREE" then
			return false
		end
		if type(origShown) == "function" then
			return origShown(self)
		end
		return origShown ~= false
	end

	-- Background and labels, drawn below the controls
	local panel = new("Control"):Control(nil, { PANEL_X, PANEL_Y, PANEL_W, PANEL_H })
	panel.shown = treePanel
	panel.Draw = function(control)
		SetDrawLayer(nil, -10)
		rect(PANEL_X, PANEL_Y, PANEL_W, PANEL_H, 0.35, 0.29, 0.19)
		rect(PANEL_X + 1, PANEL_Y + 1, PANEL_W - 2, PANEL_H - 2, 0.06, 0.055, 0.045, 0.94)
		SetDrawColor(1, 1, 1)
		local lx = PANEL_X + PANEL_PAD
		DrawString(lx, rowTop(2) + 2, "LEFT", 16, "VAR", "^x8C8478天賦")
		DrawString(lx, rowTop(3) + 2, "LEFT", 16, "VAR", "^x8C8478昇華")
		for _, entry in ipairs(panelRows) do
			if entry.label then
				DrawString(lx, rowTop(entry.row) + 2, "LEFT", 16, "VAR", "^x8C8478" .. entry.label)
			end
		end
		SetDrawLayer(nil, 0)
	end
	controls.zhTWTreePanel = panel
end

-- Points drawn as two rows (天賦 / 昇華) inside the tree panel; false when not in the panel
function ZhTWLayout.drawPanelPoints(build, control)
	if not (enabled() and build.viewMode == "TREE") then
		return false
	end
	local parts = splitPoints(control.str)
	if #parts < 2 then
		return false
	end
	local x, y = control:GetPos()
	for i = 1, 2 do
		local p = parts[i]
		DrawString(x + 4, y + (i - 1) * PANEL_ROW + 2, "LEFT", 16, "VAR", s_format("%s%s ^x8C8478/ ^7%s", p.color, p.used, p.max))
	end
	return true
end

---------------------------------------------------------------------------
-- 技能 tab: "主要技能（DPS 計算）" box between the usage tips and Gem Options.
-- Its controls are copies of the side bar ones (same callbacks), filled every frame by
-- PoB's own RefreshSkillSelectControls, so they live in the tab's own control list and
-- open drop-downs get their clicks before the tab content below them.
---------------------------------------------------------------------------

local SKILL_BOX_Y = 95 -- where Gem Options starts in PoB's layout
local SKILL_ROW = 24
local skillRows = {
	{ key = "mainSocketGroup", label = "技能群組:" },
	{ key = "mainSkill", label = "主動技能:" },
	{ key = "mainSkillPart", label = "技能部分:" },
	{ key = "mainSkillStageCount", label = "階段:" },
	{ key = "mainSkillMineCount", label = "啟動中地雷:" },
	{ key = "mainSkillMinion", label = "召喚物:" },
	{ key = "mainSkillMinionSkill", label = "召喚物技能:" },
}

function ZhTWLayout.setupSkillsTab(skillsTab)
	local build = skillsTab.build
	local src = build.controls
	local controls = skillsTab.controls
	local groupList = controls.groupList
	if not (groupList and src.mainSocketGroup) then
		return
	end
	local proxies = { }
	skillsTab.zhTWSkillControls = proxies

	local function rowShown(key)
		local control = proxies[key]
		return control:GetProperty("shown") and true or false
	end
	local function rowCount()
		local n = 0
		for _, row in ipairs(skillRows) do
			if rowShown(row.key) then
				n = n + 1
			end
		end
		return n
	end
	local function boxHeight()
		return 28 + rowCount() * SKILL_ROW
	end

	-- Gem Options and its inputs move down by the box height (only while the box is shown)
	for _, control in pairs(controls) do
		if control ~= controls.groupTip and control.anchor and control.anchor.other == groupList and control.anchor.otherPoint == "BOTTOMLEFT" then
			local origY = control.y
			control.y = function(self)
				local y = type(origY) == "function" and origY(self) or origY
				if enabled() then
					return y + boxHeight() + 12
				end
				return y
			end
		end
	end

	local box = new("SectionControl"):SectionControl({ "TOPLEFT", groupList, "BOTTOMLEFT" }, { 0, SKILL_BOX_Y, 360, boxHeight }, "Main Skill (DPS calculation)")
	box.shown = enabled
	controls.zhTWSkillBox = box

	local function rowY(key)
		local n = 0
		for _, row in ipairs(skillRows) do
			if row.key == key then
				break
			end
			if rowShown(row.key) then
				n = n + 1
			end
		end
		return 16 + n * SKILL_ROW
	end
	local function delegate(name, field)
		return function(...)
			local f = src[name][field]
			if f then
				return f(...)
			end
		end
	end
	local function place(key, control)
		control.y = function()
			return rowY(key)
		end
		proxies[key] = control
		controls["zhTW_" .. key] = control
	end
	local INPUT_X, INPUT_W = 110, 240
	local function dropDown(key, width)
		local control = new("DropDownControl"):DropDownControl({ "TOPLEFT", box, "TOPLEFT" }, { INPUT_X, 0, width or INPUT_W, 20 }, nil, delegate(key, "selFunc"))
		control.tooltipFunc = src[key].tooltipFunc
		control.maxDroppedWidth = 500
		place(key, control)
		return control
	end
	local function edit(key)
		local control = new("EditControl"):EditControl({ "TOPLEFT", box, "TOPLEFT" }, { INPUT_X, 0, 60, 20 }, nil, nil, "%D", nil, delegate(key, "changeFunc"))
		place(key, control)
		return control
	end
	dropDown("mainSocketGroup")
	dropDown("mainSkill")
	dropDown("mainSkillPart")
	edit("mainSkillStageCount")
	edit("mainSkillMineCount")
	local minion = dropDown("mainSkillMinion", 150)
	minion.CanReceiveDrag = src.mainSkillMinion.CanReceiveDrag
	minion.ReceiveDrag = src.mainSkillMinion.ReceiveDrag
	dropDown("mainSkillMinionSkill")
	local library = new("ButtonControl"):ButtonControl({ "LEFT", minion, "RIGHT" }, { 4, 0, 86, 20 }, "Manage Spectres...", function()
		build:OpenSpectreLibrary()
	end)
	proxies.mainSkillMinionLibrary = library
	controls.zhTW_mainSkillMinionLibrary = library
	for _, row in ipairs(skillRows) do
		local control = proxies[row.key]
		local label = new("LabelControl"):LabelControl({ "RIGHT", control, "LEFT" }, { -6, 0, 0, 16 }, "^7" .. row.label)
		controls["zhTW_" .. row.key .. "Label"] = label
	end
end

-- Fills the 技能 tab's main skill box (called before the tab is drawn)
local function refreshSkillsTab(build)
	local proxies = build.skillsTab and build.skillsTab.zhTWSkillControls
	if not proxies then
		return
	end
	build:RefreshSkillSelectControls(proxies, build.mainSocketGroup, "")
	-- the second drop-down only when there is something to choose
	if #proxies.mainSkill.list <= 1 then
		proxies.mainSkill.shown = false
	end
	if not proxies.mainSkillMinion.shown then
		proxies.mainSkillMinionLibrary.shown = false
	end
end

-- Called by Build.lua before the current tab is drawn
function ZhTWLayout.adjustTabViewPort(build, viewPort, inputEvents)
	if not enabled() then
		return
	end
	if build.viewMode == "SKILLS" then
		refreshSkillsTab(build)
	end
	if hiddenModes[build.viewMode] then
		build.viewMode = build.zhTWLastSheet or "ITEMS"
	end
	if isSheet[build.viewMode] then
		build.zhTWLastSheet = build.viewMode
		viewPort.y = viewPort.y + SHEET_STRIP
		viewPort.height = viewPort.height - SHEET_STRIP
	end
	-- Mouse over the tree panel: clicks and wheel must not reach the tree under it
	if inputEvents and ZhTWLayout.inTreePanel(build) then
		for id, event in pairs(inputEvents) do
			if (event.type == "KeyDown" or event.type == "KeyUp") and (event.key:match("BUTTON") or event.key:match("WHEEL")) then
				inputEvents[id] = nil
			end
		end
	end
end

---------------------------------------------------------------------------
-- Items tab: item details docked on the right instead of floating tooltips
---------------------------------------------------------------------------

local DETAILS_MIN_W = 300

-- Where the panel goes; nil when it does not fit or the item editor is open
local function detailsRect(itemsTab, viewPort)
	if not enabled() or main.portraitMode or itemsTab.displayItem or main.popups[1] then
		return nil
	end
	local shared = itemsTab.controls.sharedItemList
	if not shared or not shared:IsShown() then
		return nil
	end
	local craft = itemsTab.controls.craftDisplayItem
	local sx = shared:GetPos()
	local sw = shared:GetSize()
	local _, y = craft:GetPos()
	local x = sx + sw + 14
	local right = viewPort.x + viewPort.width - 22
	local w = m_min(458, right - x)
	if w < DETAILS_MIN_W then
		return nil
	end
	local bottom = (itemsTab.maxY or (viewPort.y + viewPort.height)) - 4
	return x, y, w, bottom - y
end

-- What the panel shows, kept per build (fromBuild: the item lives in itemsTab.items)
local function record(itemsTab, item, slot, dbMode, fromBuild)
	local details = itemsTab.zhTWDetails or { }
	itemsTab.zhTWDetails = details
	details.item, details.slot, details.dbMode, details.fromBuild = item, slot, dbMode, fromBuild
	details.frame = ZhTWLayout.detailsFrame
end

-- Lists draw their hover tooltip through AddValueTooltip; while docked, remember the item instead
function ZhTWLayout.hookItemLists(itemsTab)
	if itemsTab.zhTWListsHooked then
		return
	end
	itemsTab.zhTWListsHooked = true
	ZhTWLayout.setupItemDBs(itemsTab)
	local function hook(list, toItem, dbMode, fromBuild)
		if not list then
			return
		end
		local orig = list.AddValueTooltip
		list.AddValueTooltip = function(self, tooltip, index, value)
			if ZhTWLayout.detailsViewPort and detailsRect(itemsTab, ZhTWLayout.detailsViewPort) then
				local item = toItem(value)
				if item then
					record(itemsTab, item, nil, dbMode, fromBuild)
				end
				tooltip:Clear(true)
				return
			end
			return orig(self, tooltip, index, value)
		end
	end
	local controls = itemsTab.controls
	local function itemById(id) return itemsTab.items[id] end
	local function itself(item) return type(item) == "table" and item or nil end
	hook(controls.itemList, itemById, false, true)
	hook(controls.uniqueDB, itself, true, false)
	hook(controls.rareDB, itself, true, false)
	hook(controls.sharedItemList, itself, false, false)
	-- Equipped slots (also the jewel sockets)
	for _, slot in ipairs(itemsTab.orderedSlots) do
		local orig = slot.tooltipFunc
		if orig then
			slot.tooltipFunc = function(tooltip, mode, index, itemId)
				if ZhTWLayout.detailsViewPort and detailsRect(itemsTab, ZhTWLayout.detailsViewPort) then
					local item = itemsTab.items[slot.items[index]]
					-- same conditions as ItemSlotControl's own tooltip
					local selControl = itemsTab.selControl
					if mode ~= "OUT" and item and (slot.dropped or not selControl or selControl == slot.controls.activate or selControl.ListControl) then
						record(itemsTab, item, slot, false, true)
					end
					tooltip:Clear(true)
					return
				end
				return orig(tooltip, mode, index, itemId)
			end
		end
	end
end

ZhTWLayout.detailsRect = detailsRect

function ZhTWLayout.drawDetails(itemsTab, viewPort)
	local x, y, w, h = detailsRect(itemsTab, viewPort)
	if not x then
		return
	end
	-- Frame and heading
	rect(x, y, w, h, 0.35, 0.29, 0.19)
	rect(x + 1, y + 1, w - 2, h - 2, 0.06, 0.05, 0.04)
	local details = itemsTab.zhTWDetails or { }
	local item = details.item
	if item and details.fromBuild and itemsTab.items[item.id] ~= item then
		-- removed from the build since
		item = nil
		details.item = nil
	end
	local hovering = item and details.frame == ZhTWLayout.detailsFrame
	DrawString(x + 10, y + 6, "LEFT", 14, "VAR", GOLD .. "物品詳細" .. (item and not hovering and "^x8C8478　（最近查看）" or ""))
	if not item then
		DrawString(x + 10, y + 32, "LEFT", 14, "VAR", "^x8C8478將滑鼠移到物品上，詳細內容會固定顯示在這裡，\n不會擋住清單。")
		SetDrawColor(1, 1, 1)
		return
	end
	local tooltip = details.tooltip
	if not tooltip then
		tooltip = new("Tooltip"):Tooltip()
		details.tooltip = tooltip
	end
	tooltip.maxWidth = w - 8
	if tooltip:CheckForUpdate(item, details.slot, details.dbMode, IsKeyDown("SHIFT"), launch.devModeAlt, itemsTab.build.outputRevision) then
		itemsTab:AddItemTooltip(tooltip, item, details.slot, details.dbMode)
	end
	SetDrawColor(1, 1, 1)
	tooltip:Draw(x + 4, y + 26, nil, nil, { x = x + 4, y = y + 26, width = w - 8, height = h - 30 })
end

---------------------------------------------------------------------------
-- Import tab: the international-server login is hidden (Taiwan accounts cannot use it)
---------------------------------------------------------------------------

function ZhTWLayout.setupImportTab(importTab)
	local controls = importTab.controls
	local oauth, site = controls.sectionOauthCharImport, controls.sectionCharSiteImport
	if not oauth or not site then
		return
	end
	local origShown = oauth.shown
	oauth.shown = function(...)
		if enabled() then
			return false
		end
		if type(origShown) == "function" then
			return origShown(...)
		end
		return origShown ~= false
	end
	-- Collapsing anchor: with the login section hidden, "import by account name" moves to the top
	site:SetAnchor("TOPLEFT", oauth, "BOTTOMLEFT", 0, 18, true)
	-- PC / Xbox / Sony are international-server platforms: the realm drop-down becomes a fixed
	-- "台服" tag (still shown, since the account name box and others are anchored to it)
	local realm = controls.siteAccountRealm
	if realm then
		local twIndex
		for i, entry in ipairs(realm.list or { }) do
			if type(entry) == "table" and entry.id == "TW" then
				twIndex = i
			end
		end
		if twIndex then
			local origGetSelValue = realm.GetSelValue
			realm.GetSelValue = function(self, ...)
				if enabled() then
					return self.list[twIndex]
				end
				return origGetSelValue(self, ...)
			end
			local origEnabled = realm.enabled
			realm.enabled = function(...)
				if enabled() then
					return false
				end
				if type(origEnabled) == "function" then
					return origEnabled(...)
				end
				return origEnabled ~= false
			end
			realm.Draw = function(self, viewPort, ...)
				if not enabled() then
					return common.classes.DropDownControl.Draw(self, viewPort, ...)
				end
				local x, y = self:GetPos()
				local width, height = self:GetSize()
				rect(x, y, width, height, 0.35, 0.29, 0.19)
				rect(x + 1, y + 1, width - 2, height - 2, 0.08, 0.07, 0.05)
				DrawString(x + width / 2, y + 2, "CENTER_X", height - 4, "VAR", GOLD .. "台服")
				SetDrawColor(1, 1, 1)
			end
		end
	end
	-- One "import everything" button instead of "passive tree and jewels" + "items and skills"
	-- (their check boxes keep POB's defaults: delete jewels / skills / equipment, keep weapon swap)
	local treeButton, itemsButton, header = controls.siteCharImportTree, controls.siteCharImportItems, controls.siteCharImportHeader
	if treeButton and itemsButton and header then
		for _, button in ipairs({ treeButton, itemsButton }) do
			local origShown = button.shown
			button.shown = function(...)
				if enabled() then
					return false
				end
				if type(origShown) == "function" then
					return origShown(...)
				end
				return origShown ~= false
			end
		end
		local all = new("ButtonControl"):ButtonControl({ "LEFT", header, "RIGHT" }, { 8, 0, 260, 20 }, "全部匯入（天賦、珠寶、物品、技能）", function()
			local realm = controls.siteAccountRealm:GetSelValue()
			local function go()
				importTab.zhTWImportAll = true
				importTab.zhTWTreeResult = nil
				importTab:DownloadPassiveTree(realm)
			end
			if importTab.build.spec:CountAllocNodes() > 0 then
				main:OpenConfirmPopup("Character Import", "Importing the passive tree will overwrite your current tree.", "Import", go)
			else
				go()
			end
			importTab:SetPredefinedBuildName()
		end)
		all.shown = enabled
		all.enabled = function()
			return importTab.charImportMode == "SELECTCHAR"
		end
		controls.zhTWImportAll = all
	end
	-- The bandit tip pointed at the hidden login; Taiwan data has no bandit choice at all
	local note = controls.siteCharBanditNote
	if note then
		local origLabel = note.label
		note.label = function()
			if enabled() then
				return "^7提示：台服的角色資料不含盜賊任務的選擇，匯入後請到「設定」分頁手動選擇。"
			end
			return origLabel
		end
	end
end

return ZhTWLayout
