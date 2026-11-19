#@ SimpleGraphic
-- zhTW: headless test for the 幻化守衛裝備 row (Modules/ZhTWGuardianSet.lua)
-- Usage (from the runtime folder): Path{space}of{space}Building.exe <full path of src\zhTWGuardianSetTest.lua>
-- Results: src/zhTWGuardianSetTest.log

local realInflate, realDeflate = Inflate, Deflate
local logFile = io.open("zhTWGuardianSetTest.log", "w")
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
	ZhTWLocale.enabled = true
	local G = LoadModule("Modules/ZhTWGuardianSet")
	newBuild()
	local itemsTab = build.itemsTab
	log("controls", itemsTab.controls.zhTWGuardianSelect ~= nil, itemsTab.controls.zhTWGuardianEdit ~= nil)
	local function recalc()
		build.buildFlag = true
		runCallback("OnFrame")
		return build.calcsTab.mainOutput
	end
	log("no guardian gem: gems", #G.guardianGems(build), "enabled", itemsTab.controls.zhTWGuardianSelect:IsEnabled())
	build.skillsTab:PasteSocketGroup("Fireball 20/0  1\n")
	build.skillsTab:PasteSocketGroup("Animate Guardian 20/0  1\n")
	local before = recalc()
	log("gems", #G.guardianGems(build), "current", tostring((G.currentSetId(itemsTab))), "CritMultiplier", before.CritMultiplier)

	-- 編輯: creates the 幻化守衛 set and shows it on top
	local playerSet = itemsTab.activeItemSetId
	G.toggleEdit(itemsTab)
	log("editing set", itemsTab.activeItemSetId, itemsTab.activeItemSet.title, "player set", playerSet)
	for _, raw in ipairs({
		"Rarity: UNIQUE\nKingmaker\nDespot Axe\nImplicits: 0\n(300-360)% increased Physical Damage\nNearby Allies have Culling Strike\nNearby Allies have +50% to Critical Strike Multiplier\n",
		"Rarity: UNIQUE\nLeer Cast\nFestival Mask\n+(20-30) to Dexterity\n25% reduced Damage\nYou and nearby allies gain 50% increased Damage\n",
	}) do
		itemsTab:CreateDisplayItemFromRaw(raw)
		local item = itemsTab.displayItem
		itemsTab:AddItem(item, true)
		local slotName = item.base.type == "Helmet" and "Helmet" or "Weapon 1"
		itemsTab.slots[slotName]:SetSelItemId(item.id)
		log("equipped on guardian set", item.name, slotName)
	end
	local editing = recalc()
	log("while editing CritMultiplier", editing.CritMultiplier)
	-- 返回
	G.toggleEdit(itemsTab)
	local after = recalc()
	log("back on set", itemsTab.activeItemSetId, "guardian set", tostring((G.currentSetId(itemsTab))), "CritMultiplier", after.CritMultiplier, "AverageDamage ratio", after.AverageDamage / before.AverageDamage)
	log(after.CritMultiplier - before.CritMultiplier == 0.5 and "PASS" or "FAIL")
	log("isEditing after back", G.isEditing(itemsTab))
	-- dropdown rows and frame draw without errors
	itemsTab.controls.zhTWGuardianFrame:Draw()
	local wx, wy = itemsTab.controls.weaponSwap2:GetPos()
	local gx, gy = itemsTab.controls.zhTWGuardianSelect:GetPos()
	local sx, sy = itemsTab.slotAnchor:GetPos()
	log("weapon row y", wy, "guardian row y", gy, "slots y", sy)
	itemsTab.controls.zhTWGuardianSelect:Draw({ x = 0, y = 0, width = 1000, height = 800 })
	log("dropdown", table.concat(itemsTab.controls.zhTWGuardianSelect.list, " | "), "sel", itemsTab.controls.zhTWGuardianSelect.selIndex)
end)
if not ok then
	log("ERROR", err)
end
logFile:close()
os.exit()
