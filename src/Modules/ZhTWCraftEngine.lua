-- Path of Building
--
-- Module: zhTW Craft Engine
-- Crafting rules for the 製作 tab, ported from the crafting site's craft-engine.js (Poe-tool;
-- currency rules after Kalandralang, MIT). No drawing: the tab (Classes/ZhTWCraftTab.lua) and
-- the test (zhTWCraftTest.lua) use it. Data: Data/zhTW/CraftData.lua (Export/zhTWCraftData.py).
--
-- Item: { b = base index, lv = item level, r = 0 normal / 1 magic / 2 rare,
--         mods = { { m = mod index, v = { rolled values } } } }   (indices are 1-based here)
-- Saved / shared form (same as the site): toStored / fromStored use the RePoE base and mod ids.
--
-- Ported in this stage: the ten basic currencies, essences, fossils with resonators, tiers,
-- mod text, the mod pool view, and conversion to PoB item text. Not yet: harvest, the crafting
-- bench and the batch simulator.
--
local m_floor = math.floor
local m_min = math.min
local m_max = math.max
local t_insert = table.insert
local t_remove = table.remove
local t_sort = table.sort
local s_format = string.format

local NORMAL, MAGIC, RARE = 0, 1, 2
local RARITY_ZH = { [0] = "普通", "魔法", "稀有" }

local CURRENCIES = {
	{ k = "transmute", zh = "蛻變石", en = "Orb of Transmutation", desc = "普通 → 魔法，隨機 1～2 條詞綴（各 50%，社群推定值）" },
	{ k = "alt", zh = "改造石", en = "Orb of Alteration", desc = "魔法物品重抽，隨機 1～2 條詞綴（各 50%，社群推定值）" },
	{ k = "aug", zh = "增幅石", en = "Orb of Augmentation", desc = "魔法物品補 1 條詞綴" },
	{ k = "regal", zh = "富豪石", en = "Regal Orb", desc = "魔法 → 稀有，保留原詞綴並加 1 條" },
	{ k = "alch", zh = "點金石", en = "Orb of Alchemy", desc = "普通 → 稀有，隨機 4～6 條詞綴（機率 8 : 3 : 1，社群推定值）" },
	{ k = "chaos", zh = "混沌石", en = "Chaos Orb", desc = "稀有物品重抽，隨機 4～6 條詞綴（機率 8 : 3 : 1，社群推定值）" },
	{ k = "exalt", zh = "崇高石", en = "Exalted Orb", desc = "稀有物品加 1 條詞綴" },
	{ k = "annul", zh = "無效石", en = "Orb of Annulment", desc = "隨機拿掉 1 條詞綴（稀有度不變）" },
	{ k = "scour", zh = "重鑄石", en = "Orb of Scouring", desc = "清空所有詞綴，變回普通" },
	{ k = "divine", zh = "神聖石", en = "Divine Orb", desc = "重骰所有詞綴的數值，詞綴本身不變" },
}
local CUR = { }
for _, c in ipairs(CURRENCIES) do
	CUR[c.k] = c
end

-- stat_translations index_handlers
local function round(v)
	return m_floor(v + 0.5)
end
local HANDLERS = {
	negate = function(v) return -v end, double = function(v) return v * 2 end,
	negate_and_double = function(v) return -v * 2 end, times_twenty = function(v) return v * 20 end,
	times_one_point_five = function(v) return v * 1.5 end, canonical_stat = function(v) return v end,
	divide_by_one_hundred = function(v) return v / 100 end, divide_by_one_hundred_2dp = function(v) return v / 100 end,
	divide_by_one_hundred_2dp_if_required = function(v) return v / 100 end,
	milliseconds_to_seconds = function(v) return v / 1000 end, milliseconds_to_seconds_0dp = function(v) return round(v / 1000) end,
	milliseconds_to_seconds_1dp = function(v) return v / 1000 end, milliseconds_to_seconds_2dp = function(v) return v / 1000 end,
	milliseconds_to_seconds_2dp_if_required = function(v) return v / 1000 end,
	per_minute_to_per_second = function(v) return v / 60 end, per_minute_to_per_second_0dp = function(v) return round(v / 60) end,
	per_minute_to_per_second_1dp = function(v) return v / 60 end, per_minute_to_per_second_2dp = function(v) return v / 60 end,
	per_minute_to_per_second_2dp_if_required = function(v) return v / 60 end,
	divide_by_ten_0dp = function(v) return round(v / 10) end, divide_by_ten_1dp = function(v) return v / 10 end,
	divide_by_ten_1dp_if_required = function(v) return v / 10 end,
	locations_to_metres = function(v) return v / 10 end, deciseconds_to_seconds = function(v) return v / 10 end,
	divide_by_two_0dp = function(v) return round(v / 2) end, divide_by_five = function(v) return v / 5 end,
	divide_by_six = function(v) return v / 6 end, divide_by_twelve = function(v) return v / 12 end,
	divide_by_one_thousand = function(v) return v / 1000 end,
	["30%_of_value"] = function(v) return v * 0.3 end, ["60%_of_value"] = function(v) return v * 0.6 end,
	old_leech_percent = function(v) return v / 5 end, old_leech_permyriad = function(v) return v / 50 end,
	["permyriad_per_minute_to_%_per_second"] = function(v) return v / 6000 end,
}
local function fmtNum(v)
	if v == m_floor(v) then
		return tostring(m_floor(v))
	end
	local r = round(v * 100) / 100
	if r == m_floor(r) then
		return tostring(m_floor(r))
	end
	return (s_format("%.2f", r):gsub("0+$", ""))
end

local function contains(list, x)
	for _, y in ipairs(list) do
		if y == x then
			return true
		end
	end
	return false
end

-- JSON null comes through the data converter as false inside lists
local function val(x)
	if x == false then
		return nil
	end
	return x
end

local function create(D)
	local tagId = { }
	for i, t in ipairs(D.tags) do
		tagId[t] = i - 1 -- tag numbers in the data are 0-based
	end
	local bases, baseById = { }, { }
	for i, b in ipairs(D.bases) do
		local x = setmetatable({ i = i, ts = { } }, { __index = b })
		for _, t in ipairs(b.t) do
			x.ts[t] = true
		end
		bases[i] = x
		if b.id then
			baseById[b.id] = x
		end
	end
	local META_GROUP = { ItemGenerationCannotChangePrefixes = "PL", ItemGenerationCannotChangeSuffixes = "SL",
		ItemGenerationCannotRollAttackAffixes = "NA", ItemGenerationCannotRollCasterAffixes = "NC", ItemGenerationCanHaveMultipleCraftedMods = "MM" }
	local mods, modById = { }, { }
	for i, m in ipairs(D.mods) do
		local x = setmetatable({ i = i, pre = m.g == "p", grs = { }, atk = contains(m.tg or { }, "attack"), cst = contains(m.tg or { }, "caster") }, { __index = m })
		for _, g in ipairs(m.gr) do
			x.grs[g] = true
			if m.d == "c" and META_GROUP[g] and not x.meta then
				x.meta = META_GROUP[g]
			end
		end
		mods[i] = x
		modById[m.id] = x
	end
	local essences, essByKey = { }, { }
	for i, e in ipairs(D.essences or { }) do
		local x = setmetatable({ i = i, k = "ess:" .. e.id }, { __index = e })
		essences[i] = x
		essByKey[x.k] = x
	end
	local fossils, fosByKey, fosById = { }, { }, { }
	for i, f in ipairs(D.fossils or { }) do
		local x = setmetatable({ i = i, k = "fos:" .. f.id, addSet = { }, forceList = { } }, { __index = f })
		for _, mi in ipairs(f.add) do
			x.addSet[mi + 1] = true
		end
		for _, mi in ipairs(f.force) do
			t_insert(x.forceList, mi + 1)
		end
		fossils[i] = x
		fosByKey[x.k] = x
		fosById[f.id] = x
	end
	local resonators = D.resonators or { }
	local MAX_FOSSILS = 1
	for _, r in ipairs(resonators) do
		MAX_FOSSILS = m_max(MAX_FOSSILS, r.s or 0)
	end
	local fossilMode = "add"
	local poolCache, poolCacheSize = { }, 0

	local function setFossilMode(mode)
		mode = mode == "mul" and "mul" or "add"
		if mode ~= fossilMode then
			fossilMode = mode
			poolCache, poolCacheSize = { }, 0
		end
	end

	-- weight factor of mod m under these fossils (0 = not allowed)
	local function fossilFactor(m, fs)
		local more, less = { }, 1
		for _, f in ipairs(fs) do
			local lf, mf = 1, 0
			for _, tw in ipairs(f.neg) do
				if contains(m.tg, tw[1]) then
					if tw[2] == 0 then
						return 0
					end
					lf = m_min(lf, tw[2])
				end
			end
			for _, tw in ipairs(f.pos) do
				if contains(m.tg, tw[1]) then
					mf = m_max(mf, tw[2])
				end
			end
			if mf ~= 0 then
				t_insert(more, mf)
			end
			less = less * lf
		end
		local mo = 1
		if #more > 0 then
			mo = fossilMode == "mul" and 1 or 0
			for _, x in ipairs(more) do
				if fossilMode == "mul" then mo = mo * x else mo = mo + x end
			end
		end
		return mo * less
	end

	-- spawn weight: first tag in the list that the item has; times the generation weight (percent)
	local function firstMatch(list, ts)
		for _, tw in ipairs(list) do
			if ts[tw[1]] then
				return tw[2]
			end
		end
		return nil
	end
	local function weightOf(m, ts)
		local w = firstMatch(m.sw, ts)
		if not w or w <= 0 then
			return 0
		end
		local g = firstMatch(m.gw, ts)
		if not g then
			return w
		end
		local x = m_floor(w * g / 100)
		return x > 0 and x or 0
	end

	-- tags of the item: base tags plus tags added by its mods (e.g. has_attack_mod)
	local function addedTags(item)
		local a
		for _, x in ipairs(item.mods) do
			local at = mods[x.m].at
			if at and #at > 0 then
				a = a or { }
				for _, t in ipairs(at) do
					a[t] = true
				end
			end
		end
		return a
	end
	local function tagSet(item)
		local a = addedTags(item)
		if not a then
			return bases[item.b].ts
		end
		local s = { }
		for t in pairs(bases[item.b].ts) do
			s[t] = true
		end
		for t in pairs(a) do
			s[t] = true
		end
		return s
	end
	local function tagKey(item)
		local a = addedTags(item)
		if not a then
			return ""
		end
		local l = { }
		for t in pairs(a) do
			t_insert(l, t)
		end
		t_sort(l)
		return table.concat(l, ",")
	end

	-- mod pool for base, item level and added tags (mods already on the item not considered yet)
	local function basePool(item, fs)
		local key = item.b .. "|" .. item.lv .. "|" .. tagKey(item)
		if fs and #fs > 0 then
			local ids = { }
			for _, f in ipairs(fs) do
				t_insert(ids, f.i)
			end
			key = key .. "|" .. fossilMode .. ":" .. table.concat(ids, ",")
		end
		local p = poolCache[key]
		if p then
			return p
		end
		local ts = tagSet(item)
		local list, cum, total = { }, { }, 0
		for _, m in ipairs(mods) do
			if m.lv <= item.lv then
				local inPool = not m.d
				if m.d == "f" and fs then
					for _, f in ipairs(fs) do
						if f.addSet[m.i] then
							inPool = true
						end
					end
				end
				if inPool then
					local w = weightOf(m, ts)
					if w > 0 and fs and #fs > 0 then
						w = m_floor(w * fossilFactor(m, fs))
					end
					if w > 0 then
						t_insert(list, { m = m.i, w = w })
						total = total + w
						t_insert(cum, total)
					end
				end
			end
		end
		p = { list = list, cum = cum, total = total }
		if poolCacheSize > 400 then
			poolCache, poolCacheSize = { }, 0
		end
		poolCache[key] = p
		poolCacheSize = poolCacheSize + 1
		return p
	end

	local function maxSide(item)
		return item.r == RARE and 3 or item.r == MAGIC and 1 or 0
	end
	local function counts(item)
		local p, s = 0, 0
		for _, x in ipairs(item.mods) do
			if mods[x.m].pre then p = p + 1 else s = s + 1 end
		end
		return { p = p, s = s }
	end
	local function hasGroup(item, m)
		for _, x in ipairs(item.mods) do
			for _, g in ipairs(mods[x.m].gr) do
				if m.grs[g] then
					return true
				end
			end
		end
		return false
	end
	local function metaOf(item)
		local f, any = { }, false
		for _, x in ipairs(item.mods) do
			local k = mods[x.m].meta
			if k then
				f[k] = true
				any = true
			end
		end
		return any and f or nil
	end
	local function allowed(item, m, c, max, f)
		if m.pre and c.p >= max or (not m.pre) and c.s >= max then
			return false
		end
		if f and ((f.NA and m.atk) or (f.NC and m.cst)) then
			return false
		end
		return not hasGroup(item, m)
	end
	local function canRemove(m, f, roll)
		if not f then
			return true
		end
		if f.PL and m.pre then return false end
		if f.SL and not m.pre then return false end
		if roll and ((f.NA and m.atk) or (f.NC and m.cst)) then return false end
		return true
	end
	local function filterMods(item, keep)
		local out = { }
		for _, x in ipairs(item.mods) do
			if keep(x) then
				t_insert(out, x)
			end
		end
		return out
	end
	local function strip(item, roll)
		local f = metaOf(item)
		item.mods = filterMods(item, function(x) return not canRemove(mods[x.m], f, roll) end)
	end
	local function removable(item, roll)
		local f = metaOf(item)
		return filterMods(item, function(x) return canRemove(mods[x.m], f, roll) end)
	end
	local function rerollable(item)
		return removable(item, false)
	end
	local function capped(item, cap)
		if cap and cap > 0 and cap < item.lv then
			return { b = item.b, lv = cap, mods = item.mods }
		end
		return item
	end
	local function pool(item, cap, fs)
		local bp, c, max, f = basePool(capped(item, cap), fs), counts(item), maxSide(item), metaOf(item)
		local out = { }
		for _, x in ipairs(bp.list) do
			if allowed(item, mods[x.m], c, max, f) then
				t_insert(out, x)
			end
		end
		return out
	end
	local function pickFrom(pl, rng)
		local t = 0
		for _, x in ipairs(pl) do
			t = t + x.w
		end
		local r = rng() * t
		for _, x in ipairs(pl) do
			r = r - x.w
			if r < 0 then
				return x.m
			end
		end
		return pl[#pl].m
	end
	-- weighted pick; rejection sampling on the cached pool first (same result as the filtered pool)
	local function pickMod(item, rng, cap, fs)
		local bp = basePool(capped(item, cap), fs)
		if #bp.list == 0 then
			return nil
		end
		local c, max, f = counts(item), maxSide(item), metaOf(item)
		for _ = 1, 40 do
			local r = rng() * bp.total
			local lo, hi = 1, #bp.cum
			while lo < hi do
				local mid = m_floor((lo + hi) / 2)
				if bp.cum[mid] > r then hi = mid else lo = mid + 1 end
			end
			local m = mods[bp.list[lo].m]
			if allowed(item, m, c, max, f) then
				return m.i
			end
		end
		local pl = pool(item, cap, fs)
		if #pl == 0 then
			return nil
		end
		return pickFrom(pl, rng)
	end
	local function rollValues(m, rng)
		local v = { }
		for i, st in ipairs(m.st) do
			local lo, hi = m_min(st[2], st[3]), m_max(st[2], st[3])
			v[i] = lo + m_floor(rng() * (hi - lo + 1))
		end
		return v
	end
	local function addMod(item, mi, rng)
		t_insert(item.mods, { m = mi, v = rollValues(mods[mi], rng) })
	end
	local function spawn(item, rng, cap, fs)
		local mi = pickMod(item, rng, cap, fs)
		if not mi then
			return false
		end
		addMod(item, mi, rng)
		return true
	end
	-- fill up: magic 1 or 2 (50 : 50), rare 4 / 5 / 6 (8 : 3 : 1); community estimates (Kalandralang)
	local function spawnAdditional(item, rng, cap, fs)
		local n = 0
		if item.r == MAGIC then
			n = rng() < 0.5 and 1 or 2
		elseif item.r == RARE then
			local i = m_floor(rng() * 12)
			n = i < 8 and 4 or i < 11 and 5 or 6
		end
		for _ = #item.mods + 1, n do
			if not spawn(item, rng, cap, fs) then
				break
			end
		end
	end

	local function clone(item)
		local out = { b = item.b, lv = item.lv, r = item.r, mods = { } }
		for i, x in ipairs(item.mods) do
			local v = { }
			for j, n in ipairs(x.v) do
				v[j] = n
			end
			out.mods[i] = { m = x.m, v = v }
		end
		return out
	end
	local function make(b, lv)
		return { b = b, lv = lv, r = NORMAL, mods = { } }
	end
	local function lowestRarity(item)
		local f = metaOf(item)
		local keep = filterMods(item, function(x) return not canRemove(mods[x.m], f, false) end)
		local c = counts({ mods = keep })
		return (c.p > 1 or c.s > 1) and RARE or (c.p > 0 or c.s > 0) and MAGIC or NORMAL
	end

	-- essences: normal -> rare with the guaranteed mod; rare items only with Screaming (tier 5) and up
	local function essenceMod(item, e)
		local mi = e.m[bases[item.b].c]
		return mi and (mi + 1) or nil
	end
	local function checkEssence(item, e)
		if not essenceMod(item, e) then
			return "這顆精髓不能用在" .. ((D.classes[bases[item.b].c] or { }).zh or "這類物品") .. "上（資料裡沒有這類物品的保證詞綴）。"
		end
		if item.r == MAGIC then return "精髓只能用在普通或稀有物品上，目前是魔法物品。" end
		if metaOf(item) then return "物品上有元工藝（例如前綴不能被改變），不能使用精髓。" end
		if item.r == RARE and not ((e.lv or 0) >= 5) then return "低階精髓（哀嚎以下）只能用在普通物品上；咆哮以上才能重鑄稀有物品。" end
		return nil
	end
	local function applyEssence(item, e, rng)
		item.r = RARE
		item.mods = { }
		addMod(item, essenceMod(item, e), rng)
		spawnAdditional(item, rng, e.ilr or 0)
	end

	-- fossils in a resonator: "reso:" .. fossil ids joined by "|"
	local function resoKey(ids)
		local l = { }
		for i, id in ipairs(ids) do
			l[i] = id
		end
		t_sort(l)
		return "reso:" .. table.concat(l, "|")
	end
	local function resoFossils(k)
		local fs = { }
		for id in k:sub(6):gmatch("[^|]+") do
			t_insert(fs, fosById[id] or false)
		end
		return fs
	end
	local function checkReso(item, k)
		local fs = resoFossils(k)
		if #fs == 0 then return "鑄新儀裡還沒有放化石。" end
		local seen = { }
		for _, f in ipairs(fs) do
			if not f then return "不認得的化石。" end
			if seen[f.id] then return "同一個鑄新儀不能放兩顆一樣的化石。" end
			seen[f.id] = true
			if f.why then return "先不開放：" .. f.why .. "。" end
		end
		if #fs > MAX_FOSSILS then return "最多放 " .. MAX_FOSSILS .. " 顆化石。" end
		if item.r == MAGIC then return "鑄新儀只能用在普通（點金）或稀有（混沌）物品上，目前是魔法物品。" end
		if metaOf(item) then return "物品上有元工藝，不能使用鑄新儀。" end
		local ts = bases[item.b].ts
		for _, f in ipairs(fs) do
			if #f.allow > 0 then
				local ok = false
				for _, t in ipairs(f.allow) do
					if tagId[t] and ts[tagId[t]] then ok = true end
				end
				if not ok then return f.nz .. "不能用在這類物品上。" end
			end
			for _, t in ipairs(f.forbid) do
				if tagId[t] and ts[tagId[t]] then return f.nz .. "不能用在這類物品上。" end
			end
		end
		return nil
	end
	local function applyReso(item, k, rng)
		local fs = resoFossils(k)
		item.r = RARE
		item.mods = { }
		for _, f in ipairs(fs) do
			for _, mi in ipairs(f.forceList) do
				local has = false
				for _, x in ipairs(item.mods) do
					if x.m == mi then has = true end
				end
				if not has then
					addMod(item, mi, rng)
				end
			end
		end
		spawn(item, rng, 0, fs)
		spawnAdditional(item, rng, 0, fs)
	end

	-- nil when the currency can be used, otherwise the reason
	local function check(item, k)
		if essByKey[k] then
			return checkEssence(item, essByKey[k])
		end
		if k:sub(1, 5) == "reso:" then
			return checkReso(item, k)
		end
		local n, c = #item.mods, counts(item)
		local function need(r)
			if item.r == r then return nil end
			return "這顆只能用在" .. RARITY_ZH[r] .. "物品上，目前是" .. RARITY_ZH[item.r] .. "物品。"
		end
		local function room()
			local max = maxSide(item)
			if c.p >= max and c.s >= max then
				return "前綴、後綴都已經滿了（" .. RARITY_ZH[item.r] .. "物品各 " .. max .. " 條）。"
			end
			if #pool(item) == 0 then return "目前沒有任何可以出現的詞綴。" end
			return nil
		end
		local function room2(r)
			local t = clone(item)
			t.r = r
			if #pool(t) == 0 then return "目前沒有任何可以出現的詞綴。" end
			return nil
		end
		if k == "transmute" or k == "alch" then return need(NORMAL) end
		if k == "alt" then return need(MAGIC) end
		if k == "aug" then return need(MAGIC) or room() end
		if k == "regal" then return need(MAGIC) or room2(RARE) end
		if k == "chaos" then return need(RARE) end
		if k == "exalt" then return need(RARE) or room() end
		if k == "annul" then
			if n == 0 then return "物品上沒有詞綴可以拿掉。" end
			if #removable(item, true) == 0 then return "剩下的詞綴都受元工藝保護，無效石拿不掉。" end
			return nil
		end
		if k == "scour" then
			if item.r == NORMAL and n == 0 then return "已經是沒有詞綴的普通物品了。" end
			if n > 0 and #removable(item, false) == 0 and lowestRarity(item) == item.r then return "所有詞綴都受元工藝保護，重鑄石不會有作用。" end
			return nil
		end
		if k == "divine" then
			if n == 0 then return "物品上沒有詞綴可以重骰。" end
			if #rerollable(item) == 0 then return "所有詞綴都受元工藝保護（前綴／後綴不能被改變），數值不會重骰。" end
			return nil
		end
		return "不認得的通貨：" .. k
	end

	local function removeOne(item, list, rng)
		local x = list[m_floor(rng() * #list) + 1]
		for i, y in ipairs(item.mods) do
			if y == x then
				t_remove(item.mods, i)
				return
			end
		end
	end

	-- changes item in place (call check first)
	local function applyMut(item, k, rng)
		if essByKey[k] then
			applyEssence(item, essByKey[k], rng)
		elseif k:sub(1, 5) == "reso:" then
			applyReso(item, k, rng)
		elseif k == "transmute" then
			item.r = MAGIC; item.mods = { }; spawnAdditional(item, rng)
		elseif k == "alt" then
			strip(item, false); spawnAdditional(item, rng)
		elseif k == "aug" or k == "exalt" then
			spawn(item, rng)
		elseif k == "regal" then
			item.r = RARE; spawn(item, rng)
		elseif k == "alch" then
			item.r = RARE; item.mods = { }; spawnAdditional(item, rng)
		elseif k == "chaos" then
			strip(item, false); spawn(item, rng); spawnAdditional(item, rng)
		elseif k == "annul" then
			removeOne(item, removable(item, true), rng)
		elseif k == "scour" then
			item.r = lowestRarity(item); strip(item, false)
		elseif k == "divine" then
			for _, x in ipairs(rerollable(item)) do
				x.v = rollValues(mods[x.m], rng)
			end
		end
		return item
	end
	local function apply(item, k, rng)
		rng = rng or math.random
		local err = check(item, k)
		if err then
			return { ok = false, err = err, item = item }
		end
		return { ok = true, item = applyMut(clone(item), k, rng) }
	end

	-- tiers: same mod type that can appear on this base, by level then value sum; first = T1
	local tierCache = { }
	local function sumOf(m)
		local a = 0
		for _, s in ipairs(m.st) do
			a = a + s[2] + s[3]
		end
		return a
	end
	local function tierTable(b, ty)
		local key = b .. "|" .. ty
		local t = tierCache[key]
		if t then
			return t
		end
		local ts = bases[b].ts
		local list = { }
		for _, m in ipairs(mods) do
			if m.ty == ty and weightOf(m, ts) > 0 then
				t_insert(list, m)
			end
		end
		t_sort(list, function(x, y)
			if x.lv ~= y.lv then return x.lv > y.lv end
			local sx, sy = sumOf(x), sumOf(y)
			if sx ~= sy then return sx > sy end
			return x.i < y.i
		end)
		t = { map = { }, count = 0, sums = { } }
		local prev
		for _, m in ipairs(list) do
			local k = m.lv .. "|" .. sumOf(m)
			if k ~= prev then
				t.count = t.count + 1
				prev = k
				t_insert(t.sums, sumOf(m))
			end
			t.map[m.i] = t.count
		end
		tierCache[key] = t
		return t
	end
	local function tierOf(b, mi)
		local m = mods[mi]
		local t = tierTable(b, m.ty)
		if not m.d then
			return t.map[mi] or 0
		end
		if t.count == 0 then
			return 1
		end
		local sum = sumOf(m)
		for k, s in ipairs(t.sums) do
			if s <= sum then
				return k
			end
		end
		return t.count + 1
	end
	local function tierCount(b, mi)
		return tierTable(b, mods[mi].ty).count
	end
	local function tagLabel(b, mi)
		local m = mods[mi]
		local side = m.pre and "前" or "後"
		if m.meta then return side .. " 元工藝" end
		if m.d == "c" then return side .. " 工藝" end
		if m.d == "e" then return side .. " 精≈T" .. tierOf(b, mi) end
		if m.d == "f" then return side .. " 化石" end
		return side .. " T" .. tierOf(b, mi)
	end

	-- mod text from stat_translations with the rolled values (or ranges)
	local function condOk(c, v)
		local mn, mx, neg = val(c[1]), val(c[2]), c[3]
		local ok = (mn == nil or v >= mn) and (mx == nil or v <= mx)
		if neg == true or (type(neg) == "number" and neg ~= 0) then return not ok end -- 0 is false in the JS data
		return ok
	end
	local function statLines(stats, lang)
		local lo, hi = { }, { }
		for _, s in ipairs(stats) do
			lo[s[1]], hi[s[1]] = s[2], s[3]
		end
		local seen, lines = { }, { }
		for _, s in ipairs(stats) do
			local sid = s[1]
			local ti = D.statTr[sid]
			if ti == nil then
				if (lo[sid] or 0) ~= 0 or (hi[sid] or 0) ~= 0 then
					return nil
				end
			elseif not seen[ti] then
				seen[ti] = true
				local e = D.trans[ti + 1]
				local vl, vh = { }, { }
				for k, id in ipairs(e.ids) do
					vl[k] = lo[id] or 0
					vh[k] = hi[id] or 0
				end
				local list = (lang == "zh" and e.z) and e.z or e.v
				local function okFor(vs)
					return function(x)
						for k, c in ipairs(x.c) do
							if not condOk(c, vs[k]) then
								return false
							end
						end
						return true
					end
				end
				local pick
				for _, test in ipairs({ okFor(vh), okFor(vl) }) do
					for _, x in ipairs(list) do
						if not pick and test(x) then
							pick = x
						end
					end
				end
				if pick then
					t_insert(lines, (pick.s:gsub("{(%d+)}", function(k)
						k = tonumber(k) + 1
						local f = pick.f[k]
						if f == "ignore" then
							return ""
						end
						local a, b = vl[k], vh[k]
						for _, h in ipairs(pick.h[k] or { }) do
							if HANDLERS[h] then
								a, b = HANDLERS[h](a), HANDLERS[h](b)
							end
						end
						if a > b then
							a, b = b, a
						end
						local sign = (f == "+#" and b > 0) and "+" or ""
						if a == b then
							return sign .. fmtNum(a)
						end
						return sign .. "(" .. fmtNum(a) .. "-" .. fmtNum(b) .. ")"
					end)))
				end
			end
		end
		return lines
	end
	local function splitLines(s)
		local out = { }
		for line in (s .. "\n"):gmatch("(.-)\n") do
			t_insert(out, line)
		end
		return out
	end
	local function modRange(mi, lang)
		local m = mods[mi]
		if lang == "zh" then
			local l = statLines(m.st, "zh")
			if l and #l > 0 then
				return l
			end
		end
		return splitLines(m.tx)
	end
	local function render(mi, vals, lang)
		local m = mods[mi]
		if not vals then
			return modRange(mi, lang)
		end
		local stats = { }
		for i, s in ipairs(m.st) do
			stats[i] = { s[1], vals[i], vals[i] }
		end
		local l = statLines(stats, lang)
		if l and #l > 0 then
			return l
		end
		return splitLines(m.tx)
	end
	local function baseName(b, lang)
		local x = bases[b]
		return (lang == "zh" and x.nz) and x.nz or x.n
	end
	local function modName(mi, lang)
		local m = mods[mi]
		return (lang == "zh" and m.nz) and m.nz or m.n
	end
	local function implicitLines(b, lang)
		local x, out = bases[b], { }
		for i, t in ipairs(x.imp) do
			local l
			if lang == "zh" and x.is and x.is[i] then
				l = statLines(x.is[i], "zh")
			end
			if not (l and #l > 0) then
				l = splitLines(t)
			end
			for _, line in ipairs(l) do
				t_insert(out, line)
			end
		end
		return out
	end

	-- mod pool of a blank base at this item level, prefix and suffix chances separately
	local function poolView(b, lv)
		local bp = basePool(make(b, lv))
		local tp, tsuf = 0, 0
		for _, x in ipairs(bp.list) do
			if mods[x.m].pre then tp = tp + x.w else tsuf = tsuf + x.w end
		end
		local rows = { }
		for _, x in ipairs(bp.list) do
			local m = mods[x.m]
			t_insert(rows, { m = x.m, w = x.w, pre = m.pre, tier = tierOf(b, x.m), tiers = tierCount(b, x.m), pct = x.w / (m.pre and tp or tsuf) * 100 })
		end
		t_sort(rows, function(a, c) return a.pct > c.pct end)
		return { rows = rows, prefixTotal = tp, suffixTotal = tsuf }
	end

	-- the site's saved form: base Metadata path and mod ids
	local function toStored(item)
		local out = { base = bases[item.b].id, lv = item.lv, r = item.r, mods = { } }
		for i, x in ipairs(item.mods) do
			local v = { }
			for j, n in ipairs(x.v) do
				v[j] = n
			end
			out.mods[i] = { id = mods[x.m].id, v = v }
		end
		return out
	end
	local function fromStored(s)
		if type(s) ~= "table" or type(s.lv) ~= "number" or type(s.r) ~= "number" or type(s.mods) ~= "table" then
			return nil
		end
		local b = baseById[s.base]
		if not b then
			return nil
		end
		local out = { b = b.i, lv = s.lv, r = s.r, mods = { } }
		for i, x in ipairs(s.mods) do
			local m = modById[x.id]
			if not m or type(x.v) ~= "table" then
				return nil
			end
			local v = { }
			for j, n in ipairs(x.v) do
				v[j] = n
			end
			out.mods[i] = { m = m.i, v = v }
		end
		return out
	end

	-- PoB item text (English, as the game copies it): PoB parses it into a real item
	local RARITY_EN = { [0] = "NORMAL", "MAGIC", "RARE" }
	local function toPobText(item, name)
		local base = bases[item.b]
		local lines = { "Rarity: " .. RARITY_EN[item.r] }
		if item.r == RARE then
			t_insert(lines, name or "Crafted Item")
			t_insert(lines, base.n)
		elseif item.r == MAGIC then
			-- PoB finds the base inside a magic name
			local pre, suf
			for _, x in ipairs(item.mods) do
				local m = mods[x.m]
				if m.pre then pre = pre or m.n else suf = suf or m.n end
			end
			t_insert(lines, (pre and (pre .. " ") or "") .. base.n .. (suf and (" " .. suf) or ""))
		else
			t_insert(lines, base.n)
		end
		t_insert(lines, "Item Level: " .. item.lv)
		local implicit = implicitLines(item.b, "en")
		t_insert(lines, "Implicits: " .. #implicit)
		for _, l in ipairs(implicit) do
			t_insert(lines, l)
		end
		for _, x in ipairs(item.mods) do
			local m = mods[x.m]
			for _, l in ipairs(render(x.m, x.v, "en")) do
				if l ~= "" then
					t_insert(lines, (m.d == "c" and "{crafted}" or "") .. l)
				end
			end
		end
		return table.concat(lines, "\n")
	end

	return {
		data = D, bases = bases, mods = mods, modById = modById, baseById = baseById, tagId = tagId,
		NORMAL = NORMAL, MAGIC = MAGIC, RARE = RARE,
		essences = essences, essByKey = essByKey, essenceMod = essenceMod,
		fossils = fossils, fosByKey = fosByKey, fosById = fosById, resoKey = resoKey, setFossilMode = setFossilMode, MAX_FOSSILS = MAX_FOSSILS,
		make = make, clone = clone, check = check, apply = apply, applyMut = applyMut, pool = pool, poolView = poolView,
		counts = counts, maxSide = maxSide, metaOf = metaOf, weightOf = weightOf, tagSet = tagSet,
		tierOf = tierOf, tierCount = tierCount, tagLabel = tagLabel,
		render = render, modRange = modRange, baseName = baseName, modName = modName, implicitLines = implicitLines,
		toStored = toStored, fromStored = fromStored, toPobText = toPobText,
	}
end

return { create = create, CURRENCIES = CURRENCIES, CUR = CUR, RARITY_ZH = RARITY_ZH }
