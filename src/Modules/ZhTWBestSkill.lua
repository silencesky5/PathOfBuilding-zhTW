-- Path of Building
--
-- Module: zhTW Best Skill
-- 找出 Build 裡傷害最高的技能（KAI 11/21：匯入後的預設主要技能要用傷害最高的那招，不是連結最多的那組）。
--   M.findBest(build)    → 傷害最高的候選（見下方 candidate 欄位），沒有任何技能有傷害時回傳 nil
--   M.candidates(build)  → 所有候選與各自的 DPS（由高到低）
--   M.apply(build, cand) → 把候選設成主要技能（技能組、主動技能、召喚物技能；計算頁也一起設）
--   M.pickAfterImport(build) → 匯入用：重算一次、挑最高、套用（Classes/ImportTab.lua 呼叫）
-- 候選：每個啟用中的插槽群組裡的每個主動技能；召喚物技能再展開成每一招召喚物技能。
-- DPS：玩家的 CombinedDPS 和召喚物的 CombinedDPS 取大的（和計算頁「合計 DPS」相同）。
-- 計算時暫時改 build.mainSocketGroup 等設定，算完一定還原；Build 本身只有 apply 會改。
--
local t_insert = table.insert
local t_sort = table.sort

local M = { }

function M.dpsOf(output)
	if not output then
		return 0
	end
	local dps = output.CombinedDPS or 0
	local minionDps = output.Minion and output.Minion.CombinedDPS or 0
	if minionDps > dps then
		dps = minionDps
	end
	return dps
end

-- candidate = { groupIndex, activeIndex, minionSkillIndex (nil if not a minion skill), dps, name, minionSkillName }
local function enumerate(build)
	local list = { }
	for groupIndex, group in ipairs(build.skillsTab.socketGroupList) do
		if group.enabled and group.slotEnabled ~= false and group.displaySkillList then
			for activeIndex, activeSkill in ipairs(group.displaySkillList) do
				local effect = activeSkill.activeEffect
				local name = effect and effect.grantedEffect and effect.grantedEffect.name or "?"
				local minionSkills = activeSkill.minion and activeSkill.minion.activeSkillList
				if minionSkills and #minionSkills > 0 then
					for k, minionSkill in ipairs(minionSkills) do
						local mEffect = minionSkill.activeEffect
						t_insert(list, {
							groupIndex = groupIndex, activeIndex = activeIndex, minionSkillIndex = k,
							name = name, minionSkillName = mEffect and mEffect.grantedEffect and mEffect.grantedEffect.name,
							srcInstance = effect and effect.srcInstance,
						})
					end
				else
					t_insert(list, {
						groupIndex = groupIndex, activeIndex = activeIndex,
						name = name, srcInstance = effect and effect.srcInstance,
					})
				end
			end
		end
	end
	return list
end

-- Settings a candidate changes, so they can be put back
local function snapshot(build, list)
	local saved = { mainSocketGroup = build.mainSocketGroup, groups = { }, instances = { } }
	for _, cand in ipairs(list) do
		local group = build.skillsTab.socketGroupList[cand.groupIndex]
		if saved.groups[group] == nil then
			saved.groups[group] = group.mainActiveSkill or false
		end
		local inst = cand.srcInstance
		if inst and saved.instances[inst] == nil then
			saved.instances[inst] = inst.skillMinionSkill or false
		end
	end
	return saved
end

local function restore(build, saved)
	build.mainSocketGroup = saved.mainSocketGroup
	for group, value in pairs(saved.groups) do
		group.mainActiveSkill = value or nil
	end
	for inst, value in pairs(saved.instances) do
		inst.skillMinionSkill = value or nil
	end
end

local function selectCand(build, cand)
	build.mainSocketGroup = cand.groupIndex
	build.skillsTab.socketGroupList[cand.groupIndex].mainActiveSkill = cand.activeIndex
	if cand.minionSkillIndex and cand.srcInstance then
		cand.srcInstance.skillMinionSkill = cand.minionSkillIndex
	end
end

-- Needs the socket groups' skill lists from a main calculation (build.calcsTab:BuildOutput())
function M.candidates(build)
	local list = enumerate(build)
	if #list == 0 then
		return list
	end
	local calcs = build.calcsTab.calcs
	local saved = snapshot(build, list)
	for _, cand in ipairs(list) do
		selectCand(build, cand)
		wipeGlobalCache()
		local ok, env = pcall(calcs.initEnv, build, "CALCULATOR")
		if ok then
			ok = pcall(calcs.perform, env)
		end
		cand.dps = ok and M.dpsOf(env.player.output) or 0
	end
	restore(build, saved)
	wipeGlobalCache()
	local order = { }
	for i, cand in ipairs(list) do
		order[cand] = i
	end
	t_sort(list, function(a, b)
		if a.dps ~= b.dps then
			return a.dps > b.dps
		end
		return order[a] < order[b]
	end)
	return list
end

function M.findBest(build)
	local best = M.candidates(build)[1]
	if best and best.dps > 0 then
		return best
	end
	return nil
end

-- Main skill (side bar / 技能頁) and the 計算頁 skill both become the candidate
function M.apply(build, cand)
	selectCand(build, cand)
	local group = build.skillsTab.socketGroupList[cand.groupIndex]
	group.mainActiveSkillCalcs = cand.activeIndex
	if cand.minionSkillIndex and cand.srcInstance then
		cand.srcInstance.skillMinionSkillCalcs = cand.minionSkillIndex
	end
	if build.calcsTab and build.calcsTab.input then
		build.calcsTab.input.skill_number = cand.groupIndex
	end
	build.buildFlag = true
end

-- After an import into an empty build: recalculate, then make the highest-damage skill the main skill.
-- Keeps the current choice when nothing deals damage. Returns the chosen candidate.
function M.pickAfterImport(build)
	local ok, best = pcall(function()
		build.skillsTab:UpdateSocketGroups()
		wipeGlobalCache()
		build.calcsTab:BuildOutput()
		return M.findBest(build)
	end)
	if not ok then
		ConPrintf("zhTW best skill: %s", tostring(best))
		return nil
	end
	if best then
		M.apply(build, best)
	end
	return best
end

return M
