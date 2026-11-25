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
-- A cached picture counts only when it is a whole PNG; a cut-off file (an older download
-- could leave just the 8-byte header) is deleted so it downloads again
local function fileExists(path)
	local f = io.open(path, "rb")
	if not f then
		return false
	end
	local head = f:read(8)
	local size = f:seek("end")
	f:close()
	if head == "\137PNG\r\n\26\n" and size and size > 100 then
		return true
	end
	os.remove(path)
	return false
end

local function loadHandle(entry, path)
	entry.handle = NewImageHandle()
	entry.handle:Load(path, "ASYNC")
	entry.state = "ready"
end

-- Downloads one picture straight to a file inside the sub script: a PNG holds zero bytes, and
-- launch:DownloadPage hands the body back as a string, which can arrive cut short.
local DOWNLOAD_SCRIPT = [[
	local url, path, connectionProtocol, proxyURL, noSSL = ...
	local ok, result = pcall(function()
		local curl = require("lcurl.safe")
		local easy = curl.easy()
		local chunks = { }
		easy:setopt_url(url)
		easy:setopt(curl.OPT_FOLLOWLOCATION, 1)
		if connectionProtocol then
			easy:setopt(curl.OPT_IPRESOLVE, connectionProtocol)
		end
		if proxyURL then
			easy:setopt(curl.OPT_PROXY, proxyURL)
		end
		if noSSL then
			easy:setopt(curl.OPT_SSL_VERIFYPEER, 0)
			easy:setopt(curl.OPT_SSL_VERIFYHOST, 0)
		end
		easy:setopt_writefunction(function(data)
			chunks[#chunks + 1] = data
			return true
		end)
		local _, err = easy:perform()
		local code = easy:getinfo(curl.INFO_RESPONSE_CODE)
		easy:close()
		if err then
			return "error: " .. tostring(err:msg())
		end
		local body = table.concat(chunks)
		if code ~= 200 or body:sub(2, 4) ~= "PNG" then
			return "bad response " .. tostring(code)
		end
		local f = io.open(path, "wb")
		if not f then
			return "cannot write " .. path
		end
		f:write(body)
		f:close()
		return "ok"
	end)
	return ok and result or ("error: " .. tostring(result))
]]

local function startDownload(art, done)
	if not LaunchSubScript then
		return false
	end
	MakeDir(cacheDir())
	-- a few art paths contain spaces or apostrophes ("Ahn Artifact", "Veteran'sAwarenessJewel")
	local url = M.CDN .. art:gsub("[^%w/_%-%.]", function(c) return string.format("%%%02X", c:byte()) end) .. ".png"
	local id = LaunchSubScript(DOWNLOAD_SCRIPT, "", "", url, cacheFile(art),
		launch.connectionProtocol, launch.proxyURL, launch.noSSL or false)
	if not id then
		return false
	end
	launch.subScripts[id] = {
		type = "DOWNLOAD", -- also called (with nil) when the sub script fails
		callback = function(result)
			done(result == "ok")
		end,
	}
	return true
end

local function pump()
	while active < M.MAX_DOWNLOADS and #queue > 0 do
		local art = table.remove(queue, 1)
		local entry = icons[art]
		active = active + 1
		local started = startDownload(art, function(ok)
			active = active - 1
			if ok then
				loadHandle(entry, cacheFile(art))
			else
				entry.state = "failed"
				entry.tries = (entry.tries or 0) + 1
				entry.failedAt = GetTime()
			end
			pump()
		end)
		if not started then
			active = active - 1
			entry.state = "failed"
		end
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
		elseif launch and launch.subScripts then
			t_insert(queue, art)
			pump()
		else
			entry.state = "failed"
		end
	end
	-- try a failed picture again after 15 s, three times at most (busy server, dropped connection)
	if entry.state == "failed" and entry.failedAt and (entry.tries or 0) < 3 and GetTime() - entry.failedAt > 15000 then
		entry.state = "loading"
		entry.failedAt = nil
		t_insert(queue, art)
		pump()
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
	self:ListControl(anchor, rect, 18, "VERTICAL", false, { })
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
			if drop.variants then
				DrawString(42, lineY + 22, "LEFT", 12, "VAR", "^8" .. #drop.variants .. " 種變體（滑鼠移上去看）")
			end
			cell(2, lineY, typeColor(item.type) .. (item.type or ""))
			cell(3, lineY, "^7" .. onlyText(drop.only))
			cell(4, lineY, "^7" .. (drop.rate or "^8—"))
			cell(5, lineY, "^8" .. (drop.note or ""))
		else
			DrawString(42, lineY + 3, "LEFT", 16, "VAR", "^7" .. boss.name)
			DrawString(42, lineY + 22, "LEFT", 12, "VAR", "^8雙擊切到這隻頭目")
			cell(2, lineY, "^7" .. onlyText(drop.only))
			cell(3, lineY, "^7" .. (drop.rate or "^8—"))
			cell(4, lineY, "^8" .. (drop.note or ""))
		end
	end
	SetViewport()
end
-- Full item text for a unique from PoB's unique list (main.uniqueDB.byTitle, by English name):
-- base, defences or weapon damage, requirements, implicit and explicit modifiers.
-- PoB's own item tooltip needs a loaded build, so this draws a short version of it.
-- Returns false when the item is not in the list (not a unique, or a name PoB does not know).
local function addUniqueLines(tooltip, en)
	local db = main and main.uniqueDB
	local item = en and db and db.byTitle and db.byTitle[en:lower()]
	if not item or not item.base then
		return false
	end
	tooltip:AddLine(16, "^x7F7F7F" .. (item.baseName or ""):gsub(" %(.+%)", ""))
	-- base values only: the item's own ranges show in the modifier lines below
	local stats = { }
	local w, ar = item.base.weapon, item.base.armour
	if w then
		if (w.PhysicalMax or 0) > 0 then
			t_insert(stats, string.format("基礎物理傷害：^7%d-%d", w.PhysicalMin, w.PhysicalMax))
		end
		if w.CritChanceBase then
			t_insert(stats, string.format("基礎暴擊率：^7%.2f%%", w.CritChanceBase))
		end
		if w.AttackRateBase then
			t_insert(stats, string.format("基礎每秒攻擊次數：^7%.2f", w.AttackRateBase))
		end
	end
	if ar then
		for _, at in ipairs({ { "Armour", "護甲" }, { "Evasion", "閃避值" }, { "EnergyShield", "能量護盾" }, { "Ward", "保護" } }) do
			local v = ar[at[1] .. "BaseMax"]
			if (v or 0) > 0 then
				t_insert(stats, string.format("基礎%s：^7%d", at[2], v))
			end
		end
		if (ar.BlockChance or 0) > 0 then
			t_insert(stats, string.format("格擋率：^7%d%%", ar.BlockChance))
		end
	end
	for _, line in ipairs(stats) do
		tooltip:AddLine(16, "^x7F7F7F" .. line)
	end
	local r = item.requirements or { }
	local req = { }
	if (r.level or 0) > 0 then
		t_insert(req, "等級 ^7" .. r.level)
	end
	for _, st in ipairs({ { "str", "力量" }, { "dex", "敏捷" }, { "int", "智慧" } }) do
		local v = r[st[1] .. "Mod"] or r[st[1]] or 0
		if v > 0 then
			t_insert(req, st[2] .. " ^7" .. v)
		end
	end
	if #req > 0 then
		tooltip:AddLine(16, "^x7F7F7F需求 " .. table.concat(req, "^x7F7F7F，"))
	end
	for _, modList in ipairs({ item.enchantModLines, item.implicitModLines, item.explicitModLines }) do
		if modList and modList[1] then
			tooltip:AddSeparator(10)
			for _, modLine in ipairs(modList) do
				if item:GetModLineVariantCount(modLine) > 0 then
					local line = itemLib.formatModLine(modLine, true)
					if line then
						tooltip:AddLine(16, line, "VAR", modLine)
					end
				end
			end
		end
	end
	if item.variantList and #item.variantList > 1 then
		tooltip:AddLine(14, "^8（顯示最新版本，共 " .. #item.variantList .. " 種變體）")
	end
	return true
end

function DropTable:AddValueTooltip(tooltip, index, row)
	tooltip:Clear()
	local item, drop = row.item, row.drop
	tooltip:AddLine(20, typeColor(item.type) .. item.name)
	local full = item.type == "傳奇" and addUniqueLines(tooltip, item.en)
	tooltip:AddSeparator(10)
	local info = { }
	if not full then
		t_insert(info, "類型：^7" .. (item.type or ""))
	end
	if self.view.mode ~= "BOSS" then
		t_insert(info, "頭目：^7" .. row.boss.name)
	end
	t_insert(info, "階段：^7" .. onlyText(drop.only))
	t_insert(info, "機率：^7" .. (drop.rate or "未查"))
	if drop.variants then
		t_insert(info, "可掉變體：^7" .. table.concat(drop.variants, "、"))
	end
	if drop.note then
		t_insert(info, "備註：^7" .. drop.note)
	end
	for _, line in ipairs(info) do
		tooltip:AddLine(14, SUBTLE .. line)
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

-- Small grey box with text, for the tier tags beside the boss name; returns its width
local function drawTag(x, y, text)
	local w = DrawStringWidth(14, "VAR", text) + 12
	SetDrawColor(0.22, 0.2, 0.17)
	DrawImage(nil, x, y, w, 18)
	SetDrawColor(1, 1, 1)
	DrawString(x + 6, y + 2, "LEFT", 14, "VAR", "^xD8CCB0" .. text)
	return w
end

-- Header above the table, for a boss:
--   恐慌化身  [一般] [終極恐慌化身]
--   入場  一般：敬畏之迴響　　終極：敬畏碎片 ×4      (one line per tier when it does not fit)
--   note
-- for an item: picture, name, type and number of bosses
local HEADER_HEIGHT = 84
local function drawHeader(view, x, y, width)
	local sel = view.left.selValue
	if not sel then
		return
	end
	if view.mode == "BOSS" then
		DrawString(x, y, "LEFT", 20, "VAR", "^7" .. sel.name)
		local tx = x + DrawStringWidth(20, "VAR", sel.name) + 12
		for _, t in ipairs(sel.tiers or { }) do
			tx = tx + drawTag(tx, y + 2, type(t) == "table" and (t.title or t.name) or t) + 6
		end
		-- entry items grouped by tier, in the order they first appear
		local groups, order = { }, { }
		for _, e in ipairs(sel.entry or { }) do
			local key = e.only and onlyText(e.only) or ""
			if not groups[key] then
				groups[key] = { }
				t_insert(order, key)
			end
			t_insert(groups[key], e.name .. (e.count and e.count > 1 and (" ×" .. e.count) or ""))
		end
		local parts = { }
		for _, key in ipairs(order) do
			t_insert(parts, (key ~= "" and (SUBTLE .. key .. "：") or "") .. "^7" .. table.concat(groups[key], "、"))
		end
		local lineY = y + 30
		if #parts > 0 then
			local labelW = DrawStringWidth(14, "VAR", "入場　")
			DrawString(x, lineY, "LEFT", 14, "VAR", GOLD .. "入場")
			local oneLine = table.concat(parts, "　　")
			if DrawStringWidth(14, "VAR", oneLine) <= width - labelW then
				DrawString(x + labelW, lineY, "LEFT", 14, "VAR", oneLine)
				lineY = lineY + 18
			else
				for _, part in ipairs(parts) do
					DrawString(x + labelW, lineY, "LEFT", 14, "VAR", part)
					lineY = lineY + 18
				end
			end
		end
		if sel.note then
			DrawString(x, lineY + 2, "LEFT", 14, "VAR", "^8" .. sel.note)
		end
	else
		M.drawItemIcon(sel, x, y, 56)
		DrawString(x + 64, y + 2, "LEFT", 20, "VAR", typeColor(sel.type) .. sel.name)
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
	local header = new("Control"):Control({ "TOPLEFT", nil, "TOPLEFT" }, { 244, listTop, width - 244 - 12, HEADER_HEIGHT })
	header.Draw = function(control)
		local hx, hy = control:GetPos()
		drawHeader(view, hx, hy, width - 256)
	end
	controls.header = header
	controls.table = new("ZhTWBossDropsTable"):ZhTWBossDropsTable({ "TOPLEFT", nil, "TOPLEFT" }, { 244, listTop + HEADER_HEIGHT + 4, width - 244 - 12, height - listTop - HEADER_HEIGHT - 4 - listBottom }, view)
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
