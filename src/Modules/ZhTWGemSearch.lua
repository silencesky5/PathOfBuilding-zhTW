-- zhTW: 技能頁的倉庫寶石搜尋（只在中文介面）
--
--   * 每列寶石在「數量」左邊多一顆「複製名稱」，複製台服中文寶石名稱。
--   * 技能頁右下角「倉庫搜尋字串」：把目前技能組所有啟用中的寶石（啟用的插槽群組、啟用的寶石，
--     不含物品內建技能）組成可以貼到遊戲倉庫搜尋欄的正規表示式。
--     名稱用共同的前綴／後綴合併，例如 費爾羅(猛虎幻獸|惡狼幻獸)、(快速施放|秘能波動)輔助，讓字數變短。
--   * 遊戲搜尋欄最多 250 個字，超過時分成多段，每段一顆「複製」按鈕。
--   * 「品質至少」：加上品質條件（遊戲物品文字為「品質: +20%」）。用空白分開的兩組引號 = 兩個條件都要符合。
--
-- 寶石中文名稱來自 Data/zhTW/Gems.lua（台服客戶端匯出）。
local pairs = pairs
local ipairs = ipairs
local t_insert = table.insert
local t_concat = table.concat
local s_format = string.format

local ZhTWGemSearch = { }

ZhTWGemSearch.MAX_LENGTH = 250 -- 遊戲搜尋欄的字數上限
ZhTWGemSearch.MAX_CHUNKS = 4 -- 畫面上最多列出幾段

local function enabled()
	return ZhTWLocale and ZhTWLocale.enabled and true or false
end
ZhTWGemSearch.enabled = enabled

---------------------------------------------------------------------------
-- 寶石名稱：英文 → 台服中文

local zhByEnglish
local function better(a, b)
	-- 兩個中文名稱對到同一個英文時，挑一般的那個（不是 [DNT] 之類）
	if not a then
		return b
	end
	local aOdd, bOdd = a:find("[%[%]]") and 1 or 0, b:find("[%[%]]") and 1 or 0
	if aOdd ~= bOdd then
		return aOdd < bOdd and a or b
	end
	if #a ~= #b then
		return #a < #b and a or b
	end
	return a < b and a or b
end
local function loadNames()
	if zhByEnglish then
		return zhByEnglish
	end
	zhByEnglish = { }
	local ok, gems = pcall(LoadModule, "Data/zhTW/Gems")
	for zh, en in pairs(ok and gems or { }) do
		if type(en) == "string" then
			zhByEnglish[en] = better(zhByEnglish[en], zh)
		elseif type(en) == "table" then
			for _, e in ipairs(en) do
				local name = type(e) == "table" and e.name or e
				if type(name) == "string" then
					zhByEnglish[name] = better(zhByEnglish[name], zh)
				end
			end
		end
	end
	return zhByEnglish
end

-- 寶石的台服名稱（gemData 是 data.gems 的一筆）；找不到時回傳 nil
function ZhTWGemSearch.gemDataName(gemData)
	if not gemData then
		return nil
	end
	local names = loadNames()
	local candidates = { } -- 不能用 ipairs({ a, b, c })：a 是 nil 時會整個跳過
	t_insert(candidates, gemData.baseTypeName)
	t_insert(candidates, gemData.name)
	if gemData.name then
		t_insert(candidates, gemData.name .. " Support")
	end
	for _, en in ipairs(candidates) do
		if names[en] then
			return names[en]
		end
	end
	return nil
end

-- 技能頁一顆寶石的中文名稱（找不到台服名稱時退回畫面上的翻譯）
function ZhTWGemSearch.gemName(gemInstance)
	if not gemInstance then
		return nil
	end
	local name = ZhTWGemSearch.gemDataName(gemInstance.gemData)
	if name then
		return name
	end
	local en = gemInstance.gemData and (gemInstance.gemData.baseTypeName or gemInstance.gemData.name) or gemInstance.nameSpec
	if not en or en == "" then
		return nil
	end
	return ZhTWLocale and ZhTWLocale.translate(en) or en
end

---------------------------------------------------------------------------
-- 正規表示式

local function chars(text)
	local list = { }
	for c in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		t_insert(list, c)
	end
	return list
end

-- 字數（中文一個字算一個）
function ZhTWGemSearch.length(text)
	local n = 0
	for _ in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
		n = n + 1
	end
	return n
end
local length = ZhTWGemSearch.length

local special = { }
for c in ("\\^$.|?*+()[]{}"):gmatch(".") do
	special[c] = true
end
local function escape(name)
	return (name:gsub(".", function(c)
		return special[c] and "\\" .. c or c
	end))
end

-- names：已跳脫的名稱（不重複）。回傳最上層的選項清單，每項是一段正規表示式。
local function compress(names, depth)
	local items = { }
	for _, name in ipairs(names) do
		t_insert(items, { text = name, chars = chars(name) })
	end
	local out = { }
	local remaining = items
	while #remaining > 1 and depth < 3 do
		-- 找省最多字的共同前綴或後綴：n 個名稱共用 k 個字，省 (n-1)*k 字，但多 2 個括號
		local count = { }
		for _, item in ipairs(remaining) do
			local cs = item.chars
			local seen = { }
			for k = 1, #cs - 1 do -- 名稱本身不能等於前後綴（括號裡不能是空的）
				local prefix = "P" .. t_concat(cs, "", 1, k)
				local suffix = "S" .. t_concat(cs, "", #cs - k + 1, #cs)
				for _, key in ipairs({ prefix, suffix }) do
					if not seen[key] then
						seen[key] = true
						count[key] = (count[key] or 0) + 1
					end
				end
			end
		end
		local bestKey, bestSave = nil, 0
		for key, n in pairs(count) do
			if n > 1 then
				local save = (n - 1) * length(key:sub(2)) - 2
				if save > bestSave or (save == bestSave and bestKey and key < bestKey) then
					bestKey, bestSave = key, save
				end
			end
		end
		if not bestKey then
			break
		end
		local isPrefix, affix = bestKey:sub(1, 1) == "P", bestKey:sub(2)
		local k = length(affix)
		local rests, keep = { }, { }
		for _, item in ipairs(remaining) do
			local cs = item.chars
			local head = t_concat(cs, "", 1, k)
			local tail = t_concat(cs, "", #cs - k + 1, #cs)
			if #cs > k and ((isPrefix and head == affix) or (not isPrefix and tail == affix)) then
				t_insert(rests, isPrefix and t_concat(cs, "", k + 1, #cs) or t_concat(cs, "", 1, #cs - k))
			else
				t_insert(keep, item)
			end
		end
		table.sort(rests)
		local inner = t_concat(compress(rests, depth + 1), "|")
		t_insert(out, isPrefix and (affix .. "(" .. inner .. ")") or ("(" .. inner .. ")" .. affix))
		remaining = keep
	end
	for _, item in ipairs(remaining) do
		t_insert(out, item.text)
	end
	return out
end

-- 品質 >= minQuality 的條件（0 或空白 = 不加）
function ZhTWGemSearch.qualityTerm(minQuality)
	minQuality = math.floor(tonumber(minQuality) or 0)
	if minQuality <= 0 then
		return nil
	end
	if minQuality > 99 then
		minQuality = 99
	end
	local number
	if minQuality < 10 then
		number = s_format("([%d-9]|\\d\\d)", minQuality)
	else
		local tens, units = math.floor(minQuality / 10), minQuality % 10
		local first = units == 0 and s_format("%d\\d", tens) or s_format("%d[%d-9]", tens, units)
		if tens == 9 then
			number = "(" .. first .. ")"
		elseif tens == 8 then
			number = "(" .. first .. "|9\\d)"
		else
			number = s_format("(%s|[%d-9]\\d)", first, tens + 1)
		end
	end
	return "\"品質: \\+" .. number .. "%\""
end

-- names：中文寶石名稱清單。回傳 { 段1, 段2, … }，每段不超過 maxLength 字
function ZhTWGemSearch.buildStrings(names, minQuality, maxLength)
	maxLength = maxLength or ZhTWGemSearch.MAX_LENGTH
	local unique, seen = { }, { }
	for _, name in ipairs(names) do
		if name ~= "" and not seen[name] then
			seen[name] = true
			t_insert(unique, escape(name))
		end
	end
	table.sort(unique)
	if #unique == 0 then
		return { }
	end
	local units = compress(unique, 0)
	local quality = ZhTWGemSearch.qualityTerm(minQuality)
	local extra = 2 + (quality and (1 + length(quality)) or 0) -- 前後引號＋空白＋品質條件
	local chunks, current, currentLen = { }, { }, 0
	local function flush()
		if #current > 0 then
			local text = "\"" .. t_concat(current, "|") .. "\""
			if quality then
				text = text .. " " .. quality
			end
			t_insert(chunks, text)
		end
		current, currentLen = { }, 0
	end
	for _, unit in ipairs(units) do
		local len = length(unit)
		local add = (#current > 0 and 1 or 0) + len
		if #current > 0 and currentLen + add + extra > maxLength then
			flush()
			add = len
		end
		t_insert(current, unit)
		currentLen = currentLen + add
	end
	flush()
	return chunks
end

-- 目前技能組中啟用的寶石（啟用的插槽群組、啟用的寶石、不含物品內建技能）的中文名稱
function ZhTWGemSearch.usedGemNames(skillsTab)
	local names = { }
	for _, socketGroup in ipairs(skillsTab.socketGroupList or { }) do
		if socketGroup.enabled ~= false and not socketGroup.source then
			for _, gemInstance in ipairs(socketGroup.gemList or { }) do
				if gemInstance.enabled ~= false and gemInstance.gemData then
					local name = ZhTWGemSearch.gemName(gemInstance)
					if name then
						t_insert(names, name)
					end
				end
			end
		end
	end
	return names
end

---------------------------------------------------------------------------
-- 技能頁的控制項

-- 每列寶石：「數量」左邊的「複製名稱」（SkillsTab:CreateGemSlot 結尾呼叫）
local COPY_W, COPY_GAP = 70, 8
function ZhTWGemSearch.setupGemSlot(skillsTab, index, slot)
	local button = new("ButtonControl"):ButtonControl({ "LEFT", slot.enabled, "RIGHT" }, { COPY_GAP, 0, COPY_W, 20 }, "複製名稱", function()
		local name = ZhTWGemSearch.gemName(skillsTab.displayGroup and skillsTab.displayGroup.gemList[index])
		if name then
			Copy(name)
			ZhTWGemSearch.lastCopied = name
		end
	end)
	button.shown = function()
		local gemInstance = enabled() and skillsTab.displayGroup and skillsTab.displayGroup.gemList[index]
		return gemInstance and gemInstance.gemData and true or false
	end
	button.tooltipFunc = function(tooltip)
		tooltip:Clear()
		local name = ZhTWGemSearch.gemName(skillsTab.displayGroup and skillsTab.displayGroup.gemList[index])
		if name then
			tooltip:AddLine(16, "^7複製寶石名稱：" .. name)
		end
	end
	slot.zhTWCopyName = button
	skillsTab.controls["gemSlot" .. index .. "ZhTWCopyName"] = button
	-- 數量往右移，讓出按鈕的位置（標題「數量」跟著數量欄）
	local origX = slot.count.x
	slot.count.x = function(self)
		if enabled() then
			return COPY_GAP + COPY_W + 8
		end
		return type(origX) == "function" and origX(self) or origX
	end
end

-- 右下角「倉庫搜尋字串」區（SkillsTab 建構結尾呼叫）
local BOX_W, ROW_H = 480, 24
function ZhTWGemSearch.setupSkillsTab(skillsTab)
	local controls = skillsTab.controls
	local state = { minQuality = 0, chunks = { }, count = 0, key = nil }
	skillsTab.zhTWGemSearch = state

	local function refresh()
		local names = ZhTWGemSearch.usedGemNames(skillsTab)
		local key = t_concat(names, "\n") .. "\0" .. tostring(state.minQuality)
		if key ~= state.key then
			state.key = key
			local unique = { }
			for _, name in ipairs(names) do
				unique[name] = true
			end
			state.count = 0
			for _ in pairs(unique) do
				state.count = state.count + 1
			end
			state.chunks = ZhTWGemSearch.buildStrings(names, state.minQuality)
		end
	end
	local function rows()
		return math.max(1, math.min(#state.chunks, ZhTWGemSearch.MAX_CHUNKS))
	end

	local box = new("SectionControl"):SectionControl({ "BOTTOMRIGHT", skillsTab, "BOTTOMRIGHT" }, { -12, -28, BOX_W, function()
		refresh()
		return 52 + rows() * ROW_H + (#state.chunks > ZhTWGemSearch.MAX_CHUNKS and 20 or 0)
	end }, "倉庫搜尋字串（已啟用的寶石）")
	box.shown = enabled
	controls.zhTWGemSearchBox = box

	local qualityLabel = new("LabelControl"):LabelControl({ "TOPLEFT", box, "TOPLEFT" }, { 10, 18, 0, 16 }, "^7品質至少:")
	controls.zhTWGemSearchQualityLabel = qualityLabel
	local quality = new("EditControl"):EditControl({ "LEFT", qualityLabel, "RIGHT" }, { 6, 0, 50, 20 }, "0", nil, "%D", 2, function(buf)
		state.minQuality = tonumber(buf) or 0
	end)
	quality.tooltipFunc = function(tooltip)
		tooltip:Clear()
		tooltip:AddLine(16, "^7只標記品質大於或等於這個數字的寶石。0 = 不限品質。")
	end
	controls.zhTWGemSearchQuality = quality
	local info = new("LabelControl"):LabelControl({ "LEFT", quality, "RIGHT" }, { 10, 0, 0, 16 }, function()
		refresh()
		if state.count == 0 then
			return "^8沒有啟用中的寶石"
		end
		return s_format("^8共 %d 種寶石，%d 段（每段最多 %d 字）", state.count, #state.chunks, ZhTWGemSearch.MAX_LENGTH)
	end)
	controls.zhTWGemSearchInfo = info

	local previews = { } -- 字串 -> 截短後的預覽（每個畫面都要畫，先存起來）
	for i = 1, ZhTWGemSearch.MAX_CHUNKS do
		local button = new("ButtonControl"):ButtonControl({ "TOPLEFT", box, "TOPLEFT" }, { 10, 46 + (i - 1) * ROW_H, 60, 20 }, function()
			return #state.chunks > 1 and s_format("複製 %d", i) or "複製"
		end, function()
			local text = state.chunks[i]
			if text then
				Copy(text)
				ZhTWGemSearch.lastCopied = text
			end
		end)
		button.shown = function()
			refresh()
			return state.chunks[i] ~= nil
		end
		button.tooltipFunc = function(tooltip)
		tooltip:Clear()
			local text = state.chunks[i]
			if text then
				tooltip:AddLine(16, s_format("^7%d 字：", length(text)))
				-- 長字串分行顯示
				local cs, line = chars(text), { }
				for _, c in ipairs(cs) do
					t_insert(line, c)
					if #line >= 40 then
						tooltip:AddLine(16, "^7" .. t_concat(line))
						line = { }
					end
				end
				if #line > 0 then
					tooltip:AddLine(16, "^7" .. t_concat(line))
				end
				tooltip:AddLine(16, "^8貼到遊戲倉庫或背包的搜尋欄（Ctrl+F）。")
			end
		end
		controls["zhTWGemSearchCopy" .. i] = button
		local preview = new("LabelControl"):LabelControl({ "LEFT", button, "RIGHT" }, { 8, 0, 0, 16 }, function()
			local text = state.chunks[i]
			if not text then
				return ""
			end
			if previews[text] then
				return previews[text]
			end
			local maxW = BOX_W - 100
			local shown = text
			if DrawStringWidth(16, "VAR", shown) > maxW then
				local cs = chars(text)
				local n = #cs
				repeat
					n = n - 1
					shown = t_concat(cs, "", 1, n) .. "..."
				until n <= 1 or DrawStringWidth(16, "VAR", shown) <= maxW
			end
			previews[text] = "^7" .. shown
			return previews[text]
		end)
		controls["zhTWGemSearchText" .. i] = preview
	end
	local more = new("LabelControl"):LabelControl({ "TOPLEFT", box, "TOPLEFT" }, { 10, 50 + ZhTWGemSearch.MAX_CHUNKS * ROW_H, 0, 16 }, function()
		return s_format("^1還有 %d 段沒有列出，請提高品質條件或停用部分寶石。", #state.chunks - ZhTWGemSearch.MAX_CHUNKS)
	end)
	more.shown = function()
		return enabled() and #state.chunks > ZhTWGemSearch.MAX_CHUNKS
	end
	controls.zhTWGemSearchMore = more
	local empty = new("LabelControl"):LabelControl({ "TOPLEFT", box, "TOPLEFT" }, { 10, 48, 0, 16 }, "^8（目前沒有寶石）")
	empty.shown = function()
		return enabled() and #state.chunks == 0
	end
	controls.zhTWGemSearchEmpty = empty
end

return ZhTWGemSearch
