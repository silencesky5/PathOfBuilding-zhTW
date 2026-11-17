-- Path of Building
--
-- Module: zhTW Theme
-- The light "可愛" theme for the Chinese interface: PoB draws everything dark (grey boxes,
-- white text), so while the theme is on this module remaps colours at draw time:
--   * solid rectangles (DrawImage / DrawImageQuad without an image) get light colours by
--     brightness: dark fills -> cream, mid greys -> tan, light greys / white -> blue lines
--   * text colours (^0-^9, ^xRRGGBB and the current draw colour) get darker versions that
--     read on cream; item rarity colours have hand-picked ones
--   * images (item art, icons, the passive tree) keep their colours
-- The passive tree view itself stays dark (it is the game's own artwork).
-- With the dark theme or the English interface nothing is changed.
--
local m_max = math.max
local m_min = math.min
local m_floor = math.floor
local s_format = string.format
local s_sub = string.sub

local ZhTWTheme = { }
ZhTWTheme.name = "dark" -- "dark" or "cute"
ZhTWTheme.suspended = false -- true while the passive tree view draws

local function active()
	return ZhTWTheme.name == "cute" and ZhTWLocale and ZhTWLocale.enabled and not ZhTWTheme.suspended
end
ZhTWTheme.active = active

-- Light colours
local CREAM = { 1, 0.976, 0.94 } -- panels, list and box fills
local PAGE = { 0.98, 0.93, 0.86 } -- page background
local TAN = { 0.87, 0.8, 0.7 } -- mid grey fills (selected rows, top bar)
local LINE = { 0.66, 0.78, 0.91 } -- light grey frames (#A8C8E8)
local STRONG = { 0.43, 0.61, 0.82 } -- white frames, focus
ZhTWTheme.PAGE = PAGE

-- Text: hand-picked versions of PoB's colorCodes, the rest is computed
local textMap = {
	["8888FF"] = "3A5BC7", -- MAGIC
	["FFFF77"] = "9A7A00", -- RARE
	["AF6025"] = "B5551A", -- UNIQUE
	["60C0F0"] = "2A7DB0", -- RELIC
	["1AA29B"] = "137A74", -- GEM
	["B8DAF1"] = "4A7DA8", -- CRAFTED / ENCHANTED
	["E05030"] = "B33A1E", -- LIFE / STRENGTH
	["7070FF"] = "3A4FC7", -- MANA / INTELLIGENCE
	["70FF70"] = "2E8A2E", -- DEXTERITY
	["88FFFF"] = "1E7A8A", -- ES
	["B97123"] = "A0581A", -- FIRE
	["3F6DB3"] = "2C5799", -- COLD
	["ADAA47"] = "807A1A", -- LIGHTNING
	["D02090"] = "A01870", -- CHAOS
	["FFFFFF"] = "4A3828",
	["C8C8C8"] = "5A4C3E", -- NORMAL
	["C8A45A"] = "B0703A", -- our gold accent
	["E6DFD0"] = "5A4030", -- our titles
	["A39B8C"] = "7A6A58", -- our secondary text
	["8C8478"] = "7A6A58",
}
local digitHex = { [0] = "000000", "FF0000", "00FF00", "0000FF", "FFFF00", "FF00FF", "00FFFF", "FFFFFF", "B3B3B3", "7F7F7F" }

local function hexToRgb(hex)
	return tonumber(s_sub(hex, 1, 2), 16) / 255, tonumber(s_sub(hex, 3, 4), 16) / 255, tonumber(s_sub(hex, 5, 6), 16) / 255
end

local function rgbToHex(r, g, b)
	return s_format("%02X%02X%02X", m_floor(r * 255 + 0.5), m_floor(g * 255 + 0.5), m_floor(b * 255 + 0.5))
end

-- HSL lightness clamp: keeps the hue, makes it dark enough for cream
local function darkenHex(hex)
	hex = hex:upper()
	if textMap[hex] then
		return textMap[hex]
	end
	local r, g, b = hexToRgb(hex)
	local mx, mn = m_max(r, g, b), m_min(r, g, b)
	local l = (mx + mn) / 2
	if mx - mn < 0.12 then
		-- grey: light greys become brown text, dark ones stay
		if l > 0.7 then
			return "4A3828"
		elseif l > 0.4 then
			return "6B5D4F"
		end
		return hex
	end
	if l <= 0.38 then
		return hex
	end
	-- scale the colour down so its lightness is about 0.32
	local k = 0.32 / l
	return rgbToHex(m_min(1, r * k), m_min(1, g * k), m_min(1, b * k))
end

local textCache, textCacheSize = { }, 0
local function darkenText(text)
	local v = textCache[text]
	if v then
		return v
	end
	v = text:gsub("%^x(%x%x%x%x%x%x)", function(hex)
		return "^x" .. darkenHex(hex)
	end):gsub("%^(%d)", function(d)
		return "^x" .. darkenHex(digitHex[tonumber(d)])
	end)
	if textCacheSize > 20000 then
		textCache, textCacheSize = { }, 0
	end
	textCache[text] = v
	textCacheSize = textCacheSize + 1
	return v
end
ZhTWTheme.darkenText = darkenText

-- Light fill for a solid rectangle drawn in r, g, b
local function lightFill(r, g, b)
	local mx, mn = m_max(r, g, b), m_min(r, g, b)
	local lum = 0.3 * r + 0.59 * g + 0.11 * b
	if mx - mn < 0.12 then
		if lum < 0.2 then
			return CREAM
		elseif lum < 0.42 then
			return TAN
		elseif lum < 0.8 then
			return LINE
		end
		return STRONG
	end
	if lum < 0.25 then
		-- dark tints (drag targets, dark coloured boxes): mostly cream with a hint of the colour
		return { CREAM[1] * 0.75 + r * 0.25 + 0.05, CREAM[2] * 0.75 + g * 0.25 + 0.05, CREAM[3] * 0.75 + b * 0.25 + 0.05 }
	end
	return nil -- keep saturated colours (bars, highlights)
end

-- Current draw colour as numbers, as PoB asked for it
local cur = { 1, 1, 1, 1 }
local origSetDrawColor = SetDrawColor
local origDrawImage = DrawImage
local origDrawImageQuad = DrawImageQuad

local function setCur(r, g, b, a)
	if type(r) == "string" then
		local hex = r:match("^%^x(%x%x%x%x%x%x)")
		if hex then
			cur[1], cur[2], cur[3] = hexToRgb(hex)
		else
			local d = tonumber(r:match("^%^(%d)"))
			if d then
				cur[1], cur[2], cur[3] = hexToRgb(digitHex[d])
			end
		end
		cur[4] = 1
	else
		cur[1], cur[2], cur[3], cur[4] = r or 1, g or 1, b or 1, a or 1
	end
end

function SetDrawColor(r, g, b, a)
	setCur(r, g, b, a)
	return origSetDrawColor(r, g, b, a)
end

local function withFill(draw, ...)
	local fill = lightFill(cur[1], cur[2], cur[3])
	if not fill then
		return draw(...)
	end
	local r, g, b, a = cur[1], cur[2], cur[3], cur[4]
	origSetDrawColor(fill[1], fill[2], fill[3], a)
	draw(...)
	origSetDrawColor(r, g, b, a)
end

function DrawImage(handle, ...)
	if handle == nil and active() then
		return withFill(origDrawImage, handle, ...)
	end
	return origDrawImage(handle, ...)
end

function DrawImageQuad(handle, ...)
	if handle == nil and active() then
		return withFill(origDrawImageQuad, handle, ...)
	end
	return origDrawImageQuad(handle, ...)
end

-- Text: called by ZhTWText's DrawString after translating (translations use PoB's codes)
function ZhTWTheme.prepareText(text)
	if not active() or type(text) ~= "string" then
		return text
	end
	text = darkenText(text)
	-- text without a leading colour is drawn in the current colour: darken that too
	if s_sub(text, 1, 1) ~= "^" then
		text = "^x" .. darkenHex(rgbToHex(cur[1], cur[2], cur[3])) .. text
	end
	return text
end

-- Page background and the passive tree (called every frame by ZhTWLayout)
function ZhTWTheme.hookFrame(build)
	if main and not ZhTWTheme.backgroundHooked and main.DrawBackground then
		ZhTWTheme.backgroundHooked = true
		local origBackground = main.DrawBackground
		main.DrawBackground = function(self, viewPort)
			if active() then
				SetDrawLayer(nil, -100)
				origSetDrawColor(PAGE[1], PAGE[2], PAGE[3])
				origDrawImage(nil, viewPort.x, viewPort.y, viewPort.width, viewPort.height)
				origSetDrawColor(cur[1], cur[2], cur[3], cur[4])
				SetDrawLayer(nil, 0)
				return
			end
			return origBackground(self, viewPort)
		end
	end
	local treeTab = build and build.treeTab
	if treeTab and treeTab.viewer and not treeTab.viewer.zhTWThemeHooked then
		local viewer = treeTab.viewer
		viewer.zhTWThemeHooked = true
		-- the tree is the game's artwork: drawn as it is
		local origDraw = viewer.Draw
		viewer.Draw = function(...)
			local was = ZhTWTheme.suspended
			ZhTWTheme.suspended = true
			local ok, err = pcall(origDraw, ...)
			ZhTWTheme.suspended = was
			if not ok then
				error(err, 0)
			end
		end
	end
end

function ZhTWTheme.setTheme(name)
	ZhTWTheme.name = (name == "cute") and "cute" or "dark"
	textCache, textCacheSize = { }, 0
end

return ZhTWTheme
