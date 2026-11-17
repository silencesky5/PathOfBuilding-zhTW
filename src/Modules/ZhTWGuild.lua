-- Path of Building
--
-- Module: zhTW Guild
-- The crafting site's guild share shelf (公會分享架) from PoB: read the shelf, copy items,
-- and (logged in with Discord as an RKSA member) share crafted items. Server: the site's
-- Cloudflare Worker (Poe-tool/worker).
--
-- Login: the browser opens /auth/login?client=pob with a local port, a state and a PKCE
-- challenge; after Discord and the guild check the Worker sends the browser back to
-- http://127.0.0.1:<port> with a one-time code, and PoB exchanges it at /auth/pob-token with
-- the PKCE verifier. The 30-day token is only kept in the user's Settings.xml (zhTWGuildToken),
-- never in a URL or a log.
--
local dkjson = require "dkjson"
local base64 = require("base64")
local sha = require("sha2")

local ZhTWGuild = { }
ZhTWGuild.API = "https://poe-tool-auth.poe-tool-auth.workers.dev"
ZhTWGuild.token = nil -- set from Settings.xml by Main.lua
ZhTWGuild.me = nil -- { id, name, officer } once the shelf was read with a valid token

local ERRORS = {
	unauthorized = "登入已失效，請重新登入公會。",
	not_member = "這個 Discord 帳號不在 RKSA 公會伺服器裡。",
	no_role = "這個 Discord 帳號還沒有使用公會分享的身分組。",
	denied = "已取消 Discord 登入。",
	bad_state = "登入逾時或連結失效，請再按一次登入。",
	token_failed = "Discord 登入失敗，請再試一次。",
	user_failed = "Discord 登入失敗，請再試一次。",
	member_failed = "暫時無法確認公會成員資格，請稍後再試。",
	invalid_code = "登入代碼失效（超過 2 分鐘或已使用），請再按一次登入。",
	invalid_verifier = "登入驗證失敗，請再按一次登入。",
	per_user_limit = "你的分享已達上限，請先到網站撤下舊的分享。",
	shelf_full = "公會分享架已滿。",
	too_fast = "分享太頻繁，請等一分鐘再試。",
	rate_limited = "操作太頻繁，請等一分鐘再試。",
	bad_item = "這件裝備的格式不對，無法分享。",
	note_too_long = "備註最多 50 個字。",
	too_large = "資料太大，無法分享。",
	not_found = "找不到這件分享（可能已被撤下）。",
	server_error = "伺服器發生錯誤，請稍後再試。",
}

local function errorText(code, fallback)
	return ERRORS[code] or fallback or ("發生錯誤：" .. tostring(code))
end
ZhTWGuild.errorText = errorText

-- base64url without padding
local function b64url(bin)
	return (base64.encode(bin):gsub("%+", "-"):gsub("/", "_"):gsub("=+$", ""))
end

local function randomToken(n)
	local chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
	local out = { }
	for i = 1, n do
		local k = math.random(1, #chars)
		out[i] = chars:sub(k, k)
	end
	return table.concat(out)
end

-- Calls the Worker. callback(ok, data or error text, httpCode)
local function request(path, callback, params)
	params = params or { }
	local headers = { }
	if params.auth and ZhTWGuild.token then
		table.insert(headers, "Authorization: Bearer " .. ZhTWGuild.token)
	end
	if params.json then
		table.insert(headers, "Content-Type: application/json")
	end
	launch:DownloadPage(ZhTWGuild.API .. path, function(response, errMsg)
		local body = response and response.body or ""
		local data = body ~= "" and dkjson.decode(body) or nil
		if errMsg then
			local code = type(data) == "table" and data.error
			if code == "unauthorized" then
				ZhTWGuild.me = nil
			end
			callback(false, code and errorText(code) or ("連不上公會伺服器（" .. tostring(errMsg) .. "）"), code)
			return
		end
		callback(true, data)
	end, { header = #headers > 0 and table.concat(headers, "\n") or nil, body = params.body })
end
ZhTWGuild.request = request

-- The shelf: callback(ok, { shares, me, limits } or error text)
function ZhTWGuild.fetchShares(callback)
	request("/shares", function(ok, data)
		if ok and type(data) == "table" then
			ZhTWGuild.me = data.me
		end
		callback(ok, data)
	end, { auth = true })
end

-- Counts a copy on the server (the site shows how often an item was copied); result ignored
function ZhTWGuild.countCopy(id)
	request("/shares/" .. id .. "/copy", function() end, { body = "" })
end

-- Shares a crafted item (the site's stored form). text = { base = 底材名, lines = { 詞綴… } }
function ZhTWGuild.share(stored, note, dataVersion, text, callback)
	if not ZhTWGuild.token then
		callback(false, "請先登入公會（Discord）。")
		return
	end
	local body = dkjson.encode({ item = stored, note = note or "", dataVersion = dataVersion, text = text })
	request("/shares", callback, { auth = true, json = true, body = body })
end

-- Local callback server for the login, run as a sub script (same idea as LaunchServer.lua)
local SERVER_SCRIPT = [[
local url = ...
local socket = require("socket")
local server = socket.tcp4()
local port
for _, p in ipairs({ 49090, 49091, 49092, 49093 }) do
	if server:bind("127.0.0.1", p) then
		port = p
		break
	end
end
if not port or not server:listen(1) then
	server:close()
	return nil, "本機登入用的埠都被占用了", nil, nil
end
OpenURL(url .. "&port=" .. port)
local page = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\n\r\n" ..
	"<!DOCTYPE html><html><head><meta charset='utf-8'><title>PoB 台服版</title></head>" ..
	"<body style='background:#1a1814;color:#e6dfd0;font-family:sans-serif;display:flex;justify-content:center;align-items:center;height:100vh'>" ..
	"<div style='text-align:center'><h2>%s</h2><p>可以關掉這個分頁，回到 Path of Building。</p></div></body></html>"
local stopAt = os.time() + 180
local code, state, err
while os.time() < stopAt do
	server:settimeout(math.max(1, stopAt - os.time()))
	local client = server:accept()
	if client then
		client:settimeout(5)
		local line = client:receive("*l")
		local path = line and line:match("^GET%s+(%S+)")
		if path then
			local q = { }
			for k, v in path:gmatch("([%w_]+)=([^&]*)") do
				q[k] = v:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
			end
			if q.code or q.error then
				code, state, err = q.code, q.state, q.error
				client:send(string.format(page, code and "登入成功" or "登入沒有完成"))
				client:close()
				break
			end
			client:send("HTTP/1.1 404 Not Found\r\nConnection: close\r\n\r\n")
		end
		client:close()
	end
end
server:close()
if not code and not err then
	err = "timeout"
end
return code, err, state, port
]]

-- Opens the browser for Discord login. callback(ok, message)
function ZhTWGuild.login(callback)
	local verifier = randomToken(64)
	local challenge = b64url(sha.hex_to_bin(sha.sha256(verifier)))
	local state = randomToken(16)
	local url = ZhTWGuild.API .. "/auth/login?client=pob&state=" .. state .. "&challenge=" .. challenge
	local id = LaunchSubScript(SERVER_SCRIPT, "", "ConPrintf,OpenURL", url)
	if not id then
		callback(false, "無法啟動本機登入。")
		return
	end
	launch.subScripts[id] = {
		type = "DOWNLOAD",
		callback = function(code, err, gotState)
			if err == "timeout" then
				callback(false, "等待登入逾時（3 分鐘），請再試一次。")
				return
			end
			if not gotState and err then -- the local server could not start
				callback(false, errorText(err, err))
				return
			end
			if gotState ~= state then
				callback(false, "登入驗證失敗（state 不符），請再試一次。")
				return
			end
			if err then
				callback(false, errorText(err))
				return
			end
			request("/auth/pob-token", function(ok, data)
				if ok and type(data) == "table" and type(data.token) == "string" then
					ZhTWGuild.token = data.token
					main:SaveSettings()
					ZhTWGuild.fetchShares(function()
						callback(true, ZhTWGuild.me and ("已登入：" .. tostring(ZhTWGuild.me.name)) or "已登入。")
					end)
				else
					callback(false, ok and "登入失敗，請再試一次。" or data)
				end
			end, { body = "code=" .. code .. "&verifier=" .. verifier })
		end,
	}
end

-- Forgets the token on this computer only (the site stays logged in)
function ZhTWGuild.logout()
	ZhTWGuild.token = nil
	ZhTWGuild.me = nil
	main:SaveSettings()
end

return ZhTWGuild
