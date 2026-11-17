#@ SimpleGraphic
-- zhTW: finds text that is drawn in English although the Chinese interface is on.
--
-- Imports the saved Taiwan characters (same inputs as zhTWTest.lua), draws every build tab,
-- and builds the tooltips of every item, allocated passive node and gem. Every line that
-- ZhTWLocale could not translate is counted. Results: src/zhTWCoverage.log
--
-- Usage:
--   set ZHTW_TEST_DIR=<folder with chars.json, items<N>.json, passive<N>.json>
--   set ZHTW_TEST_CHARS=1,2
--   runtime\Path{space}of{space}Building.exe src\zhTWCoverage.lua

local realSetMainObject, realExit = SetMainObject, Exit
local logFile = io.open("zhTWCoverage.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end
print = log

local misses = { }
local where = { }
local currentArea = "?"

local ok, err = xpcall(function()
	dofile("HeadlessWrapper.lua")
	-- errors inside OnFrame come with a short stack trace in the log
	PCall = function(func, ...)
		local r = { xpcall(func, function(e)
			local parts = { }
			for level = 2, 60 do
				local info = debug.getinfo(level, "Sl")
				if not info then break end
				local who = ""
				local n, v = debug.getlocal(level, 1)
				if n == "self" and type(v) == "table" then
					who = " [" .. tostring(rawget(v, "slotName") or rawget(v, "label") or rawget(v, "_className") or tostring(v)) .. "]"
				end
				table.insert(parts, info.short_src .. ":" .. tostring(info.currentline) .. who)
			end
			return tostring(e) .. " | " .. table.concat(parts, " < ")
		end, ...) }
		if r[1] then
			return nil, unpack(r, 2)
		end
		return r[2]
	end
	local dkjson = require "dkjson"
	local ZhTW = LoadModule("Modules/ZhTWConverter")
	ZhTWLocale.enabled = true
	ZhTWLocale.onMiss = function(line)
		local core = StripEscapes(line):gsub("^%s+", ""):gsub("%s+$", "")
		-- Only text with real words; skip numbers, single letters and user/build names
		if not core:find("%a%a") then
			return
		end
		misses[core] = (misses[core] or 0) + 1
		where[core] = where[core] or currentArea
	end

	local dir = os.getenv("ZHTW_TEST_DIR") or "."
	local function readFile(name)
		local f = io.open(dir .. "/" .. name, "rb")
		if not f then return nil end
		local d = f:read("*a")
		f:close()
		return d
	end

	local function frames(n)
		for _ = 1, n or 2 do
			runCallback("OnFrame")
		end
	end

	-- Build list screen
	currentArea = "BuildList"
	frames(2)

	local charList = dkjson.decode(readFile("chars.json"))
	ZhTW.convertCharacterList(charList)
	local which = os.getenv("ZHTW_TEST_CHARS") or "1,2"
	for idx in which:gmatch("%d+") do
		local itemsResp = dkjson.decode(readFile("items" .. idx .. ".json"))
		local passiveResp = dkjson.decode(readFile("passive" .. idx .. ".json"))
		local charData
		for _, c in ipairs(charList) do
			if c.name == itemsResp.character.name then charData = copyTable(c) end
		end
		charData = charData or copyTable(itemsResp.character)
		ZhTW.convertPassiveResponse(passiveResp)
		ZhTW.convertItemsResponse(itemsResp)
		newBuild()
		local treeData = copyTable(charData)
		treeData.passives = passiveResp
		treeData.jewels = passiveResp.items
		build.importTab:ImportPassiveTreeAndJewels(treeData, true)
		local itemData = copyTable(charData)
		itemData.equipment = itemsResp.items
		build.importTab:ImportItemsAndSkills(itemData, true, true, false)
		frames(2)

		-- Every tab
		for _, mode in ipairs({ "IMPORT", "NOTES", "CONFIG", "TREE", "SKILLS", "ITEMS", "CALCS", "PARTY" }) do
			currentArea = "tab " .. mode
			build.viewMode = mode
			frames(3)
		end
		do
			local c = build.importTab.controls
			for _, zh in ipairs({ true, false }) do
				ZhTWLocale.enabled = zh
				local sx, sy = c.sectionCharSiteImport:GetPos()
				local bx, by = c.sectionBuild:GetPos()
				log(string.format("== Import tab (%s): login section shown=%s, login button shown=%s, account-name section at %d,%d shown=%s, build sharing at %d, tip=%s",
					zh and "zh" or "en", tostring(c.sectionOauthCharImport:IsShown()), tostring(c.authenticateButton:IsShown()), sx, sy,
					tostring(c.sectionCharSiteImport:IsShown()), by, ZhTWLocale.tr(c.siteCharBanditNote:GetProperty("label")):sub(1, 60)))
			end
			ZhTWLocale.enabled = true
		end
		do
			local c = build.importTab.controls
			log(string.format("== Import buttons (zh): all shown=%s label=%s | tree shown=%s items shown=%s jewels box shown=%s",
				tostring(c.zhTWImportAll:IsShown()), ZhTWLocale.tr(c.zhTWImportAll:GetProperty("label")),
				tostring(c.siteCharImportTree:IsShown()), tostring(c.siteCharImportItems:IsShown()), tostring(c.siteCharImportTreeClearJewels:IsShown())))
			ZhTWLocale.enabled = false
			log(string.format("== Import buttons (en): all shown=%s | tree shown=%s items shown=%s",
				tostring(c.zhTWImportAll:IsShown()), tostring(c.siteCharImportTree:IsShown()), tostring(c.siteCharImportItems:IsShown())))
			ZhTWLocale.enabled = true
		end
		do
			local r = build.importTab.controls.siteAccountRealm
			r.selIndex = 1 -- even with PC picked earlier, the Chinese interface asks Taiwan
			log(string.format("== Site realm: zh=%s enabled=%s", r:GetSelValue().id, tostring(r:IsEnabled())))
			ZhTWLocale.enabled = false
			log(string.format("== Site realm: en=%s enabled=%s", r:GetSelValue().id, tostring(r:IsEnabled())))
			ZhTWLocale.enabled = true
			r:SelByValue("TW", "id")
			local ax = build.importTab.controls.siteAccountName:GetPos()
			log("   account name box shown=" .. tostring(build.importTab.controls.siteAccountName:IsShown()) .. " x=" .. ax)
		end
		-- Typing in edit boxes (undo states go through the wrapped EditControl methods)
		do
			local tried, failed = 0, { }
			for _, owner in ipairs({ build.importTab, build.itemsTab, build.configTab, build.notesTab }) do
				for name, ctrl in pairs(owner.controls or { }) do
					if type(ctrl) == "table" and ctrl.OnChar and ctrl.buf ~= nil and ctrl.CreateUndoState then
						tried = tried + 1
						local saved = ctrl.buf
						local ok, err = pcall(function()
							ctrl:OnChar("s")
							ctrl:OnKeyDown("BACK")
							ctrl:OnKeyDown("BACK")
						end)
						if not ok then
							table.insert(failed, tostring(name) .. ": " .. tostring(err))
						end
						pcall(function() ctrl:SetText(saved) end)
					end
				end
			end
			log(string.format("== Edit boxes typed: %d, errors %d %s", tried, #failed, table.concat(failed, " | ")))
		end
		-- Config tab option tooltips (only shown on hover, so draw them here)
		configDump = configDump or { }
		do
			currentArea = "config tooltip"
			local n = 0
			for var, control in pairs(build.configTab.varControls or { }) do
				local ok, text = pcall(function() return control:GetProperty("tooltipText") end)
				if ok and type(text) == "string" and text ~= "" then
					n = n + 1
					local tt = new("Tooltip"):Tooltip()
					tt:AddLine(14, text)
					for _, line in ipairs(tt.lines) do
						if line.text then
							local out = ZhTWLocale.tr(line.text)
							if configDump and out == line.text and StripEscapes(out):find("%a%a") then
								configDump[line.text] = true
							end
						end
					end
				end
			end
			for _, s in ipairs({ "^7Toggling this option will give you:", "^7Selecting this option will give you:",
				"^7Enabling this group will give you:", "^7Disabling this group will give you:",
				"^1This config option is conditional with missing source and is invalid." }) do
				ZhTWLocale.tr(s)
			end
			log("== Config tooltips checked: " .. n)
			if configDump and os.getenv("ZHTW_CONFIG_DUMP") then
				local keys = { }
				for k in pairs(configDump) do table.insert(keys, k) end
				table.sort(keys)
				local f = io.open(os.getenv("ZHTW_CONFIG_DUMP"), "w")
				for _, k in ipairs(keys) do f:write(k, "\n") end
				f:close()
			end
		end
		-- Gem name boxes on the skills tab (edit controls) must show Chinese too
		do
			local seen = { }
			ZhTWLocale.onDraw = function(text)
				if type(text) == "string" and text:find("%S") then
					seen[text] = true
				end
			end
			build.viewMode = "SKILLS"
			build.skillsTab:SetDisplayGroup(build.skillsTab.socketGroupList[1])
			frames(3)
			ZhTWLocale.onDraw = nil
			for k in pairs(seen) do
				log("[gem box] " .. k)
			end
		end
		-- Items tab slot positions with and without the Chinese layout
		build.viewMode = "ITEMS"
		frames(1)
		for _, enabled in ipairs({ true, false }) do
			ZhTWLocale.enabled = enabled
			local parts = { }
			for _, name in ipairs({ "Weapon 1", "Weapon 2", "Helmet", "Boots", "Amulet", "Belt", "Flask 1", "Flask 5" }) do
				local slot = build.itemsTab.slots[name]
				local x, y = slot:GetPos()
				table.insert(parts, name .. "=" .. y)
			end
			local h = build.itemsTab.controls["zhTWHeading_Helmet"]
			local hx, hy = h:GetPos()
			log(string.format("== Item slots (%s): %s | heading 防具 at %d,%d shown=%s", enabled and "zh" or "en", table.concat(parts, " "), hx, hy, tostring(h:IsShown())))
		end
		ZhTWLocale.enabled = true
		frames(1)
		-- Items tab areas (x, y, width, height)
		do
			local parts = { }
			local c = build.itemsTab.controls
			for _, name in ipairs({ "setManage", "itemList", "uniqueDB", "rareDB", "craftDisplayItem", "displayItemTip", "sharedItemList", "specSelect", "zhTWDetails", "zhTWJewelToggle" }) do
				local ctrl = c[name]
				if ctrl and ctrl:IsShown() then
					local x, y = ctrl:GetPos()
					local w, h = ctrl:GetSize()
					table.insert(parts, string.format("%s=%d,%d,%d,%d", name, x, y, w, h))
				end
			end
			local lastShown
			for _, slot in ipairs(build.itemsTab.orderedSlots) do
				if slot:IsShown() then lastShown = slot end
			end
			local lx, ly = lastShown:GetPos()
			table.insert(parts, string.format("lastSlot=%s@%d", lastShown.slotName, ly))
			log("== Items areas: " .. table.concat(parts, " ") .. " maxY=" .. tostring(build.itemsTab.maxY))
		end
		-- Jewel sockets collapsed / expanded, docked details panel
		do
			local itemsTab = build.itemsTab
			local function socketInfo()
				local shown, total, firstY = 0, 0, nil
				for _, slot in ipairs(itemsTab.orderedSlots) do
					if slot.nodeId and not slot.inactive then
						total = total + 1
						if slot:IsShown() then
							shown = shown + 1
							firstY = firstY or select(2, slot:GetPos())
						end
					end
				end
				return shown, total, firstY
			end
			for _, expanded in ipairs({ false, true }) do
				ZhTWLayout.jewelsExpanded = expanded
				frames(1)
				local shown, total, firstY = socketInfo()
				local chips = itemsTab.controls.zhTWJewelChips
				local cx, cy = chips:GetPos()
				log(string.format("== Jewels expanded=%s: sockets shown %d/%d firstY=%s chips shown=%s at %d,%d h=%d toggle=%s",
					tostring(expanded), shown, total, tostring(firstY), tostring(chips:IsShown()), cx, cy, select(2, chips:GetSize()),
					ZhTWLocale.tr(itemsTab.controls.zhTWJewelToggle:GetProperty("label"))))
			end
			ZhTWLayout.jewelsExpanded = false
			-- headless only: "Couldn't save the build file" popup from switching builds
			while main.popups[1] do
				main:ClosePopup()
			end
			frames(1)
			local vp = ZhTWLayout.detailsViewPort
			local dx, dy, dw, dh = ZhTWLayout.detailsRect(itemsTab, vp)
			log(string.format("== Details panel: %s,%s,%s,%s", tostring(dx), tostring(dy), tostring(dw), tostring(dh)))
			if not dx then
				if main.popups[1] then
					for k, c in pairs(main.popups[1].controls or { }) do
						local lbl = c.GetProperty and c:GetProperty("label")
						if type(lbl) == "string" then log("   popup " .. tostring(k) .. ": " .. lbl) end
					end
				end
				log(string.format("   why: portrait=%s displayItem=%s popup=%s shared=%s vp=%s", tostring(main.portraitMode), tostring(itemsTab.displayItem and itemsTab.displayItem.name), tostring(main.popups[1] and (main.popups[1].title or "?")), tostring(itemsTab.controls.sharedItemList:IsShown()), vp and (vp.x .. "," .. vp.width) or "nil"))
			end
			local firstId = itemsTab.itemOrderList[1]
			local tt = new("Tooltip"):Tooltip()
			itemsTab.controls.itemList:AddValueTooltip(tt, 1, firstId)
			frames(1)
			local d = itemsTab.zhTWDetails or { }
			log(string.format("== Details hover: floating tooltip lines=%d, docked item=%s, docked lines=%d",
				#tt.lines, tostring(d.item and d.item.name), d.tooltip and #d.tooltip.lines or -1))
			-- Item editor open: docked panel steps aside
			itemsTab:SetDisplayItem(itemsTab.items[firstId])
			frames(1)
			log("== Details with editor open: " .. tostring(ZhTWLayout.detailsRect(itemsTab, vp)))
			itemsTab:SetDisplayItem()
			frames(1)
		end
		-- Database toggle buttons, top bar
		do
			local itemsTab = build.itemsTab
			ZhTWLocale.enabled = true
			frames(1)
			local c = itemsTab.controls
			for _, idx in ipairs({ 1, 2, 1 }) do
				if idx == 2 then c.zhTWSourceRare:Click() else c.zhTWSourceUnique:Click() end
				frames(1)
				local function info(ctrl)
					if not ctrl:IsShown() then return "hidden" end
					local x, y = ctrl:GetPos()
					local w, h = ctrl:GetSize()
					return string.format("%d,%d %dx%d", x, y, w, h)
				end
				log(string.format("== DB source %d: uniqueDB %s | rareDB %s | label shown=%s | buttons %s / %s",
					idx, info(c.uniqueDB), info(c.rareDB), tostring(c.selectDBLabel:IsShown()),
					ZhTWLocale.tr(c.zhTWSourceUnique:GetProperty("label")), ZhTWLocale.tr(c.zhTWSourceRare:GetProperty("label"))))
			end
			local pd = build.controls.pointDisplay
			log("== Top bar points: raw=" .. tostring(pd.str) .. " | zh=" .. tostring(ZhTWLayout.pointsText(pd.str)) .. " | width " .. pd:GetSize())
			build.unsaved = true
			log("   save label (unsaved): " .. ZhTWLocale.tr(build.controls.save:GetProperty("label")))
			build.unsaved = false
			log("   save label (saved): " .. ZhTWLocale.tr(build.controls.save:GetProperty("label")))
			-- Side bar buttons and the sheet tabs above the main view
			local bc = build.controls
			local function btn(c)
				local x, y = c:GetPos()
				local w, h = c:GetSize()
				return string.format("%s%s@%d,%d,%dx%d", c:IsShown() and "" or "-", ZhTWLocale.tr(c:GetProperty("label") or "?"), x, y, w, h)
			end
			local function sheetState(lang)
				local parts = { }
				for _, n in ipairs({ "modeImport", "zhTWModeSheets", "modeConfig", "modeNotes", "modeTree", "modeSkills", "modeItems", "modeCalcs", "modeParty", "modeCompare" }) do
					table.insert(parts, btn(bc[n]))
				end
				local _, ly = bc.mainSkillLabel:GetPos()
				log("== Mode buttons (" .. lang .. "): " .. table.concat(parts, " ") .. " | main skill label y=" .. ly
					.. " | buildName shown=" .. tostring(bc.buildName:IsShown()) .. " side bar y=" .. select(2, build.anchorSideBar:GetPos()))
				local saved = build.viewMode
				for _, mode in ipairs({ "ITEMS", "SKILLS", "TREE", "CALCS", "IMPORT", "CONFIG", "PARTY", "NOTES" }) do
					build.viewMode = mode
					local vp = { x = 312, y = 32, width = main.screenW - 312, height = main.screenH - 32 }
					ZhTWLayout.adjustTabViewPort(build, vp)
					local tabs = { }
					for _, m in ipairs({ "ITEMS", "SKILLS", "TREE", "CALCS" }) do
						local c = bc["zhTWSheet" .. m]
						table.insert(tabs, (c:IsShown() and "" or "-") .. ZhTWLocale.tr(c.label) .. (c:GetProperty("locked") and "*" or "") .. "@" .. table.concat({ c:GetPos() }, ","))
					end
					log(string.format("   %s -> %s vp.y=%d h=%d strip=%s sheetBtnLocked=%s | %s", mode, build.viewMode, vp.y, vp.height,
						tostring(bc.zhTWSheetStrip:IsShown()), tostring(bc.zhTWModeSheets:GetProperty("locked")), table.concat(tabs, " ")))
					local row = { }
					for _, n in ipairs({ "pointDisplay", "levelScalingButton", "characterLevel", "classDrop", "ascendDrop", "secondaryAscendDrop", "buildLoadouts" }) do
						local c = bc[n]
						local x, y = c:GetPos()
						local w, h = c:GetSize()
						table.insert(row, string.format("%s%s@%d,%d,%dx%d", c:IsShown() and "" or "-", n, x, y, w, h))
					end
					log("      top row: " .. table.concat(row, " ") .. " | panel shown=" .. tostring(bc.zhTWTreePanel:IsShown()))
					if mode == "TREE" and lang == "zh" then
						-- points drawn as two rows inside the panel
						log("      panel points: " .. tostring(ZhTWLayout.drawPanelPoints(build, bc.pointDisplay)) .. " str=" .. tostring(bc.pointDisplay.str))
					end
				end
				build.viewMode = saved
			end
			sheetState("zh")
			-- Save on an unnamed build must still ask for a name (the build name box is hidden)
			local savedName = build.dbFileName
			build.dbFileName = nil
			local before = #main.popups
			build:SaveDBFile()
			local popup = main.popups[1]
			log("== Save unnamed build: popup opened=" .. tostring(#main.popups > before) .. " title=" .. tostring(popup and popup.title and ZhTWLocale.tr(popup.title)))
			if #main.popups > before then
				main:ClosePopup()
			end
			build.dbFileName = savedName
			ZhTWLocale.enabled = false
			sheetState("en")
			ZhTWLocale.enabled = true
		end
		-- Main skill box in the 技能 tab (moved from the side bar)
		do
			local c, sc = build.controls, build.skillsTab.controls
			local saved = build.viewMode
			build.viewMode = "SKILLS"
			for _, zh in ipairs({ true, false }) do
				ZhTWLocale.enabled = zh
				frames(1)
				local p = build.skillsTab.zhTWSkillControls
				local rows = { }
				for _, key in ipairs({ "mainSocketGroup", "mainSkill", "mainSkillPart", "mainSkillStageCount", "mainSkillMineCount", "mainSkillMinion", "mainSkillMinionSkill" }) do
					if p[key]:IsShown() then
						local _, y = p[key]:GetPos()
						rows[#rows + 1] = key .. "@" .. y
					end
				end
				local _, boxY = sc.zhTWSkillBox:GetPos()
				local _, optY = sc.optionSection:GetPos()
				local _, levelY = sc.defaultLevel:GetPos()
				local _, cardY = c.zhTWSummary:GetPos()
				local _, statY = c.statBox:GetPos()
				log(string.format("== Skills main skill box (%s): box shown=%s y=%d h=%d | gem options y=%d level y=%d | rows %s | side bar group shown=%s part shown=%s | cards y=%d stats y=%d",
					zh and "zh" or "en", tostring(sc.zhTWSkillBox:IsShown()), boxY, sc.zhTWSkillBox:GetProperty("height"), optY, levelY, table.concat(rows, " "),
					tostring(c.mainSocketGroup:IsShown()), tostring(c.mainSkillPart:IsShown()), cardY, statY))
			end
			ZhTWLocale.enabled = true
			-- choosing through the tab's copy changes the build's main skill
			local p = build.skillsTab.zhTWSkillControls
			local before = build.mainSocketGroup
			local target = #p.mainSocketGroup.list > 1 and (before == 1 and 2 or 1) or before
			p.mainSocketGroup:SetSel(target)
			frames(1)
			log(string.format("== Skills main skill select: group %d -> %d (wanted %d), list %d", before, build.mainSocketGroup, target, #p.mainSocketGroup.list))
			p.mainSocketGroup:SetSel(before)
			frames(1)
			build.viewMode = saved
		end
		-- Side bar as the Chinese layout builds it
		log("== Side bar (" .. idx .. ")")
		for _, line in ipairs(build.controls.statBox.list) do
			log(string.format("   [%d] %s | %s", line.height or 0, tostring(line[1] and ZhTWLocale.tr(line[1]) or ""), tostring(line[2] or "")))
		end
		log("   columns: " .. build.controls.statBox.columns[1].x .. " " .. build.controls.statBox.columns[1].align .. " / " .. build.controls.statBox.columns[2].x .. " " .. build.controls.statBox.columns[2].align)
		-- Tooltips
		local tooltip = new("Tooltip"):Tooltip()
		local function drainTooltip(area)
			currentArea = area
			for _, line in ipairs(tooltip.lines) do
				if line.text then
					ZhTWLocale.tr(line.text)
				end
			end
			tooltip:Clear()
		end
		for _, item in pairs(build.itemsTab.items) do
			tooltip:Clear()
			local ok2, e2 = pcall(build.itemsTab.AddItemTooltip, build.itemsTab, tooltip, item)
			if not ok2 then log("item tooltip error: " .. tostring(e2)) end
			drainTooltip("item tooltip")
		end
		local viewer = build.treeTab.viewer
		for _, node in pairs(build.spec.allocNodes) do
			tooltip:Clear()
			local ok2, e2 = pcall(viewer.AddNodeTooltip, viewer, tooltip, node, build)
			if not ok2 then log("node tooltip error: " .. tostring(e2)) end
			drainTooltip("passive tooltip")
		end
		local GemTooltip = LoadModule("Classes/GemTooltip")
		for _, group in ipairs(build.skillsTab.socketGroupList) do
			for _, gem in ipairs(group.gemList) do
				if gem.gemData then
					tooltip:Clear()
					local ok2, e2 = pcall(GemTooltip.AddGemTooltip, tooltip, build, gem)
					if not ok2 then log("gem tooltip error: " .. tostring(e2)) end
					drainTooltip("gem tooltip")
				end
			end
		end
	end

	-- Frame time with the Chinese interface on and off (last imported build)
	for _, mode in ipairs({ "TREE", "CALCS", "ITEMS", "CONFIG" }) do
		build.viewMode = mode
		frames(3)
		local times = { }
		for _, enabled in ipairs({ true, false, true }) do
			ZhTWLocale.enabled = enabled
			local t0 = os.clock()
			frames(20)
			table.insert(times, string.format("%s %.1f ms/frame", enabled and "zh" or "en", (os.clock() - t0) * 1000 / 20))
		end
		log("== Frame time " .. mode .. ": " .. table.concat(times, ", "))
	end
	ZhTWLocale.enabled = true

	-- Report
	local list = { }
	for text, n in pairs(misses) do
		table.insert(list, { text = text, n = n })
	end
	table.sort(list, function(a, b)
		if where[a.text] ~= where[b.text] then return where[a.text] < where[b.text] end
		return a.text < b.text
	end)
	log(string.format("== Untranslated lines: %d", #list))
	for _, m in ipairs(list) do
		log(string.format("[%s] %s", where[m.text], m.text))
	end
end, function(e) return tostring(e) .. "\n" .. debug.traceback() end)
if not ok then
	log("ERROR: " .. tostring(err))
end
logFile:close()

realSetMainObject({
	OnInit = function() realExit() end,
	OnFrame = function() end,
})
