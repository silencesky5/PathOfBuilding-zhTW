#@ SimpleGraphic
-- zhTW: headless checks for Chinese text in edit boxes and Chinese search (writes zhTWSearchTest.log)
local realSetMainObject, realExit = SetMainObject, Exit
local logFile = io.open("zhTWSearchTest.log", "w")
local function log(...)
	local p = { }
	for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
	logFile:write(table.concat(p, "\t"), "\n")
	logFile:flush()
end
local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	-- Monster names
	for _, en in ipairs({ "Ancient Construct", "Solar Guard", "Host Chrysalis", "Raging Spirit" }) do
		log("name", en, ZhTWLocale.translate(en))
	end
	-- Spectre library search
	local minions = { }
	for id, m in pairs(build.data.minions) do
		if id:find("^Metadata") then table.insert(minions, id) end
	end
	if not common.classes.MinionSearchListControl then LoadModule("Classes/MinionListControl") LoadModule("Classes/MinionSearchListControl") end
	local match = common.classes.MinionSearchListControl.DoesEntryMatchFilters
	for _, q in ipairs({ "遠古", "創造物", "日耀" }) do
		local found = { }
		for _, id in ipairs(minions) do
			if match({ data = build.data }, q, id, 1) then table.insert(found, ZhTWLocale.translate(build.data.minions[id].name)) end
		end
		log("spectre search", q, #found, table.concat(found, " / ", 1, math.min(5, #found)))
	end
	-- Unique database search
	local db = build.itemsTab.controls.uniqueDB
	for _, q in ipairs({ "金縷帽", "皮帽", "全部元素抗性" }) do
		db.controls.search:SetText(q)
		db:BuildSortOrder()
		db:ListBuilder()
		local names = { }
		for i = 1, math.min(5, #db.list) do names[i] = db.list[i].name end
		log("unique search", q, #db.list, table.concat(names, " / "))
	end
	-- Gem search (GemSelectControl uses the same check on the "contains" pass)
	for _, pair in ipairs({ { "Fireball", "火球" }, { "Ball Lightning", "電球" }, { "Raise Spectre", "幽魂" }, { "Fireball", "fire" } }) do
		log("gem match", pair[1], pair[2], tostring(ZhTWLocale.searchMatch(pair[1], pair[2])), ZhTWLocale.translate(pair[1]))
	end
	-- Edit box: paste and backspace with Chinese text
	local edit = new("EditControl"):EditControl(nil, { 0, 0, 200, 20 }, "", nil, "%c")
	edit:Insert("幽魂a庫")
	edit:OnKeyDown("BACK")
	edit:OnKeyDown("BACK")
	log("edit after 2x backspace", edit.buf, #edit.buf)
	edit:OnKeyDown("HOME")
	edit:OnKeyDown("DELETE")
	log("edit after delete at start", edit.buf, #edit.buf)
end)
if not ok then log("ERROR: " .. tostring(err)) end
logFile:close()
realSetMainObject({ OnInit = function() realExit() end, OnFrame = function() end })
