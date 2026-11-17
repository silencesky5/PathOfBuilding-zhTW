-- Path of Building
--
-- Module: zhTW IME
-- Typing Chinese (any non-ASCII character) into PoB: the engine hands every such character to
-- OnChar as "?". This module subclasses the engine's window with LuaJIT FFI, records the real
-- characters of WM_CHAR messages in order, and puts them back in place of those "?".
-- Windows only; does nothing when FFI or the window can't be found.
--
local M = { installed = false }

local ok, ffi = pcall(require, "ffi")
if not ok or not ffi or (jit and jit.os ~= "Windows") then
	return M
end

local WM_CHAR = 0x0102
local queue = { } -- { text = utf8, time = ms } for every printable WM_CHAR, in order
local pendingHigh -- high surrogate waiting for its pair

local function utf8Char(cp)
	if cp < 0x80 then
		return string.char(cp)
	elseif cp < 0x800 then
		return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
	elseif cp < 0x10000 then
		return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	else
		return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
			0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
	end
end

pcall(ffi.cdef, [[
typedef void* ZHTW_HWND;
typedef intptr_t ZHTW_LRESULT;
typedef ZHTW_LRESULT (__stdcall *ZHTW_SUBCLASSPROC)(ZHTW_HWND, unsigned int, uintptr_t, intptr_t, uintptr_t, uintptr_t);
ZHTW_HWND FindWindowExW(ZHTW_HWND parent, ZHTW_HWND after, const uint16_t* cls, const uint16_t* title);
unsigned long GetWindowThreadProcessId(ZHTW_HWND hwnd, unsigned long* pid);
unsigned long GetCurrentProcessId(void);
int SetWindowSubclass(ZHTW_HWND hwnd, ZHTW_SUBCLASSPROC proc, uintptr_t id, uintptr_t data);
ZHTW_LRESULT DefSubclassProc(ZHTW_HWND hwnd, unsigned int msg, uintptr_t wParam, intptr_t lParam);
]])

local user32 = ffi.C
local comctl32
local callback -- kept referenced: the window keeps calling it

local function wide(s)
	local buf = ffi.new("uint16_t[?]", #s + 1)
	for i = 1, #s do
		buf[i - 1] = s:byte(i)
	end
	return buf
end

local function findWindow()
	-- ffi.C covers kernel32 and user32 on Windows
	local pid = ffi.C.GetCurrentProcessId()
	local cls = wide("GLFW30")
	local hwnd = nil
	for _ = 1, 50 do
		hwnd = user32.FindWindowExW(nil, hwnd, cls, nil)
		if hwnd == nil then
			return nil
		end
		local p = ffi.new("unsigned long[1]")
		user32.GetWindowThreadProcessId(hwnd, p)
		if p[0] == pid then
			return hwnd
		end
	end
end

-- Call once the window exists (after RenderInit)
function M.install()
	if M.installed then
		return true
	end
	local okAll, err = pcall(function()
		comctl32 = ffi.load("comctl32")
		local hwnd = findWindow()
		if not hwnd then
			error("window not found")
		end
		callback = ffi.cast("ZHTW_SUBCLASSPROC", function(h, msg, wParam, lParam, id, data)
			if msg == WM_CHAR then
				local cp = tonumber(wParam)
				if cp >= 0xD800 and cp <= 0xDBFF then
					pendingHigh = cp
				else
					if cp >= 0xDC00 and cp <= 0xDFFF and pendingHigh then
						cp = 0x10000 + (pendingHigh - 0xD800) * 0x400 + (cp - 0xDC00)
					end
					pendingHigh = nil
					if cp >= 32 and cp ~= 127 then
						queue[#queue + 1] = { text = utf8Char(cp), time = GetTime() }
					end
				end
			end
			return comctl32.DefSubclassProc(h, msg, wParam, lParam)
		end)
		if comctl32.SetWindowSubclass(hwnd, callback, 0x7A68, 0) == 0 then
			error("SetWindowSubclass failed")
		end
	end)
	M.installed = okAll
	M.error = not okAll and tostring(err) or nil
	-- Every typed character reaches the program through launch:OnChar (Launch.lua)
	if okAll and launch and launch.OnChar and not M.launchHooked then
		M.launchHooked = true
		local origOnChar = launch.OnChar
		launch.OnChar = function(self, key)
			return origOnChar(self, M.translate(key))
		end
	end
	if not okAll and ConPrintf then
		ConPrintf("[zhTW] IME input not available: %s", tostring(err))
	end
	return okAll
end

-- Maps a key from OnChar back to the character that was typed
function M.translate(key)
	if not M.installed or type(key) ~= "string" or #key ~= 1 or key:byte() < 32 then
		return key
	end
	local now = GetTime()
	-- Characters the engine never passed on (e.g. typed while no window had focus) go stale
	while queue[1] and now - queue[1].time > 2000 do
		table.remove(queue, 1)
	end
	local entry = table.remove(queue, 1)
	if entry and key == "?" and #entry.text > 1 then
		return entry.text
	end
	return key
end

return M
