-- Path of Building
--
-- Class: zhTW Craft Tab
-- 製作 tab of the Chinese interface: craft an item with currency, the same rules as the crafting
-- site (Modules/ZhTWCraftEngine.lua), and add it to the build.
--
-- Left: base (class, base, item level, or brought in from an equipped item) and the mods with
-- their tiers. Middle: the item card (PoB's own item tooltip, so it shows the Chinese text and
-- what equipping it would change). Right: currencies, essences, undo, "加入 Build" and a log.
--
local t_insert = table.insert
local t_remove = table.remove
local t_sort = table.sort
local m_max = math.max
local m_min = math.min
local m_floor = math.floor

local ZhTWCraftTabClass = newClass("ZhTWCraftTab", "ControlHost", "Control")

-- list of the guild share shelf
local ShareListClass = newClass("ZhTWShareListControl", "ListControl")
function ShareListClass:ZhTWShareListControl(anchor, rect, tab)
	self:ListControl(anchor, rect, 18, "VERTICAL", false, { })
	self.tab = tab
	return self
end
function ShareListClass:GetRowValue(column, index, share)
	return share.label
end
function ShareListClass:OnSelect(index, share)
	self.tab:SelectShare(share)
end

-- mod pool of the base (詞綴池): read only
local PoolListClass = newClass("ZhTWPoolListControl", "ListControl")
function PoolListClass:ZhTWPoolListControl(anchor, rect)
	self:ListControl(anchor, rect, 16, "VERTICAL", false, { })
	return self
end
function PoolListClass:GetRowValue(column, index, row)
	return row.label
end

local LEFT_W = 300
local CARD_X = 320
local CARD_W = 440
local RIGHT_X = CARD_X + CARD_W + 20
local TITLE = "^xE6DFD0"
local SUBTLE = "^xA39B8C"
local RARITY_COLOR = { [0] = "^xC8C8C8", "^x8888FF", "^xFFFF77" }
local POOL_X = RIGHT_X + 270 -- 詞綴池 column, when the window is wide enough
local POOL_MIN_W = 320

-- currency icons (Assets/zhTW/currency.png, made by Export/zhTWCraftIcons.py from the site's
-- icons): the ten currencies, then essence (11) and resonator (12). Off with the other icons
-- (SHOW_ICONS in Modules/ZhTWLayout.lua).
local currencySheet
local function currencyIcons()
	if currencySheet == nil then
		currencySheet = false
		local f = io.open("Assets/zhTW/currency.png", "rb")
		if f then
			f:close()
			currencySheet = NewImageHandle()
			currencySheet:Load("Assets/zhTW/currency.png", "CLAMP")
		end
	end
	if not (ZhTWLayout and ZhTWLayout.hasIcons()) then
		return nil
	end
	return currencySheet or nil
end
local function iconButton(button, index)
	local baseDraw = button.Draw
	button.Draw = function(self, viewPort, noTooltip)
		local sheet = currencyIcons()
		if not sheet then
			return baseDraw(self, viewPort, noTooltip)
		end
		local label = self:GetProperty("label")
		local origLabel = self.label
		self.label = ""
		baseDraw(self, viewPort, noTooltip)
		self.label = origLabel
		local x, y = self:GetPos()
		local width, height = self:GetSize()
		local size = height - 2
		local textW = DrawStringWidth(16, "VAR", label)
		local startX = m_floor(x + (width - size - 4 - textW) / 2)
		local col, row = (index - 1) % 6, m_floor((index - 1) / 6)
		SetDrawColor(1, 1, 1, self:IsEnabled() and 1 or 0.35)
		DrawImage(sheet, startX, y + 1, size, size, col / 6, row / 2, (col + 1) / 6, (row + 1) / 2)
		if self:IsEnabled() then
			SetDrawColor(1, 1, 1)
		else
			SetDrawColor(0.33, 0.33, 0.33)
		end
		DrawString(startX + size + 4, y + m_floor((height - 16) / 2), "LEFT", 16, "VAR", label)
		SetDrawColor(1, 1, 1)
	end
end

-- engine and data are shared by every build (loaded once, on first use)
local CE, Engine
local function engine()
	if not Engine then
		CE = LoadModule("Modules/ZhTWCraftEngine")
		Engine = CE.create(LoadModule("Data/zhTW/CraftData"))
	end
	return Engine
end

local function panel(x, y, w, h)
	SetDrawColor(0.29, 0.27, 0.25)
	DrawImage(nil, x, y, w, h)
	SetDrawColor(0.07, 0.065, 0.06)
	DrawImage(nil, x + 1, y + 1, w - 2, h - 2)
	SetDrawColor(1, 1, 1)
end

function ZhTWCraftTabClass:ZhTWCraftTab(build)
	self:ControlHost()
	self:Control()
	self.build = build
	self.history = { } -- earlier items, for 上一步
	self.used = { } -- currency -> count
	self.log = { }
	self.message = nil
	self.lv = 86
	self.built = false
	return self
end

-- Controls are made on first draw (the engine and its data load then, not with every build)
function ZhTWCraftTabClass:Build()
	if self.built then
		return
	end
	self.built = true
	local E = engine()
	local controls = self.controls

	-- classes, grouped like the game (weapons, armour, jewellery…), then by name
	local classList = { }
	for code, c in pairs(E.data.classes) do
		t_insert(classList, { code = code, label = c.zh or code, group = c.group or "" })
	end
	t_sort(classList, function(a, b)
		if a.group ~= b.group then return a.group < b.group end
		return a.label < b.label
	end)
	self.classList = classList

	controls.classLabel = new("LabelControl"):LabelControl({ "TOPLEFT", self, "TOPLEFT" }, { 14, 44, 0, 16 }, "^7類別:")
	controls.class = new("DropDownControl"):DropDownControl({ "TOPLEFT", self, "TOPLEFT" }, { 84, 42, 216, 20 }, classList, function(index, value)
		self:SelectClass(value.code)
	end)
	controls.baseLabel = new("LabelControl"):LabelControl({ "TOPLEFT", self, "TOPLEFT" }, { 14, 70, 0, 16 }, "^7底材:")
	controls.base = new("DropDownControl"):DropDownControl({ "TOPLEFT", self, "TOPLEFT" }, { 84, 68, 216, 20 }, { }, function(index, value)
		self:SelectBase(value.b)
	end)
	controls.base.enableDroppedWidth = true
	controls.lvLabel = new("LabelControl"):LabelControl({ "TOPLEFT", self, "TOPLEFT" }, { 14, 96, 0, 16 }, "^7物品等級:")
	controls.lv = new("EditControl"):EditControl({ "TOPLEFT", self, "TOPLEFT" }, { 84, 94, 60, 20 }, tostring(self.lv), nil, "%D", 3, function(buf)
		local lv = tonumber(buf)
		if lv and lv >= 1 and lv <= 100 then
			self.lv = lv
			if self.item then
				self.item.lv = lv
				self:Changed()
			end
		end
	end)
	controls.reset = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { 154, 94, 146, 20 }, "重新開始（普通）", function()
		self:Reset()
	end)
	controls.reset.tooltipText = "把目前的物品變回沒有詞綴的普通物品（底材、物品等級不變）。"
	controls.fromLabel = new("LabelControl"):LabelControl({ "TOPLEFT", self, "TOPLEFT" }, { 14, 122, 0, 16 }, "^7帶入:")
	controls.from = new("DropDownControl"):DropDownControl({ "TOPLEFT", self, "TOPLEFT" }, { 84, 120, 216, 20 }, { }, function(index, value)
		if value.item then
			self:BringIn(value.item)
		end
	end)
	controls.from.enableDroppedWidth = true
	controls.from.tooltipText = "從當前裝備帶入底材和物品等級（詞綴不會帶入，會從普通物品開始）。"

	-- currencies: two columns
	for i, c in ipairs(CE.CURRENCIES) do
		local col, row = (i - 1) % 2, m_floor((i - 1) / 2)
		local button = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X + col * 128, 44 + row * 28, 122, 24 }, c.zh, function()
			self:Use(c.k)
		end)
		button.enabled = function()
			return self:CanUse(c.k)
		end
		button.tooltipFunc = function(tooltip)
			tooltip:Clear()
			tooltip:AddLine(16, "^7" .. c.zh .. "  " .. SUBTLE .. c.en)
			tooltip:AddLine(14, "^7" .. c.desc)
			local err = self:CheckError(c.k)
			if err then
				tooltip:AddLine(14, colorCodes.NEGATIVE .. err)
			end
		end
		controls["cur_" .. c.k] = button
		iconButton(button, i)
	end
	local essY = 44 + 5 * 28 + 10
	controls.essLabel = new("LabelControl"):LabelControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X, essY + 2, 0, 16 }, "^7精髓:")
	controls.essence = new("DropDownControl"):DropDownControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X + 44, essY, 154, 20 }, { }, function() end)
	controls.essence.enableDroppedWidth = true
	controls.essence.tooltipFunc = function(tooltip, mode, index, value)
		tooltip:Clear()
		if value and value.e then
			local e = value.e
			tooltip:AddLine(16, "^7" .. (e.nz or e.n))
			local mi = E.essenceMod(self.item or E.make(self.b, self.lv), e)
			if mi then
				for _, line in ipairs(E.modRange(mi, "zh")) do
					tooltip:AddLine(14, "^x8888FF" .. line)
				end
			end
			tooltip:AddLine(14, SUBTLE .. ((e.lv or 0) >= 5 and "普通 → 稀有，或重鑄稀有物品" or "普通 → 稀有（不能用在稀有物品）"))
		end
	end
	controls.useEssence = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X + 202, essY, 48, 20 }, "使用", function()
		local v = controls.essence:GetSelValue()
		if v and v.e then
			self:Use(v.e.k)
		end
	end)
	controls.useEssence.enabled = function()
		local v = controls.essence:GetSelValue()
		return v and v.e and self:CanUse(v.e.k) or false
	end
	controls.useEssence.tooltipFunc = function(tooltip)
		tooltip:Clear()
		local v = controls.essence:GetSelValue()
		local err = v and v.e and self:CheckError(v.e.k)
		if err then
			tooltip:AddLine(14, colorCodes.NEGATIVE .. err)
		end
	end

	-- fossils in a resonator (1-4; the resonator size follows the number of fossils)
	local fossY = essY + 30
	local fossilList = { { label = "（無）" } }
	for _, f in ipairs(E.fossils) do
		if not f.why then
			t_insert(fossilList, { label = f.nz or f.n, f = f })
		end
	end
	controls.fossLabel = new("LabelControl"):LabelControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X, fossY + 2, 0, 16 }, "^7化石:")
	self.fossilControls = { }
	for i = 1, m_min(4, E.MAX_FOSSILS) do
		local col, row = (i - 1) % 2, m_floor((i - 1) / 2)
		local dd = new("DropDownControl"):DropDownControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X + 44 + col * 104, fossY + row * 24, 100, 20 }, fossilList, function()
			self.checkCache = { }
		end)
		dd.enableDroppedWidth = true
		dd.tooltipFunc = function(tooltip, mode, index, value)
			tooltip:Clear()
			if value and value.f then
				tooltip:AddLine(16, "^7" .. (value.f.nz or value.f.n) .. "  " .. SUBTLE .. value.f.n)
				for _, line in ipairs(value.f.desc or { }) do
					tooltip:AddLine(14, "^x8888FF" .. line)
				end
			end
		end
		controls["fossil" .. i] = dd
		self.fossilControls[i] = dd
	end
	controls.useFossils = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X + 44, fossY + 50, 206, 20 }, "使用鑄新儀", function()
		local k = self:ResoKey()
		if k then
			self:Use(k)
		end
	end)
	iconButton(controls.useFossils, 12)
	controls.useFossils.enabled = function()
		local k = self:ResoKey()
		return k and self:CanUse(k) or false
	end
	controls.useFossils.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip:AddLine(14, "^7普通物品：點金鑄新儀（變成稀有）；稀有物品：混沌鑄新儀（重鑄）。放幾顆化石就是幾孔的鑄新儀。")
		local k = self:ResoKey()
		local err = k and self:CheckError(k)
		if err then
			tooltip:AddLine(14, colorCodes.NEGATIVE .. err)
		elseif not k then
			tooltip:AddLine(14, SUBTLE .. "先選至少一顆化石。")
		end
	end

	local actY = fossY + 82
	controls.undo = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X, actY, 122, 24 }, "上一步", function()
		self:Undo()
	end)
	controls.undo.enabled = function()
		return #self.history > 0
	end
	controls.addToBuild = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X + 128, actY, 122, 24 }, "加入 Build", function()
		self:AddToBuild()
	end)
	controls.addToBuild.tooltipText = "把這件物品加到裝備頁的「當前裝備」清單（標 [尚未使用]），可以再拖到欄位上比較。"

	-- guild share shelf of the crafting site (Modules/ZhTWGuild.lua)
	local gY = actY + 34
	controls.shelf = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X, gY, 122, 24 }, function()
		return self.shelfView and "回到物品卡" or "公會分享架"
	end, function()
		self.shelfView = not self.shelfView
		if self.shelfView and not self.shares then
			self:RefreshShelf()
		end
	end)
	controls.shelf.tooltipText = "製裝網站的公會分享架：瀏覽、搜尋，複製到製作頁或 Build（不用登入）。"
	controls.share = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X + 128, gY, 122, 24 }, "分享到公會", function()
		self:ShareCurrent()
	end)
	controls.share.enabled = function()
		return ZhTWGuild and ZhTWGuild.token and self.item and #self.item.mods > 0 and not self.busy or false
	end
	controls.share.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip:AddLine(14, "^7把目前製作的物品分享到公會分享架（網站和 POB 都看得到）。")
		if not (ZhTWGuild and ZhTWGuild.token) then
			tooltip:AddLine(14, colorCodes.NEGATIVE .. "要先登入公會（Discord）。")
		elseif not (self.item and #self.item.mods > 0) then
			tooltip:AddLine(14, colorCodes.NEGATIVE .. "沒有詞綴的物品不能分享。")
		end
	end
	controls.noteLabel = new("LabelControl"):LabelControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X, gY + 32, 0, 16 }, "^7備註:")
	controls.shareNote = new("EditControl"):EditControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X + 44, gY + 30, 206, 20 }, "", "分享時附上的說明（最多 50 字）", nil, 50)
	controls.guildLogin = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { RIGHT_X, gY + 56, 122, 22 }, function()
		return (ZhTWGuild and ZhTWGuild.token) and "登出公會" or "登入公會"
	end, function()
		self:GuildLogin()
	end)
	controls.guildLogin.enabled = function()
		return ZhTWGuild ~= nil and not self.busy
	end
	controls.guildLogin.tooltipText = "用 Discord 登入（限 RKSA 公會成員）才能分享；瀏覽和複製不用登入。\n登出只會清掉這台電腦 POB 裡的登入，網站不受影響。"

	-- the shelf itself, in the middle panel instead of the item card
	local shelfShown = function()
		return self.shelfView
	end
	controls.shelfSearch = new("EditControl"):EditControl({ "TOPLEFT", self, "TOPLEFT" }, { CARD_X + 10, 34, 200, 20 }, "", "搜尋（底材／詞綴／分享者）", nil, 40, function()
		self:FilterShelf()
	end)
	controls.shelfSearch.shown = shelfShown
	controls.shelfMine = new("DropDownControl"):DropDownControl({ "TOPLEFT", self, "TOPLEFT" }, { CARD_X + 216, 34, 100, 20 }, { { label = "全部", mine = false }, { label = "我的分享", mine = true } }, function()
		self:FilterShelf()
	end)
	controls.shelfMine.shown = shelfShown
	controls.shelfRefresh = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { CARD_X + 322, 34, 108, 20 }, "重新整理", function()
		self:RefreshShelf()
	end)
	controls.shelfRefresh.shown = shelfShown
	controls.shelfRefresh.enabled = function()
		return not self.busy
	end
	controls.shelfList = new("ZhTWShareListControl"):ZhTWShareListControl({ "TOPLEFT", self, "TOPLEFT" }, { CARD_X + 10, 60, CARD_W - 20, 200 }, self)
	controls.shelfList.shown = shelfShown
	controls.copyToCraft = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { CARD_X + 10, 266, 140, 22 }, "複製到製作頁", function()
		self:CopyShare(false)
	end)
	controls.copyToCraft.shown = shelfShown
	controls.copyToCraft.enabled = function()
		return self.shareItem ~= nil
	end
	controls.copyToBuild = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { CARD_X + 156, 266, 140, 22 }, "複製到 Build", function()
		self:CopyShare(true)
	end)
	controls.copyToBuild.shown = shelfShown
	controls.copyToBuild.enabled = function()
		return self.shareItem ~= nil
	end

	-- 詞綴池: own column when wide enough, otherwise a view of the middle panel
	local function poolWide()
		return (self.width or 0) - POOL_X - 10 >= POOL_MIN_W
	end
	self.poolWide = poolWide
	controls.poolList = new("ZhTWPoolListControl"):ZhTWPoolListControl({ "TOPLEFT", self, "TOPLEFT" }, { POOL_X, 34, 300, 300 })
	controls.poolList.x = function()
		return poolWide() and POOL_X or (CARD_X + 10)
	end
	controls.poolList.width = function()
		return poolWide() and ((self.width or 0) - POOL_X - 10) or (CARD_W - 20)
	end
	controls.poolList.height = function()
		return (self.height or 400) - 44
	end
	controls.poolList.shown = function()
		return poolWide() or (self.poolView and not self.shelfView)
	end
	controls.poolToggle = new("ButtonControl"):ButtonControl({ "TOPLEFT", self, "TOPLEFT" }, { CARD_X + CARD_W - 96, 12, 90, 18 }, function()
		return self.poolView and "物品卡" or "詞綴池"
	end, function()
		self.poolView = not self.poolView
	end)
	controls.poolToggle.shown = function()
		return not poolWide() and not self.shelfView
	end
	controls.poolToggle.tooltipText = "視窗不夠寬時，詞綴池和物品卡共用中間這一格。"

	self.actY = gY + 60
	self:SelectClass(self:DefaultClass())
end

function ZhTWCraftTabClass:DefaultClass()
	for _, c in ipairs(self.classList) do
		if c.code == "Helmet" then
			return c.code
		end
	end
	return self.classList[1].code
end

-- bases of a class, highest level first
function ZhTWCraftTabClass:SelectClass(code, baseIndex)
	local E = engine()
	self.class = code
	local list = { }
	for _, b in ipairs(E.bases) do
		if b.c == code then
			t_insert(list, { label = (b.nz or b.n) .. "^x8C8478  (" .. b.lv .. ")", b = b.i, lv = b.lv })
		end
	end
	t_sort(list, function(a, b)
		if a.lv ~= b.lv then return a.lv > b.lv end
		return a.b < b.b
	end)
	self.controls.base:SetList(list)
	self.controls.class:SelByValue(code, "code")
	local pick = 1
	for i, v in ipairs(list) do
		if v.b == baseIndex then
			pick = i
		end
	end
	if list[pick] then
		self.controls.base:SetSel(pick, true)
		self:SelectBase(list[pick].b)
	end
	-- essences that have a guaranteed mod for this class
	local ess = { }
	for _, e in ipairs(E.essences) do
		if e.m[code] ~= nil then
			t_insert(ess, { label = e.nz or e.n, e = e })
		end
	end
	if #ess == 0 then
		t_insert(ess, { label = "（這類物品沒有精髓）" })
	end
	self.controls.essence:SetList(ess)
	self.controls.essence:SetSel(1, true)
end

function ZhTWCraftTabClass:SelectBase(b)
	self.b = b
	self:Reset()
end

function ZhTWCraftTabClass:Reset()
	local E = engine()
	if self.item then
		t_insert(self.history, { item = self.item, used = self:CopyUsed() })
	end
	self.item = E.make(self.b, self.lv)
	self:AddLog("^7新的普通物品：" .. E.baseName(self.b, "zh") .. "（物品等級 " .. self.lv .. "）")
	self:Changed()
end

function ZhTWCraftTabClass:BringIn(pobItem)
	local E = engine()
	local name = pobItem.baseName
	local base
	for _, b in ipairs(E.bases) do
		if b.n == name then
			base = b
		end
	end
	if not base then
		self.message = colorCodes.NEGATIVE .. "製作資料裡找不到這個底材：" .. tostring(name)
		return
	end
	if pobItem.itemLevel and pobItem.itemLevel > 0 then
		self.lv = m_min(100, pobItem.itemLevel)
		self.controls.lv:SetText(tostring(self.lv))
	end
	self:SelectClass(base.c, base.i)
	self.message = "^7已帶入底材與物品等級，詞綴從普通物品開始。"
end

function ZhTWCraftTabClass:CopyUsed()
	local c = { }
	for k, v in pairs(self.used) do
		c[k] = v
	end
	return c
end

function ZhTWCraftTabClass:Changed()
	self.checkCache = { }
	self.pobItem = nil
	self.version = (self.version or 0) + 1
end

function ZhTWCraftTabClass:CheckError(k)
	if not self.item then
		return "還沒有物品。"
	end
	self.checkCache = self.checkCache or { }
	local cached = self.checkCache[k]
	if cached == nil then
		cached = engine().check(self.item, k) or false
		self.checkCache[k] = cached
	end
	return cached or nil
end

function ZhTWCraftTabClass:CanUse(k)
	return self:CheckError(k) == nil
end

function ZhTWCraftTabClass:Use(k)
	local E = engine()
	local r = E.apply(self.item, k)
	if not r.ok then
		self.message = colorCodes.NEGATIVE .. r.err
		return
	end
	t_insert(self.history, { item = self.item, used = self:CopyUsed() })
	if #self.history > 200 then
		t_remove(self.history, 1)
	end
	self.item = r.item
	self.used[k] = (self.used[k] or 0) + 1
	self.message = nil
	self:AddLog("^7使用 " .. self:CurrencyName(k))
	self:Changed()
end

-- "reso:" key for the chosen fossils, nil when none
function ZhTWCraftTabClass:ResoKey()
	local ids = { }
	for _, dd in ipairs(self.fossilControls or { }) do
		local v = dd:GetSelValue()
		if v and v.f then
			t_insert(ids, v.f.id)
		end
	end
	if #ids == 0 then
		return nil
	end
	return engine().resoKey(ids)
end

function ZhTWCraftTabClass:CurrencyName(k)
	local E = engine()
	if k:sub(1, 5) == "reso:" then
		local names = { }
		for id in k:sub(6):gmatch("[^|]+") do
			local f = E.fosById[id]
			t_insert(names, f and (f.nz or f.n) or id)
		end
		return "鑄新儀（" .. table.concat(names, "＋") .. "）"
	end
	if CE.CUR[k] then
		return CE.CUR[k].zh
	end
	local e = E.essByKey[k]
	return e and (e.nz or e.n) or k
end

function ZhTWCraftTabClass:Undo()
	local last = t_remove(self.history)
	if not last then
		return
	end
	self.item = last.item
	self.used = last.used
	self:AddLog(SUBTLE .. "上一步")
	self:Changed()
end

function ZhTWCraftTabClass:AddLog(text)
	t_insert(self.log, 1, text)
	if #self.log > 40 then
		t_remove(self.log)
	end
end

-- ── guild share shelf ──

function ZhTWCraftTabClass:GuildLogin()
	if ZhTWGuild.token then
		ZhTWGuild.logout()
		self.message = "^7已登出公會（只有這台電腦的 POB）。"
		return
	end
	self.busy = true
	self.message = "^7已開啟瀏覽器，請在 Discord 頁面按「授權」（3 分鐘內）。"
	ZhTWGuild.login(function(ok, text)
		self.busy = false
		self.message = (ok and "^7" or colorCodes.NEGATIVE) .. text
		if ok and self.shelfView then
			self:RefreshShelf()
		end
	end)
end

function ZhTWCraftTabClass:RefreshShelf()
	self.busy = true
	self.shelfStatus = "讀取中…"
	ZhTWGuild.fetchShares(function(ok, data)
		self.busy = false
		if not ok or type(data) ~= "table" then
			self.shelfStatus = colorCodes.NEGATIVE .. tostring(data)
			return
		end
		local E = engine()
		self.shares = { }
		for _, sh in ipairs(data.shares or { }) do
			local it = type(sh.item) == "table" and E.fromStored(sh.item) or nil
			local base = it and E.baseName(it.b, "zh") or "（這個資料版本讀不到）"
			local color = it and RARITY_COLOR[it.r] or "^x8C8478"
			local search = { base, sh.sharerName or "", sh.note or "" }
			if it then
				t_insert(search, E.bases[it.b].n)
				for _, x in ipairs(it.mods) do
					for _, line in ipairs(E.render(x.m, x.v, "zh")) do
						t_insert(search, line)
					end
				end
			end
			t_insert(self.shares, {
				share = sh, item = it,
				label = color .. base .. SUBTLE .. "　" .. tostring(sh.sharerName or "?") .. ((sh.note and sh.note ~= "") and ("　「" .. sh.note .. "」") or ""),
				search = table.concat(search, "\n"):lower(),
				mine = ZhTWGuild.me and sh.sharerId == ZhTWGuild.me.id,
			})
		end
		local limits = data.limits or { }
		self.shelfStatus = "共 " .. #self.shares .. " 件" .. (limits.total and (" / 上限 " .. limits.total) or "") ..
			(ZhTWGuild.me and ("　已登入：" .. tostring(ZhTWGuild.me.name)) or "　（未登入：只能瀏覽、複製）")
		self:FilterShelf()
	end)
end

function ZhTWCraftTabClass:FilterShelf()
	local list = { }
	local text = (self.controls.shelfSearch.buf or ""):lower()
	local v = self.controls.shelfMine:GetSelValue()
	local mineOnly = v and v.mine
	for _, sh in ipairs(self.shares or { }) do
		if (not mineOnly or sh.mine) and (text == "" or sh.search:find(text, 1, true)) then
			t_insert(list, sh)
		end
	end
	self.controls.shelfList.list = list
	self.controls.shelfList.selIndex = nil
	self.controls.shelfList.selValue = nil
	self.shareItem, self.sharePob, self.shareSel = nil, nil, nil
end

function ZhTWCraftTabClass:SelectShare(sh)
	self.shareSel = sh
	self.shareItem = sh and sh.item or nil
	self.sharePob = nil
	if self.shareItem then
		local ok, item = pcall(function()
			return new("Item"):Item(engine().toPobText(self.shareItem, "Crafted Item"))
		end)
		self.sharePob = ok and item and item.base and item or nil
	end
end

function ZhTWCraftTabClass:CopyShare(toBuild)
	local sh, it = self.shareSel, self.shareItem
	if not it then
		return
	end
	local E = engine()
	if toBuild then
		local raw = E.toPobText(it, "Crafted Item")
		local item = new("Item"):Item(raw)
		local itemsTab = self.build.itemsTab
		itemsTab:AddItem(item, true)
		itemsTab:PopulateSlots()
		itemsTab:AddUndoState()
		self.build.buildFlag = true
		self.message = "^7已複製到裝備頁的「當前裝備」（[尚未使用]）。"
	else
		local copy = E.clone(it)
		self.lv = copy.lv
		self.controls.lv:SetText(tostring(copy.lv))
		self:SelectClass(E.bases[copy.b].c, copy.b)
		self.item = copy
		self.used = { }
		self:AddLog("^7從公會分享架複製：" .. E.baseName(copy.b, "zh"))
		self:Changed()
		self.shelfView = false
		self.message = "^7已複製到製作頁，可以繼續製作。"
	end
	if sh and sh.share and sh.share.id then
		ZhTWGuild.countCopy(sh.share.id)
	end
end

function ZhTWCraftTabClass:ShareCurrent()
	local E = engine()
	local item = self.item
	if not item then
		return
	end
	local lines = { }
	for _, x in ipairs(item.mods) do
		for _, line in ipairs(E.render(x.m, x.v, "zh")) do
			t_insert(lines, line)
		end
	end
	self.busy = true
	self.message = "^7分享中…"
	ZhTWGuild.share(E.toStored(item), self.controls.shareNote.buf or "", E.data.version, { base = E.baseName(item.b, "zh"), lines = lines }, function(ok, data)
		self.busy = false
		if ok then
			self.message = "^7已分享到公會分享架。"
			self:AddLog("^7分享到公會")
			self.controls.shareNote:SetText("")
			if self.shares then
				self:RefreshShelf()
			end
		else
			self.message = colorCodes.NEGATIVE .. tostring(data)
		end
	end)
end

-- PoB item for the card and for 加入 Build
function ZhTWCraftTabClass:PobItem()
	if not self.pobItem and self.item then
		-- the name must be ASCII: PoB turns every other character of item text into "?"
		-- ("Crafted Item" is shown as 製作物品 through Data/zhTW/UI.lua)
		local raw = engine().toPobText(self.item, "Crafted Item")
		local ok, item = pcall(function()
			return new("Item"):Item(raw)
		end)
		if ok and item and item.base then
			self.pobItem = item
		else
			self.pobItem = false
		end
	end
	return self.pobItem or nil
end

function ZhTWCraftTabClass:AddToBuild()
	local item = self:PobItem()
	if not item then
		self.message = colorCodes.NEGATIVE .. "PoB 讀不懂這件物品，無法加入。"
		return
	end
	local itemsTab = self.build.itemsTab
	local copy = new("Item"):Item(item.raw)
	itemsTab:AddItem(copy, true)
	itemsTab:PopulateSlots()
	itemsTab:AddUndoState()
	self.build.buildFlag = true
	self.message = "^7已加入裝備頁的「當前裝備」（[尚未使用]），可以拖到欄位上比較。"
	self:AddLog("^7加入 Build")
end

-- equipped items for 帶入
function ZhTWCraftTabClass:RefreshFromList()
	local itemsTab = self.build.itemsTab
	local rev = self.build.outputRevision
	if self.fromRevision == rev then
		return
	end
	self.fromRevision = rev
	local list = { { label = "從當前裝備帶入…" } }
	for _, slot in ipairs(itemsTab.orderedSlots or { }) do
		if not slot.nodeId and slot.selItemId and slot.selItemId > 0 then
			local item = itemsTab.items[slot.selItemId]
			if item then
				t_insert(list, { label = "^7" .. slot.label .. "：" .. (item.name or ""), item = item })
			end
		end
	end
	self.controls.from:SetList(list)
	self.controls.from:SetSel(1, true)
end

-- rows of the mod pool for the current base and item level (a blank item, like the site)
function ZhTWCraftTabClass:RefreshPool()
	if self.poolVersion == self.version then
		return
	end
	self.poolVersion = self.version
	local E = engine()
	local list = { }
	if self.item then
		local view = E.poolView(self.item.b, self.item.lv)
		local have = { }
		for _, x in ipairs(self.item.mods) do
			have[E.mods[x.m].ty] = true
		end
		for _, pre in ipairs({ true, false }) do
			local n = 0
			for _, r in ipairs(view.rows) do
				if r.pre == pre then n = n + 1 end
			end
			t_insert(list, { label = TITLE .. (pre and "前綴" or "後綴") .. SUBTLE .. "（" .. n .. " 種，機率＝同一邊的權重比例）" })
			for _, r in ipairs(view.rows) do
				if r.pre == pre then
					local text = E.modRange(r.m, "zh")[1] or ""
					local mark = have[E.mods[r.m].ty] and "^x7FD87F" or "^x8888FF"
					t_insert(list, { label = string.format("^7%5.1f%%  " .. SUBTLE .. "T%d/%d  ", r.pct, r.tier, r.tiers) .. mark .. text })
				end
			end
		end
	end
	self.controls.poolList.list = list
end

function ZhTWCraftTabClass:Draw(viewPort, inputEvents)
	self.x = viewPort.x
	self.y = viewPort.y
	self.width = viewPort.width
	self.height = viewPort.height
	self:Build()
	self:RefreshFromList()

	self:RefreshPool()
	self:ProcessControlsInput(inputEvents, viewPort)
	main:DrawBackground(viewPort)

	local E = engine()
	local x0, y0 = viewPort.x, viewPort.y
	local h = viewPort.height
	-- left: title and mod list
	DrawString(x0 + 14, y0 + 12, "LEFT", 18, "VAR BOLD", TITLE .. "製作裝備")
	DrawString(x0 + 104, y0 + 15, "LEFT", 14, "VAR", SUBTLE .. "規則與製裝網站相同（PoE1 " .. E.data.version .. "）")
	local listY = y0 + 154
	panel(x0 + 10, listY, LEFT_W - 10, h - (listY - y0) - 10)
	local item = self.item
	if item then
		local c = E.counts(item)
		local max = E.maxSide(item)
		DrawString(x0 + 18, listY + 6, "LEFT", 16, "VAR BOLD", RARITY_COLOR[item.r] .. CE.RARITY_ZH[item.r] .. "物品" ..
			SUBTLE .. "　前綴 " .. c.p .. "/" .. max .. "　後綴 " .. c.s .. "/" .. max)
		local y = listY + 30
		local maxY = y0 + h - 30
		-- prefixes first, then suffixes
		local order = { }
		for _, x in ipairs(item.mods) do
			t_insert(order, x)
		end
		t_sort(order, function(a, b)
			local pa, pb = E.mods[a.m].pre, E.mods[b.m].pre
			if pa ~= pb then return pa end
			return false
		end)
		for _, x in ipairs(order) do
			if y > maxY then
				break
			end
			DrawString(x0 + 18, y, "LEFT", 14, "VAR", SUBTLE .. E.tagLabel(item.b, x.m))
			for _, line in ipairs(E.render(x.m, x.v, "zh")) do
				DrawString(x0 + 90, y, "LEFT", 14, "VAR", "^x8888FF" .. line)
				y = y + 16
			end
			y = y + 4
		end
		if #item.mods == 0 then
			DrawString(x0 + 18, y, "LEFT", 14, "VAR", SUBTLE .. "沒有詞綴。用右邊的通貨開始製作。")
		end
	end

	-- middle: item card, or the guild share shelf
	panel(x0 + CARD_X, y0 + 10, CARD_W, h - 20)
	local pobItem
	if self.shelfView then
		DrawString(x0 + CARD_X + 10, y0 + 14, "LEFT", 14, "VAR", TITLE .. "公會分享架" .. SUBTLE .. "　" .. (self.shelfStatus or ""))
		if self.sharePob then
			self.shareTooltip = self.shareTooltip or new("Tooltip"):Tooltip()
			local tooltip = self.shareTooltip
			tooltip.maxWidth = CARD_W - 8
			if tooltip:CheckForUpdate(self.sharePob, IsKeyDown("SHIFT"), self.build.outputRevision) then
				self.build.itemsTab:AddItemTooltip(tooltip, self.sharePob, nil, true)
			end
			SetDrawColor(1, 1, 1)
			tooltip:Draw(x0 + CARD_X + 4, y0 + 294, nil, nil, { x = x0 + CARD_X + 4, y = y0 + 294, width = CARD_W - 8, height = h - 304 })
		elseif self.shareSel then
			DrawString(x0 + CARD_X + 10, y0 + 298, "LEFT", 14, "VAR", colorCodes.NEGATIVE .. "這件分享的資料版本和 POB 不同，讀不到。")
		else
			DrawString(x0 + CARD_X + 10, y0 + 298, "LEFT", 14, "VAR", SUBTLE .. "點清單裡的一件，這裡會顯示物品卡。")
		end
	elseif self.poolView and not self.poolWide() then
		DrawString(x0 + CARD_X + 10, y0 + 14, "LEFT", 14, "VAR", TITLE .. "詞綴池" .. SUBTLE .. "　綠色＝物品上已有同類詞綴")
	else
		DrawString(x0 + CARD_X + 10, y0 + 16, "LEFT", 14, "VAR", TITLE .. "物品卡")
		pobItem = self:PobItem()
	end
	if pobItem then
		self.tooltip = self.tooltip or new("Tooltip"):Tooltip()
		local tooltip = self.tooltip
		tooltip.maxWidth = CARD_W - 8
		if tooltip:CheckForUpdate(pobItem, self.version, IsKeyDown("SHIFT"), self.build.outputRevision) then
			self.build.itemsTab:AddItemTooltip(tooltip, pobItem, nil, true)
		end
		SetDrawColor(1, 1, 1)
		tooltip:Draw(x0 + CARD_X + 4, y0 + 36, nil, nil, { x = x0 + CARD_X + 4, y = y0 + 36, width = CARD_W - 8, height = h - 50 })
	elseif item and not self.shelfView then
		DrawString(x0 + CARD_X + 10, y0 + 40, "LEFT", 14, "VAR", colorCodes.NEGATIVE .. "PoB 讀不懂這件物品。")
	end
	-- login state next to the login button
	if ZhTWGuild then
		local who = ZhTWGuild.token and (ZhTWGuild.me and ("已登入：" .. tostring(ZhTWGuild.me.name)) or "已登入") or "未登入"
		DrawString(x0 + RIGHT_X + 128, y0 + self.actY - 2, "LEFT", 14, "VAR", SUBTLE .. who)
	end

	-- 詞綴池 column
	if self.poolWide() then
		local pw = self.width - POOL_X - 10
		panel(x0 + POOL_X - 10, y0 + 10, pw + 20, h - 20)
		DrawString(x0 + POOL_X, y0 + 14, "LEFT", 14, "VAR", TITLE .. "詞綴池" .. SUBTLE .. "　這個底材＋物品等級會出現的詞綴；綠色＝物品上已有同類")
	end

	-- right: headings, used currency, message and log
	DrawString(x0 + RIGHT_X, y0 + 16, "LEFT", 16, "VAR BOLD", TITLE .. "通貨")
	local ry = y0 + self.actY + 36
	local usedText = { }
	for _, c in ipairs(CE.CURRENCIES) do
		if self.used[c.k] then
			t_insert(usedText, c.zh .. "×" .. self.used[c.k])
		end
	end
	for k, n in pairs(self.used) do
		if not CE.CUR[k] then
			t_insert(usedText, self:CurrencyName(k) .. "×" .. n)
		end
	end
	DrawString(x0 + RIGHT_X, ry, "LEFT", 14, "VAR", SUBTLE .. "已用：" .. (#usedText > 0 and table.concat(usedText, "、") or "（無）"))
	ry = ry + 22
	if self.message then
		DrawString(x0 + RIGHT_X, ry, "LEFT", 14, "VAR", self.message)
		ry = ry + 22
	end
	DrawString(x0 + RIGHT_X, ry, "LEFT", 14, "VAR BOLD", TITLE .. "紀錄")
	ry = ry + 20
	for _, line in ipairs(self.log) do
		if ry > y0 + h - 20 then
			break
		end
		DrawString(x0 + RIGHT_X, ry, "LEFT", 14, "VAR", line)
		ry = ry + 16
	end

	self:DrawControls(viewPort)
end
