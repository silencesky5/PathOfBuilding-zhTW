#@ SimpleGraphic
-- zhTW: finds English text on the 計算 (Calcs) tab with the Chinese interface on.
--
-- Loads builds, expands every calcs section, opens the breakdown (來源表) of every cell and
-- draws it, also the tooltips of its rows. Also opens the tattoo / runegraft popup of the passive
-- tree (TreeTab:ModifyNodePopup). Every line ZhTWLocale could not translate is counted.
--
-- Usage (from the runtime folder):
--   set ZHTW_CALCS_BUILDS=<build xml>;<build xml>   (default: spec/TestBuilds/3.13 builds)
--   Path{space}of{space}Building.exe <full path of src\zhTWCalcsTest.lua>
-- Results: src/zhTWCalcsTest.log

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logFile = io.open("zhTWCalcsTest.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end
print = log

local misses, where = { }, { }
local area = "?"

local ok, err = xpcall(function()
	dofile("HeadlessWrapper.lua")
	Inflate, Deflate = realInflate, realDeflate
	ZhTWLocale.enabled = true
	local missingGlyphs = { }
	ZhTWLocale.onMissingGlyph = function(cp, line)
		missingGlyphs[cp] = missingGlyphs[cp] or StripEscapes(line):sub(1, 60)
	end
	ZhTWLocale.onMiss = function(line)
		local core = StripEscapes(line):gsub("^%s+", ""):gsub("%s+$", "")
		if not core:find("%a%a") then
			return
		end
		-- already Chinese, drawn again (the remaining English is only DPS / ES / AoE ...)
		if core:find("[\228-\233]") then
			local rest = core:gsub("[\128-\255]+", " "):gsub("DPS", ""):gsub("PoB", ""):gsub("Ctrl", ""):gsub("Shift", "")
				:gsub("%f[%a]ES%f[%A]", ""):gsub("%f[%a]AoE%f[%A]", "")
			if not rest:find("%a%a") then
				return
			end
		end
		misses[core] = (misses[core] or 0) + 1
		where[core] = where[core] or area
	end
	local function frames(n)
		for _ = 1, n or 2 do
			runCallback("OnFrame")
		end
	end
	local vp = { x = 0, y = 0, width = 1920, height = 1080 }
	local builds = os.getenv("ZHTW_CALCS_BUILDS") or table.concat({
		"../spec/TestBuilds/3.13/Generals Perforate Zerker.xml",
		"../spec/TestBuilds/3.13/Mirage Archer Toxic Rain.xml",
		"../spec/TestBuilds/3.13/OccVortex.xml",
		"../spec/TestBuilds/3.13/Dual Savior.xml",
		"../spec/TestBuilds/3.13/Dual Wield Cospris CoC.xml",
	}, ";")
	local cells, shown = 0, 0
	for path in builds:gmatch("[^;]+") do
		local f = io.open(path, "rb")
		if f then
			local xml = f:read("*a")
			f:close()
			loadBuildFromXML(xml, path)
			log("== " .. path)
			build.viewMode = "CALCS"
			local ct = build.calcsTab
			for _, section in ipairs(ct.sectionList) do
				for _, sub in ipairs(section.subSection) do
					sub.collapsed = false
				end
			end
			area = "calcs tab"
			frames(3)
			local bd = ct.controls.breakdown
			local tooltip = new("Tooltip"):Tooltip()
			for _, section in ipairs(ct.sectionList) do
				for _, sub in ipairs(section.subSection) do
					for _, row in ipairs(sub.data) do
						for _, col in ipairs(row) do
							if col.format and #col > 0 then
								cells = cells + 1
								area = sub.label .. " / " .. tostring(row.label)
								col.x, col.y, col.width, col.height = col.x or 300, col.y or 100, col.width or 100, col.height or 18
								local okBd, e = pcall(function()
									bd:SetBreakdownData(col, true)
									if bd.shown then
										shown = shown + 1
										bd:Draw(vp)
										for _, sec in ipairs(bd.sectionList) do
											if sec.type == "TABLE" then
												for _, c in ipairs(sec.colList) do
													ZhTWLocale.tr(c.label)
												end
												for _, r in ipairs(sec.rowList) do
													for k, fn in pairs(r) do
														if type(k) == "string" and k:match("Tooltip$") and type(fn) == "function" then
															tooltip:Clear()
															fn(tooltip)
															for _, line in ipairs(tooltip.lines) do
																if line.text then
																	ZhTWLocale.tr(line.text)
																end
															end
														end
													end
												end
											end
										end
									end
									bd:SetBreakdownData()
								end)
								if not okBd then
									log("breakdown error", area, e)
								end
							end
						end
					end
				end
			end
		else
			log("missing build " .. path)
		end
	end
	log(string.format("== cells %d, breakdowns shown %d", cells, shown))

	-- Tattoo / runegraft popup on the passive tree
	do
		area = "tattoo popup"
		local tt = build.treeTab
		local spec = build.spec
		local tried = { }
		for _, node in pairs(spec.nodes) do
			local kind = (node.dn == "Strength" or node.dn == "Dexterity" or node.dn == "Intelligence") and "attribute"
				or node.type == "Mastery" and "mastery" or node.type == "Notable" and "notable" or nil
			if kind and not tried[kind] and node.linkedId and #node.linkedId > 0 then
				tried[kind] = true
				local okP, e = pcall(function()
					tt:ModifyNodePopup(node)
					local popup = main.popups[1]
					local dd = popup.controls.modSelect
					local english, total = 0, #dd.list
					for i, v in ipairs(dd.list) do
						local text = ZhTWLocale.tr(v.label)
						if StripEscapes(text):match("^%s*[%a]") then
							english = english + 1
						end
						if i <= 3 then
							log(string.format("   %s [%d] %s", kind, i, (text:gsub("%s%s+", " | "))))
						end
					end
					log(string.format("== tattoo popup (%s %s): %d entries, %d start with English", kind, node.dn, total, english))
					for _, c in pairs(popup.controls) do
						local label = type(c) == "table" and c.GetProperty and c:GetProperty("label")
						if type(label) == "string" then
							ZhTWLocale.tr(label)
						end
					end
					ZhTWLocale.tr(popup.title or "")
					main:ClosePopup()
				end)
				if not okP then
					log("tattoo popup error", kind, e)
				end
			end
		end
	end

	-- Mastery effects and tattoo / runegraft lines of the latest tree (node tooltips)
	do
		for _, treeVersion in ipairs({ latestTreeVersion, "3_26" }) do
		local tree = main:LoadTree(treeVersion)
		for _, what in ipairs({ "mastery effect", "tattoo" }) do
			area = what
			local total, failed = 0, { }
			local list = what == "tattoo" and tree.tattoo and tree.tattoo.nodes or tree.masteryEffects
			for _, effect in pairs(list or { }) do
				for _, line in ipairs(effect.sd or { }) do
					total = total + 1
					local out = ZhTWLocale.tr(line)
					if out == line and line:find("%a%a") then
						table.insert(failed, line)
					end
				end
			end
			table.sort(failed)
			log(string.format("== %s lines (%s): %d, untranslated %d", what, treeVersion, total, #failed))
			for i = 1, math.min(#failed, 40) do
				log("   " .. failed[i])
			end
		end
		end
	end

	local list = { }
	for line, n in pairs(misses) do
		table.insert(list, line)
	end
	table.sort(list, function(a, b) return where[a] == where[b] and a < b or where[a] < where[b] end)
	log(string.format("== untranslated lines: %d", #list))
	for _, line in ipairs(list) do
		log(string.format("%4d  [%s]  %s", misses[line], where[line], line))
	end
	local glyphList = { }
	for cp, line in pairs(missingGlyphs) do
		table.insert(glyphList, string.format("U+%04X (%s)", cp, line))
	end
	log(string.format("== missing glyphs: %d %s", #glyphList, table.concat(glyphList, ", ")))
end, debug.traceback)
if not ok then
	log("ERROR", err)
end
logFile:close()

realSetMainObject({
	OnInit = function() realExit() end,
	OnFrame = function() end,
})
