-- util: JSON, events, HTTP, markdown-lite -> RichText.  Pure logic, no UI.

local Util = {}
Polaris.Util = Util

function Util.svc(name)
	local ok, s = pcall(function()
		return game:GetService(name)
	end)
	if ok then
		return s
	end
	return nil
end

----------------------------------------------------------------
-- JSON (own implementation so it also works where HttpService is blocked)
----------------------------------------------------------------

local JSON = {}
Util.JSON = JSON

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }

local function jsonString(s)
	return '"' .. s:gsub('[%c"\\]', function(c)
		return ESC[c] or string.format("\\u%04x", string.byte(c))
	end) .. '"'
end

local function isArray(t)
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
			return false
		end
		n = math.max(n, k)
	end
	for i = 1, n do
		if t[i] == nil then
			return false
		end
	end
	return true
end

function JSON.encode(v, pretty, indent)
	indent = indent or ""
	local t = type(v)
	if v == nil then
		return "null"
	elseif t == "boolean" then
		return tostring(v)
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		return (tostring(v))
	elseif t == "string" then
		return jsonString(v)
	elseif t == "table" then
		local nl = pretty and "\n" or ""
		local inner = pretty and (indent .. "  ") or ""
		local sep = pretty and ",\n" or ","
		if next(v) == nil then
			return "[]"
		end
		local out = {}
		if isArray(v) then
			for i = 1, #v do
				table.insert(out, inner .. JSON.encode(v[i], pretty, inner))
			end
			return "[" .. nl .. table.concat(out, sep) .. nl .. (pretty and indent or "") .. "]"
		end
		local keys = {}
		for k in pairs(v) do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		for _, k in keys do
			local val = v[k]
			if val == nil then
				val = v[tonumber(k)]
			end
			table.insert(out, inner .. jsonString(k) .. (pretty and ": " or ":") .. JSON.encode(val, pretty, inner))
		end
		return "{" .. nl .. table.concat(out, sep) .. nl .. (pretty and indent or "") .. "}"
	end
	return "null"
end

function JSON.decode(str)
	if type(str) ~= "string" then
		return nil, "not a string"
	end
	local pos = 1
	local function skip()
		pos = str:find("[^ \t\r\n]", pos) or (#str + 1)
	end
	local function fail(msg)
		error({ json = msg .. " at position " .. pos }, 0)
	end
	local parseValue
	local function parseString()
		pos += 1
		local out = {}
		while true do
			local c = str:sub(pos, pos)
			if c == "" then
				fail("unterminated string")
			elseif c == '"' then
				pos += 1
				break
			elseif c == "\\" then
				local n = str:sub(pos + 1, pos + 1)
				local map = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", ['"'] = '"', ["\\"] = "\\", ["/"] = "/" }
				if n == "u" then
					local hex = str:sub(pos + 2, pos + 5)
					local code = tonumber(hex, 16)
					if not code then
						fail("bad unicode escape")
					end
					pos += 6
					if code >= 0xD800 and code <= 0xDBFF and str:sub(pos, pos + 1) == "\\u" then
						local low = tonumber(str:sub(pos + 2, pos + 5), 16)
						if low and low >= 0xDC00 and low <= 0xDFFF then
							code = 0x10000 + (code - 0xD800) * 0x400 + (low - 0xDC00)
							pos += 6
						end
					end
					table.insert(out, utf8.char(code))
				elseif map[n] then
					table.insert(out, map[n])
					pos += 2
				else
					fail("bad escape")
				end
			else
				local nextSpecial = str:find('[\\"]', pos) or (#str + 1)
				table.insert(out, str:sub(pos, nextSpecial - 1))
				pos = nextSpecial
			end
		end
		return table.concat(out)
	end
	function parseValue()
		skip()
		local c = str:sub(pos, pos)
		if c == "{" then
			pos += 1
			local obj = {}
			skip()
			if str:sub(pos, pos) == "}" then
				pos += 1
				return obj
			end
			while true do
				skip()
				if str:sub(pos, pos) ~= '"' then
					fail("expected string key")
				end
				local key = parseString()
				skip()
				if str:sub(pos, pos) ~= ":" then
					fail("expected ':'")
				end
				pos += 1
				obj[key] = parseValue()
				skip()
				local d = str:sub(pos, pos)
				pos += 1
				if d == "}" then
					break
				elseif d ~= "," then
					fail("expected ',' or '}'")
				end
			end
			return obj
		elseif c == "[" then
			pos += 1
			local arr = {}
			skip()
			if str:sub(pos, pos) == "]" then
				pos += 1
				return arr
			end
			local n = 0
			while true do
				n += 1
				arr[n] = parseValue()
				skip()
				local d = str:sub(pos, pos)
				pos += 1
				if d == "]" then
					break
				elseif d ~= "," then
					fail("expected ',' or ']'")
				end
			end
			return arr
		elseif c == '"' then
			return parseString()
		elseif str:sub(pos, pos + 3) == "true" then
			pos += 4
			return true
		elseif str:sub(pos, pos + 4) == "false" then
			pos += 5
			return false
		elseif str:sub(pos, pos + 3) == "null" then
			pos += 4
			return nil
		end
		local num = str:match("^-?%d+%.?%d*[eE]?[+-]?%d*", pos)
		if num and #num > 0 and tonumber(num) then
			pos += #num
			return tonumber(num)
		end
		fail("unexpected character '" .. c .. "'")
		return nil
	end
	local ok, res = pcall(function()
		local v = parseValue()
		skip()
		if pos <= #str then
			fail("trailing characters")
		end
		return v
	end)
	if ok then
		return res
	end
	if type(res) == "table" and res.json then
		return nil, res.json
	end
	return nil, tostring(res)
end

----------------------------------------------------------------
-- Tiny event emitter
----------------------------------------------------------------

function Util.Events()
	local self = { _h = {} }
	function self:On(name, fn)
		self._h[name] = self._h[name] or {}
		local entry = { fn = fn, on = true }
		table.insert(self._h[name], entry)
		return {
			Disconnect = function()
				entry.on = false
			end,
		}
	end
	function self:Emit(name, ...)
		local list = self._h[name]
		if not list then
			return
		end
		for _, entry in list do
			if entry.on then
				local ok, err = pcall(entry.fn, ...)
				if not ok then
					warn("[Polaris] event handler error:", err)
				end
			end
		end
	end
	return self
end

----------------------------------------------------------------
-- HTTP: works with executor request() or HttpService (where enabled)
----------------------------------------------------------------

local Http = {}
Util.Http = Http

local function findRequestFn()
	local candidates = {
		function() return request end,
		function() return http_request end,
		function() return syn.request end,
		function() return http.request end,
		function() return fluxus.request end,
	}
	for _, get in candidates do
		local ok, fn = pcall(get)
		if ok and type(fn) == "function" then
			return fn
		end
	end
	return nil
end

-- Override for tests / custom environments: Polaris.Util.Http.Handler = function(opts) return {...} end
Http.Handler = nil

function Http.Available()
	if Http.Handler then
		return true
	end
	if findRequestFn() then
		return true
	end
	local hs = I.services.HttpService
	return hs ~= nil and type(hs.RequestAsync) == "function"
end

-- opts: Url, Method, Headers, Body (string or table -> JSON)
-- returns { Success, StatusCode, Body, Headers, Error }
function Http.Request(opts)
	local req = {
		Url = opts.Url,
		Method = opts.Method or "GET",
		Headers = opts.Headers or {},
		Body = opts.Body,
	}
	if type(req.Body) == "table" then
		req.Body = JSON.encode(req.Body)
		if not req.Headers["Content-Type"] then
			req.Headers["Content-Type"] = "application/json"
		end
	end
	local fn = Http.Handler or findRequestFn()
	local ok, res
	if fn then
		ok, res = pcall(fn, req)
	else
		local hs = I.services.HttpService
		ok, res = pcall(function()
			return hs:RequestAsync(req)
		end)
	end
	if not ok then
		return { Success = false, StatusCode = 0, Body = "", Error = tostring(res) }
	end
	if type(res) ~= "table" then
		return { Success = false, StatusCode = 0, Body = "", Error = "no response" }
	end
	local status = res.StatusCode or res.status_code or 0
	local success = res.Success
	if success == nil then
		success = status >= 200 and status < 300
	end
	return { Success = success, StatusCode = status, Body = res.Body or "", Headers = res.Headers, Error = (not success) and ("HTTP " .. tostring(status)) or nil }
end

function Http.Get(url)
	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if ok and type(body) == "string" then
		return body
	end
	local res = Http.Request({ Url = url, Method = "GET" })
	if res.Success then
		return res.Body
	end
	return nil, res.Error or tostring(body)
end

function Util.hostOf(url)
	if type(url) ~= "string" then
		return ""
	end
	return url:match("^%a[%w+.-]*://([^/%?#:]+)") or ""
end

----------------------------------------------------------------
-- Markdown-lite -> Roblox RichText
----------------------------------------------------------------

local Markdown = {}
Util.Markdown = Markdown

function Markdown.escape(s)
	return (tostring(s):gsub("&", "&amp;"):gsub("<", "&lt;"):gsub(">", "&gt;"):gsub('"', "&quot;"):gsub("'", "&apos;"))
end

local function hex(c)
	return string.format("#%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end
Util.hex = hex

local function inline(text, accent)
	text = Markdown.escape(text)
	text = text:gsub("%[([^%]]+)%]%(([^%)]+)%)", "<u>%1</u>")
	text = text:gsub("`([^`]+)`", '<font color="#9ec1ff">%1</font>')
	text = text:gsub("%*%*(.-)%*%*", "<b>%1</b>")
	text = text:gsub("%[web:(%d+)%]", "[%1]")
	text = text:gsub("%[(%d+)%]", '<font color="' .. accent .. '"><b>[%1]</b></font>')
	return text
end

-- opts: Accent (hex string), BaseSize (number)
function Markdown.toRichText(md, opts)
	opts = opts or {}
	local accent = opts.Accent or "#5aa9ff"
	local base = opts.BaseSize or 15
	local out = {}
	local inCode = false
	for line in (tostring(md) .. "\n"):gmatch("(.-)\r?\n") do
		if line:match("^%s*```") then
			inCode = not inCode
		elseif inCode then
			table.insert(out, '<font color="#9ec1ff">' .. Markdown.escape(line) .. "</font>")
		else
			local h, rest = line:match("^(#+)%s+(.*)$")
			if h then
				local size = base + math.max(0, 8 - #h * 2)
				table.insert(out, string.format('<font size="%d"><b>%s</b></font>', size, inline(rest, accent)))
			elseif line:match("^%s*[-*]%s+") then
				table.insert(out, "  \u{2022}  " .. inline(line:gsub("^%s*[-*]%s+", ""), accent))
			elseif line:match("^%s*>%s?") then
				table.insert(out, '<font color="#9aa3b8">  \u{258F} ' .. inline(line:gsub("^%s*>%s?", ""), accent) .. "</font>")
			elseif line:match("^%-%-%-+$") then
				table.insert(out, "")
			else
				table.insert(out, inline(line, accent))
			end
		end
	end
	while #out > 0 and out[#out] == "" do
		table.remove(out)
	end
	return table.concat(out, "\n")
end

function Markdown.toPlain(md)
	local s = tostring(md)
	s = s:gsub("%[([^%]]+)%]%(([^%)]+)%)", "%1 (%2)")
	s = s:gsub("%*%*(.-)%*%*", "%1"):gsub("`([^`]+)`", "%1"):gsub("\n#+%s*", "\n"):gsub("^#+%s*", "")
	return s
end
