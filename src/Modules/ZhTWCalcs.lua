-- Path of Building
--
-- Module: zhTW Calcs
-- 計算頁的來源表（CalcBreakdownControl）在中文介面時：
--   * 數值欄：「+12 基礎」「增加 60%」「減少 60%」「總增 10%」「總減 10%」；
--   * 屬性欄：POB 內部的詞綴名稱（SelfFreezeDuration 等）轉成中文；
--   * 技能類型欄（ModFlag / KeywordFlag）、備註欄（條件、每 X 等標籤）、來源欄轉成中文；
--   * 「Total from X:」提示與各來源合計行；
--   * 表格字體放大（列字 12 → 16）。
-- 只在中文介面作用；英文介面照 POB 原本的寫法。
--
-- Public API:
--   ZhTWCalcs.enabled()                      -> true when the Chinese interface is on
--   ZhTWCalcs.formatModValue(value, modType)
--   ZhTWCalcs.modName(name)                  -- internal mod name (CamelCase or spaced)
--   ZhTWCalcs.flags(flagNames)               -- list of ModFlag / KeywordFlag names
--   ZhTWCalcs.tags(control, mod, build)      -- 備註欄
--   ZhTWCalcs.source(sourceType)
--   ZhTWCalcs.totalFrom(sourceType)
--   ZhTWCalcs.TABLE_TEXT, ZhTWCalcs.TABLE_ROW -- table text size and row height
--
local ipairs = ipairs
local pairs = pairs
local type = type
local t_insert = table.insert
local t_concat = table.concat
local s_format = string.format

local M = { }

M.TABLE_TEXT = 16
M.TABLE_ROW = 18

function M.enabled()
	return ZhTWLocale and ZhTWLocale.enabled and true or false
end

local function tr(text)
	if type(text) ~= "string" or text == "" then
		return text
	end
	-- lookups of single words are not misses of drawn text
	local onMiss = ZhTWLocale.onMiss
	ZhTWLocale.onMiss = nil
	local out = ZhTWLocale.translate(text)
	ZhTWLocale.onMiss = onMiss
	return out
end

-- Translated only when ZhTWLocale knows it; nil otherwise
local function known(text)
	local out = tr(text)
	if out and out ~= text then
		return out
	end
	return nil
end

-- POB internal names: words and phrases -> Chinese (game terms of the Taiwan client)
local words = {
	-- damage and defences
	["Damage"] = "傷害", ["Physical"] = "物理", ["Fire"] = "火焰", ["Cold"] = "冰冷", ["Lightning"] = "閃電",
	["Chaos"] = "混沌", ["Elemental"] = "元素", ["Life"] = "生命", ["Mana"] = "魔力", ["Energy Shield"] = "能量護盾",
	["ES"] = "能量護盾", ["Ward"] = "結界", ["Armour"] = "護甲", ["Evasion"] = "閃避值", ["Accuracy"] = "命中值",
	["Defences"] = "防禦", ["Defense"] = "防禦", ["Health"] = "生命",
	["Leech"] = "偷取", ["Recoup"] = "回收", ["Pseudo Recoup"] = "類回收", ["Regen"] = "回復", ["Regen Percent"] = "百分比回復",
	["Degen"] = "流失", ["Degen Percent"] = "百分比流失", ["Recovery"] = "恢復", ["Recovery Rate"] = "恢復速度",
	["Recovery Amount"] = "恢復量", ["Recharge"] = "充能", ["Recharge Faster"] = "充能加快",
	["Resist"] = "抗性", ["Resistance"] = "抗性", ["Resist Max"] = "抗性上限", ["Penetration"] = "穿透",
	["Dot Multiplier"] = "持續傷害加成", ["Dot"] = "持續傷害", ["Damage Over Time"] = "持續傷害",
	["Crit Chance"] = "暴擊率", ["Crit Multiplier"] = "暴擊傷害加成", ["Crit"] = "暴擊", ["Critical"] = "暴擊",
	["Critical Strikes"] = "暴擊", ["Crit Extra Damage"] = "暴擊額外傷害",
	["Block Chance"] = "格擋率", ["Block"] = "格擋", ["Blocked"] = "被格擋的", ["Unblocked"] = "未被格擋的",
	["Block Recovery"] = "格擋恢復", ["Block Effect"] = "格擋效果",
	["Dodge Chance"] = "躲避率", ["Dodge"] = "躲避", ["Dodged"] = "躲避", ["Evade Chance"] = "閃避率", ["Evade"] = "閃避",
	["Evaded"] = "閃避", ["Suppression"] = "壓制", ["Suppress"] = "壓制", ["Suppressed"] = "壓制",
	["Spell Suppression Chance"] = "法術壓制率", ["Spell Suppression Effect"] = "法術壓制效果",
	["Reduction"] = "減傷", ["Damage Reduction"] = "傷害減免", ["Mitigation"] = "減傷", ["Mitigated"] = "減免的",
	["Bypass"] = "穿透", ["Absorb"] = "吸收", ["Absorb Rate"] = "吸收率", ["Absorb Limit"] = "吸收上限",
	["Guard"] = "防護", ["Aegis"] = "庇護", ["Value"] = "值", ["Val"] = "值", ["Threshold"] = "門檻",
	["Stun Threshold"] = "暈眩門檻", ["Taken"] = "承受", ["Reflected"] = "反射",
	-- ailments and effects
	["Stun"] = "暈眩", ["Interrupt Stun"] = "中斷暈眩", ["Freeze"] = "冰凍", ["Chill"] = "冰緩", ["Shock"] = "感電",
	["Ignite"] = "點燃", ["Scorch"] = "焦灼", ["Brittle"] = "易碎", ["Sap"] = "殘喘", ["Bleed"] = "流血",
	["Poison"] = "中毒", ["Poisoned"] = "中毒", ["Impale"] = "穿刺", ["Blind"] = "致盲", ["Maim"] = "癱瘓",
	["Hinder"] = "阻礙", ["Knockback"] = "擊退", ["Curse"] = "詛咒", ["Silence"] = "沉默",
	["Corrupted Blood"] = "腐化之血", ["Ailment"] = "異常狀態", ["Ailments"] = "異常狀態",
	["Elemental Ailment"] = "元素異常狀態", ["Elemental Ailments"] = "元素異常狀態", ["Damaging Ailment"] = "傷害型異常狀態",
	["Trauma"] = "創傷", ["Exposure"] = "曝露", ["Wither"] = "枯萎", ["Rage"] = "怒火", ["Rage Loss"] = "怒火流失",
	["Fortification"] = "護體", ["Fortify"] = "護體", ["Elusive"] = "迷蹤", ["Onslaught"] = "猛攻",
	["Duration"] = "持續時間", ["Effect"] = "效果", ["Chance"] = "機率", ["Stacks"] = "層數", ["Stack"] = "層數",
	["Stack Limit"] = "層數上限", ["Expire Rate"] = "消退速度", ["Faster"] = "加快", ["Slower"] = "減慢",
	["Burn Faster"] = "燃燒加快", ["Burn Slower"] = "燃燒減慢", ["Burn Rate"] = "燃燒速度",
	["Debuff Expiration Rate"] = "減益消退速度", ["Debuff"] = "減益", ["Buff"] = "增益", ["Buff Effect"] = "增益效果",
	["Buff Expire Faster"] = "增益消退加快", ["On Self"] = "（對自身）", ["Immune"] = "免疫",
	-- skills
	["Aura"] = "光環", ["Aura Effect"] = "光環效果", ["Skill"] = "技能", ["Skills"] = "技能", ["Link Effect"] = "連結效果",
	["Warcry"] = "戰吼", ["Warcry Speed"] = "戰吼速度", ["Warcry Effect"] = "戰吼效果", ["Exert"] = "激勵",
	["Speed"] = "速度", ["Action Speed"] = "行動速度", ["Movement Speed"] = "移動速度", ["Attack Speed"] = "攻擊速度",
	["Cast Speed"] = "施放速度", ["Projectile"] = "投射物", ["Projectiles"] = "投射物", ["Projectile Count"] = "投射物數量",
	["Projectile Speed"] = "投射物速度", ["Single Projectile"] = "單一投射物", ["Area Of Effect"] = "範圍效果",
	["Secondary"] = "次要", ["Tertiary"] = "第三", ["Primary"] = "主要", ["Chain"] = "連鎖", ["Chains"] = "連鎖",
	["Chain Count"] = "連鎖次數", ["Fork"] = "分岔", ["Fork Count"] = "分岔次數", ["Pierce"] = "穿透", ["Pierce Count"] = "穿透次數",
	["Split"] = "分裂", ["Splits"] = "分裂", ["Split Count"] = "分裂數量", ["Bounce Count"] = "彈跳次數",
	["Count"] = "數量", ["Repeat Count"] = "重複次數", ["Repeat"] = "重複", ["Final Repeat"] = "最後一次重複",
	["Totem"] = "圖騰", ["Totems"] = "圖騰", ["Trap"] = "陷阱", ["Mine"] = "地雷", ["Brand"] = "烙印", ["Ballista"] = "弩砲",
	["Limit"] = "上限", ["Active"] = "啟用", ["Placement Speed"] = "放置速度", ["Throw Count"] = "投擲數量",
	["Throwing Speed"] = "投擲速度", ["Laying Speed"] = "放置速度", ["Detonation"] = "引爆", ["Trigger"] = "觸發",
	["Attachment Range"] = "附著範圍", ["Seal Gain Frequency"] = "封印獲得頻率", ["Seismic Pulse Frequency"] = "地震脈衝頻率",
	["Small Explosions"] = "小型爆炸", ["Strike Target"] = "打擊目標", ["Fist Of War"] = "戰爭之拳",
	["Frost Globe"] = "冰霜球體", ["Hoarfrost"] = "白霜",
	-- flasks, charges, gems
	["Flask"] = "藥劑", ["Flask Charges"] = "藥劑充能", ["Charges"] = "充能", ["Charge"] = "充能", ["Gained"] = "獲得",
	["Generated"] = "產生", ["Used"] = "使用", ["Empty Flask"] = "空藥劑", ["Utility Flask"] = "功能藥劑",
	["Tincture"] = "藥酊", ["Tinctures"] = "藥酊", ["Mana Burn"] = "魔力燃燒", ["Mana Burn Rate"] = "魔力燃燒速度",
	["Cooldown Recovery"] = "冷卻恢復", ["Cooldown"] = "冷卻", ["Uses"] = "次數", ["Additional"] = "額外",
	["Power Charges"] = "暴擊球", ["Frenzy Charges"] = "狂怒球", ["Endurance Charges"] = "耐力球",
	["Power Charge"] = "暴擊球", ["Frenzy Charge"] = "狂怒球", ["Endurance Charge"] = "耐力球",
	["Loot"] = "掉落", ["Quantity"] = "數量", ["Rarity"] = "稀有度", ["Light Radius"] = "光照範圍", ["Radius"] = "範圍",
	["Gem"] = "寶石", ["Level"] = "等級", ["Quality"] = "品質", ["Global"] = "全域", ["Item"] = "物品", ["Socket"] = "插槽",
	["Support"] = "輔助", ["Supported"] = "輔助的", ["Reservation"] = "保留", ["Reservation Efficiency"] = "保留效率",
	["Reserved"] = "保留", ["Efficiency"] = "效率", ["Mana Multiplier"] = "魔力倍率", ["Soul Cost"] = "靈魂消耗",
	["Cost"] = "消耗", ["Reduced Mana Reservation"] = "減少魔力保留",
	-- actors
	["Corpse"] = "屍體", ["Minion"] = "召喚物", ["Spectre"] = "幽魂", ["Spectres"] = "幽魂", ["Golem"] = "魔像",
	["Stone Golem"] = "岩石魔像", ["Void Spawn"] = "虛空之子", ["Radiance Sentinel"] = "光輝哨兵",
	["Vaal Rejuvenation Totem"] = "瓦爾復甦圖騰", ["Vaal Rejuvenation Totems"] = "瓦爾復甦圖騰",
	["Party Member"] = "隊友", ["Parent"] = "本體", ["Player"] = "玩家", ["Players"] = "玩家", ["Enemy"] = "敵人",
	["Enemies"] = "敵人", ["Normal Enemies"] = "普通敵人", ["Magic Enemies"] = "魔法敵人", ["Allied"] = "友方",
	["Nightblade"] = "夜刃", ["Temporal Chains"] = "時空鎖鏈",
	-- other words
	["Total"] = "總", ["On Hit"] = "擊中時", ["On Kill"] = "擊殺時", ["On Block"] = "格擋時", ["On Spell Block"] = "法術格擋時",
	["On Suppress"] = "壓制時", ["On Crit"] = "暴擊時", ["Hit Chance"] = "命中率", ["Hit"] = "擊中", ["Hits"] = "擊中",
	["Spell"] = "法術", ["Attack"] = "攻擊", ["Melee"] = "近戰", ["Weapon"] = "武器", ["Main Hand"] = "主手",
	["Off Hand"] = "副手", ["Shield"] = "盾牌", ["Str"] = "力量", ["Dex"] = "敏捷", ["Int"] = "智慧",
	["Strength"] = "力量", ["Dexterity"] = "敏捷", ["Intelligence"] = "智慧", ["Omni"] = "全能",
	["Multiplier"] = "倍率", ["Percent"] = "百分比", ["Cull"] = "終結", ["Critical Cull"] = "暴擊終結",
	["Distance"] = "距離", ["Max"] = "上限", ["Maximum"] = "最大", ["Min"] = "下限", ["Minimum"] = "最低",
	["Increase"] = "增加", ["Extra"] = "額外", ["Base"] = "基礎", ["All"] = "全部", ["No"] = "無", ["Override"] = "覆蓋",
	["Inherent"] = "固有", ["Prevented"] = "防止", ["Lost"] = "失去", ["Loss"] = "流失", ["Delay"] = "延遲",
	["Below Half"] = "低於一半時", ["Pvp"] = "PvP", ["DPS"] = "DPS", ["Time"] = "時間", ["Frequency"] = "頻率",
	["Range"] = "範圍", ["Instead"] = "改為", ["Shared"] = "共用", ["shared"] = "共用", ["Self"] = "自身",
	["Half"] = "一半", ["Second"] = "秒", ["Killed"] = "擊殺",
	["Full Life"] = "滿血", ["Full Mana"] = "滿魔力", ["Full Energy Shield"] = "滿能量護盾", ["Low Life"] = "低血量",
	["Fortified"] = "護體狀態", ["Unnerved"] = "不安", ["Dual Wielding"] = "雙持", ["Wielding"] = "持握",
	["Inherent Dual Wielding Speed"] = "雙持固有攻擊速度", ["Inherent Dual Wielding Block"] = "雙持固有格擋",
	["Doubled Inherent Dual Wielding Speed"] = "雙持固有攻擊速度加倍", ["Doubled Inherent Dual Wielding Block"] = "雙持固有格擋加倍",
	["No Inherent Block"] = "無固有格擋", ["Ignore Movement Penalties"] = "無視移動懲罰", ["Movement Penalties"] = "移動懲罰",
	["Rare"] = "稀有", ["Unique"] = "傳奇", ["Withered"] = "枯萎", ["Withered Stack"] = "枯萎層數", ["Gale Force"] = "疾風之力",
	["Consecrated"] = "奉獻", ["Consecrated Ground"] = "奉獻地面", ["Malediction"] = "惡咒", ["Warcry Power"] = "戰吼威力",
	["Lightning Golem"] = "閃電魔像", ["Cold Golem"] = "冰冷魔像", ["Fire Golem"] = "火焰魔像", ["Chaos Golem"] = "混沌魔像",
	["Body Armour"] = "胸甲", ["Body"] = "胸甲", ["Summons Totem"] = "召喚圖騰", ["Summons"] = "召喚",
	["Enemy Config"] = "敵人設定", ["Delayed"] = "延遲", ["Moving"] = "移動中", ["Stationary"] = "靜止",
	["Leeching"] = "偷取中", ["Channelling"] = "引導中", ["Shocked"] = "感電", ["Chilled"] = "冰緩", ["Frozen"] = "冰凍",
	["Ignited"] = "點燃", ["Bleeding"] = "流血", ["Cursed"] = "被詛咒", ["Taunted"] = "被嘲諷", ["Blinded"] = "被致盲",
	["Intimidated"] = "被恐嚇", ["Maimed"] = "被癱瘓", ["Hindered"] = "被阻礙", ["Stunned"] = "被暈眩", ["Pulse"] = "脈衝", ["Tvalue"] = "T 值", ["Seal"] = "封印",
}

-- Whole names that read better written out
local overrides = {
	["3 Second Recoup"] = "3 秒回收", ["3 Second Life Recoup"] = "3 秒生命回收", ["3 Second Energy Shield Recoup"] = "3 秒能量護盾回收",
	["Add Life Recoup To Mana Recoup"] = "生命回收也套用於魔力回收",
	["Additional Chains Add Splits Instead"] = "額外連鎖改為增加分裂",
	["Additional Projectiles Add Splits Instead"] = "額外投射物改為增加分裂",
	["Armour Does Not Apply To Physical Damage Taken"] = "護甲不套用於承受的物理傷害",
	["Attack Crit Is Equal To Parent Main Hand"] = "攻擊暴擊等同本體主手",
	["Main Hand Crit Is Equal To Parent"] = "主手暴擊等同本體", ["Main Hand Crit Is Equal To Party Member"] = "主手暴擊等同隊友",
	["Blocked Damage Doesnt Bypass ES"] = "被格擋的傷害不穿透能量護盾",
	["Unblocked Damage Does Bypass ES"] = "未被格擋的傷害穿透能量護盾",
	["Chaos Not Bypass Energy Shield"] = "混沌傷害不穿透能量護盾",
	["Curse Limit Is Maximum Power Charges"] = "詛咒上限等於暴擊球上限",
	["Spell Block Chance Is Block Chance"] = "法術格擋率等於格擋率",
	["Spell Block Chance Max Is Block Chance Max"] = "法術格擋率上限等於格擋率上限",
	["Energy Shield Recharge Applies To Life"] = "能量護盾充能改為作用於生命",
	["Flask Chance Not Consume Charges"] = "藥劑不消耗充能的機率",
	["Flask Charge On Crit Chance"] = "暴擊時獲得藥劑充能的機率",
	["Flask Charges Generated Per Empty Flask"] = "每個空藥劑產生的藥劑充能",
	["Life Loss Below Half Lost"] = "生命低於一半時失去的生命", ["Life Loss Below Half Prevented"] = "生命低於一半時防止的生命流失",
	["Life Loss Prevented"] = "防止的生命流失", ["Inherent Rage Loss Is Prevented"] = "不會失去固有怒火",
	["Movement Speed Equal Highest Linked Players"] = "移動速度等同最快的連結玩家",
	["Party Member Maximum Endurance Charges Equal To Yours"] = "隊友耐力球上限等同你的",
	["Spell Skills Always Deal Critical Strikes On Final Repeat"] = "法術技能最後一次重複必定暴擊",
	["Spell Skills Cannot Deal Critical Strikes Except On Final Repeat"] = "法術技能除最後一次重複外無法暴擊",
	["Tinctures Not Inflict Mana Burn"] = "藥酊不會造成魔力燃燒", ["Cannot Multiple Poison"] = "無法多重中毒",
	["Cannot Gain Energy Shield"] = "無法獲得能量護盾", ["No Energy Shield Recharge"] = "無法能量護盾充能",
	["Replace Shield Block"] = "取代盾牌格擋", ["Unaffected By Blind"] = "不受致盲影響",
	["Pierce All Targets"] = "穿透所有目標", ["Double Enemy Stun Duration Chance"] = "敵人暈眩時間加倍的機率",
	["Self Double Stun Duration Chance"] = "自身暈眩時間加倍的機率", ["Reduce Crit Extra Damage"] = "減少承受的暴擊額外傷害",
	["Weapon Base Crit Chance"] = "武器基礎暴擊率", ["Gem Global Level"] = "全域寶石等級", ["Gem Global Quality"] = "全域寶石品質",
	["Gem Item Level"] = "物品給予的寶石等級", ["Gem Item Quality"] = "物品給予的寶石品質",
	["Gem Support Level"] = "輔助給予的寶石等級", ["Gem Support Quality"] = "輔助給予的寶石品質",
	["Gem Socket Quality"] = "插槽給予的寶石品質", ["Socket Quality"] = "插槽品質", ["Max Quality"] = "最高品質",
	["Max Level"] = "最高等級", ["Hit Chance"] = "命中率", ["DPS"] = "DPS",
	["Life On Hit"] = "擊中回復生命", ["Mana On Hit"] = "擊中回復魔力", ["Energy Shield On Hit"] = "擊中回復能量護盾",
	["Life On Kill"] = "擊殺回復生命", ["Mana On Kill"] = "擊殺回復魔力", ["Energy Shield On Kill"] = "擊殺回復能量護盾",
	["Life On Block"] = "格擋回復生命", ["Mana On Block"] = "格擋回復魔力", ["Energy Shield On Block"] = "格擋回復能量護盾",
	["Energy Shield On Spell Block"] = "法術格擋回復能量護盾",
	["Life On Suppress"] = "壓制回復生命", ["Energy Shield On Suppress"] = "壓制回復能量護盾",
	["Exert Increase"] = "激勵增加", ["Exert Attack Increase"] = "激勵攻擊增加",
	["Condition: No Fortification Mitigation"] = "條件: 護體不減傷", ["Condition: Non Poisoned Only"] = "條件: 僅未中毒",
	["Uses Warcry Power"] = "使用戰吼威力", ["Warcry Power"] = "戰吼威力",
}

-- Damage types (for "Fire Max" = maximum fire damage)
local damageTypes = { Physical = "物理", Fire = "火焰", Cold = "冰冷", Lightning = "閃電", Chaos = "混沌", Elemental = "元素" }

local nameCache = { }
local phrase

-- Words -> Chinese, longest phrase first (up to 4 words); unknown words stay English
local function joinWords(text)
	local list = { }
	for w in text:gmatch("%S+") do
		t_insert(list, w)
	end
	local out, i, lastEnglish = { }, 1, false
	while i <= #list do
		local found
		for len = math.min(4, #list - i + 1), 1, -1 do
			local key = t_concat(list, " ", i, i + len - 1)
			local zh = words[key] or overrides[key]
			if not zh and len > 1 then
				zh = known(key)
			end
			if zh then
				found = { zh = zh, len = len }
				break
			end
		end
		if found then
			t_insert(out, found.zh)
			lastEnglish = false
			i = i + found.len
		else
			local w = list[i]
			local zh = known(w)
			if zh then
				t_insert(out, zh)
				lastEnglish = false
			else
				-- keep spaces around English words
				if #out > 0 then
					t_insert(out, " ")
				end
				t_insert(out, w)
				lastEnglish = true
				if i < #list then
					t_insert(out, " ")
				end
			end
			i = i + 1
		end
	end
	return (t_concat(out):gsub("  +", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Sentence patterns of POB mod names
local rules = {
	{ "^Non (.+)$", function(a) return "非" .. phrase(a) end },
	{ "^Deal No (.+)$", function(a) return "無法造成" .. phrase(a) .. "傷害" end },
	{ "^Self (.+)$", function(a) return "自身" .. phrase(a) end },
	{ "^Enemy (.+)$", function(a) return "敵人" .. phrase(a) end },
	{ "^Totem (.+)$", function(a) return "圖騰" .. phrase(a) end },
	{ "^Total (.+) Life$", function(a) return phrase(a) .. "總生命" end },
	{ "^[Tt]aken From (.+) Before You$", function(a) return "傷害先由" .. phrase(a) .. "承受" end },
	{ "^Taken From Parent ESBefore You$", function() return "傷害先由本體能量護盾承受" end },
	{ "^Avoid (.+) Chance$", function(a) return "迴避" .. phrase(a) .. "機率" end },
	{ "^Avoid (.+) Applies To (.+)$", function(a, b) return "迴避" .. phrase(a) .. "也套用於" .. phrase(b) end },
	{ "^Avoid (.+)$", function(a) return "迴避" .. phrase(a) end },
	{ "^(.+) Immune$", function(a) return "免疫" .. phrase(a) end },
	{ "^Cannot Be (.+)$", function(a) return "無法被" .. phrase(a) end },
	{ "^Cannot (.+)$", function(a) return "無法" .. phrase(a) end },
	{ "^No Additional (.+)$", function(a) return "無額外" .. phrase(a) end },
	{ "^Have Maximum (.+)$", function(a) return "維持最大" .. phrase(a) end },
	{ "^Ignore (.+) Resistance$", function(a) return "無視" .. phrase(a) .. "抗性" end },
	{ "^reduce Enemy (.+)$", function(a) return "降低敵人" .. phrase(a) end },
	{ "^Armour Applies To (.+)$", function(a) return "護甲套用於" .. phrase(a) end },
	{ "^(.+) From Hits Taken As (.+)$", function(a, b) return "擊中承受的" .. phrase(a) .. "轉為" .. phrase(b) end },
	{ "^(.+) Taken As (.+)$", function(a, b) return "承受的" .. phrase(a) .. "轉為" .. phrase(b) end },
	{ "^(.+) Taken From Mana Before Life$", function(a) return "承受的" .. phrase(a) .. "先扣魔力" end },
	{ "^(.+) Taken When Hit$", function(a) return "被擊中時承受的" .. phrase(a) end },
	{ "^(.+) Taken Over Time$", function(a) return "承受的持續" .. phrase(a) end },
	{ "^(.+) Reflected Damage Taken$", function(a) return "承受的反射" .. phrase(a) .. "傷害" end },
	{ "^(.+) Damage Taken By (.+)$", function(a, b) return phrase(b) .. "使承受的" .. phrase(a) .. "傷害" end },
	{ "^Damage Taken By (.+)$", function(a) return phrase(a) .. "使承受的傷害" end },
	{ "^(.+) Taken$", function(a) return "承受的" .. phrase(a) end },
	{ "^(.+) Skill Convert To (.+)$", function(a, b) return "技能" .. phrase(a) .. "轉換為" .. phrase(b) end },
	{ "^(.+) Convert To (.+)$", function(a, b) return phrase(a) .. "轉換為" .. phrase(b) end },
	{ "^(.+) Gain As (.+)$", function(a, b) return phrase(a) .. "額外獲得" .. phrase(b) end },
	{ "^(.+) As Though Dealing$", function(a) return phrase(a) .. "（視為造成的傷害）" end },
	{ "^(.+) To Player$", function(a) return phrase(a) .. "（給玩家）" end },
	{ "^(.+) Is Equal To (.+)$", function(a, b) return phrase(a) .. "等同" .. phrase(b) end },
	-- condition and multiplier names (Condition: CritRecently, Multiplier: WarcryUsedRecently ...)
	{ "^(.+) In Past (%d+) Sec%a*$", function(a, n) return "過去 " .. n .. " 秒內" .. phrase(a) end },
	{ "^(.+) Recently$", function(a) return "近期" .. phrase(a) end },
	{ "^Used (.+)$", function(a) return "使用過" .. phrase(a) end },
	{ "^(.+) Used$", function(a) return "使用過" .. phrase(a) end },
	{ "^Hit By (.+)$", function(a) return "被" .. phrase(a) .. "擊中" end },
	{ "^Have (.+)$", function(a) return "擁有" .. phrase(a) end },
	{ "^Using (.+)$", function(a) return "使用" .. phrase(a) end },
	{ "^Affected By (.+)$", function(a) return "受" .. phrase(a) .. "影響" end },
	{ "^On (.+) Ground$", function(a) return "在" .. phrase(a) .. "地面上" end },
	{ "^(.+) Not Delayed By (.+)$", function(a, b) return phrase(a) .. "不會因" .. phrase(b) .. "而延遲" end },
	{ "^Quality On (.+)$", function(a) return phrase(a) .. "品質" end },
	{ "^(.+) Or (.+)$", function(a, b) return phrase(a) .. "或" .. phrase(b) end },
	{ "^(%a+) Max$", function(a) return damageTypes[a] and ("最大" .. damageTypes[a] .. "傷害") or nil end },
	{ "^(%a+) Min$", function(a) return damageTypes[a] and ("最小" .. damageTypes[a] .. "傷害") or nil end },
	{ "^Max (.+) Leech Rate$", function(a) return phrase(a) .. "偷取速度上限" end },
	{ "^(.+) Charges Max$", function(a) return phrase(a .. " Charges") .. "上限" end },
	{ "^(.+) Charges Min$", function(a) return phrase(a .. " Charges") .. "下限" end },
	{ "^(.+) Charges Duration$", function(a) return phrase(a .. " Charges") .. "持續時間" end },
}

phrase = function(text)
	if overrides[text] then
		return overrides[text]
	end
	if words[text] then
		return words[text]
	end
	for _, rule in ipairs(rules) do
		local caps = { text:match(rule[1]) }
		if caps[1] then
			local out = rule[2](unpack(caps))
			if out then
				return out
			end
		end
	end
	return joinWords(text)
end

-- Same spacing as CalcBreakdownControl:FormatModName
local function spaced(name)
	return (name:gsub("([%l%d]:?)(%u)", "%1 %2"):gsub("(%l)(%d)", "%1 %2"))
end

function M.modName(name)
	if type(name) ~= "string" or name == "" then
		return name
	end
	local c = nameCache[name]
	if c then
		return c
	end
	local text = spaced(name)
	local out
	-- "Condition: X" / "Multiplier: X"
	local head, rest = text:match("^(%a+): (.+)$")
	if head and not overrides[text] then
		local zhHead = ({ Condition = "條件", Multiplier = "數量", Skill = "技能" })[head]
		out = (zhHead or phrase(head)) .. ": " .. phrase(rest)
	else
		out = phrase(text)
	end
	nameCache[name] = out
	return out
end

-- 技能類型欄
local flagWords = {
	Attack = "攻擊", Spell = "法術", Hit = "擊中", Dot = "持續傷害", Cast = "施放", Melee = "近戰", Area = "範圍",
	Projectile = "投射物", Ailment = "異常狀態", MeleeHit = "近戰擊中", Weapon = "武器", Axe = "斧", Bow = "弓",
	Claw = "爪", Dagger = "匕首", Mace = "錘", Staff = "長杖", Sword = "劍", Wand = "法杖", Unarmed = "徒手",
	Fishing = "釣竿", WeaponMelee = "近戰武器", WeaponRanged = "遠程武器", Weapon1H = "單手武器", Weapon2H = "雙手武器",
	Aura = "光環", Curse = "詛咒", Warcry = "戰吼", Movement = "位移", Physical = "物理", Fire = "火焰", Cold = "冰冷",
	Lightning = "閃電", Chaos = "混沌", Vaal = "瓦爾", Arrow = "箭矢", Trap = "陷阱", Mine = "地雷", Totem = "圖騰",
	Minion = "召喚物", Brand = "烙印", Poison = "中毒", Bleed = "流血", Ignite = "點燃", PhysicalDot = "物理持續傷害",
	LightningDot = "閃電持續傷害", ColdDot = "冰冷持續傷害", FireDot = "火焰持續傷害", ChaosDot = "混沌持續傷害",
	MatchAll = "全部符合", SourceMask = "來源", WeaponMask = "武器",
}

function M.flagName(name)
	return flagWords[name] or known(name) or name
end

function M.flags(flagNames)
	local out = { }
	for _, name in ipairs(flagNames) do
		t_insert(out, M.flagName(name))
	end
	return t_concat(out, "、")
end

-- 數值欄
function M.formatModValue(value, modType)
	if modType == "BASE" then
		return s_format("%+g 基礎", value)
	elseif modType == "INC" then
		if value >= 0 then
			return "增加 " .. value .. "%"
		else
			return "減少 " .. -value .. "%"
		end
	elseif modType == "MORE" then
		if value >= 0 then
			return "總增 " .. value .. "%"
		else
			return "總減 " .. -value .. "%"
		end
	elseif modType == "OVERRIDE" then
		return "覆蓋: " .. tostring(value)
	elseif modType == "FLAG" then
		return value and "是" or "否"
	elseif modType == "LIST" then
		if type(value) == "table" and value.mod then
			return "詞綴: " .. M.modName(value.mod.name)
		else
			return "?"
		end
	end
	return value
end

-- 來源欄 / 「Total from X:」
local sourceWords = {
	Item = "物品", Tree = "天賦", Skill = "技能", Base = "基礎", Config = "設定", Pantheon = "眾神殿", Custom = "自訂",
	Spectre = "幽魂", Party = "隊伍", Bandit = "盜賊", Ascendancy = "昇華", Buff = "增益", Debuff = "減益",
	Charges = "充能", Multiplier = "倍率", Totem = "圖騰", Minion = "召喚物", Enemy = "敵人", Player = "玩家",
	["Max Level"] = "最高等級", ["Max Quality"] = "最高品質", ["Socket Quality"] = "插槽品質",
	["Arcane Surge"] = "秘術增強", Onslaught = "猛攻", Elusive = "迷蹤", Fortification = "護體", Blind = "致盲",
	Chill = "冰緩", Dexterity = "敏捷", Strength = "力量", Intelligence = "智慧", Rage = "怒火",
}

function M.source(sourceType)
	if type(sourceType) ~= "string" or sourceType == "" then
		return sourceType
	end
	return sourceWords[sourceType] or known(sourceType) or M.modName(sourceType)
end

function M.totalFrom(sourceType)
	return "來自" .. M.source(sourceType) .. "的合計:"
end

-- Actor of a tag
local actorWords = { enemy = "敵人", player = "玩家", minion = "召喚物", parent = "本體", partyMembers = "隊友" }

local function varList(control, var, list)
	if var then
		return M.modName(var)
	end
	local parts = { }
	for _, v in ipairs(list or { }) do
		t_insert(parts, M.modName(v))
	end
	return t_concat(parts, " / ")
end

local function modBase(mod, base)
	return mod.type == "BASE" and s_format("%+g", math.abs(base)) or math.abs(base) .. "%"
end

-- 備註欄: same tags as CalcBreakdownControl:AddModSection, written in Chinese
function M.tags(control, mod, build)
	if not mod[1] then
		return nil
	end
	local out
	local baseVal = type(mod.value) == "number" and (modBase(mod, mod.value) .. " ")
	for _, tag in ipairs(mod) do
		local desc
		local actor = tag.actor and (actorWords[tag.actor] or M.modName(tag.actor)) or ""
		if tag.type == "Condition" or tag.type == "ActorCondition" then
			local cond = (tag.var or tag.varList) and ": " .. (tag.neg and "非 " or "") .. varList(control, tag.var, tag.varList) or ""
			desc = actor .. "條件" .. cond
		elseif tag.type == "Multiplier" then
			local base = tag.base and (modBase(mod, tag.base) .. " + " .. math.abs(mod.value) .. " ") or baseVal or ""
			desc = "每 " .. (tag.div and (tag.div .. " ") or "") .. varList(control, tag.var, tag.varList) .. " " .. base
			baseVal = ""
		elseif tag.type == "PerStat" then
			local base = tag.base and (modBase(mod, tag.base) .. " + " .. math.abs(mod.value) .. " ") or baseVal or ""
			desc = "每 " .. (tag.div or 1) .. " " .. actor .. varList(control, tag.stat, tag.statList) .. " " .. base
			baseVal = ""
		elseif tag.type == "PercentStat" then
			local finalPercent = (mod.value * ((tag.percent or 1) / 100)) * 100
			local base = tag.base and (modBase(mod, tag.base) .. " + " .. math.abs(finalPercent) .. " ") or modBase(mod, finalPercent)
			desc = actor .. varList(control, tag.percentVar or tag.stat, tag.statList) .. "的 " .. base .. "%"
			baseVal = ""
		elseif tag.type == "MultiplierThreshold" or tag.type == "StatThreshold" then
			desc = "若 " .. varList(control, tag.var or tag.stat, tag.varList or tag.statList) .. (tag.upper and " <= " or " >= ")
				.. (tag.thresholdPercent and tag.thresholdPercent .. "% " or "") .. (tag.threshold or M.modName(tag.thresholdVar or tag.thresholdStat))
		elseif tag.type == "SkillName" then
			local list = { }
			for _, n in ipairs(tag.skillNameList or { tag.skillName }) do
				t_insert(list, tr(n))
			end
			desc = "技能: " .. t_concat(list, " / ")
		elseif tag.type == "SkillId" then
			local skill = build.data.skills[tag.skillId]
			desc = "技能: " .. tr(skill and skill.name or tostring(tag.skillId))
		elseif tag.type == "SkillType" then
			for name, value in pairs(SkillType) do
				if value == tag.skillType then
					desc = "技能類型: " .. (tag.neg and "非 " or "") .. (flagWords[name] or M.modName(name))
					break
				end
			end
			if not desc then
				desc = "技能類型: " .. (tag.neg and "非 " or "") .. "?"
			end
		elseif tag.type == "BaseFlag" then
			desc = "基礎標記: " .. (tag.neg and "非 " or "") .. M.modName(tostring(tag.baseFlag))
		elseif tag.type == "SlotNumber" then
			desc = "裝備於欄位 #" .. tag.num
		elseif tag.type == "GlobalEffect" then
			desc = M.modName(tag.effectType)
		elseif tag.type == "Limit" then
			desc = "上限 " .. (tag.limitVar and M.modName(tag.limitVar) or modBase(mod, tag.limit))
		elseif tag.type == "MonsterTag" then
			desc = "怪物標籤: " .. (tag.monsterTagList and t_concat(tag.monsterTagList, "/") or tostring(tag.monsterTag))
		else
			desc = M.modName(tag.type)
		end
		if desc then
			desc = desc:gsub("%s+$", "")
			out = (out and out .. "、" or "") .. desc
		end
	end
	return out
end

-- Column titles of the tables (some English words have other meanings elsewhere, e.g. Notes)
local columnWords = {
	["Value"] = "數值", ["Stat"] = "屬性", ["Skill types"] = "技能類型", ["Notes"] = "備註", ["Source"] = "來源",
	["Source Name"] = "來源名稱", ["Base"] = "基礎", ["Inc/red"] = "增加/減少", ["More/less"] = "總增/總減",
	["Total"] = "總計", ["Name"] = "名稱", ["Skill"] = "技能", ["MCM"] = "魔力倍率", ["Efficiency"] = "效率",
	["Efficiency More/less"] = "效率總增/總減", ["Reservation"] = "保留", ["From"] = "來源", ["Converted Damage"] = "轉換的傷害",
	["Conversion"] = "轉換", ["Gain"] = "額外獲得",
}

function M.column(label)
	return columnWords[label] or label
end

return M
