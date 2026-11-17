#@ SimpleGraphic
-- zhTW: headless test for Chinese item text (in-game Ctrl+C) -> PoB item.
--
-- Usage (from the runtime folder):
--   set ZHTW_ITEMTEXT_DIR=<folder with *.txt item texts>   (default: docs/zhTW/samples)
--   Path{space}of{space}Building.exe <full path of src\zhTWItemTextTest.lua>
-- Results: src/zhTWItemTextTest.log

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logFile = io.open("zhTWItemTextTest.log", "w")
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
	local ItemText = LoadModule("Modules/ZhTWItemText")
	local dir = os.getenv("ZHTW_ITEMTEXT_DIR") or "../docs/zhTW/samples"
	local files = { }
	local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. "\\*.txt\"")
	for name in p:lines() do
		table.insert(files, name)
	end
	p:close()
	table.sort(files)
	local totalFailed = 0
	for _, name in ipairs(files) do
		local f = io.open(dir .. "/" .. name, "rb")
		local text = f:read("*a")
		f:close()
		log("== " .. name)
		log("isChinese", ItemText.isChinese(text))
		local en, failures, notes = ItemText.convert(text)
		log(en)
		log("-- failures: " .. #failures)
		for _, l in ipairs(failures) do log("  FAIL " .. l) end
		for _, n in ipairs(notes or { }) do log("  note " .. n) end
		totalFailed = totalFailed + #failures
		local item = new("Item"):Item(en)
		item:BuildModList()
		log("-- parsed: base=" .. tostring(item.baseName) .. " rarity=" .. tostring(item.rarity) .. " title=" .. tostring(item.title)
			.. " ilvl=" .. tostring(item.itemLevel) .. " sockets=" .. #item.sockets .. " reqLevel=" .. tostring(item.requirements.level))
		for _, listName in ipairs({ "enchantModLines", "implicitModLines", "explicitModLines" }) do
			for _, ml in ipairs(item[listName]) do
				local flags = { }
				for _, k in ipairs({ "crafted", "fractured", "implicit", "custom", "prefix", "suffix" }) do
					if ml[k] then table.insert(flags, k) end
				end
				log(string.format("  %s %s%s [%s] range=%s", listName, ml.line, ml.extra and "  (UNSUPPORTED)" or "", table.concat(flags, ","), tostring(ml.range)))
			end
		end
		log("  prefixes", #item.prefixes, "suffixes", #item.suffixes)
		for _, a in ipairs(item.prefixes) do log("   prefix", a.modId) end
		for _, a in ipairs(item.suffixes) do log("   suffix", a.modId) end
	end
	log("== total failed lines: " .. totalFailed)

	-- Prefix / suffix groups for the tooltip (Modules/ZhTWAffixType.lua)
	do
		local AffixType = LoadModule("Modules/ZhTWAffixType")
		local function show(label, item)
			local groups = AffixType.group(item)
			log("== affix groups: " .. label)
			for _, g in ipairs(groups or { }) do
				for _, ml in ipairs(g) do
					log("  " .. tostring(g.label or "?") .. "  " .. ml.line)
				end
			end
		end
		local f = io.open(dir .. "/item_staff_plain.txt", "rb")
		local text = f:read("*a")
		f:close()
		local staff = new("Item"):Item((ItemText.convert(text)))
		show("staff (plain copy, no affix info)", staff)
		local wasEnabled = ZhTWLocale.enabled
		ZhTWLocale.enabled = true
		local tooltip = new("Tooltip"):Tooltip()
		build.itemsTab:AddItemTooltip(tooltip, staff)
		ZhTWLocale.enabled = wasEnabled
		local labels = { }
		for _, line in ipairs(tooltip.lines) do
			if type(line.text) == "string" and (line.text:find("前綴", 1, true) or line.text:find("後綴", 1, true)) then
				table.insert(labels, line.text)
			end
		end
		log("== tooltip group titles: " .. table.concat(labels, ", "))
		-- Rare templates: how many explicit lines get a type
		local known, unknown, items = 0, 0, 0
		local unknownLines = { }
		for _, item in pairs(main.rareDB and main.rareDB.list or { }) do
			items = items + 1
			-- strip affix information so the lines are matched like an imported item
			local plain = new("Item"):Item(item:BuildRaw():gsub("{prefix}", ""):gsub("{suffix}", ""):gsub("\nPrefix: [^\n]*", ""):gsub("\nSuffix: [^\n]*", ""))
			local groups = AffixType.group(plain)
			for _, g in ipairs(groups or { { } }) do
				for _, ml in ipairs(g) do
					if g.label then known = known + 1 else unknown = unknown + 1; unknownLines[ml.line] = true end
				end
			end
			if not groups then
				unknown = unknown + #plain.explicitModLines
				for _, ml in ipairs(plain.explicitModLines) do unknownLines[ml.line] = true end
			end
		end
		log(string.format("== rare templates: %d items, %d lines typed, %d unknown", items, known, unknown))
		local n = 0
		for l in pairs(unknownLines) do
			n = n + 1
			if n <= 25 then log("  unknown: " .. l) end
		end
	end

	-- The "create custom item" dialog: its paste filter converts the text, the item can be saved
	do
		local f = io.open(dir .. "/item_staff.txt", "rb")
		local text = f:read("*a")
		f:close()
		build.itemsTab:EditDisplayItemText(true)
		local popup = main.popups[1]
		local edit = popup.controls.edit
		local pasted = edit.pasteFilter(text)
		edit:SetText(pasted)
		log("== custom item dialog: has non-ASCII after paste filter = " .. tostring(pasted:find("[\128-\255]") ~= nil)
			.. ", save enabled = " .. tostring(popup.controls.save.enabled()))
		popup.controls.save.onClick()
		local item = build.itemsTab.items[build.itemsTab.itemOrderList[#build.itemsTab.itemOrderList]]
		log("   added item: " .. tostring(item and item.name) .. ", popups open: " .. #main.popups)
		-- "另存一件": open the item like a double click in the list, change it, save as a copy
		local tab = build.itemsTab
		local before = #tab.itemOrderList
		local copy = new("Item"):Item(item:BuildRaw())
		copy.id = item.id
		tab:SetDisplayItem(copy)
		local shown = tab.controls.saveDisplayItemCopy:IsShown()
		copy.title = "Copy Test"
		tab.controls.saveDisplayItemCopy.onClick()
		local newest = tab.items[tab.itemOrderList[#tab.itemOrderList]]
		log(string.format("== save as copy: button shown=%s, items %d -> %d, original title=%s, copy title=%s, copy id=%s",
			tostring(shown), before, #tab.itemOrderList, tostring(tab.items[item.id].title), tostring(newest.title), tostring(newest.id)))
	end

	-- Round trip over PoB's unique items: English item -> Chinese text written like the game's
	-- Ctrl+C (Modules/ZhTWMods.lua) -> ZhTWItemText.convert -> PoB item; compare the mod lines.
	local ZhTWMods = LoadModule("Modules/ZhTWMods")
	local tables = LoadModule("Modules/ZhTWConverter").getTables()
	local function reverseMap(map, field)
		local out = { }
		for zh, v in pairs(map) do
			if type(v) == "string" then
				out[v] = out[v] or zh
			elseif type(v) == "table" then
				for _, c in ipairs(v) do
					local en = type(c) == "table" and c[field] or c
					if type(en) == "string" then
						out[en] = out[en] or zh
					end
				end
			end
		end
		return out
	end
	local uniqueZh = reverseMap(tables.uniques.uniques)
	local baseZh = reverseMap(tables.bases, "name")
	local names = { }
	for name in pairs(main.uniqueDB.list) do
		table.insert(names, name)
	end
	table.sort(names)
	local function applied(ml)
		return itemLib.applyRange(ml.line, ml.range or 0.5, ml.valueScalar)
	end
	local tried, passed, untranslatable, mismatched, reworded = 0, 0, 0, 0, 0
	local mismatchLog = { }
	for _, name in ipairs(names) do
		local src = main.uniqueDB.list[name]
		local zhName = uniqueZh[src.title]
		local zhBase = baseZh[src.baseName]
		if zhName and zhBase and zhName ~= src.title and not src.variantList and src.base and not src.base.flask then
			local lines = { "物品種類: 測試", "稀有度: 傳奇", zhName, zhBase, "--------", "物品等級: 84" }
			local enLines = { }
			local ok2 = true
			for _, listName in ipairs({ "implicitModLines", "explicitModLines" }) do
				if #src[listName] > 0 then
					table.insert(lines, "--------")
					for _, ml in ipairs(src[listName]) do
						local en = applied(ml)
						local zh = ZhTWMods.translate(en)
						if not zh then
							ok2 = false
							break
						end
						table.insert(lines, zh)
						table.insert(enLines, en)
					end
				end
			end
			if not ok2 then
				untranslatable = untranslatable + 1
			else
				tried = tried + 1
				local en, failures = ItemText.convert(table.concat(lines, "\n"))
				local item = new("Item"):Item(en)
				local got = { }
				for _, listName in ipairs({ "implicitModLines", "explicitModLines" }) do
					for _, ml in ipairs(item[listName]) do
						got[applied(ml):lower()] = true
					end
				end
				local missing = { }
				for _, l in ipairs(enLines) do
					if not got[l:lower()] then
						table.insert(missing, l)
					end
				end
				-- English wording can differ from PoB's unique text (game text is newer): what matters is
				-- that PoB still understands every line
				local function unsupported(it)
					local n, list = 0, { }
					for _, listName in ipairs({ "implicitModLines", "explicitModLines" }) do
						for _, ml in ipairs(it[listName]) do
							if ml.extra then
								n = n + 1
								table.insert(list, ml.line)
							end
						end
					end
					return n, list
				end
				local srcUnsupported = unsupported(src)
				local gotUnsupported, gotList = unsupported(item)
				if #missing > 0 then
					reworded = reworded + 1
				end
				if item.title == src.title and item.baseName == src.baseName and gotUnsupported <= srcUnsupported and #failures == 0 then
					passed = passed + 1
				else
					mismatched = mismatched + 1
					table.insert(mismatchLog, string.format("%s | title=%s base=%s fail=%d unsupported: %s | expected: %s", src.title,
						tostring(item.title), tostring(item.baseName), #failures, table.concat(gotList, " / "), table.concat(missing, " / ")))
				end
			end
		end
	end
	log(string.format("== unique round trip: %d tried, %d passed, %d mismatched (%d skipped: a mod has no Chinese text; %d passed items use newer English wording)",
		tried, passed, mismatched, untranslatable, reworded))
	for _, m in ipairs(mismatchLog) do
		log("  " .. m)
	end
end)
if not ok then
	log("ERROR: " .. tostring(err))
end
logFile:close()

realSetMainObject({
	OnInit = function() realExit() end,
	OnFrame = function() end,
})
