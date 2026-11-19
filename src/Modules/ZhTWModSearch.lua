-- Path of Building
--
-- Module: zhTW Mod Search
-- 「新增詞綴至物品」視窗（ItemsTab:AddCustomModifierToDisplayItem）在中文介面時：
--   * 詞綴清單改成中文（ZhTWMods.translate），後面標「前綴／後綴」與詞綴等級；
--   * 多一個搜尋框：中文、英文都能搜，空白分隔的每個詞都要符合。
-- 只改清單上顯示的文字與清單內容（同一個 modList 表），加入物品時仍用英文詞綴。
--
-- Public API:
--   ZhTWModSearch.setup(itemsTab, controls, modList, sourceList) -> 新的視窗高度
--
local ipairs = ipairs
local t_insert = table.insert
local t_concat = table.concat

local M = { }

local typeNames = { Prefix = "前綴", Suffix = "後綴" }

local function zhLine(line)
	ZhTWMods = ZhTWMods or LoadModule("Modules/ZhTWMods")
	local ok, zh = pcall(ZhTWMods.translate, line)
	return ok and zh or nil
end

-- 清單上的一行：中文詞綴（翻不到的保留英文），＋前綴／後綴、等級、精髓名稱
local function makeLabel(entry)
	local mod = entry.mod
	local parts = { }
	for _, line in ipairs(mod) do
		t_insert(parts, zhLine(line) or line)
	end
	local label = t_concat(parts, " / ")
	if entry.essence and entry.essence.name then
		local name = ZhTWLocale.tr and ZhTWLocale.tr(entry.essence.name) or entry.essence.name
		label = name .. "   " .. label
	end
	local extra = { }
	local affixType = entry.affixType or mod.type
	if typeNames[affixType] then
		t_insert(extra, typeNames[affixType])
	end
	if mod.level and mod.level > 1 then
		t_insert(extra, "等級 " .. mod.level)
	end
	if #extra > 0 then
		label = label .. "  ^8（" .. t_concat(extra, "，") .. "）"
	end
	return label
end

-- 搜尋用的文字：中文、英文、詞綴名稱，全部小寫、去掉空白
local function searchText(entry)
	local mod = entry.mod
	local parts = { entry.zhTWLabel or "", entry.zhTWOrigLabel or "", mod.affix or "" }
	for _, line in ipairs(mod) do
		t_insert(parts, line)
	end
	local text = t_concat(parts, " "):gsub("%^x%x%x%x%x%x%x", ""):gsub("%^%d", ""):lower()
	return ZhTWLocale.normalizeSearch and ZhTWLocale.normalizeSearch(text) or text -- 同義詞（與→和、提高→增加…）
end

function M.setup(itemsTab, controls, modList, sourceList)
	local all = { }
	local query = ""

	-- 換上中文標籤，記住完整清單
	local function capture()
		wipeTable(all)
		for _, entry in ipairs(modList) do
			if not entry.zhTWLabel then
				entry.zhTWOrigLabel = entry.label
				entry.zhTWLabel = makeLabel(entry)
				entry.label = entry.zhTWLabel
				entry.zhTWSearch = searchText(entry)
			end
			t_insert(all, entry)
		end
	end

	local function matches(entry)
		for word in query:lower():gmatch("%S+") do
			word = ZhTWLocale.normalizeSearch and ZhTWLocale.normalizeSearch(word) or word
			if not entry.zhTWSearch:find(word, 1, true) then
				return false
			end
		end
		return true
	end

	-- 依搜尋字過濾（保持目前的排序）
	local function applyFilter()
		local selected = modList[controls.modSelect.selIndex]
		wipeTable(modList)
		for _, entry in ipairs(all) do
			if matches(entry) then
				t_insert(modList, entry)
			end
		end
		controls.modSelect.selIndex = 1
		for index, entry in ipairs(modList) do
			if entry == selected then
				controls.modSelect.selIndex = index
				break
			end
		end
		if controls.modSelect.UpdateSearch then
			controls.modSelect:UpdateSearch()
		end
	end

	-- 換來源、換排序後清單會重建／重排：重新換標籤再套用搜尋
	local function wrap(control)
		if not control or not control.selFunc then
			return
		end
		local orig = control.selFunc
		control.selFunc = function(...)
			if #all > 0 and #modList < #all then
				-- 排序要看完整清單
				local selected = modList[controls.modSelect.selIndex]
				wipeTable(modList)
				for _, entry in ipairs(all) do
					t_insert(modList, entry)
				end
				for index, entry in ipairs(modList) do
					if entry == selected then
						controls.modSelect.selIndex = index
					end
				end
			end
			orig(...)
			capture()
			applyFilter()
		end
	end
	wrap(controls.source)
	wrap(controls.sort)
	capture()

	local isCustom = function()
		local source = sourceList[controls.source.selIndex]
		return source and source.sourceId == "CUSTOM"
	end
	controls.zhTWSearchLabel = new("LabelControl"):LabelControl({ "TOPRIGHT", nil, "TOPLEFT" }, { 95, 70, 0, 16 }, "^7搜尋：")
	controls.zhTWSearchLabel.shown = function()
		return not isCustom()
	end
	controls.zhTWSearch = new("EditControl"):EditControl({ "TOPLEFT", nil, "TOPLEFT" }, { 100, 70, 400, 18 }, "", "中文或英文，例如：魔力、抗性、spell", nil, nil, function(buf)
		query = buf or ""
		applyFilter()
	end)
	controls.zhTWSearch.shown = function()
		return not isCustom()
	end
	controls.zhTWSearchCount = new("LabelControl"):LabelControl({ "TOPLEFT", nil, "TOPLEFT" }, { 510, 71, 0, 16 }, function()
		return "^8" .. #modList .. " / " .. #all .. " 條"
	end)
	controls.zhTWSearchCount.shown = function()
		return not isCustom()
	end
	-- 按鈕往下移一排
	for _, name in ipairs({ "save", "close" }) do
		if controls[name] then
			controls[name].y = 100
		end
	end
	return 130
end

return M
