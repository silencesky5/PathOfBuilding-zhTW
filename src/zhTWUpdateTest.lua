#@ SimpleGraphic
-- zhTW: headless test of PoB's own updater in an installed (packaged) copy.
-- Run by src/Export/zhTWUpdateTest.py, which copies this file into the unpacked package and
-- runs it with the package's "Path of Building.exe". It does what Launch.lua does on an update:
--   1. the dev mode check (must be off, or the updater never runs)
--   2. UpdateCheck.lua (download the remote manifest and the changed files)
--   3. UpdateApply.lua for the program files (runtime files are applied by Update.exe afterwards,
--      started by the Python driver like Launch.lua's SpawnProcess does)
-- Results: zhTWUpdateTest.log next to this file.

local logFile = io.open("zhTWUpdateTest.log", "w")
local function log(...)
	local parts = { }
	for i = 1, select("#", ...) do
		parts[i] = tostring(select(i, ...))
	end
	logFile:write(table.concat(parts, "\t"), "\n")
	logFile:flush()
end

local ok, err = pcall(function()
	-- 1. Same as launch:OnInit
	local xml = require("xml")
	local man = xml.LoadXMLFile("manifest.xml")
	local ver, branch, platform
	for _, node in ipairs(man[1]) do
		if type(node) == "table" and node.elem == "Version" then
			ver, branch, platform = node.attrib.number, node.attrib.branch, node.attrib.platform
		end
	end
	local devMode = not branch and not platform
	log("version", ver, "branch", branch, "platform", platform, "devMode", devMode)
	log("portable", GetScriptPath() == GetRuntimePath())

	-- 2. Same as launch:CheckForUpdate, but run directly instead of in a sub script
	local f = io.open("UpdateCheck.lua", "r")
	local code = f:read("*a")
	f:close()
	ConPrintf = function(fmt, ...)
		log("  " .. string.format(fmt, ...))
	end
	local fn = assert(loadstring(code, "UpdateCheck"))
	local mode, errMsg = fn(nil, nil, false)
	log("updateMode", mode, errMsg)

	-- 3. Same as launch:ApplyUpdate (program files)
	if mode == "normal" or mode == "basic" then
		LoadModule("UpdateApply")("Update/opFile.txt")
		log("applied opFile")
	end
end)
if not ok then
	log("ERROR", err)
end
logFile:close()
Exit()
