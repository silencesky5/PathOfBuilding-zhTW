-- Path of Building
--
-- Module: zhTW Import Report
-- After a Taiwan character import (Classes/ImportTab.lua): one popup that lists the modifier lines
-- that could not be converted (they are left out of the calculations), and reminds the player of
-- the settings the Taiwan data does not carry (bandit quest, pantheon).
-- Before this, unconverted lines were only printed to the console (Ctrl+~).
--
local t_insert = table.insert
local t_concat = table.concat

local M = { }

M.maxLines = 15 -- longer lists end with "另有 N 行"

local function selLabel(build, var)
	local control = build.configTab and build.configTab.varControls and build.configTab.varControls[var]
	if not control or not control.list then
		return "?", true
	end
	local index = control.selIndex or 1
	local entry = control.list[index]
	local label = type(entry) == "table" and entry.label or tostring(entry)
	return ZhTWLocale.translate(label), index == 1
end

-- The popup text; nil when there is nothing worth showing
-- (no failures, and bandit / pantheon were already changed from their defaults)
function M.message(build, failures)
	failures = failures or { }
	local bandit, banditDefault = selLabel(build, "bandit")
	local major, majorDefault = selLabel(build, "pantheonMajorGod")
	local minor, minorDefault = selLabel(build, "pantheonMinorGod")
	local remind = banditDefault and majorDefault and minorDefault
	if #failures == 0 and not remind then
		return nil
	end
	local msg = { }
	if remind then
		t_insert(msg, "^7台服的角色資料不含以下設定，匯入後請到「設定」頁確認：")
		t_insert(msg, "^7    盜賊任務：^xFFD700" .. bandit)
		t_insert(msg, "^7    萬神殿主神：^xFFD700" .. major .. "^7　次神：^xFFD700" .. minor)
		t_insert(msg, "^8    （有幫助盜賊的話要選對，例如幫助艾莉拉的 +15% 全部元素抗性才會算進去）")
	end
	if #failures > 0 then
		if remind then
			t_insert(msg, "")
		end
		t_insert(msg, "^xFFD700有 " .. #failures .. " 行詞綴無法轉換，這些詞綴不會算進數值：")
		for i, f in ipairs(failures) do
			if i > M.maxLines then
				t_insert(msg, "^8    …另有 " .. (#failures - M.maxLines) .. " 行（完整清單可按 Ctrl+~ 開主控台查看）")
				break
			end
			local item = f.item and f.item ~= "?" and ZhTWLocale.translate(f.item) or nil
			t_insert(msg, "^xD0D0D0    " .. (item and ("[" .. item .. "] ") or "") .. tostring(f.line or ""))
		end
	end
	return t_concat(msg, "\n"), remind
end

function M.show(build, failures)
	if not (main and main.OpenConfirmPopup) then
		return
	end
	local text, remind = M.message(build, failures)
	if not text then
		return
	end
	if remind then
		main:OpenConfirmPopup("匯入結果", text, "前往設定", function()
			build.viewMode = "CONFIG"
		end)
	else
		main:OpenMessagePopup("匯入結果", text)
	end
end

return M
