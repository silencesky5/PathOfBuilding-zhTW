#@ SimpleGraphic
-- zhTW: headless test for Animate Guardian item auras reaching the player (Modules/CalcPerform.lua)
-- Usage (from the runtime folder): Path{space}of{space}Building.exe <full path of src\zhTWGuardianAuraTest.lua>
-- Results: src/zhTWGuardianAuraTest.log

local realInflate, realDeflate = Inflate, Deflate
local logFile = io.open("zhTWGuardianAuraTest.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end
print = log

local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	Inflate, Deflate = realInflate, realDeflate
	newBuild()
	build.skillsTab:PasteSocketGroup("Fireball 20/0  1\n")
	build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1\n")
	runCallback("OnFrame")
	for i, group in ipairs(build.skillsTab.socketGroupList) do
		for _, gem in ipairs(group.gemList) do
			log("group", i, gem.nameSpec, gem.grantedEffect and gem.grantedEffect.name, group.enabled)
		end
	end
	build.mainSocketGroup = 1
	local function stats(label)
		build.buildFlag = true
		runCallback("OnFrame")
		local out = build.calcsTab.mainOutput
		log(label, "CritMultiplier", out.CritMultiplier, "AverageDamage", out.AverageDamage, "CullingStrike", tostring((build.calcsTab.mainEnv.player.modDB:Flag(nil, "CullingStrike"))), "MainSkill", build.calcsTab.mainEnv.player.mainSkill.activeEffect.grantedEffect.name)
		for _, a in ipairs(build.calcsTab.mainEnv.player.activeSkillList) do
			local m = a.minion
			log("  skill", a.activeEffect.grantedEffect.name, "minion", m and m.type, "itemSet", m and m.itemSet and m.itemSet.id, "uses", m and m.uses and "yes")
		end
		return out
	end
	local before = stats("no guardian items")

	local itemsTab = build.itemsTab
	local set = itemsTab:NewItemSet()
	set.title = "Guardian"
	table.insert(itemsTab.itemSetOrderList, set.id)
	local function addItem(raw, slotName)
		itemsTab:CreateDisplayItemFromRaw(raw)
		local item = itemsTab.displayItem
		itemsTab:AddItem(item, true)
		set[slotName].selItemId = item.id
		local ml = item.modList or item.slotModList[1]
		for _, m in ipairs(ml or {}) do log("   mod", m.name, m.type, type(m.value) == "table" and m.value.mod and m.value.mod.name or tostring(m.value)) end
		log("   modList?", item.modList ~= nil, "slotModList?", item.slotModList ~= nil)
		log("added", item.name, slotName)
	end
	addItem("Rarity: UNIQUE\nKingmaker\nDespot Axe\nVariant: Current\nSelected Variant: 6\nImplicits: 0\n(300-360)% increased Physical Damage\n(7-12)% increased Attack Speed\n(30-40)% increased Critical Strike Chance\nNearby Allies have 30% increased Item Rarity\nNearby Allies have Culling Strike\nNearby Allies have +50% to Critical Strike Multiplier\n", "Weapon 1")
	addItem("Rarity: UNIQUE\nLeer Cast\nFestival Mask\nVariant: Current\nSelected Variant: 2\n+(20-30) to Dexterity\n25% reduced Damage\n+(60-100) to maximum Life\n+(60-100) to maximum Mana\nYou and nearby allies gain 50% increased Damage\n", "Helmet")
	for _, group in ipairs(build.skillsTab.socketGroupList) do
		for _, gem in ipairs(group.gemList) do
			if gem.nameSpec == "Animate Guardian" then
				gem.skillMinionItemSet = set.id
				gem.skillMinionItemSetCalcs = set.id
			end
		end
	end
	local after = stats("guardian wears Kingmaker + Leer Cast")
	log("RESULT crit multi +", (after.CritMultiplier or 0) - (before.CritMultiplier or 0), "damage ratio", (after.AverageDamage or 0) / (before.AverageDamage or 1))
end)
if not ok then
	log("ERROR", err)
end
logFile:close()
os.exit()
