#@ SimpleGraphic
-- zhTW: headless test for pasting Chinese timeless jewel text (Ctrl+C and Ctrl+Alt+C).
-- Every general in Data/zhTW/Legion.lua: the seed line (with "9744(2000-10000)" roll range and
-- "(...)" after the general), the faction line and "威宏史觀 — 無法使用的值" must convert,
-- and the parsed item must have the right conqueror and seed.
--
-- Usage (from the runtime folder):
--   Path{space}of{space}Building.exe <full path of src\zhTWTimelessPasteTest.lua>
-- Results: src/zhTWTimelessPasteTest.log

local realSetMainObject, realExit, realInflate, realDeflate = SetMainObject, Exit, Inflate, Deflate
local logFile = io.open("zhTWTimelessPasteTest.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end
print = log

local pass, fail = 0, 0
local function check(ok, name, detail)
	if ok then
		pass = pass + 1
	else
		fail = fail + 1
	end
	log((ok and "OK" or "FAIL") .. "\t" .. name .. (detail and ("\t" .. detail) or ""))
end

local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	Inflate, Deflate = realInflate, realDeflate
	local ItemText = LoadModule("Modules/ZhTWItemText")
	local legion = LoadModule("Data/zhTW/Legion")

	-- Client version -> seed line template, faction line template, faction, unique, base
	local byVersion = {
		[1] = { 1, 2, "瓦爾", "輝煌的虛榮", "永恆珠寶", "vaal" },
		[2] = { 3, 2, "卡魯", "致命的驕傲", "永恆珠寶", "karui" },
		[3] = { 4, 2, "馬拉克斯", "殘酷的紀律", "永恆珠寶", "maraketh" },
		[4] = { 5, 2, "聖宗", "激進的信仰", "永恆珠寶", "templar" },
		[5] = { 6, 2, "不朽帝國", "優雅的高傲", "永恆珠寶", "eternal" },
		[6] = { 7, 2, "卡葛爾", "英勇的悲劇", "永恆珠寶", "kalguur" },
		[7] = { 8, 9, "深淵族", "潰爛復仇", "殺戮之眼珠寶", "abyss_murderous" },
		[8] = { 8, 9, "深淵族", "撲滅之握", "勘查之眼珠寶", "abyss_searching" },
		[9] = { 8, 9, "深淵族", "邪惡統治", "催眠之眼珠寶", "abyss_hypnotic" },
		[10] = { 8, 9, "深淵族", "滅亡之願", "極懼之眼珠寶", "abyss_ghastly" },
		[11] = { 10, 9, "深淵族", "重奪惡意", "拼湊之眼珠寶", "abyss_special" },
	}
	local names = { }
	for zh in pairs(legion.generals) do
		table.insert(names, zh)
	end
	table.sort(names)
	local function fill(tpl, seed, general, faction)
		return (tpl:gsub("{(%d)}", { ["0"] = faction, ["1"] = seed, ["2"] = general }))
	end
	local generalsSeen = { }
	for _, zh in ipairs(names) do
		local g = legion.generals[zh]
		local v = byVersion[g.version]
		if not v then
			check(false, zh, "unknown version " .. tostring(g.version))
		else
			for _, mode in ipairs({ "plain", "advanced" }) do
				local seedText = mode == "advanced" and "9744(2000-10000)" or "9744"
				local generalText = mode == "advanced" and (zh .. "(...)") or zh
				local lines = { "物品種類: 珠寶", "稀有度: 傳奇", v[4], v[5], "--------", "物品等級: 84", "--------" }
				if mode == "advanced" then
					table.insert(lines, "{ 傳奇詞綴 }")
				end
				table.insert(lines, fill(legion.templates[v[1]].zh, seedText, generalText, v[3]))
				table.insert(lines, fill(legion.templates[v[2]].zh, seedText, generalText, v[3]))
				table.insert(lines, mode == "advanced" and "威宏史觀 — 無法使用的值" or "威宏史觀")
				local text = table.concat(lines, "\n")
				local en, failures = ItemText.convert(text)
				local item = new("Item"):Item(en)
				item:BuildModList()
				local cb = item.jewelData and item.jewelData.conqueredBy
				local enName = g.en:gsub("^High Templar ", ""):lower()
				if enName == "mazcotl" then
					enName = "ahuana"
				end
				local good = #failures == 0 and cb and cb.id == 9744 and cb.conqueror and cb.conqueror.type == v[6]
				local historic = false
				for _, ml in ipairs(item.explicitModLines) do
					if ml.line == "Historic" then
						historic = mode == "plain" or ml.unscalable == true
					end
				end
				check(good and historic, zh .. " (" .. mode .. ")", good and historic and (g.en .. " " .. cb.conqueror.id)
					or ("failures=" .. table.concat(failures, " / ") .. " | en=" .. en:gsub("\n", " / ")))
				if good then
					generalsSeen[enName] = true
				end
			end
		end
	end
	-- Every conqueror PoB knows (ModParser conquerorList) is reachable from the Chinese names
	local expected = { "xibaqua", "zerphi", "doryani", "ahuana", "deshret", "asenath", "nasima", "balbala",
		"cadiro", "victario", "chitus", "caspiro", "kaom", "rakiata", "kiloava", "akoya", "venarius", "dominus",
		"avarius", "maxarius", "vorana", "uhtred", "medved", "tecrod", "ulaman", "kurgal", "amanamu", "zorath" }
	local missing = { }
	for _, n in ipairs(expected) do
		if not generalsSeen[n] then
			table.insert(missing, n)
		end
	end
	check(#missing == 0, "all conquerors covered", #expected - #missing .. "/" .. #expected .. " missing: " .. table.concat(missing, ", "))
end)
if not ok then
	fail = fail + 1
	log("ERROR\t" .. tostring(err))
end
log(string.format("RESULT pass %d fail %d", pass, fail))
logFile:close()
realSetMainObject({ OnInit = function() realExit() end, OnFrame = function() end })
