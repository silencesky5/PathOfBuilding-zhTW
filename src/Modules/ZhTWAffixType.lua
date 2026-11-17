-- Path of Building
--
-- Module: zhTW Affix Type
-- Works out whether each explicit modifier of a rare or magic item is a prefix or a suffix,
-- so the item tooltip can show them in two groups like the game's advanced view.
-- Imported items carry no affix information, so the lines are matched against the item's
-- possible mods (Data/ModExplicit etc. through item.affixes, and Data/ModMaster for crafted lines).
--
-- Public API:
--   ZhTWAffixType.group(item)  -- nil, or { { label = "Prefix", modLine, ... }, { label = "Suffix", ... }, { ... } }
--
local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert

local M = { }

-- "+39(36-41) to maximum Mana" / "+(36-41) to maximum Mana" / "+39 to maximum Mana" -> "# to maximum mana"
local function normalise(line)
	return (line:lower()
		:gsub("%-?[%d%.]+%(%-?[%d%.]+%-%-?[%d%.]+%)", "#")
		:gsub("%(%-?[%d%.]+%-%-?[%d%.]+%)", "#")
		:gsub("%-?%d+%.?%d*", "#")
		:gsub("[%+%-]#", "#")
		:gsub("%s+", " "))
end

local indexCache = setmetatable({ }, { __mode = "k" })

-- normalised line -> list of mods that have it
local function getIndex(modTable)
	local index = indexCache[modTable]
	if index then
		return index
	end
	index = { }
	for _, mod in pairs(modTable) do
		if type(mod) == "table" and (mod.type == "Prefix" or mod.type == "Suffix") then
			for _, line in ipairs(mod) do
				local key = normalise(line)
				index[key] = index[key] or { }
				t_insert(index[key], mod)
			end
		end
	end
	indexCache[modTable] = index
	return index
end

local function canHave(item, mod)
	if mod.weightKey then
		local ok, result = pcall(item.CanHaveMod, item, mod)
		return not ok or result
	end
	if mod.types and item.base then
		return mod.types[item.base.type] or (item.base.subType and mod.types[item.base.subType .. " " .. item.base.type])
			or mod.types[item.type] or false
	end
	return true
end

-- Picks the type from the candidate mods; nil when they disagree
local function decide(item, candidates, present)
	local function typeOf(list)
		local t
		for _, mod in ipairs(list) do
			if t and t ~= mod.type then
				return nil
			end
			t = mod.type
		end
		return t
	end
	local possible = { }
	for _, mod in ipairs(candidates) do
		if canHave(item, mod) then
			t_insert(possible, mod)
		end
	end
	if #possible == 0 then
		possible = candidates
	end
	local t = typeOf(possible)
	if t then
		return t
	end
	-- Hybrid mods: prefer the mods whose other lines are on the item too
	local full = { }
	for _, mod in ipairs(possible) do
		local all = #mod > 1
		for _, line in ipairs(mod) do
			if not present[normalise(line)] then
				all = false
				break
			end
		end
		if all then
			t_insert(full, mod)
		end
	end
	if #full > 0 then
		return typeOf(full)
	end
	-- Otherwise the single-line mods
	local single = { }
	for _, mod in ipairs(possible) do
		if #mod == 1 then
			t_insert(single, mod)
		end
	end
	return typeOf(single)
end

function M.getType(item, modLine, present)
	if modLine.prefix then
		return "Prefix"
	elseif modLine.suffix then
		return "Suffix"
	end
	if modLine.custom or modLine.extra and not modLine.crafted then
		return nil
	end
	local key = normalise(modLine.line)
	local candidates
	if modLine.crafted then
		candidates = getIndex(data.masterMods)[key]
	else
		candidates = item.affixes and getIndex(item.affixes)[key]
		if not candidates then
			candidates = getIndex(data.itemMods.Item)[key]
		end
	end
	if not candidates then
		return nil
	end
	return decide(item, candidates, present)
end

function M.group(item)
	if not item or not (item.rarity == "RARE" or item.rarity == "MAGIC") or not item.base or #item.explicitModLines == 0 then
		return nil
	end
	local present = { }
	for _, modLine in ipairs(item.explicitModLines) do
		present[normalise(modLine.line)] = true
	end
	local prefixes, suffixes, other = { label = "Prefix" }, { label = "Suffix" }, { }
	for _, modLine in ipairs(item.explicitModLines) do
		local t = M.getType(item, modLine, present)
		t_insert(t == "Prefix" and prefixes or t == "Suffix" and suffixes or other, modLine)
	end
	if #prefixes == 0 and #suffixes == 0 then
		return nil
	end
	local groups = { }
	for _, g in ipairs({ prefixes, suffixes, other }) do
		if #g > 0 then
			t_insert(groups, g)
		end
	end
	return groups
end

return M
