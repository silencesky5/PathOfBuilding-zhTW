-- Path of Building (zhTW)
--
-- Module: ZhTW Guardian Set
-- 裝備頁「幻化守衛裝備」選單（只在中文介面顯示）。
-- The Taiwan get-items API has no "guardian" field, so Animate Guardian's gear never comes in with
-- an import. This row lets the player pick (or create) the item set the guardian wears and jump to it
-- to paste the items; the top item set row is relabelled 角色裝備 so the two are told apart.
-- The guardian's auras reach the player through the zhTW block in Modules/CalcPerform.lua.
--
local ipairs = ipairs
local t_insert = table.insert

local M = { }

local NONE_LABEL = "無幻化守衛"
local UNSET_LABEL = "未設定"
local NEW_LABEL = "＋新增守衛裝備組"
local NEW_SET_TITLE = "幻化守衛"

local function enabled()
	return ZhTWLocale and ZhTWLocale.enabled
end

-- Gems whose minion wears an item set (Animate Guardian)
function M.guardianGems(build)
	local gems = { }
	for _, group in ipairs(build.skillsTab.socketGroupList) do
		for _, gem in ipairs(group.gemList) do
			local grantedEffect = gem.grantedEffect or (gem.gemData and gem.gemData.grantedEffect)
			if grantedEffect and grantedEffect.minionHasItemSet then
				t_insert(gems, gem)
			end
		end
	end
	return gems
end

-- The guardian's item set, or nil when it is unset or left on the player's own set
function M.currentSetId(itemsTab, gems)
	gems = gems or M.guardianGems(itemsTab.build)
	for _, gem in ipairs(gems) do
		for _, setId in ipairs({ gem.skillMinionItemSet, gem.skillMinionItemSetCalcs }) do
			if setId and itemsTab.itemSets[setId] and setId ~= itemsTab.activeItemSetId then
				return setId
			end
		end
	end
	-- while the guardian's own set is the one shown on top, remember it from the edit button
	local editing = itemsTab.zhTWGuardianEditing
	if editing and editing == itemsTab.activeItemSetId and itemsTab.itemSets[editing] then
		return editing
	end
end

function M.assign(itemsTab, setId)
	for _, gem in ipairs(M.guardianGems(itemsTab.build)) do
		gem.skillMinionItemSet = setId
		gem.skillMinionItemSetCalcs = setId
	end
	itemsTab.build.buildFlag = true
	itemsTab.build.modFlag = true
end

local function setTitle(itemSet)
	return itemSet.title or "Default"
end

function M.newSet(itemsTab)
	local itemSet = itemsTab:NewItemSet()
	itemSet.title = NEW_SET_TITLE
	t_insert(itemsTab.itemSetOrderList, itemSet.id)
	M.assign(itemsTab, itemSet.id)
	return itemSet
end

-- Shows the guardian's set on top so items can be pasted into it; pressed again, goes back
function M.toggleEdit(itemsTab)
	local editing = itemsTab.zhTWGuardianEditing
	if editing and editing == itemsTab.activeItemSetId then
		itemsTab.zhTWGuardianEditing = nil
		local back = itemsTab.zhTWGuardianReturnSet
		if not (back and itemsTab.itemSets[back]) or back == editing then
			back = itemsTab.itemSetOrderList[1] ~= editing and itemsTab.itemSetOrderList[1] or itemsTab.itemSetOrderList[2]
		end
		itemsTab:SetActiveItemSet(back)
		M.assign(itemsTab, editing)
	else
		local setId = M.currentSetId(itemsTab) or M.newSet(itemsTab).id
		itemsTab.zhTWGuardianReturnSet = itemsTab.activeItemSetId
		itemsTab.zhTWGuardianEditing = setId
		M.assign(itemsTab, setId)
		itemsTab:SetActiveItemSet(setId)
	end
	itemsTab:AddUndoState()
end

function M.setup(itemsTab)
	local controls = itemsTab.controls
	if not controls.setSelect or not controls.setLabel then
		return
	end
	-- 角色裝備 instead of 裝備組 for the top row
	local origLabel = controls.setLabel.label
	controls.setLabel.label = function()
		return enabled() and "^7角色裝備:" or origLabel
	end

	local rows -- the item sets behind the dropdown rows
	local select = new("DropDownControl"):DropDownControl({ "TOPLEFT", controls.setSelect, "BOTTOMLEFT" }, { 0, 4, 216, 20 }, nil, function(index)
		local row = rows and rows[index]
		if not row then
			return
		end
		if row.new then
			M.newSet(itemsTab)
		else
			M.assign(itemsTab, row.setId or itemsTab.activeItemSetId)
		end
		itemsTab:AddUndoState()
	end)
	select.enableDroppedWidth = true
	select.shown = function()
		return enabled()
	end
	select.enabled = function()
		return #M.guardianGems(itemsTab.build) > 0
	end
	select.tooltipFunc = function(tooltip, mode, index)
		tooltip:Clear()
		local row = rows and rows[index]
		if mode == "HOVER" and row and row.setId and itemsTab.AddItemSetTooltip then
			itemsTab:AddItemSetTooltip(tooltip, itemsTab.itemSets[row.setId])
		elseif mode ~= "HOVER" then
			tooltip:AddLine(16, "^7幻化守衛身上穿的裝備組。台服的角色資料不含守衛的裝備，")
			tooltip:AddLine(16, "^7請按「編輯」切到這一組，貼上守衛的裝備（物品文字 Ctrl+V）。")
			tooltip:AddLine(16, "^7守衛裝備上的光環（例如王者之刃、共鳴之面）會算進你的數值。")
		end
	end
	local origDraw = select.Draw
	select.Draw = function(self, ...)
		local gems = M.guardianGems(itemsTab.build)
		local list = { }
		rows = { }
		if #gems == 0 then
			list[1] = NONE_LABEL
			self.selIndex = 1
		else
			local current = M.currentSetId(itemsTab, gems)
			t_insert(list, UNSET_LABEL)
			t_insert(rows, { })
			self.selIndex = 1
			for _, setId in ipairs(itemsTab.itemSetOrderList) do
				if setId ~= itemsTab.activeItemSetId or setId == current then
					t_insert(list, setTitle(itemsTab.itemSets[setId]))
					t_insert(rows, { setId = setId })
					if setId == current then
						self.selIndex = #list
					end
				end
			end
			t_insert(list, NEW_LABEL)
			t_insert(rows, { new = true })
		end
		self:SetList(list)
		return origDraw(self, ...)
	end
	controls.zhTWGuardianSelect = select
	controls.zhTWGuardianLabel = new("LabelControl"):LabelControl({ "RIGHT", select, "LEFT" }, { -2, 0, 0, 16 }, "^7幻化守衛裝備:")
	controls.zhTWGuardianLabel.shown = select.shown

	local button = new("ButtonControl"):ButtonControl({ "LEFT", select, "RIGHT" }, { 4, 0, 90, 20 }, function()
		local editing = itemsTab.zhTWGuardianEditing
		return (editing and editing == itemsTab.activeItemSetId) and "返回" or "編輯"
	end, function()
		M.toggleEdit(itemsTab)
	end)
	button.shown = select.shown
	button.enabled = select.enabled
	button.tooltipFunc = function(tooltip)
		tooltip:Clear()
		local editing = itemsTab.zhTWGuardianEditing
		if editing and editing == itemsTab.activeItemSetId then
			tooltip:AddLine(16, "^7回到你自己的角色裝備。")
		else
			tooltip:AddLine(16, "^7把守衛的裝備組切到上方顯示，方便貼上裝備（沒有就自動新增一組）。")
			tooltip:AddLine(16, "^7顯示守衛裝備時，左側數值是「你穿這組」的結果，按「返回」就恢復。")
		end
	end
	controls.zhTWGuardianEdit = button

	-- The Chinese layout moves the equipped items up into the hidden trade button's row (ZhTWLayout),
	-- which is where this row sits: push them (and the 武器組 buttons on their top edge) back down one row.
	local anchor = itemsTab.slotAnchor
	if anchor then
		local origY = anchor.y
		anchor.y = function(self)
			local y = type(origY) == "function" and origY(self) or origY
			return enabled() and (y + 24) or y
		end
	end
end

return M
