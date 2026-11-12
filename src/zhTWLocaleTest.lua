#@ SimpleGraphic
-- zhTW: headless checks for Modules/ZhTWLocale.lua (writes zhTWLocaleTest.log)
local realSetMainObject, realExit = SetMainObject, Exit
local logFile = io.open("zhTWLocaleTest.log", "w")
local function log(...) local p = { } for i = 1, select("#", ...) do p[i] = tostring(select(i, ...)) end logFile:write(table.concat(p, "\t"), "\n") end
print = log
local ok, err = pcall(function()
	dofile("HeadlessWrapper.lua")
	local samples = os.getenv("ZHTW_SAMPLES") or ""
	local f = io.open(samples, "r")
	if f then
		for line in f:lines() do
			line = line:gsub("\n", "\n")
			log(line:gsub("\n", "\n"), " => ", (ZhTWLocale.tr(line):gsub("\n", "\n")))
		end
		f:close()
	end
end)
if not ok then log("ERROR: " .. tostring(err)) end
logFile:close()
realSetMainObject({ OnInit = function() realExit() end, OnFrame = function() end })
