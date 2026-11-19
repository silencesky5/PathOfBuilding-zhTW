-- Path of Building
--
-- Module: zhTW Game Text
-- 中文介面才用：
--   * 寶石說明：以 granted effect id 取台服客戶端的中文說明（Data/zhTW/GemDescriptions.lua，
--     Export/Scripts/zhTWExtra.lua 匯出）。POB 的英文說明常和客戶端不同（舊版文字、斷行），
--     多行說明在提示框裡又是逐行翻譯，只靠英文原文對照會漏掉。
--   * 塗油配方：天賦樹資料的 node.recipe（POB 自己的資料，例如 { "GoldenOil", ... }）→「塗油：金黃油瓶、…」。
--     油的中文名來自台服底材名稱（Data/zhTW/Bases.lua 反查，經 ZhTWLocale.translate）。
--
-- Public API:
--   ZhTWGameText.gemDescription(grantedEffect) -> 中文說明或 nil
--   ZhTWGameText.oilName(recipeId)              -> "金黃油瓶"（翻不到時回傳英文名）
--   ZhTWGameText.recipeLine(recipe)             -> "塗油：A、B、C" 或 nil
--   ZhTWGameText.statLine(line)                 -> 寶石 stat 描述（整段，含多行）的中文，翻不到回傳原文
--
local ipairs = ipairs
local t_insert = table.insert
local t_concat = table.concat

local M = { }

local gemDescriptions
function M.gemDescription(grantedEffect)
	if type(grantedEffect) ~= "table" or not grantedEffect.id then
		return nil
	end
	if gemDescriptions == nil then
		local ok, tbl = pcall(LoadModule, "Data/zhTW/GemDescriptions")
		gemDescriptions = ok and type(tbl) == "table" and tbl or false
	end
	return gemDescriptions and gemDescriptions[grantedEffect.id] or nil
end

-- "GoldenOil" -> "Golden Oil" -> "金黃油瓶"
local oilCache = { }
function M.oilName(recipeId)
	if type(recipeId) ~= "string" then
		return nil
	end
	if not oilCache[recipeId] then
		local en = recipeId:gsub("(%l)(%u)", "%1 %2")
		local zh = ZhTWLocale and ZhTWLocale.translate(en) or en
		oilCache[recipeId] = zh
	end
	return oilCache[recipeId]
end

-- 寶石的 stat 描述（可能多行，例如「最高可使用物品需求等級 {1}」接「幻化武器轉化至…」）：
-- 整段交給 ZhTWMods 翻譯，翻不到就原樣回傳。提示框會依換行拆開，逐行翻譯對不上多行描述。
function M.statLine(line)
	if type(line) ~= "string" or line == "" or line:find("[\128-\255]") then
		return line
	end
	ZhTWMods = ZhTWMods or LoadModule("Modules/ZhTWMods")
	local function try(text)
		local ok, zh = pcall(ZhTWMods.translate, text)
		if not (ok and type(zh) == "string" and zh ~= "") and ZhTWMods.translateLoose then
			ok, zh = true, ZhTWMods.translateLoose(text)
		end
		return ok and type(zh) == "string" and zh ~= "" and zh ~= text and zh or nil
	end
	local zh = try(line)
	if zh then
		return zh
	end
	-- POB 的英文有時在句子中間多斷一行（"random Unique\nWeapons with ..."），客戶端沒有：
	-- 依序試著把某些換行改成空白（最多 3 個換行，8 種組合）
	local parts = { }
	for part in (line .. "\n"):gmatch("([^\n]*)\n") do
		t_insert(parts, part)
	end
	local breaks = #parts - 1
	if breaks >= 1 and breaks <= 3 then
		for mask = 1, 2 ^ breaks - 1 do
			local out = { parts[1] }
			for i = 1, breaks do
				local join = math.floor(mask / 2 ^ (i - 1)) % 2 == 1
				t_insert(out, join and " " or "\n")
				t_insert(out, parts[i + 1])
			end
			zh = try(t_concat(out))
			if zh then
				return zh
			end
		end
	end
	return line
end

-- StatDescriber 把多行描述拆成單行回傳。從每一行開始，先試著把接下來最多 3 行合成一段翻譯
-- （statLine 會試換行／空白兩種接法），翻得到就整段用；翻不到才逐行翻。
-- 回傳新的行列表；lineMap 也補上中文行（指向第一行的 stat）。
local spanCache = { }
local spanCacheSize = 0
function M.statLines(descriptions, lineMap)
	local out = { }
	local i, n = 1, #descriptions
	while i <= n do
		local used = false
		for span = math.min(3, n - i + 1), 2, -1 do
			local whole = t_concat(descriptions, "\n", i, i + span - 1)
			local zh = spanCache[whole]
			if zh == nil then
				zh = M.statLine(whole)
				if spanCacheSize > 5000 then
					spanCache, spanCacheSize = { }, 0
				end
				spanCache[whole] = zh
				spanCacheSize = spanCacheSize + 1
			end
			if zh ~= whole then
				lineMap[zh] = lineMap[zh] or lineMap[descriptions[i]]
				t_insert(out, zh)
				i = i + span
				used = true
				break
			end
		end
		if not used then
			local line = descriptions[i]
			local zh = M.statLine(line)
			lineMap[zh] = lineMap[zh] or lineMap[line]
			t_insert(out, zh)
			i = i + 1
		end
	end
	return out
end

function M.recipeLine(recipe)
	if type(recipe) ~= "table" or #recipe == 0 then
		return nil
	end
	local names = { }
	for _, id in ipairs(recipe) do
		t_insert(names, M.oilName(id) or id)
	end
	return "塗油：" .. t_concat(names, "、")
end

return M
