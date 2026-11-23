-- zhTW: 比較頁「設定」子頁的「套用對方設定」＋「復原設定」（只在中文介面使用）
-- 把比較對象目前設定組的全部設定（勾選、數值、下拉、自訂詞綴）覆蓋到自己目前的設定組，然後重算。
-- 不動裝備、天賦、技能。套用前跳確認；套用後可按「復原設定」還原（設定頁 Ctrl+Z 也可以）。

local ZhTWCompareConfig = { }

local function configSetTitle(configTab)
	local set = configTab.configSets[configTab.activeConfigSetId]
	return set and set.title or "Default"
end

-- 直接套用（不跳確認）；回傳 true 表示有套用
function ZhTWCompareConfig.applyNow(compareTab, compareEntry)
	compareEntry = compareEntry or compareTab:GetActiveCompare()
	if not compareEntry or not compareEntry.configTab then
		return false
	end
	local pConfig = compareTab.primaryBuild.configTab
	compareTab.zhTWConfigUndo = {
		setId = pConfig.activeConfigSetId,
		state = pConfig:CreateUndoState(),
	}
	-- 對方的狀態（input＋自訂詞綴）整組蓋過來；RestoreUndoState 會清掉我方多出來的設定
	pConfig:RestoreUndoState(compareEntry.configTab:CreateUndoState())
	pConfig:UpdateCustomModsControls()
	pConfig:AddUndoState()
	compareTab.primaryBuild.buildFlag = true
	compareTab.configNeedsRebuild = true
	return true
end

function ZhTWCompareConfig.canUndo(compareTab)
	local undo = compareTab.zhTWConfigUndo
	return undo ~= nil and undo.setId == compareTab.primaryBuild.configTab.activeConfigSetId
end

function ZhTWCompareConfig.undo(compareTab)
	if not ZhTWCompareConfig.canUndo(compareTab) then
		return false
	end
	local pConfig = compareTab.primaryBuild.configTab
	pConfig:RestoreUndoState(compareTab.zhTWConfigUndo.state)
	pConfig:UpdateCustomModsControls()
	pConfig:AddUndoState()
	compareTab.zhTWConfigUndo = nil
	compareTab.primaryBuild.buildFlag = true
	compareTab.configNeedsRebuild = true
	return true
end

-- 按鈕：先確認再套用
function ZhTWCompareConfig.apply(compareTab)
	local compareEntry = compareTab:GetActiveCompare()
	if not compareEntry or not compareEntry.configTab then
		return
	end
	local msg = "把對方目前設定組的全部設定（含自訂詞綴）覆蓋到你目前的設定組「"
		.. configSetTitle(compareTab.primaryBuild.configTab) .. "」。\n"
		.. "裝備、天賦、技能不會變。\n"
		.. "套用後可按「復原設定」還原。"
	main:OpenConfirmPopup("套用對方設定", msg, "套用", function()
		ZhTWCompareConfig.applyNow(compareTab, compareEntry)
	end)
end

return ZhTWCompareConfig
