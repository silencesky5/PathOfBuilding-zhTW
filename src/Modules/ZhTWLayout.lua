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
			rect(x, y, width + 2, height, 0.35, 0.29, 0.19)
			rect(x + 1, y + 1, width, height - 2, 0.08, 0.07, 0.05)
			SetDrawColor(1, 1, 1)
			DrawString(x + 6, y + 2, "LEFT", 16, "VAR", pointsText(control.str))
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
local TREE_ROW = 28 -- points / level / class row under the tabs on the 天賦 tab
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
	for _, name in ipairs({ "modeNotes", "modeTree", "modeSkills", "modeItems", "modeCalcs", "modeParty", "modeCompare" }) do
		hideWhenEnabled(controls[name])
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
	-- Skill selection moves up into the space of the two hidden button rows
	local label = controls.mainSkillLabel
	local origY = label.y
	label.y = function(self)
		if enabled() then
			return 28
		end
		return type(origY) == "function" and origY(self) or origY
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
		if build.viewMode == "TREE" then
			-- dark band behind the points / level / class row
			rect(x, y + height, width, TREE_ROW, 0.06, 0.055, 0.045)
			rect(x, y + height + TREE_ROW - 1, width, 1, 0.3, 0.25, 0.15)
		end
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
	end

	-- Points / level / class / ascendancy / loadout row: only on the 天賦 tab, moved into
	-- the tab row next to the tabs. Everything else in that row is anchored to pointDisplay,
	-- so moving or hiding it moves or hides the whole row.
	local points = controls.pointDisplay
	if points then
		local origX, origY, origShown = points.x, points.y, points.shown
		local function treeRow()
			return enabled() and build.viewMode == "TREE"
		end
		points.x = function(self)
			if treeRow() then
				local ax = build.anchorTopBarRight:GetPos()
				local aw = build.anchorTopBarRight:GetSize()
				return 316 - ax - aw
			end
			return type(origX) == "function" and origX(self) or origX
		end
		points.y = function(self)
			if treeRow() then
				-- anchor top is 4; row sits just below the tab strip
				return 32 + SHEET_STRIP + 4 - 4
			end
			return type(origY) == "function" and origY(self) or origY
		end
		points.shown = function(self)
			if enabled() and build.viewMode ~= "TREE" then
				return false
			end
			if type(origShown) == "function" then
				return origShown(self)
			end
			return origShown ~= false
		end
	end
end

-- Called by Build.lua before the current tab is drawn
function ZhTWLayout.adjustTabViewPort(build, viewPort)
	if not enabled() then
		return
	end
	if hiddenModes[build.viewMode] then
		build.viewMode = build.zhTWLastSheet or "ITEMS"
	end
	if isSheet[build.viewMode] then
		build.zhTWLastSheet = build.viewMode
		local push = SHEET_STRIP + (build.viewMode == "TREE" and TREE_ROW or 0)
		viewPort.y = viewPort.y + push
		viewPort.height = viewPort.height - push
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
