-- Lua side of the engine comparison (run through zhTWCraftTest.lua with ZHTW_CRAFT_SCRIPT)
-- zhTW: Lua side of the engine comparison (see Export/zhTWCraftCompare.py)
local E, CE, log = ...
local N = tonumber(os.getenv("ZHTW_CRAFT_N") or "3000")
math.randomseed(12345)
local out = io.open(os.getenv("ZHTW_CRAFT_OUT"), "w")
local function emit(a, b, c)
	out:write(a, "\t", b, "\t", c, "\n")
end
local function byName(n)
	for i, b in ipairs(E.bases) do
		if b.n == n then return i end
	end
end
local function tally(name, makeItem)
	local ty, cnt = { }, { }
	for _ = 1, N do
		local it = makeItem()
		cnt[#it.mods] = (cnt[#it.mods] or 0) + 1
		for _, x in ipairs(it.mods) do
			local m = E.mods[x.m]
			local k = m.ty .. "/" .. m.g
			ty[k] = (ty[k] or 0) + 1
		end
	end
	for k, v in pairs(ty) do emit(name, "ty:" .. k, string.format("%.4f", v / N)) end
	for k, v in pairs(cnt) do emit(name, "n:" .. k, string.format("%.4f", v / N)) end
end
local helm, ring, bow = byName("Hubris Circlet"), byName("Two-Stone Ring"), byName("Thicket Bow")
local function ap(it, k)
	local r = E.apply(it, k)
	return r.item
end
local t0 = os.clock()
tally("alch_helm", function() return ap(E.make(helm, 86), "alch") end)
tally("transmute_ring", function() return ap(E.make(ring, 84), "transmute") end)
tally("chaos_bow", function() return ap(ap(E.make(bow, 84), "alch"), "chaos") end)
tally("exalt_helm", function() return ap(ap(E.make(helm, 86), "alch"), "exalt") end)
tally("aug_ring", function()
	local t = ap(E.make(ring, 84), "transmute")
	if #t.mods == 1 then return ap(t, "aug") end
	return t
end)
local ess
for _, e in ipairs(E.essences) do
	if not ess and (e.lv or 0) >= 5 and e.m["Helmet"] ~= nil then ess = e end
end
tally("essence_helm", function() return ap(E.make(helm, 86), ess.k) end)
local fos = { }
for _, f in ipairs(E.fossils) do
	if not f.why and #fos < 2 then table.insert(fos, f.id) end
end
tally("fossil_helm", function() return ap(E.make(helm, 86), E.resoKey(fos)) end)
log(string.format("lua tallies: %d trials each, %.2fs", N, os.clock() - t0))
emit("meta", "essence", ess.id)
emit("meta", "fossils", table.concat(fos, "|"))
emit("check", "chaos_normal", tostring(E.check(E.make(helm, 86), "chaos")))
local life = E.modById["IncreasedLife7"].i
emit("text", "IncreasedLife7_en", table.concat(E.render(life, { 80 }, "en"), "|"))
emit("text", "IncreasedLife7_zh", table.concat(E.render(life, { 80 }, "zh"), "|"))
emit("text", "IncreasedLife7_range", table.concat(E.render(life, nil, "zh"), "|"))
emit("tier", "IncreasedLife7_helm", tostring(E.tierOf(helm, life)))
emit("implicit", "ring", table.concat(E.implicitLines(ring, "zh"), "|"))
-- one crafted item as PoB text
local item = ap(E.make(helm, 86), "alch")
log("PoB text sample:\n" .. E.toPobText(item))
out:close()
