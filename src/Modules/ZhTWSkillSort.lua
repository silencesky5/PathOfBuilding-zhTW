-- Path of Building
--
-- Module: zhTW Skill Sort
-- 技能頁「插槽群組」清單（Classes/SkillListControl.lua，只在中文介面）：
--   - 依裝備頁的部位順序排列：武器1、武器2、頭部、胸甲、手套、鞋子、項鍊、左戒指、右戒指、腰帶、
--     切換武器；沒有插在裝備上的群組放在最後。同一部位內維持原本的先後（可拖曳調整）。
--   - 每列在部位圖示後面加上部位名稱，例如「武器1：精準 G」。
-- 排序會真的改變 socketGroupList 的順序，主要技能（build.mainSocketGroup）、計算頁選的技能
-- （calcsTab.input.skill_number）和清單選取都跟著換到新位置，計算結果不變。
--
local t_sort = table.sort

local M = { }

local SLOT_ORDER = {
	"Weapon 1", "Weapon 2",
	"Helmet", "Body Armour", "Gloves", "Boots",
	"Amulet", "Ring 1", "Ring 2", "Ring 3", "Belt",
	"Weapon 1 Swap", "Weapon 2 Swap",
}
local slotRank = { }
for i, slot in ipairs(SLOT_ORDER) do
	slotRank[slot] = i
end
local OTHER_SLOT = #SLOT_ORDER + 1 -- a slot not in the list (kept before the groups without a slot)
local NO_SLOT = #SLOT_ORDER + 2

-- 部位名稱：武器用 KAI 指定的「武器1／武器2」，其他和裝備頁相同
M.slotLabels = {
	["Weapon 1"] = "武器1",
	["Weapon 2"] = "武器2",
	["Weapon 1 Swap"] = "武器1 (切換)",
	["Weapon 2 Swap"] = "武器2 (切換)",
	["Helmet"] = "頭部",
	["Body Armour"] = "胸甲",
	["Gloves"] = "手套",
	["Boots"] = "鞋子",
	["Amulet"] = "項鍊",
	["Ring 1"] = "左戒指",
	["Ring 2"] = "右戒指",
	["Ring 3"] = "戒指3",
	["Belt"] = "腰帶",
}

function M.enabled()
	return ZhTWLocale and ZhTWLocale.enabled and true or false
end

local function rank(socketGroup)
	local slot = socketGroup.slot
	if not slot or slot == "" then
		return NO_SLOT
	end
	return slotRank[slot] or OTHER_SLOT
end
M.rank = rank

-- Sorts the skill tab's socket group list by equipment slot (stable). Returns true if the order changed.
function M.sort(skillsTab)
	local list = skillsTab.socketGroupList
	if not list or #list < 2 then
		return false
	end
	local sorted = true
	for i = 2, #list do
		if rank(list[i]) < rank(list[i - 1]) then
			sorted = false
			break
		end
	end
	if sorted then
		return false
	end
	local oldIndex = { }
	for i, socketGroup in ipairs(list) do
		oldIndex[socketGroup] = i
	end
	t_sort(list, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return oldIndex[a] < oldIndex[b]
	end)
	local newIndex = { }
	for i, socketGroup in ipairs(list) do
		newIndex[oldIndex[socketGroup]] = i
	end
	local build = skillsTab.build
	if build.mainSocketGroup and newIndex[build.mainSocketGroup] then
		build.mainSocketGroup = newIndex[build.mainSocketGroup]
	end
	local input = build.calcsTab and build.calcsTab.input
	if input and input.skill_number and newIndex[input.skill_number] then
		input.skill_number = newIndex[input.skill_number]
	end
	local groupList = skillsTab.controls and skillsTab.controls.groupList
	if groupList and groupList.selValue then
		groupList.selIndex = isValueInArray(list, groupList.selValue)
		if not groupList.selIndex then
			groupList.selValue = nil
		end
	end
	build.buildFlag = true
	return true
end

-- Row text: 部位名稱 + the translated label, e.g. "武器1：精準 G"
function M.rowLabel(socketGroup, label)
	local slot = socketGroup.slot
	if not slot or slot == "" then
		return label
	end
	local name = M.slotLabels[slot] or ZhTWLocale.translate(slot)
	local esc = label:match("^%^x%x%x%x%x%x%x") or label:match("^%^%d") or "^7"
	return esc .. name .. "：" .. ZhTWLocale.tr(label)
end

return M
