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
local pairs = pairs
local m_min = math.min

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

-- true while the item slots below show the guardian's set (button 套用 pressed)
function M.isEditing(itemsTab)
	local editing = itemsTab.zhTWGuardianEditing
	return editing ~= nil and editing == itemsTab.activeItemSetId
end

-- Gold frame around the row whose gear the item slots below are showing
local FRAME_PAD = 4
local function drawFrame(left, right)
	local lx = left:GetPos()
	local _, ly = left:GetPos()
	local rx, ry = right:GetPos()
	local rw, rh = right:GetSize()
	local x1, y1 = lx - FRAME_PAD - 2, m_min(ly, ry) - FRAME_PAD
	local x2, y2 = rx + rw + FRAME_PAD, ry + rh + FRAME_PAD
	SetDrawColor(0.85, 0.68, 0.3)
	DrawImage(nil, x1, y1, x2 - x1, 1)
	DrawImage(nil, x1, y2 - 1, x2 - x1, 1)
	DrawImage(nil, x1, y1, 1, y2 - y1)
	DrawImage(nil, x2 - 1, y1, 1, y2 - y1)
	SetDrawColor(0.85, 0.68, 0.3, 0.08)
	DrawImage(nil, x1 + 1, y1 + 1, x2 - x1 - 2, y2 - y1 - 2)
	SetDrawColor(1, 1, 1)
end

function M.setup(itemsTab)
	local controls = itemsTab.controls
	if not controls.setSelect or not controls.setLabel or not controls.setManage then
		return
	end
	local setSelect, setManage = controls.setSelect, controls.setManage
	-- Row 1: 角色 (the player's own item set)
	local origLabel = controls.setLabel.label
	controls.setLabel.label = function()
		return enabled() and "^7角色:" or origLabel
	end
	-- While the guardian's set is shown below, this row still names the player's set
	local origSetDraw = setSelect.Draw
	setSelect.Draw = function(self, ...)
		if enabled() and M.isEditing(itemsTab) then
			for index, setId in ipairs(itemsTab.itemSetOrderList) do
				if setId == itemsTab.zhTWGuardianReturnSet then
					self.selIndex = index
				end
			end
		end
		return origSetDraw(self, ...)
	end

	-- Row 2: 武器組 I II (moved up from the top edge of the item slots)
	local function rowTwoPos(offsetX)
		local x, y = setManage:GetPos()
		local w, h = setManage:GetSize()
		return x + w - offsetX, y + h + 6
	end
	for name, offsetX in pairs({ weaponSwap1 = 38, weaponSwap2 = 18 }) do
		local button = controls[name]
		if button then
			local origGetPos = button.GetPos
			button.GetPos = function(self)
				if enabled() then
					return rowTwoPos(offsetX)
				end
				return origGetPos(self)
			end
		end
	end

	-- Row 3: 幻化守衛
	local rows -- the item sets behind the dropdown rows
	local select = new("DropDownControl"):DropDownControl({ "TOPLEFT", setSelect, "BOTTOMLEFT" }, { 0, 32, 216, 20 }, nil, function(index)
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
		return #M.guardianGems(itemsTab.build) > 0 and not M.isEditing(itemsTab)
	end
	select.tooltipFunc = function(tooltip, mode, index)
		tooltip:Clear()
		local row = rows and rows[index]
		if mode == "HOVER" and row and row.setId and itemsTab.AddItemSetTooltip then
			itemsTab:AddItemSetTooltip(tooltip, itemsTab.itemSets[row.setId])
		elseif mode ~= "HOVER" then
			tooltip:AddLine(16, "^7幻化守衛身上穿的裝備組。台服的角色資料不含守衛的裝備，")
			tooltip:AddLine(16, "^7請按「套用」顯示這一組，再貼上守衛的裝備（物品文字 Ctrl+V）。")
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
	controls.zhTWGuardianLabel = new("LabelControl"):LabelControl({ "RIGHT", select, "LEFT" }, { -2, 0, 0, 16 }, "^7幻化守衛:")
	controls.zhTWGuardianLabel.shown = select.shown

	local button = new("ButtonControl"):ButtonControl({ "LEFT", select, "RIGHT" }, { 4, 0, 90, 20 }, function()
		return M.isEditing(itemsTab) and "返回角色" or "套用"
	end, function()
		M.toggleEdit(itemsTab)
	end)
	button.shown = select.shown
	button.enabled = function()
		return #M.guardianGems(itemsTab.build) > 0
	end
	button.tooltipFunc = function(tooltip)
		tooltip:Clear()
		if M.isEditing(itemsTab) then
			tooltip:AddLine(16, "^7下面裝備欄換回你自己的角色裝備。")
		else
			tooltip:AddLine(16, "^7下面裝備欄改成顯示守衛的裝備，可以直接放上或更換（沒有裝備組會自動新增一組）。")
			tooltip:AddLine(16, "^7顯示守衛裝備時，左側數值是「你穿這組」的結果，按「返回角色」就恢復。")
		end
	end
	controls.zhTWGuardianEdit = button

	-- The frame: drawn as a control so it follows the rows
	local frame = new("Control"):Control({ "TOPLEFT", itemsTab, "TOPLEFT" }, { 0, 0, 0, 0 })
	frame.shown = select.shown
	frame.Draw = function()
		if M.isEditing(itemsTab) then
			drawFrame(controls.zhTWGuardianLabel, button)
		else
			drawFrame(controls.setLabel, setManage)
		end
	end
	controls.zhTWGuardianFrame = frame

	-- While the guardian's gear is shown, only the slots it can wear stay (weapons and armour); the
	-- 飾品／藥劑 slots, tree jewels and the 天賦配置 row belong to the player and are hidden
	local function guardianUses()
		local gem = M.guardianGems(itemsTab.build)[1]
		local grantedEffect = gem and (gem.grantedEffect or (gem.gemData and gem.gemData.grantedEffect))
		return grantedEffect and grantedEffect.minionUses
	end
	local function hideWhileEditing(control, keep)
		if not control then
			return
		end
		local orig = control.shown
		control.shown = function(self)
			if enabled() and M.isEditing(itemsTab) and not (keep and keep()) then
				return false
			end
			if type(orig) == "function" then
				return orig(self)
			end
			return orig ~= false
		end
	end
	local function slotUsable(slot)
		local uses = guardianUses()
		local base = slot.parentSlot or slot
		local name = base.slotName and base.slotName:gsub(" Swap$", "")
		return uses ~= nil and name ~= nil and uses[name] == true
	end
	for _, slot in ipairs(itemsTab.orderedSlots or { }) do
		hideWhileEditing(slot, not slot.nodeId and function() return slotUsable(slot) end or nil)
	end
	for _, name in ipairs({ "specSelect", "specButton", "specLabel", "zhTWJewelToggle", "zhTWJewelChips" }) do
		hideWhileEditing(controls[name])
	end

	-- The Chinese layout moves the item slots up into the hidden trade button's row (ZhTWLayout);
	-- they go below the three rows instead
	local anchor = itemsTab.slotAnchor
	if anchor then
		local origY = anchor.y
		anchor.y = function(self)
			local y = type(origY) == "function" and origY(self) or origY
			return enabled() and (y + 36) or y
		end
	end
end

return M
