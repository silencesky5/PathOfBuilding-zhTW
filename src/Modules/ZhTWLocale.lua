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

local ZhTWLocale = { enabled = true }

local ui -- English -> Chinese interface strings
local formats -- compiled printf-style strings, e.g. "x %.2f (MH chance to hit)"
local names -- English -> Chinese game names
local modTranslator -- function(line) -> Chinese or nil

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
	if count == 0 or #longest < 2 then
		return nil
	end
	return { pattern = t_concat(parts), anchor = longest, zh = zh, count = count }
end

local function load()
	if ui then
		return
	end
	local data = LoadModule("Data/zhTW/UI") or { }
	ui = data.strings or data
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
	if not modTranslator then
		local ok, mods = pcall(LoadModule, "Modules/ZhTWMods")
		if ok and type(mods) == "table" then
			mods.setNameLookup(function(en) return names[en] end)
			modTranslator = mods.translate
		elseif not ok then
			ConPrintf("zhTW: modifier translation unavailable: %s", tostring(mods))
		end
	end
end

function ZhTWLocale.setModTranslator(func)
	modTranslator = func
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

local function lookup(core)
	local v = ui[core] or ui[core .. " "] or names[core]
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

-- Translates one line without leading escapes; returns nil if nothing applies
local function translateCore(core)
	if core == "" or not s_find(core, "%a") then
		return nil
	end
	local v = lookup(core)
	if v then
		return v
	end
	-- Surrounding spaces
	local lead, mid, trail = s_match(core, "^(%s*)(.-)(%s*)$")
	if mid ~= core and mid ~= "" then
		v = lookup(mid)
		if v then
			return lead .. v .. trail
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
	-- Game modifier text
	if modTranslator then
		v = modTranslator(core)
		if v then
			return v
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
	-- Text with an embedded colour change, e.g. "^7Life: ^x33FF77+20"
	local a, rest = s_match(core, "^(.-)(%^[x%d].*)$")
	if a and a ~= "" and rest then
		local ta = translateCore(a)
		if ta then
			return esc .. ta .. (translateLine(rest) or rest)
		end
	end
	return nil
end

local cache = { }
local cacheSize = 0

function ZhTWLocale.tr(text)
	if not ZhTWLocale.enabled or type(text) ~= "string" or text == "" then
		return text
	end
	local c = cache[text]
	if c then
		return c
	end
	load()
	local out
	if s_find(text, "\n", 1, true) then
		local lines = { }
		local changed = false
		for line in (text .. "\n"):gmatch("([^\n]*)\n") do
			local t = translateLine(line)
			if t then
				changed = true
			end
			t_insert(lines, t or line)
		end
		out = changed and t_concat(lines, "\n") or text
	else
		out = translateLine(text) or text
	end
	if cacheSize > 50000 then
		cache = { }
		cacheSize = 0
	end
	cache[text] = out
	cacheSize = cacheSize + 1
	return out
end

-- Forget cached translations (after tables change)
function ZhTWLocale.clearCache()
	cache = { }
	cacheSize = 0
end

return ZhTWLocale
