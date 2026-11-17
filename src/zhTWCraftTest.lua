#@ SimpleGraphic
-- zhTW: no-window test of the 製作 tab's engine (Modules/ZhTWCraftEngine.lua).
-- Run from the runtime folder:  Path{space}of{space}Building.exe <full path of this file>
-- Writes src/zhTWCraftTest.log. ZHTW_CRAFT_N sets the trials per currency (default 3000).
local logFile = io.open("zhTWCraftTest.log", "w")
local function log(s)
	logFile:write(s, "\n")
	logFile:flush()
end

local ok, err = xpcall(function()
	local t0 = os.clock()
	local D = assert(loadfile("Data/zhTW/CraftData.lua"))()
	log(string.format("data %s: bases %d, mods %d, essences %d, trans %d, load %.2fs", D.version, #D.bases, #D.mods, #D.essences, #D.trans, os.clock() - t0))
	if not io.open("Modules/ZhTWCraftEngine.lua", "r") then
		return
	end
	local CE = assert(loadfile("Modules/ZhTWCraftEngine.lua"))()
	t0 = os.clock()
	local E = CE.create(D)
	log(string.format("engine create %.2fs", os.clock() - t0))
	if os.getenv("ZHTW_CRAFT_SCRIPT") then
		assert(loadfile(os.getenv("ZHTW_CRAFT_SCRIPT")))(E, CE, log)
	end
end, debug.traceback)
if not ok then
	log("ERROR: " .. tostring(err))
end
logFile:close()
os.exit(0)
