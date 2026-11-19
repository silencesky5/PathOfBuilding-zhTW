#@ SimpleGraphic
-- zhTW: headless test for timeless jewels and tattoos from the Taiwan server (writes zhTWLegionTest.log)
--
-- Chinese timeless jewel lines (written like the Taiwan site sends them) are converted with
-- Modules/ZhTWConverter.lua, parsed by PoB as a unique jewel, socketed into the tree, and the
-- nodes in radius are checked. Also checks Chinese names of conquered passives and tattoos.
--
-- Usage: runtime\Path{space}of{space}Building.exe <full path of src\zhTWLegionTest.lua>
local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logFile = io.open("zhTWLegionTest.log", "w")
local function log(...)
	local p = { }
	for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end
	logFile:write(table.concat(p, "\t"), "\n")
	logFile:flush()
end
local pass, fail = 0, 0
local function check(cond, label, detail)
	if cond then
		pass = pass + 1
		log("OK", label, detail or "")
	else
		fail = fail + 1
		log("FAIL", label, detail or "")
	end
end

local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	Inflate, Deflate = realInflate, realDeflate -- timeless jewel LUTs are zipped
	ZhTW = ZhTW or LoadModule("Modules/ZhTWConverter")

	-- { unique name, base, Chinese mod lines (one API entry each), conqueror type, conqueror id, seed }
	local samples = {
		-- KAI's report: two lines that showed "(PoB 尚未支援)"
		{ "Lethal Pride", { "萊基亞塔指揮領導超過14832名戰士", "範圍內的天賦臣服於卡魯" }, "karui", 2, 14832 },
		{ "Lethal Pride", { "岡姆指揮領導超過10000名戰士\n範圍內的天賦臣服於卡魯" }, "karui", 1, 10000 },
		{ "Lethal Pride", { "艾古亞指揮領導超過18000名戰士\n範圍內的天賦臣服於卡魯" }, "karui", "3_v2", 18000 },
		{ "Glorious Vanity", { "浸泡在以賽巴昆之名獻祭的2345條生命中\n範圍內的天賦臣服於瓦爾" }, "vaal", 1, 2345 },
		{ "Glorious Vanity", { "浸泡在以多里亞尼之名獻祭的8000條生命中", "範圍內的天賦臣服於瓦爾" }, "vaal", 3, 8000 },
		{ "Glorious Vanity", { "浸泡在以瑪茲科特爾之名獻祭的100條生命中\n範圍內的天賦臣服於瓦爾" }, "vaal", "2_v2", 100 },
		{ "Brutal Restraint", { "6000位部屬宣誓服從於芭芭拉的血脈\n範圍內的天賦臣服於馬拉克斯" }, "maraketh", "1_v2", 6000 },
		{ "Brutal Restraint", { "3000 位部屬宣誓服從於納西瑪的血脈\n範圍內的天賦臣服於馬拉克斯" }, "maraketh", 3, 3000 },
		{ "Brutal Restraint", { "500位部屬宣誓服從於安賽娜絲的血脈\n範圍內的天賦臣服於馬拉克斯" }, "maraketh", 2, 500 },
		{ "Militant Faith", { "為了禮讚5000名受到聖宗領導人神主感化的信眾所雕刻\n範圍內的天賦臣服於聖宗" }, "templar", 2, 5000 },
		{ "Militant Faith", { "為了禮讚 7000 名受到神主感化的信眾所雕刻\n範圍內的天賦臣服於聖宗" }, "templar", 2, 7000 },
		{ "Militant Faith", { "為了禮讚 2000 名受到聖宗瑪薩里歐斯感化的信眾所雕刻\n範圍內的天賦臣服於聖宗" }, "templar", "1_v2", 2000 },
		{ "Militant Faith", { "為了禮讚10000名受到聖宗伊爾莉斯感化的信眾所雕刻\n範圍內的天賦臣服於聖宗" }, "templar", 3, 10000 },
		-- From a real Taiwan character
		{ "Elegant Hubris", { "授銜153960個硬幣以紀念卡斯皮羅\n範圍內的天賦臣服於不朽帝國" }, "eternal", "3_v2", 153960 },
		{ "Elegant Hubris", { "授銜2000個硬幣以紀念卡迪羅\n範圍內的天賦臣服於不朽帝國" }, "eternal", 1, 2000 },
		{ "Heroic Tragedy", { "緬懷由4000位沃拉娜(沃拉娜-梅德偉)血脈所傳誦的壯舉\n範圍內的天賦臣服於卡葛爾" }, "kalguur", 1, 4000 },
		{ "Heroic Tragedy", { "緬懷由1234位烏特雷血脈所傳誦的壯舉\n範圍內的天賦臣服於卡爾葛" }, "kalguur", 2, 1234 },
		{ "Heroic Tragedy", { "緬懷由 8000 位梅德偉(沃拉娜-梅德偉)血脈所傳誦的壯舉\n範圍內的天賦臣服於卡葛爾" }, "kalguur", 3, 8000 },
	}

	-- Jewel socket reached from the class start (as in spec/System/TestRadiusJewelStatDiff_spec.lua)
	local spec = build.spec
	local function allocatePathToSocket()
		local classStart
		for _, node in pairs(spec.allocNodes) do
			if node.type == "ClassStart" then classStart = node break end
		end
		local queue, visited, parent, head = { classStart }, { [classStart.id] = true }, { }, 1
		local target
		while head <= #queue do
			local current = queue[head]
			head = head + 1
			if current.isJewelSocket then target = current break end
			for _, linked in ipairs(current.linked) do
				if not visited[linked.id] and linked.type ~= "Mastery" and linked.type ~= "AscendClassStart" then
					visited[linked.id] = true
					parent[linked.id] = current
					table.insert(queue, linked)
				end
			end
		end
		local current = target
		while current do
			current.alloc = true
			spec.allocNodes[current.id] = current
			current = parent[current.id]
		end
		return target
	end
	local socketNode = allocatePathToSocket()
	spec:BuildAllDependsAndPaths()
	runCallback("OnFrame")
	log("socket", socketNode and socketNode.id)

	for i, s in ipairs(samples) do
		local name, lines, cType, cId, seed = s[1], s[2], s[3], s[4], s[5]
		local label = string.format("#%d %s", i, name)
		-- Convert like convertModList does: one API entry at a time
		local enLines, okAll = { }, true
		for _, zh in ipairs(lines) do
			local en = ZhTW.convertModLine(zh, "explicitMods")
			if not en then
				okAll = false
				log("  not converted", zh)
			else
				table.insert(enLines, en)
			end
		end
		check(okAll, label .. " converted", table.concat(enLines, " / "):gsub("\n", " / "))
		if okAll then
			local raw = "Rarity: UNIQUE\n" .. name .. "\nTimeless Jewel\nRadius: Large\nImplicits: 0\n" .. table.concat(enLines, "\n") .. "\nHistoric\n"
			local item = new("Item"):Item(raw)
			local unsupported = { }
			for _, modLine in ipairs(item.explicitModLines or { }) do
				if modLine.extra then table.insert(unsupported, modLine.line) end
			end
			check(#unsupported == 0, label .. " no unsupported lines", table.concat(unsupported, " / "))
			local cb = item.jewelData and item.jewelData.conqueredBy
			check(cb and cb.conqueror and cb.conqueror.type == cType and tostring(cb.conqueror.id) == tostring(cId) and cb.id == seed,
				label .. " conqueredBy", cb and string.format("type=%s id=%s seed=%s", tostring(cb.conqueror and cb.conqueror.type), tostring(cb.conqueror and cb.conqueror.id), tostring(cb.id)) or "nil")
			-- Socket it and look at the nodes in radius
			if socketNode and cb and cb.conqueror then
				build.itemsTab:AddItem(item, true)
				spec.jewels[socketNode.id] = item.id
				local slot = build.itemsTab.sockets[socketNode.id]
				if slot then slot.selItemId = item.id end
				spec:BuildAllDependsAndPaths()
				local inRadius = socketNode.nodesInRadius and item.jewelRadiusIndex and socketNode.nodesInRadius[item.jewelRadiusIndex] or { }
				local total, conquered, changed, zhNames = 0, 0, 0, { }
				for nodeId in pairs(inRadius) do
					local node = spec.nodes[nodeId]
					if node and node.type ~= "Socket" and node.type ~= "Mastery" and node.type ~= "ClassStart" and node.type ~= "AscendClassStart" then
						total = total + 1
						if node.conqueredBy then conquered = conquered + 1 end
						local orig = spec.tree.nodes[nodeId]
						local sdNow, sdOrig = table.concat(node.sd or { }, "|"), table.concat(orig and orig.sd or { }, "|")
						if node.dn ~= (orig and orig.dn) or sdNow ~= sdOrig then
							changed = changed + 1
							if node.dn ~= (orig and orig.dn) and #zhNames < 3 then
								table.insert(zhNames, node.dn .. "=" .. ZhTWLocale.translate(node.dn))
							end
						end
					end
				end
				check(total > 0 and conquered == total, label .. " nodes conquered", string.format("%d/%d", conquered, total))
				check(changed > 0, label .. " nodes replaced", string.format("%d changed; %s", changed, table.concat(zhNames, ", ")))
				spec.jewels[socketNode.id] = 0
				if slot then slot.selItemId = 0 end
				build.itemsTab:DeleteItem(item, true)
			end
		end
	end

	-- Chinese names of conquered passives and tattoos (display, English -> Chinese)
	local legion = LoadModule("Data/zhTW/Legion")
	local legionNodes = spec.tree.legion and spec.tree.legion.nodes or { }
	local nNodes, nZh, missing = 0, 0, { }
	local seen = { }
	for _, node in ipairs(legionNodes) do
		if node.dn and node.dn ~= "" and not seen[node.dn] then
			seen[node.dn] = true
			nNodes = nNodes + 1
			if ZhTWLocale.translate(node.dn):find("[\128-\255]") then
				nZh = nZh + 1
			elseif #missing < 10 then
				table.insert(missing, node.dn)
			end
		end
	end
	check(nNodes > 0 and nZh / nNodes > 0.9, "timeless passive names in Chinese", string.format("%d/%d; missing: %s", nZh, nNodes, table.concat(missing, ", ")))
	local tattoos = spec.tree.tattoo and spec.tree.tattoo.nodes or { }
	local nT, nTZh, missingT = 0, 0, { }
	for dn in pairs(tattoos) do
		if dn ~= "" then
			nT = nT + 1
			if ZhTWLocale.translate(dn):find("[\128-\255]") then
				nTZh = nTZh + 1
			elseif #missingT < 10 then
				table.insert(missingT, dn)
			end
		end
	end
	check(nT > 0 and nTZh / nT > 0.9, "tattoo names in Chinese", string.format("%d/%d; missing: %s", nTZh, nT, table.concat(missingT, ", ")))
	-- Tattoo import: Chinese override names resolve to PoB's tattoo nodes
	local resolved, total = 0, 0
	for zh, en in pairs(legion.tattoos or { }) do
		local e = type(en) == "table" and en[1] or en
		if tattoos[e] then
			total = total + 1
			local resp = { skill_overrides = { ["1"] = { name = zh, stats = { } } } }
			ZhTW.convertPassiveResponse(resp)
			local o = resp.skill_overrides["1"]
			if o and tattoos[o.name] then resolved = resolved + 1 end
		end
	end
	check(total > 0 and resolved == total, "tattoo import names", string.format("%d/%d", resolved, total))
end)
if not ok then
	fail = fail + 1
	log("ERROR: " .. tostring(err))
end
log(string.format("RESULT pass %d fail %d", pass, fail))
logFile:close()
realSetMainObject({ OnInit = function() realExit() end, OnFrame = function() end })
