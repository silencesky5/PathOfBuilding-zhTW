-- Path of Building
--
-- Module: zhTW Item Text
-- Converts item text copied in the Taiwan client (Ctrl+C, or Ctrl+Alt+C with "{ 前綴 ... }"
-- headers and value ranges) to the English in-game copy format that Classes/Item.lua parses.
-- Uses the same Chinese -> English tables as the Taiwan import (Modules/ZhTWConverter.lua).
--
-- Public API:
--   ZhTWItemText.isChinese(text)   -- true for Chinese item text (has a 稀有度 line)
--   ZhTWItemText.convert(text)     -- returns english text, { failed lines }, { notes }
--
local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert
local t_concat = table.concat

local M = { }

local ZhTW -- Modules/ZhTWConverter, loaded on first use
local reverse -- Chinese -> English lookups built from Data/zhTW

local SEPARATOR = "--------"
local EM_DASH = "\226\128\148"

local IDEO_SPACE = "\227\128\128" -- U+3000
local FULL_COLON = "\239\188\154" -- U+FF1A

local function trim(s)
	s = s:gsub("^%s+", ""):gsub("%s+$", "")
	while s:sub(1, 3) == IDEO_SPACE do
		s = s:sub(4):gsub("^%s+", "")
	end
	while #s >= 3 and s:sub(-3) == IDEO_SPACE do
		s = s:sub(1, -4):gsub("%s+$", "")
	end
	return s
end

-- "名稱: 值" or "名稱：值" (multi-byte characters can't go in a Lua [] class)
local function splitSpec(line)
	local a = line:find(":", 1, true)
	local b = line:find(FULL_COLON, 1, true)
	local pos, len
	if a and (not b or a < b) then
		pos, len = a, 1
	elseif b then
		pos, len = b, 3
	end
	if pos and pos > 1 then
		return trim(line:sub(1, pos - 1)), trim(line:sub(pos + len))
	end
end

local rarityNames = {
	["普通"] = "Normal", ["魔法"] = "Magic", ["稀有"] = "Rare", ["傳奇"] = "Unique",
	["寶石"] = "Gem", ["通貨"] = "Currency", ["命運卡"] = "Divination Card", ["聖物"] = "Relic",
}
local frameTypes = { Normal = 0, Magic = 1, Rare = 2, Unique = 3, Gem = 4, Currency = 5, Relic = 9 }

-- zhTW: the last line of a Wickerman part (Data/zhTW/Display.lua clientStrings)
local VISCERA_ATTACH = "將此物帶給城鎮或藏身處中的柳條人以將其附上。"

-- Whole lines that are flags; English text as Classes/Item.lua expects it
local flagLinesEn = { "Corrupted", "Mirrored", "Unidentified", "Split", "Synthesised Item", "Fractured Item",
	"Shaper Item", "Elder Item", "Crusader Item", "Redeemer Item", "Hunter Item", "Warlord Item",
	"Searing Exarch Item", "Eater of Worlds Item", "Veiled Prefix", "Veiled Suffix" }

-- End-of-line markers of the plain Ctrl+C format
local lineMarkers = {
	implicit = "implicit", crafted = "crafted", enchant = "enchant", fractured = "fractured",
	["固定"] = "implicit", ["固定詞綴"] = "implicit", ["工藝"] = "crafted", ["已工藝"] = "crafted",
	["大師工藝"] = "crafted", ["附魔"] = "enchant", ["破裂"] = "fractured", ["已破裂"] = "fractured",
}

-- Property lines kept before the item level (Classes/Item.lua reads these)
local keepProperties = { Quality = true, Armour = true, ["Evasion Rating"] = true, ["Energy Shield"] = true,
	Ward = true, Radius = true, ["Limited to"] = true }

-- Words in a "{ ... }" header that become English flags (Classes/Item.lua lineFlags)
local headerFlags = {
	{ zh = "大師工藝", en = "Master Crafted" },
	{ zh = "破裂", en = "Fractured" },
	{ zh = "卓烙總督", en = "Searing Exarch" },
	{ zh = "吞噬天地", en = "Eater of Worlds" },
	{ zh = "災魘", en = "Scourge" },
	{ zh = "穢生", en = "Foulborn" },
}

local function buildReverse()
	if reverse then
		return reverse
	end
	ZhTW = ZhTW or LoadModule("Modules/ZhTWConverter")
	reverse = { flags = { }, affixes = { prefix = { }, suffix = { } }, rarity = { }, affixNames = { } }
	local display = LoadModule("Data/zhTW/Display") or { }
	local strings = display.clientStrings or { }
	for _, en in ipairs(flagLinesEn) do
		if strings[en] then
			reverse.flags[strings[en]] = en
		end
	end
	reverse.flags["已腐化"] = "Corrupted"
	reverse.flags["已汙染"] = "Corrupted"
	for zh, en in pairs(rarityNames) do
		reverse.rarity[zh] = en
	end
	for _, en in ipairs({ "Normal", "Magic", "Rare", "Unique", "Relic", "Currency", "Gem" }) do
		local zh = strings[en]
		if zh and not reverse.rarity[zh] and en ~= "Normal" then -- "Normal" is "中" there (size)
			reverse.rarity[zh] = en
		end
	end
	local affixes = LoadModule("Data/zhTW/Affixes") or { }
	for kind, list in pairs(reverse.affixes) do
		for en, zh in pairs(affixes[kind] or { }) do
			list[zh] = list[zh] or { }
			t_insert(list[zh], en)
		end
		for _, names in pairs(list) do
			table.sort(names)
		end
	end
	for _, mods in pairs(data.itemMods) do
		for _, mod in pairs(mods) do
			if type(mod) == "table" and mod.affix then
				reverse.affixNames[mod.affix] = true
			end
		end
	end
	return reverse
end

local function affixName(kind, zh)
	local list = buildReverse().affixes[kind][zh]
	if not list then
		return nil
	end
	for _, en in ipairs(list) do
		if reverse.affixNames[en] then
			return en
		end
	end
	return list[1]
end

-- "{ 已大師工藝 後綴 "工藝之"(階級：2) }" -> "{ Master Crafted Suffix Modifier "of Crafting" (Rank: 2) }"
-- Returns header text and the line postfix for the lines below it
local function translateHeader(inner)
	local body = inner
	local dash = body:find(EM_DASH, 1, true)
	if dash then
		body = body:sub(1, dash - 1) -- modifier tags: cosmetic
	end
	local nameZh = body:match("\"(.-)\"") or body:match("「(.-)」")
	local rest = body:gsub("\".-\"", ""):gsub("「.-」", "")
	local tier = rest:match("階層%D-(%d+)")
	local rank = rest:match("階級%D-(%d+)")
	local kind, affixKind, postfix
	if rest:find("前綴", 1, true) then
		kind, affixKind = "Prefix Modifier", "prefix"
	elseif rest:find("後綴", 1, true) then
		kind, affixKind = "Suffix Modifier", "suffix"
	elseif rest:find("傳奇詞綴", 1, true) then
		kind = "Unique Modifier"
	elseif rest:find("附魔", 1, true) then
		kind, postfix = "Modifier", " (enchant)"
	elseif rest:find("固定", 1, true) then
		kind = "Implicit Modifier"
	else
		kind = "Modifier"
	end
	local flags = { }
	for _, f in ipairs(headerFlags) do
		if rest:find(f.zh, 1, true) then
			t_insert(flags, f.en)
		end
	end
	local out = "{ " .. (#flags > 0 and (t_concat(flags, " ") .. " ") or "") .. kind
	local nameEn = nameZh and affixKind and affixName(affixKind, nameZh)
	if nameEn then
		out = out .. " \"" .. nameEn .. "\""
	end
	if tier then
		out = out .. " (Tier: " .. tier .. ")"
	elseif rank then
		out = out .. " (Rank: " .. rank .. ")"
	end
	return out .. " }", postfix
end

-- Removes "40(33-43)" roll ranges; returns the line and { { value, range } ... }
local function stripRanges(line)
	local ranges = { }
	line = line:gsub("(%-?%d+%.?%d*)%((%-?%d+%.?%d*%-%-?%d+%.?%d*)%)", function(value, range)
		t_insert(ranges, { value = value, range = range })
		return value
	end)
	return line, ranges
end

-- Puts roll ranges back after the same numbers in the English text, in order
local function restoreRanges(en, ranges)
	local pos = 1
	for _, r in ipairs(ranges) do
		local from = pos
		local found
		for _ = 1, 2 do
			local s = from
			while true do
				local a, b = en:find(r.value, s, true)
				if not a then
					break
				end
				local before = a > 1 and en:sub(a - 1, a - 1) or ""
				local after = en:sub(b + 1, b + 1)
				if not before:match("[%d%.]") and not after:match("[%d%.]") and after ~= "(" then
					found = b
					break
				end
				s = b + 1
			end
			if found or from == 1 then
				break
			end
			from = 1
		end
		if found then
			local insert = "(" .. r.range .. ")"
			en = en:sub(1, found) .. insert .. en:sub(found + 1)
			pos = found + #insert + 1
		end
	end
	return en
end

-- Splits a mod line into text, ranges and end-of-line marker
local function prepareModLine(line)
	local marker
	local text, m = line:match("^(.-)%s*%(([^%(%)]+)%)$")
	if not text then
		text, m = line:match("^(.-)%s*（(.-)）$")
	end
	if text and lineMarkers[m] then
		line, marker = text, lineMarkers[m]
	end
	local stripped, ranges = stripRanges(line)
	return { raw = line, text = stripped, ranges = ranges, marker = marker }
end

local function isAscii(s)
	return not s:find("[\128-\255]")
end

-- Converts a group of mod lines (the lines under one header, or one plain section).
-- Returns english lines and the failed lines (left out: Classes/Item.lua would show them as "???").
local function convertModGroup(group, joinFirst)
	local out, failed = { }, { }
	local function emit(en, items, postfix)
		local ranges = { }
		for _, item in ipairs(items) do
			for _, r in ipairs(item.ranges) do
				t_insert(ranges, r)
			end
		end
		en = restoreRanges(en, ranges)
		local marker = items[#items].marker
		for enLine in (en .. "\n"):gmatch("([^\n]*)\n") do
			if enLine ~= "" then
				t_insert(out, enLine .. (marker and (" (" .. marker .. ")") or "") .. (postfix or ""))
			end
		end
	end
	local function textOf(i, j)
		local parts = { }
		for k = i, j do
			t_insert(parts, group[k].text)
		end
		return t_concat(parts, "\n")
	end
	local function itemsOf(i, j)
		local items = { }
		for k = i, j do
			t_insert(items, group[k])
		end
		return items
	end
	if joinFirst and #group > 1 then
		local en = ZhTW.convertModLine(textOf(1, #group))
		if en then
			emit(en, group, group.postfix)
			return out, failed
		end
	end
	local i = 1
	while i <= #group do
		local done = false
		for span = math.min(6, #group - i + 1), 1, -1 do
			local text = textOf(i, i + span - 1)
			local en = isAscii(text) and text or ZhTW.convertModLine(text)
			if en then
				emit(en, itemsOf(i, i + span - 1), group.postfix)
				i = i + span
				done = true
				break
			end
		end
		if not done then
			t_insert(failed, group[i].raw)
			i = i + 1
		end
	end
	return out, failed
end

function M.isChinese(text)
	if type(text) ~= "string" or not text:find("[\128-\255]") then
		return false
	end
	return text:find("稀有度", 1, true) ~= nil or text:find("物品種類", 1, true) ~= nil
end

function M.convert(text)
	local rev = buildReverse()
	local failures, notes = { }, { }
	local lines = { }
	for raw in (text:gsub("\r\n", "\n"):gsub("\r", "\n") .. "\n"):gmatch("([^\n]*)\n") do
		local line = trim(raw)
		if line ~= "" then
			t_insert(lines, line)
		end
	end

	-- Header: item class, rarity, name lines
	local l = 1
	local rarity = "Rare"
	local names = { }
	local viscera, hasRarity = false, false -- zhTW: Wickerman parts (物品種類: 臟器) have no rarity line
	while lines[l] and lines[l] ~= SEPARATOR do
		local key, val = splitSpec(lines[l])
		if key == "物品種類" then
			-- the base type decides the item class
			viscera = val == "臟器"
		elseif key == "稀有度" then
			hasRarity = true
			rarity = rev.rarity[val] or (isAscii(val) and val) or "Rare"
		else
			t_insert(names, lines[l])
		end
		l = l + 1
	end

	-- Body: first pass collects the item level and requirement level for the base lookup
	local reqLevel
	for i = l, #lines do
		local key, val = splitSpec(lines[i])
		if key == "等級" and not reqLevel then
			reqLevel = val:match("%d+")
		end
	end

	local itemData = {
		name = #names >= 2 and names[1] or "",
		typeLine = names[#names] or "",
		frameType = frameTypes[rarity] or 2,
		requirements = reqLevel and { { name = "Level", values = { { reqLevel } } } } or nil,
	}
	ZhTW.convertItemHeader(itemData)
	local report = ZhTW.getReport()
	for _, f in ipairs(report.failures) do
		t_insert(failures, f.line)
	end
	for _, n in ipairs(report.notes) do
		t_insert(notes, n)
	end
	local baseEn = itemData.baseType
	if baseEn and not isAscii(baseEn) then
		baseEn = nil
	end

	local out = { "Rarity: " .. rarity }
	if viscera and not hasRarity then
		-- zhTW: Classes/Item.lua reads a Viscera item without a rarity line as a normal item named by its base
		out = { "Item Class: Viscera" }
		names = { names[#names] }
	end
	if baseEn then
		local typeLine = isAscii(itemData.typeLine or "") and itemData.typeLine or baseEn
		if #names >= 2 and rarity ~= "Normal" and rarity ~= "Magic" then
			-- Rare names are cosmetic; Classes/Item.lua turns non-ASCII text into "?",
			-- so an untranslatable name becomes the base name
			local name = itemData.name
			if not name or name == "" or not isAscii(name) then
				name = typeLine
			end
			t_insert(out, name)
		end
		t_insert(out, typeLine)
	else
		for _, n in ipairs(names) do
			t_insert(out, n)
		end
	end

	-- Body
	ZhTW.setItemContext(baseEn)
	local afterItemLevel = false
	local group -- mod lines waiting for conversion
	local function flush()
		if not group then
			return
		end
		local g = group
		group = nil
		if #g == 0 then
			return
		end
		local en, failed = convertModGroup(g, g.header)
		if not g.header and #failed == #g and #g > 0 and not afterItemLevel then
			return
		end
		if not g.header and #failed == #g and g.mayBeFlavour then
			-- unique flavour text: nothing to parse
			t_insert(notes, "Skipped text: " .. t_concat(failed, " / "))
			return
		end
		for _, f in ipairs(failed) do
			t_insert(failures, f)
		end
		for _, line in ipairs(en) do
			t_insert(out, line)
		end
	end
	local sectionHasHeader = false
	while lines[l] do
		local line = lines[l]
		local key, val = splitSpec(line)
		local inner = line:match("^{%s*(.-)%s*}$")
		if line == SEPARATOR then
			flush()
			sectionHasHeader = false
			t_insert(out, SEPARATOR)
		elseif inner then
			flush()
			sectionHasHeader = true
			local header, postfix = translateHeader(inner)
			t_insert(out, header)
			group = { header = true, postfix = postfix }
		elseif viscera and line == VISCERA_ATTACH then
			-- zhTW: "Take this to the Wickerman ..." (Classes/Item.lua skips it for Viscera)
			flush()
			t_insert(out, "Take this to the Wickerman in a town or hideout to attach it.")
		elseif rev.flags[line] then
			flush()
			t_insert(out, rev.flags[line])
		elseif line:sub(1, 1) == "(" or line:sub(1, 3) == "（" then
			-- reminder text
		elseif key == "物品等級" then
			flush()
			afterItemLevel = true
			t_insert(out, "Item Level: " .. (val:match("%d+") or val))
		elseif key == "插槽" then
			flush()
			t_insert(out, "Sockets: " .. val)
		elseif not afterItemLevel and key == "需求" and val == "" then
			t_insert(out, "Requirements:")
		elseif not afterItemLevel and (key == "等級" or key == "力量" or key == "敏捷" or key == "智慧") then
			local en = ({ ["等級"] = "Level", ["力量"] = "Str", ["敏捷"] = "Dex", ["智慧"] = "Int" })[key]
			local num = val:match("%d+")
			if num then
				t_insert(out, en .. ": " .. num)
			end
		elseif not afterItemLevel and key and ZhTW.getTables().properties.names[key] then
			local en = ZhTW.getTables().properties.names[key]
			local v = trim((val:gsub("%b()", ""):gsub("（.-）", "")))
			if keepProperties[en] then
				v = ZhTW.getTables().properties.values[v] or v
				if isAscii(v) then
					t_insert(out, en .. ": " .. v)
				end
			end
		elseif not afterItemLevel and not sectionHasHeader then
			-- weapon class line, unknown properties: Classes/Item.lua does not need them
		else
			if not group then
				group = { mayBeFlavour = rarity == "Unique" or rarity == "Relic" }
			end
			t_insert(group, prepareModLine(line))
		end
		l = l + 1
	end
	flush()
	ZhTW.setItemContext(nil)
	return t_concat(out, "\n"), failures, notes
end

-- Converts Chinese item text; other text is returned unchanged
function M.convertIfChinese(text)
	if M.isChinese(text) then
		local ok, en, failures, notes = pcall(M.convert, text)
		if ok then
			if ConPrintf then
				for _, f in ipairs(failures) do
					ConPrintf("[zhTW] Item text: could not convert: %s", f)
				end
			end
			return en, failures, notes
		elseif ConPrintf then
			ConPrintf("[zhTW] Item text conversion error: %s", tostring(en))
		end
	end
	return text
end

-- For paste handlers (Classes/ItemsTab.lua): converts, and lists the lines that could not be
-- converted in a message box, since they are left out of the item
function M.paste(text)
	local en, failures = M.convertIfChinese(text)
	if failures and #failures > 0 and main and main.OpenMessagePopup then
		local msg = { "^7以下 " .. #failures .. " 行無法轉換成英文，已從物品中略過：", "" }
		for _, f in ipairs(failures) do
			t_insert(msg, "^xD0D0D0" .. f)
		end
		main:OpenMessagePopup("繁中物品文字", t_concat(msg, "\n"))
	end
	return en
end

return M
