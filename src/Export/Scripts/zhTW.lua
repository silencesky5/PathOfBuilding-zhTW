-- zhTW: Taiwan server (Traditional Chinese) lookup table export
--
-- Builds the Traditional Chinese -> English tables used by Modules/ZhTWConverter.lua
-- Output: src/Data/zhTW/*.lua
--
-- The English and Traditional Chinese .datc64 tables share the same row order, so
-- every table here is built by pairing row N of "Data/X.datc64" with row N of
-- "Data/Traditional Chinese/X.datc64".
--
-- Can be run from the dat viewer (Scripts >> zhTW) or headless via Export/zhTWRun.lua.

local t_insert = table.insert
local s_format = string.format

local LANG = "Traditional Chinese"
local OUT_DIR = "../Data/zhTW/"

local datNames = {
	"BaseItemTypes",
	"Words",
	"ClientStrings",
	"GemEffects",
	"LeagueNames",
	"AlternateQualityTypes",
	"PassiveSkills",
	"ItemVisualIdentity",
	"Characters",
	"Ascendancy",
	"Mods",
	"ActiveSkills",
	"GemTags",
	"FlavourText",
	"ReminderText",
}
-- Stat description files whose Traditional Chinese blocks are exported.
-- Item modifiers are described by these (tincture/graft include stat_descriptions).
local statFiles = {
	"stat_descriptions",
	"tincture_stat_descriptions",
	"graft_stat_descriptions",
}

-- Stat description files exported in StatDescriber format, English and Traditional Chinese,
-- for showing modifiers in Chinese (Modules/ZhTWMods.lua). Parents (include "...") are added
-- automatically. Output: src/Data/StatDescriptions/zhTW/en/ and .../zhTW/tc/
local displayStatFiles = {
	"stat_descriptions", "tincture_stat_descriptions", "graft_stat_descriptions",
	"passive_skill_stat_descriptions", "passive_skill_aura_stat_descriptions",
	"active_skill_gem_stat_descriptions", "aura_skill_stat_descriptions", "banner_aura_skill_stat_descriptions",
	"beam_skill_stat_descriptions", "brand_skill_stat_descriptions", "buff_skill_stat_descriptions",
	"curse_skill_stat_descriptions", "debuff_skill_stat_descriptions", "secondary_debuff_skill_stat_descriptions",
	"gem_stat_descriptions", "minion_attack_skill_stat_descriptions", "minion_skill_stat_descriptions",
	"minion_spell_skill_stat_descriptions", "minion_spell_damage_skill_stat_descriptions",
	"single_minion_spell_skill_stat_descriptions", "monster_stat_descriptions", "offering_skill_stat_descriptions",
	"skill_stat_descriptions", "variable_duration_skill_stat_descriptions",
}

local ggpk = main.ggpk
if not ggpk or not ggpk.oozPath then
	print("zhTW: GGPK source is not set")
	return
end

---------------------------------------------------------------------------
-- File extraction / loading
---------------------------------------------------------------------------
-- UTF-8 -> UTF-16LE, for PowerShell -EncodedCommand
local function utf8to16le(s)
	local out = { }
	local i, n = 1, #s
	while i <= n do
		local c = s:byte(i)
		local cp
		if c < 0x80 then
			cp = c
			i = i + 1
		elseif c < 0xE0 then
			cp = (c % 0x20) * 0x40 + (s:byte(i + 1) % 0x40)
			i = i + 2
		elseif c < 0xF0 then
			cp = (c % 0x10) * 0x1000 + (s:byte(i + 1) % 0x40) * 0x40 + (s:byte(i + 2) % 0x40)
			i = i + 3
		else
			cp = (c % 0x08) * 0x40000 + (s:byte(i + 1) % 0x40) * 0x1000 + (s:byte(i + 2) % 0x40) * 0x40 + (s:byte(i + 3) % 0x40)
			i = i + 4
		end
		if cp >= 0x10000 then
			cp = cp - 0x10000
			local hi, lo = 0xD800 + math.floor(cp / 0x400), 0xDC00 + cp % 0x400
			t_insert(out, string.char(hi % 256, math.floor(hi / 256), lo % 256, math.floor(lo / 256)))
		else
			t_insert(out, string.char(cp % 256, math.floor(cp / 256)))
		end
	end
	return table.concat(out)
end

-- os.execute passes the command line in the system ANSI code page, which breaks
-- non-ASCII paths (e.g. the Taiwan Steam folder "流亡黯道"). PowerShell's
-- -EncodedCommand takes a pure ASCII (base64 UTF-16LE) command instead.
local function runUnicode(psCommand)
	local base64 = require("base64")
	local cmd = "powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " .. base64.encode(utf8to16le(psCommand))
	ConPrintf("%s", psCommand)
	return os.execute(cmd)
end

local function psQuote(s)
	return "'" .. s:gsub("'", "''") .. "'"
end

local function extract(fileList)
	if not ggpk.path or ggpk.path == "" then
		-- Using a pre-extracted dat folder; assume files are already there
		return
	end
	local manifest = ggpk.oozPath .. "zhTW_extract_list.txt"
	local f = assert(io.open(manifest, "w"))
	for _, name in ipairs(fileList) do
		f:write(name:lower(), "\n")
	end
	f:close()
	runUnicode("Set-Location -LiteralPath " .. psQuote(ggpk.oozPath) ..
		"; Get-Content -LiteralPath " .. psQuote(manifest) ..
		" | & .\\bun_extract_file.exe extract-files " .. psQuote(ggpk.path) .. " .")
	os.remove(manifest)
end

local function readFile(path)
	local f = io.open(ggpk.oozPath .. path:lower():gsub("/", "\\"), "rb")
	if not f then
		return nil
	end
	local data = f:read("*a")
	f:close()
	return data
end

local extractList = { }
for _, name in ipairs(datNames) do
	t_insert(extractList, "Data/" .. name .. ".datc64")
	t_insert(extractList, "Data/" .. LANG .. "/" .. name .. ".datc64")
end
for _, name in ipairs(statFiles) do
	t_insert(extractList, "Metadata/StatDescriptions/" .. name .. ".txt")
end
for _, name in ipairs(displayStatFiles) do
	t_insert(extractList, "Metadata/StatDescriptions/" .. name .. ".txt")
end
-- English only: used to rank stats that share one Chinese text
local englishOnlyDats = { "Stats" }
for _, name in ipairs(englishOnlyDats) do
	t_insert(extractList, "Data/" .. name .. ".datc64")
end
extract(extractList)

local dats = { en = { }, tc = { } }
for _, name in ipairs(datNames) do
	local enRaw = readFile("Data/" .. name .. ".datc64")
	local tcRaw = readFile("Data/" .. LANG .. "/" .. name .. ".datc64")
	if not enRaw or not tcRaw then
		print("zhTW: missing " .. name .. ".datc64 (English or " .. LANG .. ")")
		return
	end
	dats.en[name] = new("Dat64File"):Dat64File(name, enRaw)
	dats.tc[name] = new("Dat64File"):Dat64File(name, tcRaw)
	if dats.en[name].rowCount ~= dats.tc[name].rowCount then
		print(s_format("zhTW: WARNING row count mismatch in %s (%d vs %d)", name, dats.en[name].rowCount, dats.tc[name].rowCount))
	end
	-- Allow Key columns of our English tables to resolve (e.g. BaseItemTypes -> ItemVisualIdentity)
	if not main.datFileByName[name:lower()] then
		main.datFileByName[name:lower()] = dats.en[name]
	end
end
for _, name in ipairs(englishOnlyDats) do
	local enRaw = readFile("Data/" .. name .. ".datc64")
	if enRaw then
		dats.en[name] = new("Dat64File"):Dat64File(name, enRaw)
		if not main.datFileByName[name:lower()] then
			main.datFileByName[name:lower()] = dats.en[name]
		end
	else
		print("zhTW: missing " .. name .. ".datc64; ambiguous stat ranking will be skipped")
	end
end

local function trim(s)
	return s and (s:gsub("^%s+", ""):gsub("%s+$", "")) or s
end

-- Pair column `col` of English and Chinese rows
local function eachPair(name, col, filter)
	local en, tc = dats.en[name], dats.tc[name]
	local i = 0
	local n = math.min(en.rowCount, tc.rowCount)
	return function()
		while true do
			i = i + 1
			if i > n then
				return
			end
			local enRow, tcRow = en:GetRowByIndex(i), tc:GetRowByIndex(i)
			if not filter or filter(enRow, tcRow) then
				return enRow, tcRow, i
			end
		end
	end
end

---------------------------------------------------------------------------
-- Version info
---------------------------------------------------------------------------
local versionInfo = { }
do
	t_insert(versionInfo, "-- Source: " .. tostring(ggpk.path or ggpk.oozPath))
	-- Steam / standalone directories keep a client log with the engine build revision
	local dir = ggpk.path and (ggpk.path:match("^(.*)[/\\][^/\\]+%.ggpk$") or ggpk.path)
	local revision
	if dir then
		local f = io.open(dir .. "\\logs\\LatestClient.txt", "r")
		if f then
			local text = f:read("*a")
			f:close()
			revision = text:match("Build Revision: (%d+)")
		end
	end
	t_insert(versionInfo, "-- Client build revision: " .. (revision or "unknown"))
	local leagues = dats.en.LeagueNames
	local lastLeague = leagues.rowCount > 0 and leagues:GetRowByIndex(leagues.rowCount).Name
	t_insert(versionInfo, "-- Latest league in client data: " .. tostring(lastLeague))
	t_insert(versionInfo, "-- Exported: " .. os.date("%Y-%m-%d %H:%M"))
end

runUnicode("New-Item -ItemType Directory -Force -Path " .. psQuote(GetWorkDir() .. "\\..\\Data\\zhTW") .. " | Out-Null")

local function writeTable(fileName, tbl, comment)
	local out = io.open(OUT_DIR .. fileName, "w")
	out:write("-- This file is automatically generated by Export/Scripts/zhTW.lua, do not edit!\n")
	out:write("-- Item data (c) Grinding Gear Games\n")
	for _, line in ipairs(versionInfo) do
		out:write(line, "\n")
	end
	if comment then
		out:write("-- ", comment, "\n")
	end
	out:write("\nreturn ")
	writeLuaTable(out, tbl, 1)
	out:write("\n")
	out:close()
end

local summary = { }
local conflictLog = { }

-- Simple map builder: map[zh] = en; records conflicts (same zh, different en)
local function newMap(label)
	return { label = label, map = { }, count = 0, conflicts = { } }
end
local function mapAdd(m, zh, en, extra)
	zh, en = trim(zh), trim(en)
	if not zh or zh == "" or not en or en == "" then
		return
	end
	local cur = m.map[zh]
	if cur == nil then
		m.map[zh] = en
		m.count = m.count + 1
	elseif cur ~= en then
		m.conflicts[zh] = m.conflicts[zh] or { cur }
		if not isValueInArray(m.conflicts[zh], en) then
			t_insert(m.conflicts[zh], en)
		end
	end
end
-- Map with conflicting names written as a list of English candidates
local function finalMap(m)
	local out = { }
	for zh, en in pairs(m.map) do
		out[zh] = m.conflicts[zh] or en
	end
	return out
end
local function countKeys(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end
local function logConflicts(m)
	local n = countKeys(m.conflicts)
	t_insert(summary, s_format("%-24s %6d entries, %4d name conflicts", m.label, m.count, n))
	local keys = { }
	for zh in pairs(m.conflicts) do t_insert(keys, zh) end
	table.sort(keys)
	for _, zh in ipairs(keys) do
		t_insert(conflictLog, s_format("[%s] %s => %s", m.label, zh, table.concat(m.conflicts[zh], " | ")))
	end
end

---------------------------------------------------------------------------
-- Bases.lua
---------------------------------------------------------------------------
do
	-- Several English bases share one Chinese name (e.g. alternate art / legacy versions).
	-- Those are written as a list of { name, art } so the importer can pick using the item icon.
	local candidates = { }
	local count, conflicts = 0, 0
	for enRow, tcRow in eachPair("BaseItemTypes", "Name") do
		local zh, en = trim(tcRow.Name), trim(enRow.Name)
		if zh and zh ~= "" and en and en ~= "" and not enRow.Id:match("^Metadata/Items/Microtransaction") then
			local art
			local ivi = enRow.ItemVisualIdentityKey
			if ivi and ivi.DDSFile then
				art = ivi.DDSFile:match("([^/]+)%.dds$")
			end
			candidates[zh] = candidates[zh] or { }
			local list = candidates[zh]
			local found
			for _, c in ipairs(list) do
				if c.name == en then
					found = c
					break
				end
			end
			if not found then
				t_insert(list, { name = en, art = art, id = enRow.Id })
			end
		end
	end
	local out = { }
	local keys = { }
	for zh in pairs(candidates) do t_insert(keys, zh) end
	table.sort(keys)
	for _, zh in ipairs(keys) do
		local list = candidates[zh]
		count = count + 1
		if #list == 1 then
			out[zh] = list[1].name
		else
			conflicts = conflicts + 1
			local names = { }
			out[zh] = { }
			for _, c in ipairs(list) do
				t_insert(out[zh], { name = c.name, art = c.art })
				t_insert(names, c.name .. (c.art and (" (" .. c.art .. ")") or ""))
			end
			t_insert(conflictLog, s_format("[Bases] %s => %s", zh, table.concat(names, " | ")))
		end
	end
	writeTable("Bases.lua", out, "Base item type names: Traditional Chinese -> English. Conflicts are lists of { name, art }.")
	t_insert(summary, s_format("%-24s %6d entries, %4d name conflicts", "Bases", count, conflicts))
end

---------------------------------------------------------------------------
-- Uniques.lua (unique names) + rare name words
---------------------------------------------------------------------------
do
	local uniques = newMap("Uniques")
	local words = newMap("Rare name words")
	for enRow, tcRow in eachPair("Words", "Text") do
		local en = trim(enRow.Text2) ~= "" and enRow.Text2 or enRow.Text
		local zh = trim(tcRow.Text2) ~= "" and tcRow.Text2 or tcRow.Text
		if enRow.Wordlist == 6 then
			mapAdd(uniques, zh, en)
		elseif enRow.Wordlist == 1 or enRow.Wordlist == 2 then
			mapAdd(words, zh, en)
		end
	end
	writeTable("Uniques.lua", { uniques = finalMap(uniques), words = finalMap(words) }, "uniques: unique item names; words: rare item name prefixes/suffixes")
	logConflicts(uniques)
	logConflicts(words)
end

---------------------------------------------------------------------------
-- Gems.lua
---------------------------------------------------------------------------
do
	local gems = newMap("Gems")
	for enRow, tcRow in eachPair("BaseItemTypes", "Name", function(en) return en.Id:match("^Metadata/Items/Gems/") end) do
		mapAdd(gems, tcRow.Name, enRow.Name)
	end
	-- Transfigured gem names and secondary support names (hybrid gems)
	for enRow, tcRow in eachPair("GemEffects", "Name") do
		mapAdd(gems, tcRow.Name, enRow.Name)
		local enSec, tcSec = enRow.SecondarySupportName, tcRow.SecondarySupportName
		if type(enSec) == "table" and type(tcSec) == "table" then
			for i = 1, math.min(#enSec, #tcSec) do
				mapAdd(gems, tcSec[i], enSec[i])
			end
		elseif type(enSec) == "string" then
			mapAdd(gems, tcSec, enSec)
		end
	end
	writeTable("Gems.lua", finalMap(gems), "Skill gem names (incl. transfigured and secondary support names): Traditional Chinese -> English (a list when ambiguous)")
	logConflicts(gems)
end

---------------------------------------------------------------------------
-- Properties.lua
---------------------------------------------------------------------------
do
	-- ClientStrings Ids that produce item property / requirement names.
	-- Order matters: the first English text found for a Chinese string wins.
	local exactIds = {
		"Quality", "Level", "Strength", "Dexterity", "Intelligence", "ItemRequiredClass",
		"JewelRadiusLabel", "JewelItemLimit", "GhostItem", "ZanaInfluencedItem", "Experience",
		"ItemDisplayArmourArmour", "ItemDisplayArmourEvasionRating", "ItemDisplayArmourEnergyShield", "ItemDisplayArmourWard",
		"ItemDisplayShieldBlockChance",
	}
	local prefixIds = {
		"^ItemDisplayArmour", "^ItemDisplayWeapon", "^ItemDisplayShield", "^ItemDisplaySkillGem",
		"^ItemDisplayFlask", "^ItemDisplayCharges", "^ItemDisplayTincture", "^WeaponClassDisplayName",
	}
	local valueIds = {
		"^JewelRadius",
	}
	local props = newMap("Properties")
	local values = newMap("Property values")
	local byId = { }
	for enRow, tcRow in eachPair("ClientStrings", "Text") do
		byId[enRow.Id] = { en = enRow.Text, zh = tcRow.Text }
	end
	for _, id in ipairs(exactIds) do
		if byId[id] then
			mapAdd(props, byId[id].zh, byId[id].en)
		else
			print("zhTW: ClientStrings Id not found: " .. id)
		end
	end
	local ids = { }
	for id in pairs(byId) do t_insert(ids, id) end
	table.sort(ids)
	for _, pattern in ipairs(prefixIds) do
		for _, id in ipairs(ids) do
			if id:match(pattern) then
				mapAdd(props, byId[id].zh, byId[id].en)
			end
		end
	end
	for _, pattern in ipairs(valueIds) do
		for _, id in ipairs(ids) do
			if id:match(pattern) and id ~= "JewelRadiusLabel" then
				mapAdd(values, byId[id].zh, byId[id].en)
			end
		end
	end
	-- Catalyst qualities: "Quality (Attack Modifiers)"
	for enRow, tcRow in eachPair("AlternateQualityTypes", "Description") do
		mapAdd(props, tcRow.Description, enRow.Description)
	end
	-- Item name prefixes (typeLine) e.g. "Synthesised {0}", "Vestigial {0}", "Foulborn {0}", built-in support
	local templates = { }
	for _, id in ipairs({ "SynthesisedItem", "DivergentItem", "MutatedUniqueName", "ItemDisplayBuiltInSupport" }) do
		if byId[id] then
			templates[id] = { zh = byId[id].zh, en = byId[id].en }
		end
	end
	writeTable("Properties.lua", { names = props.map, values = values.map, templates = templates },
		"names: property/requirement names; values: text property values; templates: name prefix templates")
	logConflicts(props)
	logConflicts(values)
end

---------------------------------------------------------------------------
-- Leagues.lua
---------------------------------------------------------------------------
do
	local leagues = newMap("Leagues")
	for enRow, tcRow in eachPair("LeagueNames", "Name") do
		mapAdd(leagues, tcRow.Name, enRow.Name)
	end
	local byId = { }
	for enRow, tcRow in eachPair("ClientStrings", "Text") do
		if enRow.Id:match("^League") then
			mapAdd(leagues, tcRow.Text, enRow.Text)
		end
		byId[enRow.Id] = { en = enRow.Text, zh = tcRow.Text }
	end
	-- Mode words used when building league names at import time
	local modes = { }
	for _, id in ipairs({ "CreateCharacterStateHardcore", "CreateCharacterStateSSF", "LeagueRuthless" }) do
		if byId[id] then
			modes[id] = { zh = byId[id].zh, en = byId[id].en }
		end
	end
	-- League (short) names from LeagueNames.dat, used to recognise full seasonal league names
	-- such as "亡焰咒海" which contain the short name "咒海".
	local short = { }
	for enRow, tcRow in eachPair("LeagueNames", "Name") do
		if trim(tcRow.Name) ~= "" then
			t_insert(short, { zh = trim(tcRow.Name), en = trim(enRow.Name) })
		end
	end
	writeTable("Leagues.lua", { names = finalMap(leagues), modes = modes, short = short },
		"League names. Seasonal league names change every league: re-run this export after each league launch.")
	logConflicts(leagues)
end

---------------------------------------------------------------------------
-- Affixes.lua (magic item name prefixes/suffixes, English -> Chinese, for display)
-- Chinese magic names are prefix + suffix + base, e.g. 涉獵者的 + 工藝之 + 紫晶藥劑
---------------------------------------------------------------------------
do
	local out = { prefix = { }, suffix = { } }
	local count = 0
	for enRow, tcRow in eachPair("Mods", "Name") do
		local en, zh = trim(enRow.Name), trim(tcRow.Name)
		local kind = enRow.GenerationType == 1 and "prefix" or enRow.GenerationType == 2 and "suffix"
		if kind and en ~= "" and zh ~= "" and en ~= zh and not out[kind][en] then
			out[kind][en] = zh
			count = count + 1
		end
	end
	writeTable("Affixes.lua", out, "Magic item affix names: English -> Traditional Chinese (display only)")
	t_insert(summary, s_format("%-24s %6d entries", "Affixes", count))
end

---------------------------------------------------------------------------
-- Display.lua (English -> Chinese texts shown by PoB: skill descriptions, gem tags,
-- flavour text, ClientStrings and their {0} templates)
---------------------------------------------------------------------------
do
	local out = { descriptions = { }, skillNames = { }, tags = { }, flavour = { }, reminders = { }, clientStrings = { }, clientFormats = { } }
	local counts = { }
	local function add(tbl, en, zh)
		-- writeLuaTable does not escape carriage returns, so drop them
		en = trim((escapeGGGString(en or ""):gsub("\r", "")))
		zh = trim((escapeGGGString(zh or ""):gsub("\r", "")))
		if en ~= "" and zh ~= "" and en ~= zh and not out[tbl][en] then
			out[tbl][en] = zh
			counts[tbl] = (counts[tbl] or 0) + 1
		end
	end
	for enRow, tcRow in eachPair("ActiveSkills", "DisplayName") do
		add("skillNames", enRow.DisplayName, tcRow.DisplayName)
		add("descriptions", enRow.Description, tcRow.Description)
	end
	for enRow, tcRow in eachPair("GemEffects", "Description") do
		add("descriptions", enRow.Description, tcRow.Description)
	end
	for enRow, tcRow in eachPair("GemTags", "Name") do
		add("tags", enRow.Name, tcRow.Name)
	end
	-- Flavour text is drawn line by line; map lines when both languages have the same count
	for enRow, tcRow in eachPair("FlavourText", "Text") do
		local enLines, tcLines = { }, { }
		for l in (escapeGGGString(enRow.Text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
			t_insert(enLines, l)
		end
		for l in (escapeGGGString(tcRow.Text or "") .. "\n"):gmatch("([^\r\n]*)\r?\n") do
			t_insert(tcLines, l)
		end
		if #enLines == #tcLines then
			for i = 1, #enLines do
				add("flavour", enLines[i], tcLines[i])
			end
		end
	end
	-- Reminder text, e.g. "(Maximum Resistances cannot be raised above 90%)"
	for enRow, tcRow in eachPair("ReminderText", "Text") do
		add("reminders", enRow.Text, tcRow.Text)
	end
	for enRow, tcRow in eachPair("ClientStrings", "Text") do
		local en, zh = enRow.Text or "", tcRow.Text or ""
		if not en:find("[<%[]") and not en:find("\n") and #en <= 120 then
			if en:find("{%d}") then
				add("clientFormats", en, zh)
			else
				add("clientStrings", en, zh)
			end
		end
	end
	writeTable("Display.lua", out, "English -> Traditional Chinese texts for display (Modules/ZhTWLocale.lua)")
	local parts = { }
	for _, k in ipairs({ "descriptions", "skillNames", "tags", "flavour", "reminders", "clientStrings", "clientFormats" }) do
		t_insert(parts, k .. " " .. (counts[k] or 0))
	end
	t_insert(summary, s_format("%-24s %s", "Display", table.concat(parts, ", ")))
end

---------------------------------------------------------------------------
-- Classes.lua (character classes and ascendancies, for display)
---------------------------------------------------------------------------
do
	local classes = newMap("Classes")
	for enRow, tcRow in eachPair("Characters", "Name") do
		mapAdd(classes, tcRow.Name, enRow.Name)
	end
	for enRow, tcRow in eachPair("Ascendancy", "Name") do
		mapAdd(classes, tcRow.Name, enRow.Name)
	end
	writeTable("Classes.lua", finalMap(classes), "Character class and ascendancy names: Traditional Chinese -> English")
	logConflicts(classes)
end

---------------------------------------------------------------------------
-- Passives.lua (for "Allocates {0}" etc.)
---------------------------------------------------------------------------
do
	local passives = newMap("Passives")
	for enRow, tcRow in eachPair("PassiveSkills", "Name") do
		mapAdd(passives, tcRow.Name, enRow.Name)
	end
	writeTable("Passives.lua", finalMap(passives), "Passive skill names: Traditional Chinese -> English (a list when several English names share one Chinese name)")
	logConflicts(passives)
end

---------------------------------------------------------------------------
-- StatDescriptions.lua
---------------------------------------------------------------------------
do
	-- Parses the Traditional Chinese blocks of the stat description files.
	-- Same line format handling as Export/Scripts/statdesc.lua (which keeps only English).
	local function parseLimits(statLimits)
		local limits = { }
		for statLimit in statLimits:gmatch("[!%d%-#|]+") do
			local limit = { }
			if statLimit == "#" then
				limit[1] = "#"
				limit[2] = "#"
			elseif statLimit:match("^%-?%d+$") then
				limit[1] = tonumber(statLimit)
				limit[2] = tonumber(statLimit)
			else
				local negate = statLimit:match("^!(-?%d+)$")
				if negate then
					limit[1] = "!"
					limit[2] = tonumber(negate)
				else
					limit[1], limit[2] = statLimit:match("([%d%-#]+)|([%d%-#]+)")
					limit[1] = tonumber(limit[1]) or limit[1]
					limit[2] = tonumber(limit[2]) or limit[2]
				end
			end
			t_insert(limits, limit)
		end
		return limits
	end
	local function parseSpecial(special)
		local list = { }
		local tokens = { }
		for token in special:gmatch("([%w%%_]+)") do
			t_insert(tokens, token)
		end
		local i = 1
		while i <= #tokens do
			local token = tokens[i]
			local value = tonumber(tokens[i + 1])
			if token == "canonical_line" or token == "reminderstring" then
				i = i + (token == "reminderstring" and 2 or 1)
			elseif value then
				t_insert(list, { token, value })
				i = i + 2
			else
				i = i + 1
			end
		end
		return list
	end

	local out = { files = statFiles }
	local descCount, lineCount = 0, 0
	for fileIndex, name in ipairs(statFiles) do
		local raw = readFile("Metadata/StatDescriptions/" .. name .. ".txt")
		if not raw then
			print("zhTW: missing stat description file " .. name)
		else
			-- Drop the byte order mark, otherwise the first "description" line is not recognised
			local text = convertUTF16to8(raw):gsub("^\239\187\191", "")
			local cur, inLang, pending
			for line in text:gmatch("[^\r\n]+") do
				if pending then
					line = pending .. line
					pending = nil
				end
				if line:match("^%s*no_description") or line:match("^%s*include") then
					cur = nil
				elseif line:match("^%s*handed_description") or (line:match("^%s*description") and not line:match("_description")) then
					cur = { f = fileIndex }
					inLang = false
				elseif cur and not cur.s then
					local stats = line:match("^%s*%d+%s+([%w_%+%-%% ]+)")
					if stats then
						cur.s = { }
						for stat in stats:gmatch("[%w_%+%-%%]+") do
							t_insert(cur.s, stat)
						end
					else
						pending = line
					end
				elseif cur then
					local langName = line:match('lang "(.+)"')
					if langName then
						inLang = (langName == LANG)
						if inLang then
							cur.v = { }
							t_insert(out, cur)
							descCount = descCount + 1
						end
					elseif inLang and not line:match("table_only") then
						local statLimits, quality, descText, special = line:match('([%d%-#| !]+)%s*([%w_]*)%s*"(.-)"%s*(.*)')
						if statLimits then
							local variant = { l = parseLimits(statLimits), t = escapeGGGString(descText) }
							local sp = parseSpecial(special)
							if #sp > 0 then
								variant.p = sp
							end
							if quality:match("gem_quality") then
								variant.q = true
							end
							t_insert(cur.v, variant)
							lineCount = lineCount + 1
						end
					end
				end
			end
		end
	end
	-- Mod usage per stat: some different stats share one Chinese text
	-- (e.g. life_regeneration_rate_+% and life_recovery_rate_+% are both "增加 {0}% 生命恢復率").
	-- The importer picks the stat that real item mods of that kind use.
	-- u = { i = implicit-type mods, e = prefix/suffix, q = unique, n = enchantment }
	local usage = { }
	local mods = dats.en.Mods
	if mods then
		local statCols = { }
		for k = 1, 6 do
			if mods.colMap["Stat" .. k] then
				t_insert(statCols, "Stat" .. k)
			end
		end
		for i = 1, mods.rowCount do
			local row = mods:GetRowByIndex(i)
			if row.Domain == 1 then -- item mods
				local gt = row.GenerationType
				local kind
				if row.Id:match("Implicit") then
					kind = "i"
				elseif gt == 1 or gt == 2 then
					kind = "e"
				elseif gt == 3 then
					kind = "q"
				elseif gt == 10 then
					kind = "n"
				else
					kind = "i"
				end
				for _, col in ipairs(statCols) do
					local stat = row[col]
					if stat and stat.Id then
						usage[stat.Id] = usage[stat.Id] or { }
						usage[stat.Id][kind] = (usage[stat.Id][kind] or 0) + 1
					end
				end
			end
		end
	end
	-- Attach usage to descriptors whose Chinese text is shared with another stat
	local byText = { }
	for _, desc in ipairs(out) do
		for _, v in ipairs(desc.v) do
			byText[v.t] = byText[v.t] or { }
			byText[v.t][desc] = true
		end
	end
	local ambiguousTexts = 0
	for text, set in pairs(byText) do
		local stats = { }
		for desc in pairs(set) do
			stats[table.concat(desc.s, " ")] = desc
		end
		if countKeys(stats) > 1 then
			ambiguousTexts = ambiguousTexts + 1
			local names = { }
			for key, desc in pairs(stats) do
				desc.u = usage[desc.s[1]] or { }
				t_insert(names, key)
			end
			table.sort(names)
			t_insert(conflictLog, s_format("[StatDescriptions] %s => %s", text, table.concat(names, " | ")))
		end
	end
	t_insert(summary, s_format("%-24s %6d Chinese texts shared by different stats (ranked by mod usage)", "StatDescriptions", ambiguousTexts))
	writeTable("StatDescriptions.lua", out, "Traditional Chinese stat description templates. s = stat ids, v = variants { l = limits, t = template, p = special functions }, u = mod usage counts (only on ambiguous texts)")
	t_insert(summary, s_format("%-24s %6d descriptors, %d templates", "StatDescriptions", descCount, lineCount))
end

---------------------------------------------------------------------------
-- Data/StatDescriptions/zhTW/{en,tc}/*.lua  (StatDescriber format, for display)
---------------------------------------------------------------------------
do
	-- Same parsing as Export/Scripts/statdesc.lua, but keeps the requested language
	local function parseFile(name, wantLang, dirName)
		local raw = readFile("Metadata/StatDescriptions/" .. name .. ".txt")
		if not raw then
			return nil
		end
		local text = convertUTF16to8(raw):gsub("^\239\187\191", "")
		local statDescriptor = { }
		local curDescriptor = { }
		local curLang, langName
		local prepend
		for line in text:gmatch("[^\r\n]+") do
			if prepend then
				line = prepend .. line
				prepend = nil
			end
			local parent = line:match('include "Metadata/StatDescriptions/(.+)%.txt"$')
			if parent then
				statDescriptor.parent = dirName .. "/" .. parent
			else
				local noDesc = line:match("no_description ([%w_%+%-%%]+)")
				if noDesc then
					t_insert(statDescriptor, { stats = { noDesc } })
					statDescriptor[noDesc] = #statDescriptor
				elseif line:match("handed_description") or (line:match("description") and not line:match("_description")) then
					curLang = { }
					langName = "English"
					curDescriptor = { curLang, name = line:match("description ([%w_]+)") }
					t_insert(statDescriptor, curDescriptor)
				elseif not curDescriptor.stats then
					local stats = line:match("%d+%s+([%w_%+%-%% ]+)")
					if stats then
						curDescriptor.stats = { }
						for stat in stats:gmatch("[%w_%+%-%%]+") do
							t_insert(curDescriptor.stats, stat)
							statDescriptor[stat] = #statDescriptor
						end
					else
						prepend = line
					end
				else
					local l = line:match('lang "(.+)"')
					if l then
						langName = l
					elseif langName == wantLang and not line:match("table_only") then
						local statLimits, quality, descText, special = line:match('([%d%-#| !]+)%s*([%w_]*)%s*"(.-)"%s*(.*)')
						if statLimits then
							local desc = { text = escapeGGGString(descText), limit = { } }
							for statLimit in statLimits:gmatch("[!%d%-#|]+") do
								local limit = { }
								if statLimit == "#" then
									limit[1], limit[2] = "#", "#"
								elseif statLimit:match("^%-?%d+$") then
									limit[1], limit[2] = tonumber(statLimit), tonumber(statLimit)
								else
									local negate = statLimit:match("^!(-?%d+)$")
									if negate then
										limit[1], limit[2] = "!", tonumber(negate)
									else
										limit[1], limit[2] = statLimit:match("([%d%-#]+)|([%d%-#]+)")
										limit[1] = tonumber(limit[1]) or limit[1]
										limit[2] = tonumber(limit[2]) or limit[2]
									end
								end
								t_insert(desc.limit, limit)
							end
							local tokens = { }
							for token in special:gmatch("([%w%%_]+)") do
								t_insert(tokens, token)
							end
							local i = 1
							while i <= #tokens do
								local token = tokens[i]
								if token == "canonical_line" then
									i = i + 1
								else
									local value = tokens[i + 1]
									if value then
										t_insert(desc, { k = token, v = tonumber(value) or value })
										i = i + 2
									else
										i = i + 1
									end
								end
							end
							if quality:match("gem_quality") then
								desc[quality] = true
							end
							t_insert(curLang, desc)
						end
					end
				end
			end
		end
		return statDescriptor
	end
	for _, dir in ipairs({ "en", "tc" }) do
		runUnicode("New-Item -ItemType Directory -Force -Path " .. psQuote(GetWorkDir() .. "\\..\\Data\\StatDescriptions\\zhTW\\" .. dir) .. " | Out-Null")
	end
	local done, queue = { }, { }
	for _, name in ipairs(displayStatFiles) do
		t_insert(queue, name)
	end
	local fileCount, missing = 0, { }
	while #queue > 0 do
		local name = table.remove(queue, 1)
		if not done[name] then
			done[name] = true
			for lang, dir in pairs({ English = "en", ["Traditional Chinese"] = "tc" }) do
				local sd = parseFile(name, lang, "zhTW/" .. dir)
				if not sd then
					t_insert(missing, name)
					break
				end
				local out = io.open("../Data/StatDescriptions/zhTW/" .. dir .. "/" .. name .. ".lua", "w")
				out:write("-- This file is automatically generated by Export/Scripts/zhTW.lua, do not edit!\n")
				out:write("-- Item data (c) Grinding Gear Games\n")
				for _, line in ipairs(versionInfo) do
					out:write(line, "\n")
				end
				out:write("\nreturn ")
				writeLuaTable(out, sd, 1)
				out:close()
				if sd.parent then
					local parentName = sd.parent:match("[^/]+$")
					if not done[parentName] then
						-- Parent files must be extracted too
						extract({ "Metadata/StatDescriptions/" .. parentName .. ".txt" })
						t_insert(queue, parentName)
					end
				end
			end
			fileCount = fileCount + 1
		end
	end
	t_insert(summary, s_format("%-24s %6d files (English + Traditional Chinese)%s", "Display stat descs", fileCount, #missing > 0 and (", missing: " .. table.concat(missing, ", ")) or ""))
end

---------------------------------------------------------------------------
-- Summary
---------------------------------------------------------------------------
local report = io.open(OUT_DIR .. "ExportReport.txt", "w")
report:write("zhTW export report\n")
for _, line in ipairs(versionInfo) do
	report:write(line:gsub("^%-%- ", ""), "\n")
end
report:write("\n")
for _, line in ipairs(summary) do
	report:write(line, "\n")
	print(line)
end
report:write("\nName conflicts:\n")
for _, line in ipairs(conflictLog) do
	report:write(line, "\n")
end
report:close()
print("zhTW lookup tables exported.")
