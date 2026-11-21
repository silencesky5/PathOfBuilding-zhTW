-- Path of Building
--
-- Module: zhTW Boss Drops
-- 頭目掉落 window for the Chinese interface: a menu on the left of the build list screen
-- (我的 Build / 頭目掉落 / 命運卡) and a popup that lists each boss's drops, or the bosses that
-- drop an item (依物品反查). Not tied to a build.
--
-- Data: Data/zhTW/BossDrops.lua (generated from Poe-tool data.js).
-- Item pictures: downloaded from the Taiwan CDN on first view and cached in
-- <user folder>/ItemIcons/; items without a CDN path use Assets/zhTW/bossdrops.png.
-- SHOW_MENU = false hides the menu; SHOW_ICONS = false turns the pictures off.
--
local t_insert = table.insert
local t_sort = table.sort
local m_floor = math.floor
local m_min = math.min
local m_max = math.max

local M = { }

M.SHOW_MENU = true
M.SHOW_ICONS = true
M.CDN = "https://webtw.poecdn.com/image/Art/"
M.MAX_DOWNLOADS = 4

local GOLD = "^xC8A45A"
local SUBTLE = "^xA39B8C"
local TYPE_COLOR = {
	["傳奇"] = "^xAF6025", ["珠寶"] = "^xAF6025", ["藥劑"] = "^xAF6025", ["地圖"] = "^xAF6025",
	["通貨"] = "^xAA9E82", ["碎片"] = "^xAA9E82", ["任務"] = "^x4AE63A",
	["技能"] = "^x1BA29B", ["卡片"] = "^x7AC3E6", ["野獸"] = "^xD0D0D0", ["屍體"] = "^xD0D0D0",
}
local function typeColor(t)
	return TYPE_COLOR[t] or "^7"
end

local function enabled()
	return ZhTWLocale and ZhTWLocale.enabled
end

---------------------------------------------------------------------------
-- Data
---------------------------------------------------------------------------
local data
function M.data()
	if data == nil then
		local ok, result = pcall(LoadModule, "Data/zhTW/BossDrops")
		data = ok and result or false
		if data then
			-- every item once, for 依物品反查
			local items, byName = { }, { }
			for _, boss in ipairs(data.bosses) do
				boss.drops = boss.drops or { }
				for _, drop in ipairs(boss.drops) do
					local item = byName[drop.name]
					if not item then
						item = { name = drop.name, en = drop.en, type = drop.type, art = drop.art, cell = drop.cell, sources = { } }
						byName[drop.name] = item
						t_insert(items, item)
					end
					t_insert(item.sources, { boss = boss, drop = drop })
				end
			end
			local typeOrder = { ["傳奇"] = 1, ["珠寶"] = 2, ["技能"] = 3, ["通貨"] = 4, ["碎片"] = 5, ["卡片"] = 6 }
			t_sort(items, function(a, b)
				local ta, tb = typeOrder[a.type] or 9, typeOrder[b.type] or 9
				if ta ~= tb then
					return ta < tb
				end
				return a.name < b.name
			end)
			data.items = items
			data.itemByName = byName
		end
	end
	return data or nil
end

local function lower(s)
	return s and s:lower() or ""
end

-- plain substring search on the Chinese and English names
local function matches(filter, ...)
	if filter == "" then
		return true
	end
	for i = 1, select("#", ...) do
		local s = select(i, ...)
		if s and lower(s):find(filter, 1, true) then
			return true
		end
	end
	return false
end

local function onlyText(only)
	if type(only) == "table" then
		return table.concat(only, "、")
	end
	return only or "全部"
end

---------------------------------------------------------------------------
-- Item pictures
---------------------------------------------------------------------------
local icons = { } -- art -> { handle, state = "ready" | "loading" | "failed" }
local queue, active = { }, 0
local sheet

local function cacheDir()
	return (main and main.userPath or "") .. "ItemIcons/"
end
local function cacheFile(art)
	return cacheDir() .. art:gsub("[^%w]", "_") .. ".png"
end
local function fileExists(path)
	local f = io.open(path, "rb")
	if f then
		f:close()
		return true
	end
	return false
end

local function loadHandle(entry, path)
	entry.handle = NewImageHandle()
	entry.handle:Load(path, "ASYNC")
	entry.state = "ready"
end

local function pump()
	while active < M.MAX_DOWNLOADS and #queue > 0 do
		local art = table.remove(queue, 1)
		local entry = icons[art]
		active = active + 1
		launch:DownloadPage(M.CDN .. art .. ".png", function(response, errMsg)
			active = active - 1
			local body = response and response.body
			-- a PNG starts with \137PNG; anything else (an error page) is not cached
			if not errMsg and body and body:sub(2, 4) == "PNG" then
				MakeDir(cacheDir())
				local f = io.open(cacheFile(art), "wb")
				if f then
					f:write(body)
					f:close()
					loadHandle(entry, cacheFile(art))
				else
					entry.state = "failed"
				end
			else
				entry.state = "failed"
			end
			pump()
		end)
	end
end

-- Image handle for a CDN art path (nil while it downloads or when it failed)
function M.getIcon(art)
	local entry = icons[art]
	if not entry then
		entry = { state = "loading" }
		icons[art] = entry
		local path = cacheFile(art)
		if fileExists(path) then
			loadHandle(entry, path)
		elseif launch and launch.DownloadPage then
			t_insert(queue, art)
			pump()
		else
			entry.state = "failed"
		end
	end
	if entry.state == "ready" and not entry.handle:IsLoading() then
		return entry.handle
	end
end

local function getSheet()
	if sheet == nil then
		sheet = false
		if fileExists("Assets/zhTW/bossdrops.png") then
			sheet = NewImageHandle()
			sheet:Load("Assets/zhTW/bossdrops.png", "CLAMP")
		end
	end
	return sheet
end

-- Draws the picture of an item (anything with .art or .cell) fitted into a size x size square
function M.drawItemIcon(item, x, y, size)
	SetDrawColor(0.12, 0.12, 0.12)
	DrawImage(nil, x, y, size, size)
	if not M.SHOW_ICONS then
		return
	end
	SetDrawColor(1, 1, 1)
	if item.art then
		local handle = M.getIcon(item.art)
		if handle then
			local w, h = handle:ImageSize()
			if w and h and w > 0 and h > 0 then
				local scale = m_min(size / w, size / h)
				local dw, dh = m_floor(w * scale), m_floor(h * scale)
				DrawImage(handle, x + m_floor((size - dw) / 2), y + m_floor((size - dh) / 2), dw, dh)
			end
		end
	elseif item.cell then
		local img = getSheet()
		local d = M.data()
		if img and d then
			local cols, rows = d.sheetCols, d.sheetRows
			local col, row = item.cell % cols, m_floor(item.cell / cols)
			DrawImage(img, x, y, size, size, col / cols, row / rows, (col + 1) / cols, (row + 1) / rows)
		end
	end
end

---------------------------------------------------------------------------
-- Lists
---------------------------------------------------------------------------
-- Left: bosses (依頭目) or items (依物品反查)
local LeftList = newClass("ZhTWBossDropsLeftList", "ListControl")
function LeftList:ZhTWBossDropsLeftList(anchor, rect, view)
	self:ListControl(anchor, rect, 22, "VERTICAL", false, { })
	self.view = view
	self.defaultText = "^8沒有符合的結果"
	return self
end
function LeftList:GetRowValue(column, index, value)
	if self.view.mode == "BOSS" then
		return "^7" .. value.name .. "  ^8" .. #value.drops
	end
	return typeColor(value.type) .. value.name
end
function LeftList:OnSelect(index, value)
	self.view:Refresh(true)
end

-- Right: drops of a boss, or the bosses that drop an item
local DropTable = newClass("ZhTWBossDropsTable", "ListControl")
function DropTable:ZhTWBossDropsTable(anchor, rect, view)
	self:ListControl(anchor, rect, 40, "VERTICAL", false, { })
	self.view = view
	self.colLabels = true
	self.defaultText = ""
	return self
end
function DropTable:SetColumns(mode)
	if mode == "BOSS" then
		self.colList = {
			{ width = function() return m_max(self:GetSize() - 20 - 330, 200) end, label = "物品" },
			{ width = 60, label = "類型" },
			{ width = 90, label = "階段" },
			{ width = 60, label = "機率" },
			{ width = 120, label = "備註" },
		}
	else
		self.colList = {
			{ width = function() return m_max(self:GetSize() - 20 - 270, 200) end, label = "頭目" },
			{ width = 90, label = "階段" },
			{ width = 60, label = "機率" },
			{ width = 120, label = "備註" },
		}
	end
end
function DropTable:GetRowValue()
	return "" -- drawn in Draw below (two lines and a picture per row)
end
function DropTable:Draw(viewPort, noTooltip)
	self.ListControl.Draw(self, viewPort, noTooltip)
	local x, y = self:GetPos()
	local width, height = self:GetSize()
	local rowHeight = self.rowHeight
	local offset = self.controls.scrollBarV.offset
	SetViewport(x + 2, y + 20, width - 20, height - 22)
	local first = m_floor(offset / rowHeight) + 1
	local last = m_min(m_floor((offset + height) / rowHeight) + 1, #self.list)
	local cols = self.colList
	local function cell(col, lineY, text)
		local c = cols[col]
		DrawString(c._offset + 4, lineY + 12, "LEFT", 14, "VAR", text)
	end
	for index = first, last do
		local row = self.list[index]
		local lineY = rowHeight * (index - 1) - offset
		local item, drop, boss = row.item, row.drop, row.boss
		M.drawItemIcon(item, 4, lineY + 4, 32)
		SetDrawColor(1, 1, 1)
		if self.view.mode == "BOSS" then
			DrawString(42, lineY + 3, "LEFT", 16, "VAR", typeColor(item.type) .. item.name)
			local sub = item.en or ""
			if drop.variants then
				sub = sub .. (sub ~= "" and "　" or "") .. "變體：" .. table.concat(drop.variants, "、")
			end
			DrawString(42, lineY + 22, "LEFT", 12, "VAR", "^8" .. sub)
			cell(2, lineY, typeColor(item.type) .. (item.type or ""))
			cell(3, lineY, "^7" .. onlyText(drop.only))
			cell(4, lineY, "^7" .. (drop.rate or "^8—"))
			cell(5, lineY, "^8" .. (drop.note or ""))
		else
			DrawString(42, lineY + 3, "LEFT", 16, "VAR", "^7" .. boss.name)
			DrawString(42, lineY + 22, "LEFT", 12, "VAR", "^8" .. (boss.en or "") .. "　雙擊切到這隻頭目")
			cell(2, lineY, "^7" .. onlyText(drop.only))
			cell(3, lineY, "^7" .. (drop.rate or "^8—"))
			cell(4, lineY, "^8" .. (drop.note or ""))
		end
	end
	SetViewport()
end
function DropTable:AddValueTooltip(tooltip, index, row)
	tooltip:Clear()
	local item, drop = row.item, row.drop
	tooltip:AddLine(18, typeColor(item.type) .. item.name)
	if item.en then
		tooltip:AddLine(14, "^8" .. item.en)
	end
	tooltip:AddLine(14, "^7類型：" .. (item.type or ""))
	if self.view.mode ~= "BOSS" then
		tooltip:AddLine(14, "^7頭目：" .. row.boss.name)
	end
	tooltip:AddLine(14, "^7階段：" .. onlyText(drop.only))
	tooltip:AddLine(14, "^7機率：" .. (drop.rate or "未查"))
	if drop.variants then
		tooltip:AddLine(14, "^7變體：" .. table.concat(drop.variants, "、"))
	end
	if drop.note then
		tooltip:AddLine(14, "^7備註：" .. drop.note)
	end
end
function DropTable:OnSelClick(index, row, doubleClick)
	if doubleClick and self.view.mode == "ITEM" then
		self.view:ShowBoss(row.boss)
	end
end

---------------------------------------------------------------------------
-- Popup
---------------------------------------------------------------------------
local View = { }
View.__index = View

function View:Refresh(keepSelection)
	local d = M.data()
	local filter = lower(self.filter or "")
	local left = self.left
	local prevValue = left.selValue
	local list = { }
	if self.mode == "BOSS" then
		for _, boss in ipairs(d.bosses) do
			local hit = matches(filter, boss.name, boss.en)
			if not hit then
				for _, drop in ipairs(boss.drops) do
					if matches(filter, drop.name, drop.en) then
						hit = true
						break
					end
				end
			end
			if hit then
				t_insert(list, boss)
			end
		end
	else
		for _, item in ipairs(d.items) do
			if matches(filter, item.name, item.en) then
				t_insert(list, item)
			end
		end
	end
	if not keepSelection then
		left.list = list
		left.selIndex, left.selValue = nil, nil
		for i, v in ipairs(list) do
			if v == prevValue then
				left.selIndex, left.selValue = i, v
			end
		end
		if not left.selValue and list[1] then
			left.selIndex, left.selValue = 1, list[1]
		end
	end
	-- right side
	local sel = left.selValue
	local rows = { }
	if sel and self.mode == "BOSS" then
		local bossHit = matches(filter, sel.name, sel.en)
		for _, drop in ipairs(sel.drops) do
			if bossHit or matches(filter, drop.name, drop.en) then
				t_insert(rows, { item = drop, drop = drop, boss = sel })
			end
		end
	elseif sel then
		for _, src in ipairs(sel.sources) do
			t_insert(rows, { item = sel, drop = src.drop, boss = src.boss })
		end
	end
	self.table:SetColumns(self.mode)
	self.table.list = rows
	self.table.selIndex, self.table.selValue = nil, nil
	self.table.controls.scrollBarV:SetOffset(0)
	self.table.defaultText = sel and "^8沒有資料" or "^8請在左邊選擇"
end

function View:SetMode(mode)
	if self.mode ~= mode then
		self.mode = mode
		self.left.selIndex, self.left.selValue = nil, nil
		self.left.controls.scrollBarV:SetOffset(0)
		self:Refresh()
	end
end

function View:ShowBoss(boss)
	self.mode = "BOSS"
	self.filter = ""
	self.search:SetText("")
	self:Refresh()
	for i, v in ipairs(self.left.list) do
		if v == boss then
			self.left:SelectIndex(i)
		end
	end
end

-- Header above the table: boss name, note, entry fragments (or item name and drop count)
local function drawHeader(view, x, y, width)
	local sel = view.left.selValue
	if not sel then
		return
	end
	if view.mode == "BOSS" then
		local title = sel.name .. (sel.en and ("  ^8" .. sel.en) or "")
		DrawString(x, y, "LEFT", 20, "VAR", "^7" .. title)
		local tiers = { }
		for _, t in ipairs(sel.tiers or { }) do
			t_insert(tiers, type(t) == "table" and (t.title or t.name) or t)
		end
		local entry = { }
		for _, e in ipairs(sel.entry or { }) do
			t_insert(entry, e.name .. (e.count and e.count > 1 and (" ×" .. e.count) or "") .. (e.only and ("（" .. onlyText(e.only) .. "）") or ""))
		end
		local line = (#tiers > 0 and ("階段：" .. table.concat(tiers, "、") .. "　") or "") .. (#entry > 0 and ("入場：" .. table.concat(entry, "、")) or "")
		DrawString(x, y + 24, "LEFT", 14, "VAR", SUBTLE .. line)
		if sel.note then
			DrawString(x, y + 42, "LEFT", 14, "VAR", "^8" .. sel.note)
		end
	else
		M.drawItemIcon(sel, x, y, 56)
		DrawString(x + 64, y + 2, "LEFT", 20, "VAR", typeColor(sel.type) .. sel.name .. (sel.en and ("  ^8" .. sel.en) or ""))
		DrawString(x + 64, y + 28, "LEFT", 14, "VAR", SUBTLE .. (sel.type or "") .. "　共 " .. #sel.sources .. " 隻頭目會掉")
	end
end

function M.open()
	local d = M.data()
	if not d then
		main:OpenMessagePopup("頭目掉落", "找不到頭目掉落資料（Data/zhTW/BossDrops.lua）。")
		return
	end
	local width = m_min(1000, main.screenW - 40)
	local height = m_min(680, main.screenH - 40)
	local view = setmetatable({ mode = "BOSS", filter = "" }, View)
	local controls = { }
	local function modeLabel(mode, text)
		return function()
			return (view.mode == mode and GOLD or "^7") .. text
		end
	end
	controls.modeBoss = new("ButtonControl"):ButtonControl({ "TOPLEFT", nil, "TOPLEFT" }, { 12, 24, 90, 22 }, modeLabel("BOSS", "依頭目"), function()
		view:SetMode("BOSS")
	end)
	controls.modeItem = new("ButtonControl"):ButtonControl({ "LEFT", controls.modeBoss, "RIGHT" }, { 6, 0, 110, 22 }, modeLabel("ITEM", "依物品反查"), function()
		view:SetMode("ITEM")
	end)
	controls.search = new("EditControl"):EditControl({ "LEFT", controls.modeItem, "RIGHT" }, { 12, 0, width - 12 - 90 - 6 - 110 - 12 - 12, 22 }, "", nil, "%c", 100, function(buf)
		view.filter = buf
		view:Refresh()
	end, nil, nil, true)
	controls.search:SetPlaceholder("搜尋頭目或物品名稱（中文或英文）")
	local listTop, listBottom = 56, 40
	controls.left = new("ZhTWBossDropsLeftList"):ZhTWBossDropsLeftList({ "TOPLEFT", nil, "TOPLEFT" }, { 12, listTop, 220, height - listTop - listBottom }, view)
	local header = new("Control"):Control({ "TOPLEFT", nil, "TOPLEFT" }, { 244, listTop, width - 244 - 12, 62 })
	header.Draw = function(control)
		local hx, hy = control:GetPos()
		drawHeader(view, hx, hy, width - 256)
	end
	controls.header = header
	controls.table = new("ZhTWBossDropsTable"):ZhTWBossDropsTable({ "TOPLEFT", nil, "TOPLEFT" }, { 244, listTop + 66, width - 244 - 12, height - listTop - 66 - listBottom }, view)
	controls.source = new("LabelControl"):LabelControl({ "BOTTOMLEFT", nil, "BOTTOMLEFT" }, { 12, -12, 0, 14 }, "^8資料來源：Poe-tool 王掉落資料　物品圖片第一次顯示時從官方圖片伺服器下載，之後存在本機")
	controls.close = new("ButtonControl"):ButtonControl({ "BOTTOMRIGHT", nil, "BOTTOMRIGHT" }, { -12, -10, 80, 22 }, "關閉", function()
		main:ClosePopup()
	end)
	view.left, view.table, view.search = controls.left, controls.table, controls.search
	view:Refresh()
	return main:OpenPopup(width, height, "頭目掉落查詢", controls, nil, "search", "close")
end

---------------------------------------------------------------------------
-- Menu on the build list screen (Modules/BuildList.lua calls this once)
---------------------------------------------------------------------------
function M.setupListMenu(listMode)
	local controls = listMode.controls
	local function shown()
		return M.SHOW_MENU and enabled()
	end
	controls.zhTWMenuBuilds = new("ButtonControl"):ButtonControl(nil, { 10, 4, 150, 28 }, GOLD .. "我的 Build", function() end)
	controls.zhTWMenuBuilds.shown = shown
	controls.zhTWMenuBuilds.tooltipText = "目前顯示的就是 Build 清單"
	controls.zhTWMenuBoss = new("ButtonControl"):ButtonControl(nil, { 10, 38, 150, 28 }, "^7頭目掉落", function()
		M.open()
	end)
	controls.zhTWMenuBoss.shown = shown
	controls.zhTWMenuBoss.tooltipText = "查詢頭目會掉什麼，或某件物品是哪隻頭目掉的"
	controls.zhTWMenuCards = new("ButtonControl"):ButtonControl(nil, { 10, 72, 150, 28 }, "命運卡　^8即將推出", function() end)
	controls.zhTWMenuCards.shown = shown
	controls.zhTWMenuCards.enabled = false
end

return M
