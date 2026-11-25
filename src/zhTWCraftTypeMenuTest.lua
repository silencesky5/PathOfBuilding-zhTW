#@ SimpleGraphic
-- zhTW: headless test for the 類型 menu of the 製作物品 popup (Modules/ZhTWCraftTypeMenu.lua).
-- Checks that every type is in the three columns exactly once, the column contents and order,
-- that clicking a type selects it the same way the normal list does, that the menu stays inside
-- the window, and that the English interface keeps the normal drop-down.
--
-- Usage (from the runtime folder):
--   Path{space}of{space}Building.exe <full path of src\zhTWCraftTypeMenuTest.lua>
-- Results: src/zhTWCraftTypeMenuTest.log

local realSetMainObject, realExit = SetMainObject, Exit
local logFile = io.open("zhTWCraftTypeMenuTest.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end
print = log

local pass, fail = 0, 0
local function check(ok, name, detail)
	if ok then
		pass = pass + 1
	else
		fail = fail + 1
	end
	log((ok and "OK" or "FAIL") .. "\t" .. name .. (detail and ("\t" .. detail) or ""))
end

local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	ZhTWLocale.enabled = true
	newBuild()
	local itemsTab = build.itemsTab
	local typeList = build.data.itemBaseTypeList
	local cursorX, cursorY = 0, 0
	GetCursorPos = function()
		return cursorX, cursorY
	end
	local viewPort = { x = 0, y = 0, width = 1920, height = 1080 }

	local function openPopup()
		itemsTab:CraftItem()
		local popup = main.popups[1]
		return popup, popup.controls
	end

	-- Chinese interface
	local popup, controls = openPopup()
	local dd = controls.type
	check(dd.zhTWTypeMenu ~= nil, "Chinese interface: three-column menu attached")
	local menu = dd.zhTWTypeMenu.getMenu()
	check(#menu.columns == 3, "three columns", #menu.columns)
	check(menu.columns[1][1].title == "武器" and menu.columns[2][1].title == "防具" and menu.columns[3][1].title == "飾品／珠寶", "column titles")

	-- every type exactly once
	local seen = { }
	for _, cell in ipairs(menu.cells) do
		seen[cell.index] = (seen[cell.index] or 0) + 1
	end
	local missing, twice = { }, { }
	for index, key in ipairs(typeList) do
		if not seen[index] then
			table.insert(missing, key)
		elseif seen[index] > 1 then
			table.insert(twice, key)
		end
	end
	check(#missing == 0, "every type is in the menu", table.concat(missing, ", "))
	check(#twice == 0, "no type twice", table.concat(twice, ", "))
	check(#menu.cells == #typeList, "cells = types", #menu.cells .. " / " .. #typeList)

	-- column of each type
	local columnOf = { }
	for c, column in ipairs(menu.columns) do
		for _, row in ipairs(column) do
			for _, cell in ipairs(row.cells or { }) do
				columnOf[typeList[cell.index]] = c
			end
		end
	end
	for key, c in pairs(columnOf) do
		local want = 3
		if key:match("^One Handed") or key:match("^Two Handed") or key:match("^Dagger") or key:match("^Staff")
				or ({ Claw = true, Sceptre = true, Wand = true, Bow = true, Quiver = true, ["Fishing Rod"] = true })[key] then
			want = 1
		elseif key:match("^Helmet") or key:match("^Body Armour") or key:match("^Gloves") or key:match("^Boots") or key:match("^Shield") then
			want = 2
		end
		check(c == want, "column of " .. key, c)
	end

	-- dump the menu and check that nothing is left in English
	local english = 0
	for c, column in ipairs(menu.columns) do
		for _, row in ipairs(column) do
			if row.title then
				log("COLUMN", c, row.title)
			elseif row.heading then
				log("", row.heading)
			else
				local labels = { }
				for _, cell in ipairs(row.cells) do
					table.insert(labels, cell.label .. " (" .. typeList[cell.index] .. ")")
					if cell.label:find("%a%a") then
						english = english + 1
					end
				end
				log("", "", table.concat(labels, "  |  "))
			end
		end
	end
	check(english == 0, "all labels in Chinese", english)
	log("MENU SIZE", menu.width, menu.height)

	-- order in the weapon column: one-handed first, then two-handed
	local function rowIndexOf(key)
		for c, column in ipairs(menu.columns) do
			for r, row in ipairs(column) do
				for _, cell in ipairs(row.cells or { }) do
					if typeList[cell.index] == key then
						return r, c
					end
				end
			end
		end
	end
	check(rowIndexOf("Claw") < rowIndexOf("Wand") and rowIndexOf("Wand") < rowIndexOf("Bow"), "weapons: one-handed before two-handed")
	check(rowIndexOf("Helmet: Armour") < rowIndexOf("Body Armour: Armour") and rowIndexOf("Body Armour: Armour") < rowIndexOf("Gloves: Armour")
		and rowIndexOf("Gloves: Armour") < rowIndexOf("Boots: Armour") and rowIndexOf("Boots: Armour") < rowIndexOf("Shield: Armour"), "armour: 頭部 胸甲 手套 鞋子 護盾")
	check(rowIndexOf("Amulet") < rowIndexOf("Jewel") and rowIndexOf("Jewel") < rowIndexOf("Flask: Life"), "third column: 飾品, 珠寶, 藥劑")

	-- open, click a type, check what the normal list would do
	popup:Draw(viewPort)
	local bx, by = dd:GetPos()
	local bw, bh = dd:GetSize()
	cursorX, cursorY = bx + 5, by + 5
	dd:OnKeyDown("LEFTBUTTON")
	dd:OnKeyUp("LEFTBUTTON")
	check(dd.dropped, "click on the box opens the menu")
	popup:Draw(viewPort)
	local mx, my = dd.zhTWTypeMenu.menuPos(menu)
	check(mx >= 0 and my >= 0 and mx + menu.width <= 1920 and my + menu.height <= 1080, "menu inside the window", mx .. "," .. my)
	local function clickType(key)
		for _, cell in ipairs(menu.cells) do
			if typeList[cell.index] == key then
				cursorX, cursorY = mx + cell.x + 2, my + cell.y + 5
				dd:OnKeyDown("LEFTBUTTON")
				dd:OnKeyUp("LEFTBUTTON")
				return
			end
		end
	end
	clickType("Boots: Armour/Evasion")
	check(not dd.dropped, "menu closes after choosing")
	check(typeList[dd.selIndex] == "Boots: Armour/Evasion", "chosen type selected", typeList[dd.selIndex])
	check(controls.base.list == build.data.itemBaseLists["Boots: Armour/Evasion"] and controls.base.selIndex == 1, "base list follows the type")
	-- clicking a heading keeps the menu open
	cursorX, cursorY = bx + 5, by + 5
	dd:OnKeyDown("LEFTBUTTON")
	dd:OnKeyUp("LEFTBUTTON")
	check(dd.dropped, "reopened")
	local heading = menu.columns[2][2]
	cursorX, cursorY = mx + menu.columns[2].x + 2, my + heading.y + 5
	dd:OnKeyDown("LEFTBUTTON")
	dd:OnKeyUp("LEFTBUTTON")
	check(dd.dropped and typeList[dd.selIndex] == "Boots: Armour/Evasion", "click on a heading keeps the menu open")
	-- click outside closes without changing anything
	cursorX, cursorY = 5, 5
	dd:OnKeyDown("LEFTBUTTON")
	dd:OnKeyUp("LEFTBUTTON")
	check(not dd.dropped and typeList[dd.selIndex] == "Boots: Armour/Evasion", "click outside closes")
	-- Create makes an item of the chosen base
	controls.save.onClick()
	check(itemsTab.displayItem and itemsTab.displayItem.base and itemsTab.displayItem.base.type == "Boots"
		and itemsTab.displayItem.base.subType == "Armour/Evasion", "Create uses the chosen type", itemsTab.displayItem and itemsTab.displayItem.baseName)
	check(itemsTab.lastCraftTypeSel == dd.selIndex, "last type remembered")

	-- small window: the menu moves to stay inside
	popup, controls = openPopup()
	dd = controls.type
	local small = { x = 0, y = 0, width = 800, height = 600 }
	popup:Draw(small)
	bx, by = dd:GetPos()
	cursorX, cursorY = bx + 5, by + 5
	dd:OnKeyDown("LEFTBUTTON")
	dd:OnKeyUp("LEFTBUTTON")
	popup:Draw(small)
	mx, my = dd.zhTWTypeMenu.menuPos(dd.zhTWTypeMenu.getMenu())
	check(mx >= 0 and my >= 0 and mx + menu.width <= 800 and my + menu.height <= 600, "menu inside a 800x600 window", mx .. "," .. my)
	main:ClosePopup()

	-- English interface: normal drop-down
	ZhTWLocale.enabled = false
	popup, controls = openPopup()
	check(controls.type.zhTWTypeMenu == nil and rawget(controls.type, "Draw") == nil, "English interface: normal drop-down")
	main:ClosePopup()
	ZhTWLocale.enabled = true
end)
if not ok then
	fail = fail + 1
	log("ERROR\t" .. tostring(err))
end
log(string.format("RESULT pass %d fail %d", pass, fail))
logFile:close()
if not os.getenv("ZHTW_NO_EXIT") then
	realSetMainObject({ OnInit = function() realExit() end, OnFrame = function() end })
end
