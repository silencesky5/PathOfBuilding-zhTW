-- Path of Building
--
-- Module: zhTW Craft Type Menu
-- Chinese interface only: the "類型" drop-down of the 製作物品 popup (ItemsTab:CraftItem) opens a
-- three-column menu instead of one long list: 武器 | 防具 | 飾品／珠寶 (藥劑 and the rest go to
-- the third column). The drop-down's list, selIndex and selFunc are untouched, so choosing a type
-- does exactly what choosing it in the normal list does.
--
local t_insert = table.insert
local m_max = math.max
local m_min = math.min

local M = { }

local ROW = 16 -- row height
local TEXT = 14 -- text size (same as the normal drop-down lines)
local PAD = 8 -- inner padding
local GAP = 18 -- space between columns
local INDENT = 8 -- items are indented under their section heading
local SUBGAP = 12 -- space between the two armour sub-columns

local TITLE = "^xE6DFD0" -- column titles (warm off-white, same as ZhTWLayout)
local SUBTLE = "^xA39B8C" -- section headings
local LINE = { 0.29, 0.27, 0.25 } -- separators (#4A4540)

-- Each section lists list keys (data.itemBaseTypeList values) in display order.
-- short = true: show only the part after "類型: " (the section heading already says what it is).
local WEAPONS = {
	{ title = "單手武器", short = true, keys = { "Claw", "Dagger", "Dagger: Rune Dagger", "One Handed Axe", "One Handed Sword", "One Handed Sword: Thrusting", "One Handed Mace", "Sceptre", "Wand" } },
	{ title = "雙手武器", short = true, keys = { "Bow", "Staff", "Staff: Warstaff", "Two Handed Axe", "Two Handed Sword", "Two Handed Mace", "Fishing Rod" } },
	{ title = "副手", short = true, keys = { "Quiver" } },
}
-- Armour: one section per slot; single defence types on the left, hybrids on the right
local ARMOUR_SLOTS = { "Helmet", "Body Armour", "Gloves", "Boots", "Shield" }
local ARMOUR_LEFT = { "Armour", "Evasion", "Energy Shield", "Ward" }
local ARMOUR_RIGHT = { "Armour/Evasion", "Armour/Energy Shield", "Evasion/Energy Shield", "Armour/Evasion/Energy Shield" }
local OTHERS = {
	{ title = "飾品", keys = { "Amulet", "Amulet: Talisman", "Ring", "Belt" } },
	{ title = "珠寶", keys = { "Jewel", "Jewel: Abyss", "Jewel: Cluster", "Jewel: Timeless", "Jewel: Charm", "Jewel: Blightcore" } },
	{ title = "藥劑", keys = { "Flask: Life", "Flask: Mana", "Flask: Hybrid", "Flask: Utility", "Tincture" } },
	{ title = "其他", keys = { "Graft", "Viscera" }, rest = true }, -- also every type not placed anywhere else
}

local function tr(text)
	return ZhTWLocale and ZhTWLocale.translate(text) or text
end

local function textWidth(text)
	return DrawStringWidth(TEXT, "VAR", text)
end

-- Columns of rows: { title = "..." } (column title), { heading = "..." }, { cells = { cell, ... } }
-- cell = { index = list index, label = "...", col = 1|2 (armour sub-column) }
local function buildColumns(list)
	local indexOf = { }
	for index, key in ipairs(list) do
		indexOf[key] = index
	end
	local used = { }
	local function take(key)
		local index = indexOf[key]
		if index and not used[index] then
			used[index] = true
			return index
		end
	end
	local function sections(column, spec)
		for _, section in ipairs(spec) do
			local rows = { }
			for _, key in ipairs(section.keys) do
				local index = take(key)
				if index then
					local label = tr(key)
					if section.short then
						label = label:match(":%s*(.+)$") or label
					end
					t_insert(rows, { cells = { { index = index, label = label } } })
				end
			end
			if section.rest then
				for index, key in ipairs(list) do
					if not used[index] then
						used[index] = true
						t_insert(rows, { cells = { { index = index, label = tr(key) } } })
					end
				end
			end
			if rows[1] then
				t_insert(column, { heading = section.title })
				for _, row in ipairs(rows) do
					t_insert(column, row)
				end
			end
		end
	end

	local weapons = { { title = "武器" } }
	sections(weapons, WEAPONS)

	local armour = { { title = "防具" } }
	for _, slot in ipairs(ARMOUR_SLOTS) do
		local left, right = { }, { }
		for _, sub in ipairs(ARMOUR_LEFT) do
			local index = take(slot .. ": " .. sub)
			if index then
				t_insert(left, { index = index, label = tr(sub) })
			end
		end
		for _, sub in ipairs(ARMOUR_RIGHT) do
			local index = take(slot .. ": " .. sub)
			if index then
				t_insert(right, { index = index, label = tr(sub), col = 2 })
			end
		end
		-- other sub-types of this slot (new league bases), then the slot without a sub-type
		-- (special bases such as the golden ones) as 其他
		for index, key in ipairs(list) do
			if not used[index] and key:sub(1, #slot + 2) == slot .. ": " then
				used[index] = true
				t_insert(left, { index = index, label = tr(key:sub(#slot + 3)) })
			end
		end
		local plain = take(slot)
		if plain then
			t_insert(left, { index = plain, label = "其他" })
		end
		if left[1] or right[1] then
			t_insert(armour, { heading = tr(slot) })
			for i = 1, m_max(#left, #right) do
				local row = { cells = { } }
				if left[i] then
					left[i].col = 1
					t_insert(row.cells, left[i])
				end
				if right[i] then
					t_insert(row.cells, right[i])
				end
				t_insert(armour, row)
			end
		end
	end

	local others = { { title = "飾品／珠寶" } }
	sections(others, OTHERS)

	return { weapons, armour, others }
end

-- Positions relative to the menu's top left; returns the menu size
local function layout(columns)
	local x = PAD
	local height = 0
	local cells = { }
	for _, column in ipairs(columns) do
		local subWidth = { 0, 0 }
		local width = 0
		for _, row in ipairs(column) do
			if row.title or row.heading then
				width = m_max(width, textWidth(row.title or row.heading))
			else
				for _, cell in ipairs(row.cells) do
					local col = cell.col or 1
					subWidth[col] = m_max(subWidth[col], textWidth(cell.label) + 6)
				end
			end
		end
		local itemsWidth = INDENT + subWidth[1] + (subWidth[2] > 0 and SUBGAP + subWidth[2] or 0)
		column.x = x
		column.width = m_max(width, itemsWidth)
		local y = PAD
		for _, row in ipairs(column) do
			row.y = y
			if row.title then
				y = y + ROW + 6
			elseif row.heading then
				if y > PAD + ROW + 6 then
					row.y = y + 4
					y = y + 4
				end
				y = y + ROW
			else
				for _, cell in ipairs(row.cells) do
					cell.x = x + INDENT + (cell.col == 2 and subWidth[1] + SUBGAP or 0)
					cell.y = y
					cell.width = cell.col == 2 and subWidth[2] or subWidth[1]
					t_insert(cells, cell)
				end
				y = y + ROW
			end
		end
		height = m_max(height, y)
		x = x + column.width + GAP
	end
	return x - GAP + PAD, height + PAD, cells
end

function M.attach(dropDown)
	local DropDown = common.classes.DropDownControl -- call the class methods directly (see 交接 4. 踩過的坑)
	local menu -- { list, columns, cells, width, height }
	local function getMenu()
		if not menu or menu.list ~= dropDown.list or menu.count ~= #dropDown.list then
			menu = { list = dropDown.list, count = #dropDown.list, columns = buildColumns(dropDown.list) }
			menu.width, menu.height, menu.cells = layout(menu.columns)
		end
		return menu
	end
	-- Menu position on screen, kept inside the window
	local lastViewPort
	local function menuPos(m)
		local x, y = dropDown:GetPos()
		local _, height = dropDown:GetSize()
		local vp = lastViewPort or { x = 0, y = 0, width = 1920, height = 1080 }
		local mx = m_max(vp.x + 2, m_min(x, vp.x + vp.width - m.width - 2))
		local my = y + height
		if my + m.height > vp.y + vp.height - 2 then
			if y - m.height >= vp.y + 2 then
				my = y - m.height
			else
				my = m_max(vp.y + 2, vp.y + vp.height - m.height - 2)
			end
		end
		return mx, my
	end
	local function hoverCell()
		local m = getMenu()
		local mx, my = menuPos(m)
		local cx, cy = GetCursorPos()
		for _, cell in ipairs(m.cells) do
			if cx >= mx + cell.x - 3 and cx < mx + cell.x + cell.width and cy >= my + cell.y and cy < my + cell.y + ROW then
				return cell
			end
		end
	end

	-- The list's own scroll bar is never used by this menu
	dropDown.controls.scrollBar.shown = function()
		return false
	end

	function dropDown:IsMouseOver()
		if not self.dropped then
			return DropDown.IsMouseOver(self)
		end
		if not self:IsShown() then
			return false
		end
		local x, y = self:GetPos()
		local width, height = self:GetSize()
		local cx, cy = GetCursorPos()
		if cx >= x and cy >= y and cx < x + width and cy < y + height then
			return true, "BODY"
		end
		local m = getMenu()
		local mx, my = menuPos(m)
		if cx >= mx and cy >= my and cx < mx + m.width and cy < my + m.height then
			return true, "DROP"
		end
		return false
	end

	function dropDown:Draw(viewPort, noTooltip)
		lastViewPort = viewPort
		if not self.dropped then
			return DropDown.Draw(self, viewPort, noTooltip)
		end
		-- the box itself, drawn as a closed drop-down
		self.dropped = false
		DropDown.Draw(self, viewPort, true)
		self.dropped = true

		local m = getMenu()
		local mx, my = menuPos(m)
		local hover = hoverCell()
		SetDrawLayer(nil, 5)
		SetDrawColor(1, 1, 1)
		DrawImage(nil, mx, my, m.width, m.height)
		SetDrawColor(0, 0, 0)
		DrawImage(nil, mx + 1, my + 1, m.width - 2, m.height - 2)
		for i, column in ipairs(m.columns) do
			if i > 1 then -- separator between columns
				SetDrawColor(LINE[1], LINE[2], LINE[3])
				DrawImage(nil, mx + column.x - GAP / 2, my + PAD, 1, m.height - PAD * 2)
			end
			for _, row in ipairs(column) do
				if row.title then
					SetDrawColor(1, 1, 1)
					DrawString(mx + column.x, my + row.y, "LEFT", ROW, "VAR", TITLE .. row.title)
					SetDrawColor(LINE[1], LINE[2], LINE[3])
					DrawImage(nil, mx + column.x, my + row.y + ROW + 2, column.width, 1)
				elseif row.heading then
					SetDrawColor(1, 1, 1)
					DrawString(mx + column.x, my + row.y, "LEFT", TEXT, "VAR", SUBTLE .. row.heading)
				end
			end
		end
		for _, cell in ipairs(m.cells) do
			local selected = cell.index == self.selIndex
			if cell == hover then
				SetDrawColor(0.33, 0.33, 0.33)
				DrawImage(nil, mx + cell.x - 3, my + cell.y, cell.width + 3, ROW)
			elseif selected then
				SetDrawColor(0.2, 0.2, 0.2)
				DrawImage(nil, mx + cell.x - 3, my + cell.y, cell.width + 3, ROW)
			end
			if selected then
				SetDrawColor(1, 1, 1)
				DrawImage(nil, mx + cell.x - 3, my + cell.y + 1, 1, ROW - 2) -- selection mark
			end
			if cell == hover or selected then
				SetDrawColor(1, 1, 1)
			else
				SetDrawColor(0.66, 0.66, 0.66)
			end
			DrawString(mx + cell.x, my + cell.y + 1, "LEFT", TEXT, "VAR", cell.label)
		end
		SetDrawColor(1, 1, 1)
		SetDrawLayer(nil, 0)
	end

	function dropDown:OnChar(key)
		-- typing to search the long list is not needed in this menu
		return self.dropped and self or nil
	end

	function dropDown:OnKeyDown(key)
		if not self:IsShown() or not self:IsEnabled() then
			return
		end
		if key == "LEFTBUTTON" or key == "RIGHTBUTTON" then
			local mOver, mOverComp = self:IsMouseOver()
			if not mOver or (self.dropped and mOverComp == "BODY") then
				self.dropped = false
				return self
			end
			self.dropped = true
		elseif key == "ESCAPE" then
			self.dropped = false
		end
		return self.dropped and self
	end

	function dropDown:OnKeyUp(key)
		if not self:IsShown() or not self:IsEnabled() then
			return
		end
		if key == "LEFTBUTTON" or key == "RIGHTBUTTON" then
			local mOver, mOverComp = self:IsMouseOver()
			if not mOver then
				self.dropped = false
			elseif self.dropped and mOverComp == "DROP" then
				local cell = hoverCell()
				if cell then -- clicks on headings and empty space keep the menu open
					self.dropped = false
					if cell.index ~= self.selIndex then
						self.selIndex = cell.index
						if self.selFunc then
							self.selFunc(cell.index, self.list[cell.index])
						end
					end
				end
			end
			return self.dropped and self
		end
		if self.dropped then
			return self
		end
		return DropDown.OnKeyUp(self, key)
	end

	-- for the tests
	dropDown.zhTWTypeMenu = { getMenu = getMenu, menuPos = menuPos }
	return dropDown
end

return M
