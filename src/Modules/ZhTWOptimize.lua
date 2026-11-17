-- Path of Building
--
-- Module: zhTW Optimize
-- 裝備頁「稀有裝備傷害最佳化」：對稀有裝備的底材，在遊戲規則內找出 DPS 最高的詞綴組合。
--   * 詞綴來源：POB 自己的詞綴表（item.affixes），只取能自然出現的（權重 > 0、非化石專屬）、
--     等級不超過物品等級的前綴／後綴；同一個 mod group 只取一個；最多 3 前綴 3 後綴。
--   * 數值取最高（range = 1）。
--   * 計算：POB 的 GetMiscCalculator（和物品提示的「裝上後的變化」同一套），
--     比較的是主要技能的 DPS；DPS 相同時用生命＋能量護盾當次要依據。
--   * 不能改的詞綴保留：破裂詞綴；瑪文的昇華（Elevated）詞綴不算（不會自然出現）；
--     已汙染的物品照樣計算，結果是不帶汙染的新物品。
--   * 勾選「保留抗性」：火／冰／電／混沌各自的抗性總量不低於目前，用最少的欄位湊（可換成全抗、雙抗），
--     剩下的欄位放傷害詞綴；最大抗性詞綴原樣保留；湊不到時才把原本的抗性詞綴原樣留著。
--   * 結果以新物品加入裝備清單（[尚未使用]），不會換掉身上的裝備。
--
-- Public API:
--   ZhTWOptimize.setup(itemsTab)   -- 在裝備頁加按鈕（只在中文介面顯示）
--   ZhTWOptimize.optimizeSlot(itemsTab, slot, keepRes, yield) -- 測試用，回傳結果表
--
local ipairs = ipairs
local pairs = pairs
local t_insert = table.insert
local t_sort = table.sort
local s_format = string.format
local m_max = math.max

local M = { }

local POOL_SIZE = 8        -- 單獨效果最好的前幾名才進入組合搜尋（每種前綴／後綴）
local SWAP_PASSES = 2      -- 組好之後，逐一嘗試替換的輪數
local FRAME_BUDGET = 25    -- 每個畫面最多計算幾毫秒（避免整個視窗卡住）

local function enabled()
	return ZhTWLocale and ZhTWLocale.enabled
end

-- 和 ZhTWAffixType 相同的正規化：數字換成 #
local function normalise(line)
	return (line:lower()
		:gsub("%-?[%d%.]+%(%-?[%d%.]+%-%-?[%d%.]+%)", "#")
		:gsub("%(%-?[%d%.]+%-%-?[%d%.]+%)", "#")
		:gsub("%-?%d+%.?%d*", "#")
		:gsub("[%+%-]#", "#")
		:gsub("%s+", " "))
end

-- 自己的抗性（正值）："+40% to Fire Resistance"、"+15% to all Elemental Resistances"、"+1% to maximum Cold Resistance"
local function isResistLine(line)
	local lower = line:lower()
	return lower:match("^%+[%d%.]+%% to [%a ]*resistances?$") ~= nil
end

local ELEMENTS = { "fire", "cold", "lightning", "chaos" }

-- 一行抗性加多少：{ fire = 40 } / 全抗 → 火冰電；最大抗性回傳 nil（另外保留）
local function resistOf(line)
	local value, target = line:lower():match("^%+([%d%.]+)%% to ([%a ]-) resistances?$")
	if not value or target:match("maximum") then
		return nil
	end
	value = tonumber(value)
	local res = { }
	if target == "all elemental" then
		res.fire, res.cold, res.lightning = value, value, value
	else
		for name in (target .. " and "):gmatch("(%a+) and ") do
			if name ~= "fire" and name ~= "cold" and name ~= "lightning" and name ~= "chaos" then
				return nil
			end
			res[name] = value
		end
	end
	return next(res) and res or nil
end

local function isMaxResistLine(line)
	return isResistLine(line) and line:lower():match("maximum") ~= nil
end

-- 一個詞綴的抗性（每一行都要是抗性才算抗性詞綴）
local function modResist(mod)
	local total = { }
	for _, line in ipairs(mod) do
		local res = resistOf(itemLib.applyRange(line, 1))
		if not res then
			return nil
		end
		for k, v in pairs(res) do
			total[k] = (total[k] or 0) + v
		end
	end
	return next(total) and total or nil
end

-- 用最少的欄位湊到需要的抗性（同欄位數時，多出來的抗性越多越好）
local function pickResistSet(cands, need, capacity)
	local resCands = { }
	for _, cand in ipairs(cands) do
		cand.resist = modResist(cand.mod)
		if cand.resist and capacity[cand.type] > 0 then
			t_insert(resCands, cand)
		end
	end
	local best, bestSize, bestSurplus
	local function check(set)
		local surplus = 0
		for _, e in ipairs(ELEMENTS) do
			local got = 0
			for _, c in ipairs(set) do
				got = got + (c.resist[e] or 0)
			end
			if got < (need[e] or 0) then
				return
			end
			surplus = surplus + got - (need[e] or 0)
		end
		if not best or #set < bestSize or (#set == bestSize and surplus > bestSurplus) then
			best, bestSize, bestSurplus = { unpack(set) }, #set, surplus
		end
	end
	local set, used = { }, { Prefix = 0, Suffix = 0 }
	local function walk(start)
		check(set)
		if #set >= 3 then
			return
		end
		for i = start, #resCands do
			local c = resCands[i]
			local ok = used[c.type] < capacity[c.type]
			for _, o in ipairs(set) do
				if o.group == c.group then
					ok = false
				end
			end
			if ok then
				t_insert(set, c)
				used[c.type] = used[c.type] + 1
				walk(i + 1)
				set[#set] = nil
				used[c.type] = used[c.type] - 1
			end
		end
	end
	walk(1)
	return best
end

-- 同一組詞綴裡比較數值大小：最高數值的總和
local function modValue(mod)
	local total = 0
	for _, line in ipairs(mod) do
		for num in itemLib.applyRange(line, 1):gmatch("%d+%.?%d*") do
			total = total + tonumber(num)
		end
	end
	return total
end

-- 主要技能 DPS（召喚物技能用召喚物的）
local function dpsOf(output)
	if not output then
		return 0
	end
	local dps = output.CombinedDPS or 0
	if dps <= 0 and output.Minion then
		dps = output.Minion.CombinedDPS or 0
	end
	return dps
end

local function scoreOf(output)
	return dpsOf(output) + ((output.Life or 0) + (output.EnergyShield or 0)) * 1e-4
end

local function slotLabel(slot)
	local label = slot.label or slot.slotName
	if ZhTWLocale and ZhTWLocale.tr then
		label = ZhTWLocale.tr(label) or label
	end
	return label
end

-- 可以最佳化的欄位：身上的稀有裝備（不含藥劑、珠寶）
function M.listSlots(itemsTab)
	local list = { }
	for _, slot in ipairs(itemsTab.orderedSlots or { }) do
		if not slot.nodeId and not slot.slotName:match("^Flask") and not slot.slotName:match("Swap") and not slot.inactive then
			local item = itemsTab.items[slot.selItemId]
			if item and item.rarity == "RARE" and item.base and item.affixes and not item.base.flask
				and item.type ~= "Jewel" and (not slot.IsShown or slot:IsShown()) then
				t_insert(list, slot)
			end
		end
	end
	return list
end

-- 不會變動的詞綴：破裂；keepRes = "lines" 時原本的抗性詞綴，"max" 時最大抗性詞綴。回傳 { modLine, type }
local function keptLines(item, keepRes)
	ZhTWAffixType = ZhTWAffixType or LoadModule("Modules/ZhTWAffixType")
	local present = { }
	for _, modLine in ipairs(item.explicitModLines) do
		present[normalise(modLine.line)] = true
	end
	local kept = { }
	for _, modLine in ipairs(item.explicitModLines) do
		local keep = modLine.fractured or (keepRes == "lines" and isResistLine(modLine.line))
			or (keepRes == "max" and isMaxResistLine(modLine.line))
		if keep then
			local t = ZhTWAffixType.getType(item, modLine, present)
			if t ~= "Prefix" and t ~= "Suffix" then
				t = isResistLine(modLine.line) and "Suffix" or "Prefix"
			end
			t_insert(kept, { modLine = modLine, type = t })
		end
	end
	return kept
end

-- 候選詞綴：每個 mod group（＋詞綴內容）取物品等級允許、數值最高的一階
local function candidateMods(item, blockedKeys)
	local ilvl = item.itemLevel or 100
	local best = { }
	for modId, mod in pairs(item.affixes) do
		if (mod.type == "Prefix" or mod.type == "Suffix") and (mod.level or 1) <= ilvl
			and not item:CheckIfModIsDelve(mod) and not (mod.affix or ""):match("Elevated")
			and item:GetModSpawnWeight(mod) > 0 then
			local blocked = false
			for _, line in ipairs(mod) do
				if blockedKeys[normalise(line)] then
					blocked = true
					break
				end
			end
			if not blocked then
				local key = (mod.group or modId) .. "|" .. table.concat(mod.statOrder or { }, ",")
				local cur = best[key]
				local value = modValue(mod)
				if not cur or value > cur.value or (value == cur.value and (mod.level or 0) > (cur.mod.level or 0)) then
					best[key] = { id = modId, mod = mod, group = mod.group or modId, type = mod.type, value = value }
				end
			end
		end
	end
	local list = { }
	for _, cand in pairs(best) do
		t_insert(list, cand)
	end
	t_sort(list, function(a, b) return a.id < b.id end)
	return list
end

-- 建一件物品：原物品（基底、品質、插槽、固定詞綴、附魔不變）＋保留的詞綴＋選中的詞綴
local function buildItem(orig, kept, chosen, title)
	local item = new("Item"):Item(orig:BuildRaw())
	item.crafted = false
	item.prefixes = { }
	item.suffixes = { }
	item.title = title or orig.title
	item.corrupted = false
	item.mirrored = false
	item.split = false
	wipeTable(item.explicitModLines)
	for _, k in ipairs(kept) do
		t_insert(item.explicitModLines, copyTable(k.modLine, true))
	end
	for _, cand in ipairs(chosen) do
		for _, line in ipairs(cand.mod) do
			t_insert(item.explicitModLines, {
				line = itemLib.applyRange(line, 1),
				prefix = cand.type == "Prefix" or nil,
				suffix = cand.type == "Suffix" or nil,
				modTags = cand.mod.modTags or { },
			})
		end
	end
	item:BuildAndParseRaw()
	return item
end

-- 最佳化一個欄位。yield(progressText) 會在每次計算後被呼叫（可為 nil）
-- 可以選來計算 DPS 的技能：技能頁有主動技能的每一組。回傳 { { index, label } ... }
function M.listSkills(build)
	local list = { }
	for index, group in ipairs(build.skillsTab.socketGroupList or { }) do
		if group.displaySkillList and #group.displaySkillList > 0 then
			local label = group.displayLabel or group.label or ("#" .. index)
			if ZhTWLocale and ZhTWLocale.tr then
				label = ZhTWLocale.tr(label) or label
			end
			t_insert(list, { index = index, label = label })
		end
	end
	return list
end

-- 以 groupIndex 那組技能當主要技能的計算函數（不動到 Build 本身的主要技能設定）
local function makeCalculator(build, groupIndex)
	if not groupIndex or groupIndex == build.mainSocketGroup then
		local calcFunc = build.calcsTab:GetMiscCalculator()
		return function(override)
			return calcFunc(override, false)
		end
	end
	local function withGroup(f, ...)
		local saved = build.mainSocketGroup
		build.mainSocketGroup = groupIndex
		local ok, a, b = pcall(f, ...)
		build.mainSocketGroup = saved
		if not ok then
			error(a, 0)
		end
		return a, b
	end
	local calcFunc = withGroup(build.calcsTab.calcs.getMiscCalculator, build)
	return function(override)
		return withGroup(calcFunc, override, false)
	end
end

-- groupIndex：用哪一組技能算 DPS（nil = Build 的主要技能）
function M.optimizeSlot(itemsTab, slot, keepRes, yield, groupIndex)
	local orig = itemsTab.items[slot.selItemId]
	local result = { slot = slot, label = slotLabel(slot), orig = orig }
	if not orig then
		result.skip = "沒有裝備"
		return result
	end
	-- 已汙染／複製的物品不能再改，但結果是同底材的另一件新物品，所以照樣計算（結果不帶汙染）
	result.wasLocked = orig.corrupted or orig.mirrored or orig.split
	local calcFunc = makeCalculator(itemsTab.build, groupIndex)
	local slotName = slot.slotName
	local count = 0
	local function eval(item)
		local output = calcFunc({ repSlotName = slotName, repItem = item })
		count = count + 1
		if yield then
			yield(s_format("%s：已計算 %d 種組合", result.label, count))
		end
		return output
	end

	-- 保留抗性：目前（不含破裂）各元素的抗性總量要保住；用最少的欄位重新湊（可以換成全抗、雙抗），
	-- 湊不到才把原本的抗性詞綴原樣留著
	local need
	if keepRes then
		need = { }
		for _, modLine in ipairs(orig.explicitModLines) do
			local res = not modLine.fractured and resistOf(modLine.line)
			if res then
				for k, v in pairs(res) do
					need[k] = (need[k] or 0) + v
				end
			end
		end
	end
	local function setup(mode)
		local kept = keptLines(orig, mode)
		local capacity = { Prefix = 3, Suffix = 3 }
		local blockedKeys = { }
		for _, k in ipairs(kept) do
			capacity[k.type] = m_max(0, capacity[k.type] - 1)
			blockedKeys[normalise(k.modLine.line)] = true
		end
		return kept, capacity, candidateMods(orig, blockedKeys)
	end
	local kept, capacity, cands = setup(keepRes and "max" or nil)
	local fixed = { }
	if keepRes then
		local set = pickResistSet(cands, need, capacity)
		if set then
			fixed = set
		else
			kept, capacity, cands = setup("lines")
			result.resistFallback = true
		end
	end
	result.kept = kept
	result.fixed = fixed
	result.need = need
	result.candidateCount = #cands

	local beforeOutput = eval(orig)
	result.before = dpsOf(beforeOutput)

	-- 1. 每個候選詞綴單獨加上去的效果
	-- 固定的抗性詞綴佔用欄位，同 group 不能再選
	local fixedCount = { Prefix = 0, Suffix = 0 }
	local fixedGroup = { }
	for _, c in ipairs(fixed) do
		fixedCount[c.type] = fixedCount[c.type] + 1
		fixedGroup[c.group] = true
	end
	local emptyScore = scoreOf(eval(buildItem(orig, kept, fixed)))
	local pools = { Prefix = { }, Suffix = { } }
	for _, cand in ipairs(cands) do
		if capacity[cand.type] - fixedCount[cand.type] > 0 and not fixedGroup[cand.group] then
			local test = { unpack(fixed) }
			t_insert(test, cand)
			cand.single = scoreOf(eval(buildItem(orig, kept, test))) - emptyScore
			t_insert(pools[cand.type], cand)
		end
	end
	local pool = { }
	for _, t in ipairs({ "Prefix", "Suffix" }) do
		t_sort(pools[t], function(a, b)
			if a.single ~= b.single then
				return a.single > b.single
			end
			return a.id < b.id
		end)
		for i = 1, math.min(POOL_SIZE, #pools[t]) do
			t_insert(pool, pools[t][i])
		end
	end

	local function fits(chosen, cand, skipIndex)
		local used = 0
		for i, c in ipairs(chosen) do
			if i ~= skipIndex then
				if c.group == cand.group then
					return false
				end
				if c.type == cand.type then
					used = used + 1
				end
			end
		end
		return used < capacity[cand.type]
	end

	-- 2. 逐一加入讓分數最高的詞綴
	local chosen = { unpack(fixed) }
	local nFixed = #fixed
	local curScore = emptyScore
	while true do
		local bestCand, bestScore
		for _, cand in ipairs(pool) do
			if fits(chosen, cand) then
				local test = { unpack(chosen) }
				t_insert(test, cand)
				local s = scoreOf(eval(buildItem(orig, kept, test)))
				if not bestScore or s > bestScore then
					bestCand, bestScore = cand, s
				end
			end
		end
		if not bestCand or bestScore <= curScore then
			break
		end
		t_insert(chosen, bestCand)
		curScore = bestScore
	end

	-- 3. 逐一替換看看有沒有更好（處理詞綴之間的加乘，例如固定傷害＋百分比）
	for _ = 1, SWAP_PASSES do
		local improved = false
		for i = nFixed + 1, #chosen do
			for _, cand in ipairs(pool) do
				if cand ~= chosen[i] and cand.type == chosen[i].type and fits(chosen, cand, i) then
					local test = { unpack(chosen) }
					test[i] = cand
					local s = scoreOf(eval(buildItem(orig, kept, test)))
					if s > curScore then
						chosen[i] = cand
						curScore = s
						improved = true
					end
				end
			end
		end
		if not improved then
			break
		end
	end

	t_sort(chosen, function(a, b)
		if a.type ~= b.type then
			return a.type == "Prefix"
		end
		return a.id < b.id
	end)
	local title = "最佳化 " .. (orig.title or orig.name or "")
	local newItem = buildItem(orig, kept, chosen, title)
	local afterOutput = eval(newItem)
	result.after = dpsOf(afterOutput)
	result.item = newItem
	result.chosen = chosen
	result.evals = count
	return result
end

local function formatDPS(value)
	return formatNumSep(s_format("%.0f", value or 0))
end

local function resultLine(r)
	if r.skip then
		return "^8" .. r.label .. "：" .. r.skip
	end
	local diff = (r.after or 0) - (r.before or 0)
	local pct = (r.before or 0) > 0 and diff / r.before * 100 or 0
	local color = diff > 0.5 and colorCodes.POSITIVE or "^8"
	local text = s_format("^7%s：DPS %s → %s  %s%+.1f%%", r.label, formatDPS(r.before), formatDPS(r.after), color, pct)
	if not r.added then
		text = text .. "  ^8(" .. (diff > 0.5 and "提升不到 0.1%" or "沒有更好的組合") .. "，未加入)"
	elseif r.wasLocked then
		text = text .. "  ^8(原物品已汙染，需同底材重做)"
	end
	return text
end

-- 視窗
function M.openPopup(itemsTab)
	local slots = M.listSlots(itemsTab)
	local controls = { }
	local build = itemsTab.build
	local skills = M.listSkills(build)
	local state = { lines = { }, running = false, keepRes = true, selIndex = 1, skillIndex = 1 }
	local skillChoices = { }
	for i, skill in ipairs(skills) do
		t_insert(skillChoices, skill.label .. (skill.index == build.mainSocketGroup and "  （主要技能）" or ""))
		if skill.index == build.mainSocketGroup then
			state.skillIndex = i
		end
	end
	local width, height = 620, 450

	local choices = { "全部稀有裝備" }
	for _, slot in ipairs(slots) do
		local item = itemsTab.items[slot.selItemId]
		t_insert(choices, slotLabel(slot) .. "：" .. (item.title or item.name or ""))
	end

	controls.slotLabel = new("LabelControl"):LabelControl({ "TOPLEFT", nil, "TOPLEFT" }, { 16, 32, 0, 16 }, "^7欄位：")
	controls.slot = new("DropDownControl"):DropDownControl({ "TOPLEFT", nil, "TOPLEFT" }, { 70, 30, 360, 20 }, choices, function(index)
		state.selIndex = index
	end)
	controls.keepRes = new("CheckBoxControl"):CheckBoxControl({ "TOPLEFT", nil, "TOPLEFT" }, { 530, 30, 20 }, "^7保留抗性", function(checked)
		state.keepRes = checked
	end, "勾選時，火／冰／電／混沌抗性各自不低於目前，用最少的欄位湊到（可以換成全抗、雙抗），\n剩下的欄位放傷害詞綴。", true)
	controls.skillLabel = new("LabelControl"):LabelControl({ "TOPLEFT", nil, "TOPLEFT" }, { 16, 62, 0, 16 }, "^7計算技能：")
	controls.skill = new("DropDownControl"):DropDownControl({ "TOPLEFT", nil, "TOPLEFT" }, { 100, 60, 330, 20 }, skillChoices, function(index)
		state.skillIndex = index
	end, "比較的是這個技能的 DPS（預設是主要技能）。\n主要技能如果是攻擊，結果會挑攻擊詞綴；法術流請改選你的法術。")
	controls.skill.selIndex = state.skillIndex
	controls.info = new("LabelControl"):LabelControl({ "TOPLEFT", nil, "TOPLEFT" }, { 16, 90, 0, 14 },
		"^8依底材與物品等級，最多 3 前綴 3 後綴、同類詞綴不重複、數值取最高；比較主要技能的 DPS。")

	local results = new("Control"):Control({ "TOPLEFT", nil, "TOPLEFT" }, { 16, 114, width - 32, height - 114 - 40 })
	results.Draw = function(control, viewPort)
		if state.co then
			local start = GetTime()
			repeat
				local ok, err = coroutine.resume(state.co)
				if not ok then
					t_insert(state.lines, colorCodes.NEGATIVE .. "發生錯誤：" .. tostring(err))
					ConPrintf("ZhTWOptimize: %s", tostring(err))
					state.co = nil
					state.running = false
				elseif coroutine.status(state.co) == "dead" then
					state.co = nil
					state.running = false
				end
			until not state.co or GetTime() - start > FRAME_BUDGET
		end
		local x, y = control:GetPos()
		local w, h = control:GetSize()
		SetDrawColor(0.3, 0.3, 0.3)
		DrawImage(nil, x, y, w, h)
		SetDrawColor(0.05, 0.05, 0.05)
		DrawImage(nil, x + 1, y + 1, w - 2, h - 2)
		SetDrawColor(1, 1, 1)
		local lineY = y + 6
		for _, line in ipairs(state.lines) do
			DrawString(x + 8, lineY, "LEFT", 16, "VAR", line)
			lineY = lineY + 18
		end
		if state.progress then
			DrawString(x + 8, lineY, "LEFT", 16, "VAR", "^8" .. state.progress)
		end
	end
	controls.results = results

	local function run()
		local targets = { }
		if state.selIndex == 1 then
			targets = slots
		else
			targets = { slots[state.selIndex - 1] }
		end
		wipeTable(state.lines)
		local skill = skills[state.skillIndex]
		t_insert(state.lines, "^7用「" .. (skill and skill.label or "主要技能") .. "」的 DPS 比較")
		local added = 0
		for _, slot in ipairs(targets) do
			local r = M.optimizeSlot(itemsTab, slot, state.keepRes, function(text)
				state.progress = text
				coroutine.yield()
			end, skill and skill.index)
			state.progress = nil
			if r.item and (r.after or 0) > (r.before or 0) * 1.001 then
				itemsTab:AddItem(r.item, true)
				r.added = true
				added = added + 1
			end
			t_insert(state.lines, resultLine(r))
		end
		if added > 0 then
			itemsTab:PopulateSlots()
			itemsTab:AddUndoState()
			itemsTab.build.buildFlag = true
			t_insert(state.lines, "")
			t_insert(state.lines, s_format("^7已把 %d 件加入裝備清單（[尚未使用]），身上的裝備沒有更換。", added))
			t_insert(state.lines, "^8把滑鼠移到清單裡的物品上，可以看到裝上後的完整變化。")
		elseif #targets == 0 then
			t_insert(state.lines, "^8身上沒有可以最佳化的稀有裝備（藥劑、珠寶不算）。")
		end
	end

	controls.go = new("ButtonControl"):ButtonControl({ "BOTTOMLEFT", nil, "BOTTOM" }, { -150, -10, 140, 20 }, function()
		return state.running and "計算中…" or "開始最佳化"
	end, function()
		if state.running then
			return
		end
		state.running = true
		state.co = coroutine.create(run)
	end)
	controls.go.enabled = function()
		return not state.running and #slots > 0
	end
	controls.close = new("ButtonControl"):ButtonControl({ "BOTTOMLEFT", nil, "BOTTOM" }, { 10, -10, 140, 20 }, "關閉", function()
		state.co = nil
		main:ClosePopup()
	end)
	main:OpenPopup(width, height, "稀有裝備傷害最佳化", controls, nil, nil, "close")
end

function M.setup(itemsTab)
	local controls = itemsTab.controls
	local anchor = controls.newDisplayItem
	if not anchor then
		return
	end
	local button = new("ButtonControl"):ButtonControl({ "TOPLEFT", anchor, "TOPRIGHT" }, { 8, 0, 160, 20 }, "稀有裝備傷害最佳化", function()
		M.openPopup(itemsTab)
	end)
	button.shown = function()
		return enabled() and itemsTab.displayItem == nil and anchor:IsShown()
	end
	button.tooltipText = "依照底材、物品等級與遊戲的詞綴規則，找出主要技能 DPS 最高的詞綴組合，\n結果加入裝備清單（[尚未使用]），不會換掉身上的裝備。"
	controls.zhTWOptimize = button
end

return M
