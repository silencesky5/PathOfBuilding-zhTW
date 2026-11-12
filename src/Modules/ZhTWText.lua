-- Path of Building
--
-- Module: zhTW Text
-- Draws Chinese characters.
--
-- SimpleGraphic's bitmap fonts only contain ASCII; every other character is drawn as "[U+xxxx]".
-- This module wraps DrawString / DrawStringWidth / DrawStringCursorIndex: ASCII runs still go
-- to the engine, Chinese characters are drawn from a glyph atlas (Data/zhTW/Font.png, built by
-- Export/zhTWFont.ps1) with DrawImage. Strings without bytes >= 128 take the original path
-- untouched, so English-only text costs one string.find.
--
local s_byte = string.byte
local s_find = string.find
local s_sub = string.sub
local m_floor = math.floor
local m_ceil = math.ceil
local t_insert = table.insert

-- Translation to Chinese happens here too (Modules/ZhTWLocale.lua), so every drawn string is covered
ZhTWLocale = LoadModule("Modules/ZhTWLocale")
local tr = ZhTWLocale.tr

local origDrawString = DrawString
local origDrawStringWidth = DrawStringWidth
local origDrawStringCursorIndex = DrawStringCursorIndex

-- Two atlases with the same character order: 16px (drawn at native size, sharp for normal UI
-- text) and 32px (large text). Built by Export/zhTWFont.ps1.
local atlases = { }
for _, name in ipairs({ "Font16", "Font32" }) do
	local data = LoadModule("Data/zhTW/" .. name)
	local image = NewImageHandle()
	image:Load("Data/zhTW/" .. name .. ".png", "MIPMAP")
	t_insert(atlases, { data = data, image = image })
end
local glyphs = atlases[1].data.glyphs

local function atlasFor(height)
	if height <= 20 then
		return atlases[1]
	end
	return atlases[2]
end

-- Decodes the UTF-8 character at byte i; returns codepoint and byte length
local function decode(s, i)
	local c = s_byte(s, i)
	if c < 0xE0 then
		local c2 = s_byte(s, i + 1) or 0x80
		return (c % 0x20) * 0x40 + (c2 % 0x40), 2
	elseif c < 0xF0 then
		local c2, c3 = s_byte(s, i + 1, i + 2)
		return (c % 0x10) * 0x1000 + ((c2 or 0x80) % 0x40) * 0x40 + ((c3 or 0x80) % 0x40), 3
	else
		local c2, c3, c4 = s_byte(s, i + 1, i + 3)
		return (c % 0x08) * 0x40000 + ((c2 or 0x80) % 0x40) * 0x1000 + ((c3 or 0x80) % 0x40) * 0x40 + ((c4 or 0x80) % 0x40), 4
	end
end

-- Last colour escape in a piece of text (^0-^9 or ^xRRGGBB)
local function lastEscape(s, current)
	local esc = current
	local i = 1
	while true do
		local a, b = s_find(s, "%^x%x%x%x%x%x%x", i)
		local c, d = s_find(s, "%^%d", i)
		if a and (not c or a <= c) then
			esc = s_sub(s, a, b)
			i = b + 1
		elseif c then
			esc = s_sub(s, c, d)
			i = d + 1
		else
			return esc
		end
	end
end

-- Splits one line into segments:
--   { text = "..." }                 drawn by the engine
--   { cp = codepoint, len = bytes }  drawn from the atlas
local function segments(line)
	local segs = { }
	local buf = { }
	local i, n = 1, #line
	while i <= n do
		local hi = s_find(line, "[\192-\255]", i)
		if not hi then
			t_insert(buf, s_sub(line, i))
			break
		end
		if hi > i then
			t_insert(buf, s_sub(line, i, hi - 1))
		end
		local cp, len = decode(line, hi)
		if glyphs[cp] then
			if #buf > 0 then
				t_insert(segs, { text = table.concat(buf) })
				buf = { }
			end
			t_insert(segs, { cp = cp, len = len })
		else
			-- Not in the atlas: let the engine draw its placeholder
			t_insert(buf, s_sub(line, hi, hi + len - 1))
		end
		i = hi + len
	end
	if #buf > 0 then
		t_insert(segs, { text = table.concat(buf) })
	end
	return segs
end

local function glyphAdvance(cp, height)
	return m_ceil(glyphs[cp][2] * height)
end

local function lineWidth(segs, height, font)
	local w = 0
	local esc
	for _, seg in ipairs(segs) do
		if seg.cp then
			w = w + glyphAdvance(seg.cp, height)
		else
			w = w + origDrawStringWidth(height, font, (esc or "") .. seg.text)
			esc = lastEscape(seg.text, esc)
		end
	end
	return w
end

local function hasWide(text)
	return type(text) == "string" and s_find(text, "[\192-\255]") ~= nil
end

local function eachLine(text)
	return (text .. "\n"):gmatch("([^\n]*)\n")
end

function DrawString(left, top, align, height, font, text)
	text = tr(text)
	if not hasWide(text) then
		return origDrawString(left, top, align, height, font, text)
	end
	local r, g, b, a = GetDrawColor()
	local screenW = GetVirtualScreenSize()
	local esc
	local y = top
	for line in eachLine(text) do
		local segs = segments(line)
		local w = lineWidth(segs, height, font)
		local x = left
		if align == "CENTER" then
			x = m_floor((screenW - w) / 2 + left)
		elseif align == "RIGHT" then
			x = m_floor(screenW - w - left)
		elseif align == "CENTER_X" then
			x = m_floor(left - w / 2)
		elseif align == "RIGHT_X" then
			x = m_floor(left - w)
		end
		x = m_floor(x + 0.5)
		for _, seg in ipairs(segs) do
			if seg.cp then
				local at = atlasFor(height)
				local cell, cols = at.data.cell, at.data.cols
				local texW, texH = at.data.width, at.data.height
				local glyph = at.data.glyphs[seg.cp]
				local adv = glyphAdvance(seg.cp, height)
				local idx = glyph[1]
				local tx = (idx % cols) * cell
				local ty = m_floor(idx / cols) * cell
				if esc then
					SetDrawColor(esc)
				else
					SetDrawColor(r, g, b, a)
				end
				-- The glyph is centred in a square cell; centre the cell on the advance
				DrawImage(at.image, x + (adv - height) / 2, y, height, height,
					tx / texW, ty / texH, (tx + cell) / texW, (ty + cell) / texH)
				x = x + adv
			else
				local s = (esc or "") .. seg.text
				SetDrawColor(r, g, b, a)
				origDrawString(x, y, "LEFT", height, font, s)
				x = x + origDrawStringWidth(height, font, s)
				esc = lastEscape(seg.text, esc)
			end
		end
		y = y + height
	end
	SetDrawColor(r, g, b, a)
end

function DrawStringWidth(height, font, text)
	text = tr(text)
	if not hasWide(text) then
		return origDrawStringWidth(height, font, text)
	end
	local max = 0
	for line in eachLine(text) do
		local w = lineWidth(segments(line), height, font)
		if w > max then
			max = w
		end
	end
	return max
end

-- Returns the 1-based byte position of the caret, like the engine does for ASCII text.
-- Not translated: this is used for text the user is editing.
function DrawStringCursorIndex(height, font, text, cursorX, cursorY)
	if not hasWide(text) then
		return origDrawStringCursorIndex(height, font, text, cursorX, cursorY)
	end
	local lineStart = 1
	local lineY = height
	for line in eachLine(text) do
		if cursorY <= lineY or lineStart + #line > #text then
			-- Walk this line character by character
			local x = 0
			local pos = 1
			local esc
			for _, seg in ipairs(segments(line)) do
				if seg.cp then
					local adv = glyphAdvance(seg.cp, height)
					if cursorX <= x + adv / 2 then
						return lineStart + pos - 1
					end
					x = x + adv
					pos = pos + seg.len
				else
					local idx = origDrawStringCursorIndex(height, font, seg.text, cursorX - x, height / 2)
					if idx <= #seg.text then
						return lineStart + pos - 1 + idx - 1
					end
					x = x + origDrawStringWidth(height, font, seg.text)
					pos = pos + #seg.text
				end
			end
			return lineStart + #line
		end
		lineStart = lineStart + #line + 1
		lineY = lineY + height
	end
	return #text + 1
end
