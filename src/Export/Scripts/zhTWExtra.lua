-- zhTW: extra Taiwan client tables (timeless jewels, tattoos, gem descriptions)
--
-- Output:
--   src/Data/zhTW/Legion.lua            Timeless jewel generals / factions / line templates,
--                                       timeless jewel passive names, tattoo passive names
--   src/Data/zhTW/GemDescriptions.lua   granted effect id -> Traditional Chinese description
--
-- Like the other zhTW exports, every table pairs row N of "Data/X.datc64" with row N of
-- "Data/Traditional Chinese/X.datc64".
--
-- Headless: set ZHTW_GGPK (see Export/zhTWRun.lua) and ZHTW_SCRIPT=Scripts/zhTWExtra.lua
-- Run after Scripts/zhTW.lua: the timeless line templates are read from its stat description output.

local t_insert = table.insert
local s_format = string.format
local LANG = "Traditional Chinese"
local OUT_DIR = "../Data/zhTW/"

local ggpk = main.ggpk
if not ggpk or not ggpk.oozPath then
	print("zhTW: GGPK source is not set")
	return
end

-- AlternateTreeVersionKeystones has no spec in Export/spec.lua: one row per general
-- (tree version, keystone index 1-3, "v2" flag for the newer generals, display name)
main.datSpecs.alternatetreeversionkeystones = {
	{ list = false, name = "AlternateTreeVersion", refTo = "AlternateTreeVersions", type = "Key", width = 150 },
	{ list = false, name = "Index", refTo = "", type = "Int", width = 80 },
	{ list = false, name = "Name", refTo = "", type = "String", width = 150 },
	{ list = false, name = "Version2", refTo = "", type = "Int", width = 80 },
}

-- AlternateTreeVersions: the faction name ("Karui") follows the spec's last column (byte 38 of 46)
do
	local spec = main.datSpecs.alternatetreeversions
	if spec and #spec == 7 then
		t_insert(spec, { list = false, name = "Name", refTo = "", type = "String", width = 150 })
	end
end

local datNames = {
	"AlternateTreeVersions", "AlternateTreeVersionKeystones", "AlternatePassiveSkills",
	"PassiveSkillOverrides", "GemEffects", "GrantedEffects", "ActiveSkills",
}

-- UTF-8 -> UTF-16LE, for PowerShell -EncodedCommand (same as Scripts/zhTW.lua)
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

local function runUnicode(psCommand)
	local base64 = require("base64")
	return os.execute("powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand " .. base64.encode(utf8to16le(psCommand)))
end

local function psQuote(s)
	return "'" .. s:gsub("'", "''") .. "'"
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

if ggpk.path and ggpk.path ~= "" then
	local manifest = ggpk.oozPath .. "zhTW_extract_list.txt"
	local f = assert(io.open(manifest, "w"))
	for _, name in ipairs(datNames) do
		f:write(("Data/" .. name .. ".datc64"):lower(), "\n")
		f:write(("Data/" .. LANG .. "/" .. name .. ".datc64"):lower(), "\n")
	end
	f:close()
	runUnicode("Set-Location -LiteralPath " .. psQuote(ggpk.oozPath) ..
		"; Get-Content -LiteralPath " .. psQuote(manifest) ..
		" | & .\\bun_extract_file.exe extract-files " .. psQuote(ggpk.path) .. " .")
	os.remove(manifest)
end

-- English tables are registered for references (row.GrantedEffect.Id etc.); Chinese ones are paired by row
local en, tc = { }, { }
for _, name in ipairs(datNames) do
	local enRaw = readFile("Data/" .. name .. ".datc64")
	local tcRaw = readFile("Data/" .. LANG .. "/" .. name .. ".datc64")
	if not enRaw or not tcRaw then
		print("zhTW: missing " .. name .. ".datc64 (English or " .. LANG .. ")")
		return
	end
	en[name] = new("Dat64File"):Dat64File(name, enRaw)
	main.datFileByName[name:lower()] = en[name]
	tc[name] = new("Dat64File"):Dat64File(name, tcRaw)
	if en[name].rowCount ~= tc[name].rowCount then
		print(s_format("zhTW: WARNING %s row count mismatch (%d vs %d)", name, en[name].rowCount, tc[name].rowCount))
	end
end

local function trim(s)
	return type(s) == "string" and (s:gsub("^%s+", ""):gsub("%s+$", "")) or s
end
local function stripLinks(s)
	if type(s) ~= "string" or not s:find("[", 1, true) then
		return s
	end
	return (s:gsub("%[([^%[%]|]+)|([^%[%]]+)%]", "%2"):gsub("%[([^%[%]|]+)%]", "%1"))
end
local function clean(s)
	return trim(stripLinks(s and s:gsub("\r", "")))
end
local function isChinese(s)
	return type(s) == "string" and s:find("[\128-\255]") ~= nil
end
local function rows(name)
	local i = 0
	local n = math.min(en[name].rowCount, tc[name].rowCount)
	return function()
		i = i + 1
		if i <= n then
			return i, en[name]:GetRowByIndex(i), tc[name]:GetRowByIndex(i)
		end
	end
end
local function countKeys(t)
	local n = 0
	for _ in pairs(t) do n = n + 1 end
	return n
end

local function writeTable(fileName, tbl, comment)
	local out = io.open(OUT_DIR .. fileName, "w")
	out:write("-- This file is automatically generated by Export/Scripts/zhTWExtra.lua, do not edit!\n")
	out:write("-- Item data (c) Grinding Gear Games\n")
	out:write("-- Source: ", tostring(ggpk.path or ggpk.oozPath), "\n")
	out:write("-- Exported: ", os.date("%Y-%m-%d %H:%M"), "\n")
	out:write("-- ", comment, "\n")
	out:write("\nreturn ")
	writeLuaTable(out, tbl, 1)
	out:write("\n")
	out:close()
end

---------------------------------------------------------------------------
-- Legion.lua
---------------------------------------------------------------------------
local legion = { factions = { }, generals = { }, templates = { }, passives = { }, tattoos = { } }

-- Tree versions: 1 Vaal, 2 Karui, 3 Maraketh, 4 Templar, 5 Eternal, 6 Kalguur, 7+ Abyss
local versionName = { }
for i, enRow, tcRow in rows("AlternateTreeVersions") do
	local enName, zhName = clean(enRow.Name), clean(tcRow.Name)
	versionName[i - 1] = enName
	if enName and enName ~= "" and isChinese(zhName) and enName ~= "None" then
		legion.factions[zhName] = enName
	end
end

-- Generals, keyed by tree version / keystone index / v2 flag
local generalByKey = { }
for _, enRow, tcRow in rows("AlternateTreeVersionKeystones") do
	local version = enRow.AlternateTreeVersion and (enRow.AlternateTreeVersion._rowIndex - 1)
	local enName, zhName = clean(enRow.Name), clean(tcRow.Name)
	if version and enName and enName ~= "" then
		generalByKey[s_format("%d/%d/%d", version, enRow.Index, enRow.Version2)] = enName
		if isChinese(zhName) then
			legion.generals[zhName] = { en = enName, version = version, index = enRow.Index, v2 = enRow.Version2 == 1 or nil }
		end
	end
end

-- Line templates from the exported stat descriptions (Scripts/zhTW.lua output, same row order)
local enDesc = LoadModule("../Data/StatDescriptions/zhTW/en/stat_descriptions")
local tcDesc = LoadModule("../Data/StatDescriptions/zhTW/tc/stat_descriptions")
local function escapePattern(s)
	return (s:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%0"))
end
local function variantLimit(variant, i)
	local l = variant.limit and variant.limit[i]
	return l and type(l[1]) == "number" and l[1] or nil
end
local function isGeneric(variant)
	for _, h in ipairs(variant) do
		if h.k == "alternate_tree_version_keystone" then
			return true
		end
	end
	return false
end
local templateSeen = { }
local specificNames = 0
local genericByVersion = { }
local timelessDescs = { }
for di, desc in ipairs(enDesc or { }) do
	local tcd = tcDesc and tcDesc[di]
	if desc.stats and desc.stats[1] == "local_unique_jewel_alternate_tree_version" and tcd and tcd.stats
		and tcd.stats[1] == desc.stats[1] and desc[1] and tcd[1] then
		t_insert(timelessDescs, { desc, tcd })
		for vi, enVariant in ipairs(desc[1]) do
			local tcVariant = tcd[1][vi]
			if tcVariant and isGeneric(enVariant) and isGeneric(tcVariant) and enVariant.text and tcVariant.text
				and variantLimit(enVariant, 1) == variantLimit(tcVariant, 1) then
				local version = variantLimit(enVariant, 1)
				local enLines, tcLines = { }, { }
				for line in (enVariant.text .. "\n"):gmatch("([^\n]*)\n") do t_insert(enLines, line) end
				for line in (clean(tcVariant.text) .. "\n"):gmatch("([^\n]*)\n") do t_insert(tcLines, line) end
				if #enLines == #tcLines then
					for li = 1, #enLines do
						local key = tcLines[li] .. "|" .. enLines[li]
						if not templateSeen[key] then
							templateSeen[key] = true
							t_insert(legion.templates, { zh = tcLines[li], en = enLines[li] })
						end
					end
					if version then
						genericByVersion[version] = clean(tcVariant.text)
					end
				end
			end
		end
	end
end
-- Specific variants write the general into the text ("受到神主感化"), sometimes with a
-- different name than the keystone table: learn those names too. Only the Chinese file has
-- these variants, so their own limits say which general they are.
for _, pair in ipairs(timelessDescs) do
	local tcd = pair[2]
	do
		for _, tcVariant in ipairs(tcd[1]) do
			local version = variantLimit(tcVariant, 1)
			local generic = version and genericByVersion[version]
			if not isGeneric(tcVariant) and generic and tcVariant.text then
				local index, v2 = variantLimit(tcVariant, 3), variantLimit(tcVariant, 4) or 0
				local parts, order, pos = { "^" }, { }, 1
				while true do
					local a, b, n = generic:find("{(%d)}", pos)
					if not a then
						t_insert(parts, escapePattern(generic:sub(pos)))
						break
					end
					t_insert(parts, escapePattern(generic:sub(pos, a - 1)))
					t_insert(parts, n == "1" and "%s*{1}%s*" or "(.-)")
					if n ~= "1" then
						t_insert(order, n)
					end
					pos = b + 1
				end
				t_insert(parts, "$")
				local caps = { clean(tcVariant.text):match(table.concat(parts)) }
				for ci, n in ipairs(order) do
					local zh = caps[ci] and trim(caps[ci])
					if zh and zh ~= "" then
						if n == "0" and versionName[version] and not legion.factions[zh] then
							legion.factions[zh] = versionName[version]
						elseif n == "2" and index then
							local enName = generalByKey[s_format("%d/%d/%d", version, index, v2)]
							if enName and not legion.generals[zh] then
								legion.generals[zh] = { en = enName, version = version, index = index, v2 = v2 == 1 or nil }
								specificNames = specificNames + 1
							end
						end
					end
				end
			end
		end
	end
end

-- Timeless jewel passives (names shown on conquered nodes) and tattoo passives
local function addName(map, zh, enName)
	zh, enName = clean(zh), clean(enName)
	if not enName or enName == "" or not isChinese(zh) or zh == enName then
		return
	end
	local old = map[zh]
	if old == nil then
		map[zh] = enName
	elseif type(old) == "string" and old ~= enName then
		map[zh] = { old, enName }
	elseif type(old) == "table" then
		for _, e in ipairs(old) do
			if e == enName then return end
		end
		t_insert(old, enName)
	end
end
for _, enRow, tcRow in rows("AlternatePassiveSkills") do
	addName(legion.passives, tcRow.Name, enRow.Name)
end
for _, enRow, tcRow in rows("PassiveSkillOverrides") do
	addName(legion.tattoos, tcRow.Name, enRow.Name)
end

writeTable("Legion.lua", legion, "Timeless jewels (generals, factions, line templates, conquered passive names) and tattoo passive names: Traditional Chinese -> English")
print(s_format("zhTW: Legion: %d factions, %d generals (%d from description variants), %d templates, %d timeless passives, %d tattoos",
	countKeys(legion.factions), countKeys(legion.generals), specificNames, #legion.templates, countKeys(legion.passives), countKeys(legion.tattoos)))

---------------------------------------------------------------------------
-- GemDescriptions.lua: granted effect id -> Chinese description
-- PoB's own English description can differ from the client's (older text, line breaks), so the
-- English-text lookup in Display.lua misses some; this one is keyed by granted effect id.
---------------------------------------------------------------------------
local gemDesc = { }
local function addDesc(id, zh, overwrite)
	zh = clean(zh)
	if id and isChinese(zh) and (overwrite or not gemDesc[id]) then
		gemDesc[id] = zh
	end
end
-- Active skills: ActiveSkills.Description through GrantedEffects.ActiveSkill
for enRow in en.GrantedEffects:Rows() do
	local active = enRow.ActiveSkill
	if active and not enRow.IsSupport then
		local tcActive = tc.ActiveSkills:GetRowByIndex(active._rowIndex)
		addDesc(enRow.Id, tcActive and tcActive.Description)
	end
end
-- Gems: GemEffects.Description (supports, and actives without their own text)
for _, enRow, tcRow in rows("GemEffects") do
	for _, col in ipairs({ "GrantedEffect", "GrantedEffect2" }) do
		local ge = enRow[col]
		if ge and ge.Id then
			addDesc(ge.Id, tcRow.Description, ge.IsSupport)
		end
	end
end
writeTable("GemDescriptions.lua", gemDesc, "Skill gem descriptions: granted effect id -> Traditional Chinese")
print(s_format("zhTW: %d gem descriptions", countKeys(gemDesc)))
