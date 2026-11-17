-- Path of Building
--
-- Module: zhTW Mods
-- Shows game modifier text (item mods, passive skill stats, gem stats) in Traditional Chinese.
--
-- The reverse of Modules/ZhTWConverter.lua: an English line is matched against the English
-- templates of the Taiwan client (Data/StatDescriptions/zhTW/en), its values are turned back
-- into stat values, and Modules/StatDescriber writes the line with the Chinese templates
-- (Data/StatDescriptions/zhTW/tc). Display only; calculations keep using the English text.
--
local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert
local t_concat = table.concat
local s_format = string.format

local ZhTWMods = { }

local helpers = LoadModule("Modules/ZhTWConverter").internal
local compileTemplate = helpers.compileTemplate
local inverse = helpers.inverse
local nameSpecials = helpers.nameSpecials
local roundInt = helpers.roundInt
local limitOk = helpers.limitOk
local valueForLimit = helpers.valueForLimit

-- Files are tried in this order when several give the same match
local files = {
	"stat_descriptions", "passive_skill_stat_descriptions", "passive_skill_aura_stat_descriptions",
	"tincture_stat_descriptions", "graft_stat_descriptions",
	"skill_stat_descriptions", "gem_stat_descriptions", "active_skill_gem_stat_descriptions",
	"aura_skill_stat_descriptions", "banner_aura_skill_stat_descriptions", "beam_skill_stat_descriptions",
	"brand_skill_stat_descriptions", "buff_skill_stat_descriptions", "curse_skill_stat_descriptions",
	"debuff_skill_stat_descriptions", "secondary_debuff_skill_stat_descriptions",
	"minion_attack_skill_stat_descriptions", "minion_skill_stat_descriptions",
	"minion_spell_skill_stat_descriptions", "minion_spell_damage_skill_stat_descriptions",
	"single_minion_spell_skill_stat_descriptions", "offering_skill_stat_descriptions",
	"variable_duration_skill_stat_descriptions", "monster_stat_descriptions",
}

local compiled -- single-line English templates
local nameLookup -- function(english name) -> Chinese name

local function compileAll()
	if compiled then
		return compiled
	end
	compiled = { }
	local seen = { }
	-- PoB's own English descriptions first: they are exactly what PoB displays, while the
	-- client's English may already use newer wording ("+8% to Item Rarity").
	local sources = { }
	for fileIndex, file in ipairs(files) do
		local f = io.open("Data/StatDescriptions/" .. file .. ".lua", "r")
		if f then
			f:close()
			t_insert(sources, { "Data/StatDescriptions/" .. file, file, fileIndex })
		end
	end
	for fileIndex, file in ipairs(files) do
		t_insert(sources, { "Data/StatDescriptions/zhTW/en/" .. file, file, fileIndex })
	end
	for _, source in ipairs(sources) do
		local file, fileIndex = source[2], source[3]
		local scope = LoadModule(source[1])
		for _, desc in ipairs(scope or { }) do
			if desc.stats and desc[1] then
				for _, variant in ipairs(desc[1]) do
					if not variant.gem_quality then
						local nameIndex = { }
						local specials = { }
						for _, sp in ipairs(variant) do
							if sp.k and type(sp.v) == "number" then
								t_insert(specials, { sp.k, sp.v })
								if nameSpecials[sp.k] then
									nameIndex[sp.v] = sp.k
								end
							end
						end
						-- Each file includes its parent, so the same descriptor appears once per file
						local key = variant.text .. "|" .. t_concat(desc.stats, ",")
						if not seen[key] then
							seen[key] = true
							-- PoB draws each line of a description separately, so every line of a
							-- multi-line description is also matched on its own (partIndex).
							-- Matching ignores case: passive tree text differs in capitals.
							local text = variant.text:lower()
							local parts = { }
							-- (line breaks are real newlines in the generated data files)
							for part in (text:gsub("\\n", "\n") .. "\n"):gmatch("(.-)\n") do
								t_insert(parts, part)
							end
							for partIndex, part in ipairs(parts) do
								local c = compileTemplate(part, nameIndex)
								if c and c.lineCount == 1 and c.fixed >= 4 then
									c.desc = desc
									c.variant = variant
									c.specials = specials
									c.nameIndex = nameIndex
									c.file = file
									c.fileIndex = fileIndex
									if #parts > 1 then
										c.partIndex = partIndex
										c.partCount = #parts
									end
									t_insert(compiled, c)
								end
							end
						end
					end
				end
			end
		end
	end
	-- Longest fixed text first; ties keep file order
	table.sort(compiled, function(a, b)
		if a.fixed ~= b.fixed then
			return a.fixed > b.fixed
		end
		if (a.partIndex ~= nil) ~= (b.partIndex ~= nil) then
			return a.partIndex == nil
		end
		return a.fileIndex < b.fileIndex
	end)
	return compiled
end

local tcScopes = { }
local function getTcScope(file)
	if not tcScopes[file] then
		tcScopes[file] = LoadModule("Data/StatDescriptions/zhTW/tc/" .. file)
	end
	return tcScopes[file]
end

local function sameStats(a, b)
	if #a ~= #b then
		return false
	end
	for i = 1, #a do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

-- Chinese line for descriptors with name placeholders (StatDescriber can't do these)
local function renderNamed(c, values, names)
	local scope = getTcScope(c.file)
	local idx = scope[c.desc.stats[1]]
	local desc = idx and scope[idx]
	if not desc or not desc.stats or not sameStats(desc.stats, c.desc.stats) then
		return nil
	end
	for _, variant in ipairs(desc[1] or { }) do
		local ok = not variant.gem_quality
		for i, limit in ipairs(variant.limit) do
			if ok and not limitOk(limit, values[i] or 0) then
				ok = false
			end
		end
		if ok then
			local text = variant.text:gsub("{(%d*):?(%+?)d?}", function(n, plus)
				local i = (tonumber(n) or 0) + 1
				if names[i] then
					return names[i]
				end
				return s_format(plus == "+" and "%+d" or "%d", values[i] or 0)
			end):gsub("%%%%", "%%")
			if not text:find("\\n", 1, true) then
				return text
			end
		end
	end
end

local describer

local function tryCandidate(c, caps)
	local desc, variant = c.desc, c.variant
	local values, names, shown = { }, { }, { }
	for capIndex, placeholder in ipairs(c.order) do
		local i = placeholder + 1
		local raw = caps[capIndex]
		shown[i] = true
		if c.nameIndex[i] then
			local zh = nameLookup and nameLookup(raw)
			if not zh then
				return nil
			end
			names[i] = zh
			values[i] = 1
		else
			local num = tonumber((raw:gsub(",", "")))
			if not num then
				return nil
			end
			values[i] = num
		end
	end
	for k = #c.specials, 1, -1 do
		local name, statIndex = c.specials[k][1], c.specials[k][2]
		if not nameSpecials[name] and values[statIndex] and shown[statIndex] and inverse[name] then
			values[statIndex] = inverse[name](values[statIndex])
		end
	end
	for i = 1, #desc.stats do
		if values[i] then
			if not names[i] then
				values[i] = roundInt(values[i])
			end
		else
			values[i] = valueForLimit(variant.limit[i] or { "#", "#" }, #c.order == 0)
		end
		local limit = variant.limit[i]
		if limit and not names[i] and not limitOk(limit, values[i]) then
			return nil
		end
	end
	if next(names) then
		return renderNamed(c, values, names)
	end
	describer = describer or LoadModule("Modules/StatDescriber")
	local stats = { }
	local any = false
	for i, stat in ipairs(desc.stats) do
		if values[i] ~= 0 then
			stats[stat] = values[i]
			any = true
		end
	end
	if not any then
		return nil
	end
	local ok, lines = pcall(describer, stats, "zhTW/tc/" .. c.file)
	if not ok or not lines then
		return nil
	end
	local out = { }
	for _, l in ipairs(lines) do
		for part in (l .. "\n"):gmatch("(.-)\n") do
			t_insert(out, part)
		end
	end
	if c.partIndex then
		-- One line of a multi-line description: take the same line of the Chinese text
		if #out ~= c.partCount then
			return nil
		end
		return out[c.partIndex]
	end
	if #out ~= 1 then
		return nil
	end
	return out[1]
end

local function translateSingle(line)
	line = line:lower()
	for _, c in ipairs(compileAll()) do
		if line:find(c.anchor, 1, true) then
			local caps = { line:match(c.pattern) }
			if caps[1] ~= nil then
				local zh = tryCandidate(c, caps)
				if zh then
					return zh
				end
			end
		end
	end
end

-- Lines with value ranges like "(100-150)% increased Armour": translate the line with the
-- minimum and with the maximum values, then put the ranges back where the numbers differ.
local RANGE = "%((%-?[%d%.]+)%-(%-?[%d%.]+)%)"
local function translateRange(line)
	local lo = line:gsub(RANGE, "%1")
	local hi = line:gsub(RANGE, "%2")
	local zhLo, zhHi = translateSingle(lo), translateSingle(hi)
	if not zhLo or not zhHi then
		return nil
	end
	local numPat = "%-?%d+%.?%d*"
	local partsLo, partsHi = { }, { }
	local textLo = zhLo:gsub(numPat, function(n) t_insert(partsLo, n) return "\0" end)
	local textHi = zhHi:gsub(numPat, function(n) t_insert(partsHi, n) return "\0" end)
	if textLo ~= textHi or #partsLo ~= #partsHi then
		return nil
	end
	local i = 0
	return (textLo:gsub("%z", function()
		i = i + 1
		local a, b = partsLo[i], partsHi[i]
		if a == b then
			return a
		end
		if a:sub(1, 1) == "-" and b:sub(1, 1) == "-" then
			return "-(" .. a:sub(2) .. "-" .. b:sub(2) .. ")"
		end
		return "(" .. a .. "-" .. b .. ")"
	end))
end

-- Fixed English prefixes that wrap another modifier
local prefixes = {
	{ en = "Added Small Passive Skills grant: ", zh = "附加的小型天賦給予：" },
	{ en = "Added Small Passive Skills also grant: ", zh = "附加的小天賦給予：" },
}

-- English modifier line -> Chinese, or nil
function ZhTWMods.translate(line)
	if #line < 4 then
		return nil
	end
	local zh
	if line:find(RANGE) then
		zh = translateRange(line)
	else
		zh = translateSingle(line)
	end
	if zh then
		return zh
	end
	for _, p in ipairs(prefixes) do
		if line:sub(1, #p.en) == p.en then
			local inner = ZhTWMods.translate(line:sub(#p.en + 1))
			if inner then
				return p.zh .. inner
			end
		end
	end
	return nil
end

-- Names are looked up without case (the line is matched in lower case)
function ZhTWMods.setNameLookup(func, names)
	local lower = { }
	for en, zh in pairs(names or { }) do
		lower[en:lower()] = zh
	end
	nameLookup = function(en)
		return func(en) or lower[en:lower()]
	end
end

return ZhTWMods
