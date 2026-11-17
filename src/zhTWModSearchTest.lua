#@ SimpleGraphic
-- zhTW: headless test for the 新增詞綴 popup (Modules/ZhTWModSearch.lua)
-- Usage: Path{space}of{space}Building.exe <full path of src\zhTWModSearchTest.lua>  → src/zhTWModSearchTest.log

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logFile = io.open("zhTWModSearchTest.log", "w")
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
	newBuild()
	local itemsTab = build.itemsTab
	itemsTab:CreateDisplayItemFromRaw("Rarity: RARE\nTest Ring\nSapphire Ring\nItem Level: 84\nImplicits: 1\n+25% to Cold Resistance\n+40 to maximum Life")
	itemsTab:AddCustomModifierToDisplayItem()
	local controls = main.popups[1].controls
	local function dump(title)
		local list = controls.modSelect.list
		log(string.format("-- %s: %d shown (%s)", title, #list, controls.zhTWSearchCount:GetProperty("label")))
		for i = 1, math.min(6, #list) do
			log("   " .. list[i].label)
		end
	end
	for index, source in ipairs(controls.source.list) do
		controls.source.selIndex = index
		controls.source.selFunc(index, source)
		dump("source " .. source.label)
	end
	-- 工藝台 + search
	controls.source.selIndex = 1
	controls.source.selFunc(1, controls.source.list[1])
	for _, q in ipairs({ "魔力", "抗性", "spell", "火焰 抗性", "zzzz", "" }) do
		controls.zhTWSearch:SetText(q)
		controls.zhTWSearch.changeFunc(q)
		dump("search '" .. q .. "'")
	end
	-- search, then sort, the filter must stay
	controls.zhTWSearch:SetText("生命")
	controls.zhTWSearch.changeFunc("生命")
	controls.sort.selIndex = 1
	controls.sort.selFunc(1, controls.sort.list[1])
	dump("search 生命 then sort")
	-- add the selected modifier
	local before = #itemsTab.displayItem.explicitModLines
	controls.modSelect.selIndex = 1
	local wanted = controls.modSelect.list[1].mod[1]
	controls.save.onClick()
	log("added lines", before, "->", #itemsTab.displayItem.explicitModLines, "wanted", wanted)
	for _, ml in ipairs(itemsTab.displayItem.explicitModLines) do log("   " .. ml.line) end
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
