local H = require("./harness")
local check = H.check
local Polaris, env = H.load(nil, function(e)
	local luau = require("@lune/luau")
	e.loadstring = function(code)
		local ok, fn = pcall(luau.load, code, { environment = e })
		if not ok then return nil, tostring(fn) end
		return fn
	end
end)

local function newWin()
	return Polaris:CreateWindow({ Name = "L" .. tostring(math.random(1, 1e9)) })
end

check("library normalize validates", function()
	local L = Polaris.Library
	local e = L.normalize({ Name = "Hello World", Url = "https://example.com/a.lua", Tags = "fun, easy" })
	assert(e.Id == "hello_world" or e.Id:find("hello"), e.Id)
	assert(#e.Tags == 2 and e.Url)
	H.expectError(function() L.normalize({ Name = "x" }) end)
	H.expectError(function() L.normalize({ Url = "https://x" }) end)
	local e2 = L.normalize({ Name = "Src", Source = "https://x.y/z.lua" })
	assert(e2.Url == "https://x.y/z.lua")
	local e3 = L.normalize({ Name = "Src2", Source = "print(1)" })
	assert(e3.Code == "print(1)")
end)

check("library add/query/favourite", function()
	local lib = Polaris.Library.new({ Name = "T" })
	lib:AddMany({
		{ Name = "Alpha", Description = "first", Tags = { "fun" }, Run = function() end },
		{ Name = "Beta", Description = "second thing", Tags = { "tool", "fun" }, Run = function() end },
		{ Name = "Gamma", Author = "zed", Tags = { "tool" }, Run = function() end },
	})
	assert(lib:Count() == 3)
	assert(#lib:Query({ Text = "second" }) == 1)
	assert(#lib:Query({ Tag = "fun" }) == 2)
	assert(#lib:Query({ Text = "zed" }) == 1)
	lib:Favourite("gamma", true)
	assert(lib:Query({})[1].Name == "Gamma", "favourites sort first")
	assert(#lib:Query({ Favourites = true }) == 1)
	local tags = lib:Tags()
	assert(#tags == 2 and tags[1] == "fun")
	assert(lib:Remove("alpha") and lib:Count() == 2)
	-- re-adding same id replaces
	lib:Add({ Name = "Beta", Run = function() end })
	assert(lib:Count() == 2)
end)

check("library run: function, code, url, errors, trusted hosts", function()
	local lib = Polaris.Library.new({ TrustedHosts = { "good.example" } })
	local hits = 0
	lib:Add({ Name = "Fn", Run = function() hits += 1 end })
	lib:Add({ Name = "Boom", Run = function() error("kaput") end })
	lib:Add({ Name = "Code", Code = "RAN_CODE = true" })
	lib:Add({ Name = "BadCode", Code = "this is not lua (((" })
	lib:Add({ Name = "Remote", Url = "https://good.example/a.lua" })
	lib:Add({ Name = "Evil", Url = "https://evil.example/a.lua" })
	assert(lib:Run("fn") and hits == 1)
	local ok, err = lib:Run("boom")
	assert(not ok and err:find("kaput"))
	assert(lib:Run("code"))
	local ok2, err2 = lib:Run("badcode")
	assert(not ok2 and err2:find("mistake"))
	env.game.HttpGet = function(_, url) return "REMOTE_RAN = '" .. url .. "'" end
	assert(lib:Run("remote"))
	local ok3, err3 = lib:Run("evil")
	assert(not ok3 and err3:find("TrustedHosts"))
	local ok4 = lib:Run("nope")
	assert(not ok4)
	assert(lib._runs.fn == 1)
end)

check("manifest import/export", function()
	local lib = Polaris.Library.new({})
	local n, err = lib:LoadManifest('{"scripts":[{"Name":"A","Url":"https://x.y/a.lua","Tags":["t"]},{"Name":"Bad"}]}')
	assert(n == 1 and err and err:find("needs"), tostring(err))
	local json = lib:Export()
	local lib2 = Polaris.Library.new({})
	assert(lib2:LoadManifest(json) == 1)
	local n3, err3 = lib2:LoadManifest("{nope")
	assert(n3 == 0 and err3)
end)

check("script library widget", function()
	local w = newWin()
	local t = w:CreateTab({ Name = "Lib" })
	local ran = 0
	local el = t:CreateScriptLibrary({
		Scripts = {
			{ Name = "One", Description = "d", Tags = "a", Run = function() ran += 1 end },
			{ Name = "Two", Url = "https://x.y/z.lua" },
		},
	})
	assert(#el._list:GetChildren() >= 2)
	el._search.Text = "one"
	assert(#el.Library:Query(el._filter) == 1)
	el:_runEntry(el.Library:Get("one"))
	assert(ran == 1)
	-- remote script asks for confirmation first (dialog overlay appears)
	el._search.Text = ""
	el:_runEntry(el.Library:Get("two"))
	assert(w._frame:FindFirstChild("DialogOverlay"), "expected confirm dialog")
	el:Destroy()
	w:Destroy()
end)

check("tab accepts library object and plain list", function()
	local w = newWin()
	local t = w:CreateTab({ Name = "Lib" })
	local lib = Polaris.Library.new({ Scripts = { { Name = "A", Run = function() end } } })
	local el = t:CreateScriptLibrary(lib)
	assert(el.Library == lib)
	local el2 = t:CreateScriptLibrary({ { Name = "B", Run = function() end } })
	assert(el2.Library:Count() == 1)
	w:Destroy()
end)

H.finish()
