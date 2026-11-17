#@ SimpleGraphic
-- zhTW: headless runner for Export/Scripts/zhTW.lua
--
-- Usage (from the repository root):
--   set ZHTW_GGPK=C:\Program Files (x86)\Steam\steamapps\common\流亡黯道
--   runtime\Path{space}of{space}Building.exe src\Export\zhTWRun.lua
--
-- ZHTW_GGPK is a Content.ggpk file or a Steam game directory (anything bun_extract_file accepts).
-- Output goes to src/Data/zhTW/, and a log to src/Export/zhTWRun.log.

local runner = { }

function runner:OnInit()
	local logLines = { }
	local function log(text)
		for line in tostring(text):gmatch("[^\r\n]+") do
			table.insert(logLines, line)
		end
	end
	local ok, err = pcall(function()
		launch = { devMode = true }
		LoadModule("../Modules/Common.lua")
		LoadModule("Classes/Dat64File")
		main = {
			datSpecs = LoadModule("spec"),
			datFileByName = { },
			datFileList = { },
			scriptOutput = { },
		}
		function print(text) log(text) end
		function printf(...) log(string.format(...)) end
		local path = os.getenv("ZHTW_GGPK")
		if not path or path == "" then
			error("Set ZHTW_GGPK to the Taiwan client Content.ggpk or Steam directory")
		end
		main.ggpk = { path = path, oozPath = GetWorkDir() .. "\\ggpk\\" }
		log("GGPK: " .. path)
		local errMsg = PLoadModule(os.getenv("ZHTW_SCRIPT") or "Scripts/zhTW.lua") -- ZHTW_SCRIPT: e.g. Scripts/zhTWMonsters.lua
		if errMsg then
			error(errMsg)
		end
	end)
	if not ok then
		log("ERROR: " .. tostring(err))
	end
	local f = io.open(GetWorkDir() .. "\\zhTWRun.log", "w")
	f:write(table.concat(logLines, "\n"), "\n")
	f:close()
	Exit()
end

function runner:OnFrame()
end

SetMainObject(runner)
