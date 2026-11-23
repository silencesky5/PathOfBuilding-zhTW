#@ SimpleGraphic
-- zhTW: 比較頁「套用對方設定」無頭測試（Modules/ZhTWCompareConfig.lua）
-- 用法（runtime 資料夾）：
--   set ZHTW_COMPARE_PRIMARY=<我的 Build xml>   set ZHTW_COMPARE_OTHER=<對方 Build xml>（預設用 spec/TestBuilds/3.13 的兩個）
--   Path{space}of{space}Building.exe <src\zhTWCompareConfigTest.lua 的完整路徑> → src\zhTWCompareConfigTest.log
-- 檢查：
--   1. 套用後我方目前設定組的 input、自訂詞綴和對方完全相同（我方多出的設定被清掉）。
--   2. 重算後的 DPS 等於「真的把設定改成對方的再重算」；裝備、天賦、技能沒變。
--   3. 「復原設定」還原成套用前（input、自訂詞綴、DPS）。
--   4. 按鈕：中文介面顯示「套用對方設定」並先跳確認視窗；英文介面維持原本行為。

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logPath = "zhTWCompareConfigTest.log"
local log = io.open(logPath, "w")
local fails = 0
local function out(fmt, ...)
	local line = string.format(fmt, ...)
	log:write(line, "\n")
	log:flush()
	print(line)
end
local function check(cond, fmt, ...)
	if not cond then
		fails = fails + 1
		out("FAIL " .. fmt, ...)
	else
		out("ok   " .. fmt, ...)
	end
end
local function near(a, b)
	a, b = a or 0, b or 0
	return math.abs(a - b) <= math.max(1e-6, math.abs(b) * 1e-6)
end
local function readFile(path)
	local f = io.open(path, "r")
	if not f then
		return nil
	end
	local text = f:read("*a")
	f:close()
	return text
end
local function sameTable(a, b)
	for k, v in pairs(a) do
		if b[k] ~= v then return false, k end
	end
	for k, v in pairs(b) do
		if a[k] ~= v then return false, k end
	end
	return true
end
local function modsText(configTab)
	local set = configTab.configSets[configTab.activeConfigSetId]
	local parts = { }
	for _, block in ipairs(set.customModsList or { }) do
		table.insert(parts, tostring(block.enabled) .. ":" .. (block.text or ""))
	end
	return table.concat(parts, "|")
end

local runOk, runErr = pcall(function()
dofile("HeadlessWrapper.lua")
if realInflate then Inflate, Deflate = realInflate, realDeflate end
local primaryPath = os.getenv("ZHTW_COMPARE_PRIMARY") or "../spec/TestBuilds/3.13/Dual Wield Cospris CoC.xml"
local comparePath = os.getenv("ZHTW_COMPARE_OTHER") or "../spec/TestBuilds/3.13/Generals Perforate Zerker.xml"

local main = __mainObject__.main
ZhTWLocale.enabled = true

loadBuildFromXML(assert(readFile(primaryPath), "missing " .. primaryPath), "primary")
local primary = main.modes["BUILD"]
build = primary
primary.calcsTab:BuildOutput()

local compareTab = primary.compareTab
compareTab:ImportBuild(assert(readFile(comparePath), "missing " .. comparePath), "對方")
local entry = compareTab:GetActiveCompare()
check(entry ~= nil, "對方 Build 匯入比較頁")

local pConfig, cConfig = primary.configTab, entry.configTab
-- 製造差異：我方多一個對方沒有的設定、對方多幾個（詛咒數、敵人狀態、自訂詞綴）
pConfig.input.zhTWTestOnlyMine = true
cConfig.input.conditionEnemyShocked = true
cConfig.input.multiplierCurseOnEnemy = nil
cConfig.input.overrideCurseCount = nil
cConfig.input.playerCursedWithCount = nil
cConfig.input.enemyIsBoss = "Pinnacle"
cConfig.configSets[cConfig.activeConfigSetId].customModsList = { { title = "Default", enabled = true, text = "100% more Damage" } }
cConfig:BuildModList()
entry.buildFlag = true

local function rebuild()
	primary.buildFlag = false
	primary.calcsTab:BuildOutput()
	return primary.calcsTab.mainOutput
end
local before = rebuild()
local beforeDPS = before.CombinedDPS or before.TotalDPS or 0
local beforeInput = copyTable(pConfig.input)
local beforeMods = modsText(pConfig)
local itemsBefore, skillsBefore = primary.itemsTab.activeItemSetId, #primary.skillsTab.socketGroupList
local nodesBefore = 0
for _ in pairs(primary.spec.allocNodes) do nodesBefore = nodesBefore + 1 end
local itemIdsBefore = { }
for slotName, slot in pairs(primary.itemsTab.slots) do itemIdsBefore[slotName] = slot.selItemId end

local M = LoadModule("Modules/ZhTWCompareConfig")
check(not M.canUndo(compareTab), "還沒套用時「復原設定」不能按")
check(M.applyNow(compareTab, entry), "套用對方設定")

local same, diffKey = sameTable(pConfig.input, cConfig.input)
check(same, "套用後 input 與對方相同（不同的欄位：%s）", tostring(diffKey))
check(pConfig.input.zhTWTestOnlyMine == nil, "我方多出的設定被清掉")
check(modsText(pConfig) == modsText(cConfig), "自訂詞綴與對方相同：%s", modsText(pConfig))
check(pConfig.configSets[pConfig.activeConfigSetId].customModsList ~= cConfig.configSets[cConfig.activeConfigSetId].customModsList, "自訂詞綴是複本，不會連動對方")
check(primary.buildFlag == true, "套用後標記重算")
check(pConfig.modFlag == true, "套用後 Build 標記未儲存")
local after = rebuild()
local afterDPS = after.CombinedDPS or after.TotalDPS or 0
out("  DPS 套用前 %.1f → 套用後 %.1f", beforeDPS, afterDPS)
check(not near(beforeDPS, afterDPS), "套用後 DPS 有變（含 100%% more Damage）")

-- 對照：手動把設定改成對方的再重算，結果要相同
local saved = pConfig:CreateUndoState()
pConfig:RestoreUndoState(cConfig:CreateUndoState())
local refOut = rebuild()
check(near(refOut.CombinedDPS or refOut.TotalDPS, afterDPS), "與手動改成對方設定的 DPS 相同（%.1f）", refOut.CombinedDPS or refOut.TotalDPS or 0)
pConfig:RestoreUndoState(saved)
rebuild()

-- 裝備、天賦、技能不變
local nodesAfter = 0
for _ in pairs(primary.spec.allocNodes) do nodesAfter = nodesAfter + 1 end
local itemsSame = true
for slotName, slot in pairs(primary.itemsTab.slots) do
	if itemIdsBefore[slotName] ~= slot.selItemId then itemsSame = false end
end
check(itemsSame and primary.itemsTab.activeItemSetId == itemsBefore, "裝備沒變")
check(nodesAfter == nodesBefore, "天賦沒變（%d 點）", nodesAfter)
check(#primary.skillsTab.socketGroupList == skillsBefore, "技能沒變（%d 組）", skillsBefore)

-- 復原
check(M.canUndo(compareTab), "套用後「復原設定」可以按")
check(M.undo(compareTab), "復原設定")
local same2, diffKey2 = sameTable(pConfig.input, beforeInput)
check(same2, "復原後 input 與套用前相同（不同的欄位：%s）", tostring(diffKey2))
check(modsText(pConfig) == beforeMods, "復原後自訂詞綴與套用前相同")
local restored = rebuild()
check(near(restored.CombinedDPS or restored.TotalDPS, beforeDPS), "復原後 DPS 與套用前相同（%.1f）", restored.CombinedDPS or restored.TotalDPS or 0)
check(not M.canUndo(compareTab), "復原後「復原設定」不能再按")

-- 按鈕
local btn = compareTab.controls.copyConfigBtn
local undoBtn = compareTab.controls.zhTWUndoConfigBtn
check(undoBtn ~= nil, "有「復原設定」按鈕")
local label = type(btn.label) == "function" and btn.label() or btn.label
check(label == "套用對方設定", "中文介面按鈕文字：%s", tostring(label))
local popupOpened, confirmFn
local realOpen = main.OpenConfirmPopup
main.OpenConfirmPopup = function(self, title, msg, confirmLabel, onConfirm)
	popupOpened = title
	confirmFn = onConfirm
	out("  確認視窗：%s / %s", title, (msg:gsub("\n", " ")))
end
btn.onClick()
check(popupOpened == "套用對方設定" and sameTable(pConfig.input, beforeInput), "按下後先跳確認、還沒套用")
confirmFn()
check(sameTable(pConfig.input, cConfig.input), "按確認後套用")
check(undoBtn.enabled(), "套用後復原按鈕可按")
undoBtn.onClick()
check(sameTable(pConfig.input, beforeInput), "按復原後還原")
main.OpenConfirmPopup = realOpen

-- 英文介面維持原本行為（不跳視窗）
ZhTWLocale.enabled = false
label = type(btn.label) == "function" and btn.label() or btn.label
check(label == "Copy Config from Compare Build", "英文介面按鈕文字不變")
compareTab.compareViewMode = "CONFIG"
check(not undoBtn:IsShown(), "英文介面不顯示復原按鈕")
ZhTWLocale.enabled = true

out("%s：%d 項失敗", fails == 0 and "PASS" or "FAIL", fails)
end)
if not runOk then
	out("ERROR %s", tostring(runErr))
end
log:close()
if not os.getenv("ZHTW_NO_EXIT") then
	realSetMainObject({
		OnInit = function() realExit() end,
		OnFrame = function() end,
	})
end
