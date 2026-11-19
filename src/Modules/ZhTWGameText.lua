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
