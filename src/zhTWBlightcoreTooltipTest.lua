#@ SimpleGraphic
-- zhTW: 腐敗之種（Putrid Seed）長出的附加天賦，提示框要列出該天賦的效果敘述（Classes/PassiveTreeView.lua）
-- 用法（runtime 資料夾）：
--   Path{space}of{space}Building.exe <src\zhTWBlightcoreTooltipTest.lua 的完整路徑> → src\zhTWBlightcoreTooltipTest.log
-- 檢查：中文介面下附加天賦的提示框含原天賦每一行效果；英文介面維持原本（只有 Allocates X）。

local realSetMainObject, realExit = SetMainObject, Exit
local log = io.open("zhTWBlightcoreTooltipTest.log", "w")
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

local runOk, runErr = pcall(function()
dofile("HeadlessWrapper.lua")
local main = __mainObject__.main
ZhTWLocale.enabled = true
newBuild()
local spec = build.spec
local tree = spec.tree

-- 找一個有腐敗之種版面的大型珠寶插槽
local socketId
for id in pairs(tree.blightcoreLayouts) do
	if not socketId or id < socketId then socketId = id end
end
check(socketId ~= nil, "天賦樹有腐敗之種版面（插槽 %s）", tostring(socketId))

local notables = { "Contemplative Meditation", "Storm Weaver", "Stamina", "Swagger" } -- 沉思冥想、風暴織者、充沛精力、雙刃之舞
local available = { }
for _, name in ipairs(notables) do
	if tree.notableMap[name:lower()] then table.insert(available, name) end
end
local lines = { "Rarity: UNIQUE", "Putrid Seed", "Mycelium Core" }
for _, name in ipairs(available) do
	table.insert(lines, "1 Added Passive Skill is " .. name)
end
local item = new("Item"):Item(table.concat(lines, "\n"))
check(item.jewelData and item.jewelData.blightcoreNotables and #item.jewelData.blightcoreNotables == #available, "珠寶解析出 %d 個附加天賦", #available)
build.itemsTab:AddItem(item, true)
local slot = build.itemsTab.sockets[socketId]
slot:SetSelItemId(item.id)
spec:AllocNode(spec.nodes[socketId])
spec:BuildAllDependsAndPaths()
spec:BuildClusterJewelGraphs()
build.buildFlag = true
build.calcsTab:BuildOutput()

local grown = { }
for _, node in pairs(spec.nodes) do
	if node.isBlightcore and node.sd and node.sd[1] and node.sd[1]:match("^Allocates ") then
		table.insert(grown, node)
	end
end
check(#grown == #available, "長出 %d 個附加天賦點", #grown)

local function tooltipText(node)
	local tip = { lines = { } }
	local fake = setmetatable({ }, { __index = function(t, k)
		if k == "AddLine" then
			return function(self, size, text) table.insert(tip.lines, text or "") end
		end
		return function() end
	end })
	build.treeTab.viewer:AddNodeTooltip(fake, node, build)
	return table.concat(tip.lines, "\n")
end

for _, node in ipairs(grown) do
	local name = node.sd[1]:match("^Allocates (.+)$")
	local notable = tree.notableMap[name:lower()]
	local text = tooltipText(node)
	local missing
	for _, line in ipairs(notable.sd) do
		if not text:find(line, 1, true) then missing = line break end
	end
	check(not missing, "中文介面「%s」提示框含 %d 行效果%s", name, #notable.sd, missing and ("，缺：" .. missing) or "")
	ZhTWLocale.enabled = false
	local enText = tooltipText(node)
	ZhTWLocale.enabled = true
	check(not enText:find(notable.sd[1], 1, true), "英文介面「%s」維持原本", name)
end

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
