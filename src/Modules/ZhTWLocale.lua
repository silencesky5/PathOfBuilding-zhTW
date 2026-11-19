-- Path of Building
--
-- Module: zhTW Locale
-- Translates text to Traditional Chinese at draw time.
--
-- Every string PoB draws passes through DrawString / DrawStringWidth (wrapped in
-- Modules/ZhTWText.lua), which call ZhTWLocale.tr(). Calculations never see the Chinese text,
-- and PoB's own files need almost no changes, which keeps upstream merges simple.
--
-- Sources, in lookup order for each line:
--   1. Data/zhTW/UI.lua             PoB interface strings (hand translated)
--   2. game names                   items, uniques, gems, passives (from the Taiwan client data)
--   3. game modifier lines          English mod text -> stats -> Chinese template
--      (registered by Modules/ZhTWMods.lua when available)
--
local s_find = string.find
local s_sub = string.sub
local s_match = string.match
local t_insert = table.insert
local t_concat = table.concat

local ZhTWLocale = { enabled = true, suspend = 0 }

local ui -- English -> Chinese interface strings
local formats -- compiled printf-style strings, e.g. "x %.2f (MH chance to hit)"
local names -- English -> Chinese game names
local rareWords -- English rare name word -> Chinese
local affixes -- { prefix = { [en] = zh }, suffix = { [en] = zh } }
local baseNames -- English base names, longest first (for magic item names)
local baseSet -- the same names as a set
local patterns -- { { pattern, replacement } } from Data/zhTW/UI.lua
local display -- Data/zhTW/Display.lua: descriptions, skill names, tags, flavour, client strings
local braceFormats -- compiled ClientStrings templates like "+{0} Levels from Item"
local modTranslator -- function(line) -> Chinese or nil
-- Measuring text (DrawStringWidth) skips the slow modifier matching: tooltips measure many
-- partial lines while word-wrapping. Full lines are translated when drawn and then cached.
local quick = false

local function escapePattern(s)
	return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

-- "Hit chance %.1f%%" -> Lua pattern capturing the values
local function compileFormat(en, zh)
	local parts, literal = { "^" }, ""
	local longest = ""
	local pos = 1
	local count = 0
	while pos <= #en do
		local s, e, flags, conv = en:find("%%([%-%+#0]*%d*%.?%d*)([dsfgx%%])", pos)
		local lit = en:sub(pos, (s or #en + 1) - 1)
		if #lit > #longest then
			longest = lit
		end
		t_insert(parts, escapePattern(lit))
		if not s then
			break
		end
		if conv == "%" then
			t_insert(parts, "%%")
		elseif conv == "s" then
			t_insert(parts, "(.-)")
			count = count + 1
		elseif conv == "d" or conv == "x" then
			t_insert(parts, "([%+%-]?[%d,]+)")
			count = count + 1
		else
			t_insert(parts, "([%+%-]?[%d,]*%.?%d+)")
			count = count + 1
		end
		pos = e + 1
	end
	t_insert(parts, "$")
	-- Formats with almost no fixed text ("%d%% to %s") would match unrelated lines
	local letters = select(2, en:gsub("%%[%-%+#0]*%d*%.?%d*[dsfgx%%]", ""):gsub("%a", ""))
	if count == 0 or #longest < 2 or letters < 4 then
		return nil
	end
	return { pattern = t_concat(parts), anchor = longest, zh = zh, count = count }
end

-- Leading colour escapes (^7, ^xRRGGBB) are kept and the rest is translated
local function splitEscape(line)
	local pos = 1
	while true do
		local e = s_match(line, "^%^x%x%x%x%x%x%x", pos) and pos + 7 or (s_match(line, "^%^%d", pos) and pos + 1)
		if not e then
			break
		end
		pos = e + 1
	end
	return s_sub(line, 1, pos - 1), s_sub(line, pos)
end

local function load()
	if ui then
		return
	end
	local data = LoadModule("Data/zhTW/UI") or { }
	ui = data.strings or data
	display = LoadModule("Data/zhTW/Display") or { }
	for _, k in ipairs({ "descriptions", "skillNames", "tags", "flavour", "reminders", "clientStrings", "clientFormats" }) do
		display[k] = display[k] or { }
	end
	-- Keys are matched without leading colour codes; normalise entries stored with them
	local fixed = { }
	for en, zh in pairs(ui) do
		local esc, rest = splitEscape(en)
		if esc ~= "" and rest ~= "" then
			local zEsc, zRest = splitEscape(zh)
			fixed[rest] = zEsc == esc and zRest or zh
		end
	end
	for en, zh in pairs(fixed) do
		if not ui[en] then
			ui[en] = zh
		end
	end
	formats = { }
	for en, zh in pairs(data.formats or { }) do
		local f = compileFormat(en, zh)
		if f then
			t_insert(formats, f)
		end
	end
	table.sort(formats, function(a, b) return #a.anchor > #b.anchor end)
	names = { }
	-- Reverse the import tables (Chinese -> English) for display (English -> Chinese)
	local function addReverse(map)
		for zh, en in pairs(map or { }) do
			if type(en) == "string" then
				if not names[en] then
					names[en] = zh
				end
			elseif type(en) == "table" then
				for _, e in ipairs(en) do
					local name = type(e) == "table" and e.name or e
					if name and not names[name] then
						names[name] = zh
					end
				end
			end
		end
	end
	addReverse(LoadModule("Data/zhTW/Bases"))
	local uniques = LoadModule("Data/zhTW/Uniques")
	addReverse(uniques and uniques.uniques)
	addReverse(LoadModule("Data/zhTW/Gems"))
	addReverse(LoadModule("Data/zhTW/Passives"))
	addReverse(LoadModule("Data/zhTW/Classes"))
	-- zhTW: timeless jewel passives (conquered nodes) and tattoos (Export/Scripts/zhTWExtra.lua)
	local legionOk, legion = pcall(LoadModule, "Data/zhTW/Legion")
	if legionOk and type(legion) == "table" then
		addReverse(legion.passives)
		addReverse(legion.tattoos)
	end
	-- Monster names (spectres, minions): English -> Chinese (Export/Scripts/zhTWMonsters.lua)
	for en, zh in pairs(LoadModule("Data/zhTW/Monsters") or { }) do
		if not names[en] then
			names[en] = zh
		end
	end
	-- PoB shows support gems without the word "Support"
	local extra = { }
	for en, zh in pairs(names) do
		local short = en:match("^(.+) Support$")
		if short and not names[short] then
			extra[short] = zh
		end
	end
	for en, zh in pairs(extra) do
		names[en] = zh
	end
	rareWords = { }
	for zh, en in pairs(uniques and uniques.words or { }) do
		for _, e in ipairs(type(en) == "table" and en or { en }) do
			rareWords[e] = rareWords[e] or zh
		end
	end
	affixes = LoadModule("Data/zhTW/Affixes") or { prefix = { }, suffix = { } }
	baseNames = { }
	for zh, en in pairs(LoadModule("Data/zhTW/Bases") or { }) do
		for _, e in ipairs(type(en) == "table" and en or { en }) do
			local name = type(e) == "table" and e.name or e
			if name and #name >= 4 then
				t_insert(baseNames, name)
			end
		end
	end
	table.sort(baseNames, function(a, b) return #a > #b end)
	-- Item bases only (gems are base items too, but "Skill, Skill" lists are not item names)
	local gemNames = { }
	for _, en in pairs(LoadModule("Data/zhTW/Gems") or { }) do
		for _, e in ipairs(type(en) == "table" and en or { en }) do
			gemNames[e] = true
		end
	end
	baseSet = { }
	for _, name in ipairs(baseNames) do
		if not gemNames[name] then
			baseSet[name] = true
		end
	end
	patterns = { }
	for _, p in ipairs(data.patterns or { }) do
		t_insert(patterns, { p[1], p[2] })
	end
	braceFormats = { }
	for en, zh in pairs(display.clientFormats or { }) do
		local parts, order, longest, pos = { "^" }, { }, "", 1
		while true do
			local bs, be, n = en:find("{(%d)[^}]*}", pos)
			local lit = en:sub(pos, (bs or #en + 1) - 1)
			if #lit > #longest then
				longest = lit
			end
			t_insert(parts, escapePattern(lit))
			if not bs then
				break
			end
			t_insert(parts, "(.-)")
			t_insert(order, tonumber(n))
			pos = be + 1
		end
		t_insert(parts, "$")
		-- Generic templates such as "{0} or {1}" would cut any sentence apart; keep only
		-- templates with a real piece of fixed text
		local fixedLen = #en:gsub("{%d[^}]*}", "")
		if #order > 0 and #longest >= 6 then
			t_insert(braceFormats, { pattern = t_concat(parts), order = order, anchor = longest, zh = zh, fixedLen = fixedLen })
		end
	end
	table.sort(braceFormats, function(a, b) return #a.anchor > #b.anchor end)
	if not modTranslator then
		local ok, mods = pcall(LoadModule, "Modules/ZhTWMods")
		if ok and type(mods) == "table" then
			mods.setNameLookup(function(en) return names[en] end, names)
			modTranslator = mods.translate
		elseif not ok then
			ConPrintf("zhTW: modifier translation unavailable: %s", tostring(mods))
		end
	end
end

function ZhTWLocale.setModTranslator(func)
	modTranslator = func
end

local function lookup(core)
	local v = ui[core] or ui[core .. " "] or names[core]
		or display.descriptions[core] or display.skillNames[core] or display.tags[core] or display.flavour[core]
		or display.reminders[core]
		or display.clientStrings[core]
	if v then
		return (v:gsub("%s+$", ""))
	end
	return nil
end

-- A label is often stored with its colon ("Character import status: ")
local function lookupLabel(label)
	local v = lookup(label)
	if v then
		return v
	end
	v = ui[label .. ":"] or ui[label .. ": "]
	if v then
		return (v:gsub(":%s*$", ""):gsub("：%s*$", ""))
	end
	return nil
end

local translateLine

-- Item names: magic names (prefix + base + suffix) and rare names (two words)
local function translateMagicName(core)
	for _, base in ipairs(baseNames) do
		local s, e = s_find(core, base, 1, true)
		if s then
			local pre = core:sub(1, s - 1):gsub("%s+$", "")
			local suf = core:sub(e + 1):gsub("^%s+", "")
			local zhPre = pre == "" and "" or affixes.prefix[pre]
			local zhSuf = suf == "" and "" or affixes.suffix[suf]
			if zhPre and zhSuf and (pre ~= "" or suf ~= "") then
				-- Chinese order: prefix + suffix + base (涉獵者的 + 工藝之 + 紫晶藥劑)
				return zhPre .. zhSuf .. names[base]
			end
			return nil
		end
	end
end

local function translateRareName(core)
	local words = { }
	for w in core:gmatch("%S+") do
		t_insert(words, w)
	end
	if #words < 2 or #words > 4 then
		return nil
	end
	for split = 1, #words - 1 do
		local a = rareWords[t_concat(words, " ", 1, split)]
		local b = rareWords[t_concat(words, " ", split + 1)]
		if a and b then
			return a .. " " .. b
		end
	end
end

local function translateName(part)
	return lookup(part) or translateMagicName(part) or translateRareName(part)
end

-- Translates one line without leading escapes; returns nil if nothing applies
local function translateCore(core)
	if core == "" or not s_find(core, "%a") then
		return nil
	end
	local v = lookup(core)
	if v then
		return v
	end
	-- Flavour text lines carry their own quotes; reminder text is in parentheses
	local q1, inner, q2 = s_match(core, '^(["(]?)(.-)([")]?)$')
	if inner and inner ~= core and inner ~= "" then
		v = lookup(inner)
		if v then
			return q1 .. v .. q2
		end
	end
	-- Surrounding spaces
	local lead, mid, trail = s_match(core, "^(%s*)(.-)(%s*)$")
	if mid ~= core and mid ~= "" then
		v = lookup(mid)
		if v then
			return lead .. v .. trail
		end
	end
	-- Pattern rules (e.g. "Socket #3:")
	for _, p in ipairs(patterns) do
		local caps = { s_match(core, p[1]) }
		if caps[1] ~= nil then
			return (p[2]:gsub("%%(t?)(%d)", function(t, n)
				local c = caps[tonumber(n)] or ""
				if t == "t" then
					return translateLine(c) or c
				end
				return c
			end))
		end
	end
	-- printf-style interface strings
	for _, f in ipairs(formats) do
		if s_find(core, f.anchor, 1, true) then
			local caps = { s_match(core, f.pattern) }
			if caps[1] ~= nil then
				local i = 0
				local out = f.zh:gsub("%%[%-%+#0]*%d*%.?%d*([dsfgx%%])", function(conv)
					if conv == "%" then
						return "%"
					end
					i = i + 1
					local v = caps[i] or ""
					if conv == "s" then
						-- English plural suffixes passed as %s ("Brand%s") are dropped in Chinese
						if v == "s" or v == "es" then
							return ""
						end
						return translateLine(v) or v
					end
					return v
				end)
				return out
			end
		end
	end
	-- "Label:" and "Label: value"
	local label, sep, value = s_match(core, "^([^:]-)(:%s*)(.*)$")
	if label and label ~= "" then
		local l = lookupLabel(label)
		if l then
			if value == "" then
				return l .. sep
			end
			return l .. sep .. (translateLine(value) or value)
		end
	end
	-- Stat comparison lines: number, stat label, optional "(+0.8%)"
	-- (also with a trailing "[... per point]" part, which is translated separately)
	local statCore, bracket = s_match(core, "^(.-)( %b[])$")
	if not statCore then
		statCore, bracket = core, ""
	end
	local num, label2, pct = s_match(statCore, "^([%+%-]?[%d,]+%.?%d*%%?) (.-)( %([%+%-]?[%d,]+%.?%d*%%%))$")
	if not num then
		num, label2 = s_match(statCore, "^([%+%-]?[%d,]+%.?%d*%%?) ([%a][%a%s%.']+)$")
		pct = ""
	end
	if num then
		local l = lookupLabel(label2)
		if l then
			if bracket ~= "" then
				local inner = bracket:sub(3, -2)
				bracket = " [" .. (translateLine(inner) or inner) .. "]"
			end
			return num .. " " .. l .. pct .. bracket
		end
	end
	-- Game modifier text
	if modTranslator and not quick then
		v = modTranslator(core)
		if v then
			return v
		end
	end
	-- Game client templates (after modifiers: these are loose), e.g. "+{0} Levels from Item"
	for _, f in ipairs(braceFormats) do
		if f.fixedLen * 10 >= #core * 6 and s_find(core, f.anchor, 1, true) then
			local caps = { s_match(core, f.pattern) }
			if caps[1] ~= nil then
				local byIndex = { }
				for i, n in ipairs(f.order) do
					byIndex[n] = caps[i]
				end
				return (f.zh:gsub("{(%d)[^}]*}", function(n)
					local c = byIndex[tonumber(n)] or ""
					return translateLine(c) or c
				end))
			end
		end
	end
	-- Item and gem names, also "Title, Base" and "Skill, Skill" lists
	v = translateName(core)
	if v then
		return v
	end
	if s_find(core, ", ", 1, true) then
		local parts, any = { }, false
		for part in (core .. ", "):gmatch("(.-), ") do
			local t = translateLine(part)
			any = any or t ~= nil
			t_insert(parts, t or part)
		end
		if any then
			-- Chinese separators: "名稱 · 基底" for an item name, "、" for lists
			local englishParts = { }
			for part in (core .. ", "):gmatch("(.-), ") do
				t_insert(englishParts, part)
			end
			local last = englishParts[#englishParts]
			local isItem = #parts == 2 and last and baseSet[(StripEscapes(last):gsub("%^[x%d]%x*", ""))]
			return t_concat(parts, isItem and " · " or "、")
		end
	end
	-- Trailing notes like "(Disabled)"
	local body, note = s_match(core, "^(.-)%s*(%b())$")
	if body and body ~= "" then
		local tb = translateCore(body)
		local tn = lookup(note) or lookup(note:sub(2, -2))
		if tb or tn then
			if tn and not tn:find("^%(") then
				tn = "(" .. tn .. ")"
			end
			return (tb or body) .. " " .. (tn or note)
		end
	end
	return nil
end

-- Translates a single line, keeping colour escapes
translateLine = function(line)
	local esc, core = splitEscape(line)
	local v = translateCore(core)
	if v then
		return esc .. v
	end
	-- Trailing colour code and closing punctuation, e.g. "Girded Tower Shield^7)"
	local body, tail = s_match(core, "^(.-)(%^x%x%x%x%x%x%x[%)%]%.,]*)$")
	if not body then
		body, tail = s_match(core, "^(.-)(%^%d[%)%]%.,]*)$")
	end
	if body and body ~= "" then
		local tb = translateLine(body)
		if tb then
			return esc .. tb .. tail
		end
	end
	-- Text with an embedded colour change, e.g. "^7Life: ^x33FF77+20"
	local a, rest = s_match(core, "^(.-)(%^[x%d].*)$")
	if a and a ~= "" and rest then
		local ta = translateCore(a)
		if ta then
			return esc .. ta .. (translateLine(rest) or rest)
		end
		-- Last resort: drop the inner colour codes, e.g. "1,234 Gold ^7required to ..."
		local plain = core:gsub("%^x%x%x%x%x%x%x", ""):gsub("%^%d", "")
		local tp = translateCore(plain)
		if tp then
			return esc .. tp
		end
	end
	return nil
end

local cache = { }
local cacheSize = 0

-- measure = true when the text is only measured, not drawn
function ZhTWLocale.tr(text, measure)
	-- suspend > 0 while an edit box draws: typed text is shown as typed
	if not ZhTWLocale.enabled or ZhTWLocale.suspend > 0 or type(text) ~= "string" or text == "" then
		return text
	end
	local c = cache[text]
	if c then
		return c
	end
	load()
	quick = measure and true or false
	local onMiss = not measure and ZhTWLocale.onMiss or nil
	local out
	-- Whole multi-line text first (help texts are stored as one entry)
	local esc0, core0 = splitEscape(text)
	local whole = s_find(text, "\n", 1, true) and ui[core0]
	if whole then
		out = esc0 .. whole
	elseif s_find(text, "\n", 1, true) then
		local lines = { }
		local changed = false
		for line in (text .. "\n"):gmatch("([^\n]*)\n") do
			local t = translateLine(line)
			if t then
				changed = true
			elseif onMiss then
				onMiss(line)
			end
			t_insert(lines, t or line)
		end
		out = changed and t_concat(lines, "\n") or text
	else
		out = translateLine(text)
		if not out then
			out = text
			if onMiss then
				onMiss(text)
			end
		end
	end
	if cacheSize > 50000 then
		cache = { }
		cacheSize = 0
	end
	quick = false
	if measure and out == text then
		-- Might still be a modifier line; let the drawing call decide and cache it
		return out
	end
	cache[text] = out
	cacheSize = cacheSize + 1
	return out
end

-- Chinese text for an English name or line, also while an edit box runs or in the English interface
function ZhTWLocale.translate(text)
	local enabled, suspend = ZhTWLocale.enabled, ZhTWLocale.suspend
	ZhTWLocale.enabled, ZhTWLocale.suspend = true, 0
	local ok, out = pcall(ZhTWLocale.tr, text)
	ZhTWLocale.enabled, ZhTWLocale.suspend = enabled, suspend
	return ok and out or text
end

-- Search boxes: true when the query has Chinese text and the Chinese name contains it
-- (spaces and colour codes ignored). Returns nil for queries without Chinese.
local searchCache = { }
function ZhTWLocale.searchMatch(en, query)
	if type(query) ~= "string" or not s_find(query, "[\128-\255]") or type(en) ~= "string" then
		return nil
	end
	local zh = searchCache[en]
	if not zh then
		zh = ZhTWLocale.translate(en):gsub("%^x%x%x%x%x%x%x", ""):gsub("%^%d", ""):gsub("%s+", ""):lower()
		searchCache[en] = zh
	end
	return s_find(zh, (query:gsub("%s+", ""):lower()), 1, true) ~= nil
end

-- Forget cached translations (after tables change)
function ZhTWLocale.clearCache()
	cache = { }
	cacheSize = 0
end

return ZhTWLocale
