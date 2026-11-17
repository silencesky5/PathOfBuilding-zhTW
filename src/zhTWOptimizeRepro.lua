#@ SimpleGraphic
-- zhTW: 傷害最佳化：最佳化時算的 DPS 和「真的裝上後」的 DPS 要一致（電能釋放＋長杖）
-- Usage: Path{space}of{space}Building.exe <full path of src\zhTWOptimizeRepro.lua>  → src/zhTWOptimizeRepro.log

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logFile = io.open("zhTWOptimizeRepro.log", "w")
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
	local Opt = LoadModule("Modules/ZhTWOptimize")
	local setups = {
		{ name = "self-cast Discharge", gems = "Slot: Weapon 1\nDischarge 20/0  1\nSpell Echo 20/0  1\nControlled Destruction 20/0  1\n" },
		{ name = "Discharge + Cast while Channelling", gems = "Slot: Weapon 1\nCast while Channelling 20/0  1\nDischarge 20/0  1\nBlight 20/0  1\nControlled Destruction 20/0  1\n" },
		{ name = "Lightning Tendrils (電能釋放)", gems = "Slot: Weapon 1\nLightning Tendrils 20/0  1\nControlled Destruction 20/0  1\n" },
	}
	local staff = [[Rarity: RARE
Test Staff
Eclipse Staff
Item Level: 84
Quality: 20
Sockets: B-B-B-B-B-B
Implicits: 1
100% increased Global Critical Strike Chance
40% increased Spell Damage
Adds 10 to 100 Lightning Damage to Spells
+39 to maximum Mana
+3 to Level of all Lightning Spell Skill Gems
+33% to Global Critical Strike Multiplier
12% Chance to Block Spell Damage]]
	for _, setup in ipairs(setups) do
		newBuild()
		-- group 1: an attack as the build's main skill; group 2: the spell the player actually looks at
		build.skillsTab:PasteSocketGroup("Slot: Gloves\nCleave 20/0  1\n")
		build.skillsTab:PasteSocketGroup(setup.gems)
		build.itemsTab:CreateDisplayItemFromRaw(staff)
		build.itemsTab:AddDisplayItem()
		build.configTab.input.usePowerCharges = true
		build.configTab.input.useFrenzyCharges = true
		build.configTab.input.useEnduranceCharges = true
		build.configTab:BuildModList()
		runCallback("OnFrame")
		local main = build.calcsTab.mainOutput
		log("== " .. setup.name, "main skill", build.calcsTab.mainEnv.player.mainSkill.activeEffect.grantedEffect.name)
		log("equipped CombinedDPS", main.CombinedDPS, "FullDPS", main.FullDPS)
		local itemsTab = build.itemsTab
		local slot = itemsTab.slots["Weapon 1"]
		local origId = slot.selItemId
		build.mainSocketGroup = 1
		build.buildFlag = true
		runCallback("OnFrame")
		log("skills:")
		for _, sk in ipairs(Opt.listSkills(build)) do log("   " .. sk.index .. " " .. sk.label) end
		for _, keepRes in ipairs({ false, true }) do
			local r = Opt.optimizeSlot(itemsTab, slot, keepRes, nil, 2)
			assert(build.mainSocketGroup == 1, "main skill changed by the optimiser")
			log(string.format("keepRes=%s  optimiser before %.1f  after %.1f  evals %d", tostring(keepRes), r.before, r.after, r.evals))
			for _, c in ipairs(r.chosen) do
				log("   " .. c.type .. " " .. c.id .. ": " .. table.concat(c.mod, " / "))
			end
			-- really equip it
			itemsTab:AddItem(r.item, true)
			slot:SetSelItemId(r.item.id)
			build.mainSocketGroup = 2
			build.buildFlag = true
			runCallback("OnFrame")
			local real = build.calcsTab.mainOutput.CombinedDPS
			build.mainSocketGroup = 1
			log(string.format("   really equipped: %.1f   (optimiser said %.1f, diff %.2f%%)", real, r.after, (r.after / real - 1) * 100))
			slot:SetSelItemId(origId)
			build.mainSocketGroup = 2
			build.buildFlag = true
			runCallback("OnFrame")
			log(string.format("   back to original: %.1f", build.calcsTab.mainOutput.CombinedDPS))
			build.mainSocketGroup = 1
			build.buildFlag = true
			runCallback("OnFrame")
		end
	end
	log("DONE")
end)
if not ok then
	log("ERROR", err)
end
logFile:close()

realSetMainObject({
	OnInit = function() realExit() end,
	OnFrame = function() end,
})
