local H = require("./harness")
local check = H.check
local Polaris, env = H.load()
local tasklib = require("@lune/task")

local function newWin(extra)
	local cfg = { Name = "T" .. tostring(math.random(1, 1e9)) }
	for k, v in extra or {} do cfg[k] = v end
	return Polaris:CreateWindow(cfg)
end

check("json round trip", function()
	local J = Polaris.Util.JSON
	local v = J.decode('{"a":[1,2,{"b":"x\\n\\u00e9"}],"t":true,"n":null,"f":-1.5e2}')
	assert(v.a[3].b == "x\n\u{e9}" and v.t == true and v.f == -150)
	local enc = J.encode({ name = "q\"uote", list = { 1, 2, 3 }, nested = { ok = true } })
	local back = J.decode(enc)
	assert(back.name == 'q"uote' and #back.list == 3 and back.nested.ok == true)
	local bad, err = J.decode("{bad")
	assert(bad == nil and err)
end)

check("markdown to richtext escapes and formats", function()
	local M = Polaris.Util.Markdown
	local out = M.toRichText("# Title\n- **bold** item [1]\n<script> & `code`")
	assert(out:find("<b>Title</b>", 1, true))
	assert(out:find("<b>bold</b>", 1, true))
	assert(out:find("&lt;script&gt; &amp;", 1, true))
	assert(out:find("[1]", 1, true))
	assert(not out:find("<script>", 1, true))
end)

check("new elements create and update", function()
	local w = newWin()
	local t = w:CreateTab({ Name = "Main" })
	local lbl = t:CreateLabel({ Text = "Hello", Size = 20 })
	lbl:SetText("Changed")
	assert(lbl:Get() == "Changed")
	local p = t:CreateProgress({ Name = "Load", Value = 0.25 })
	p:Set(0.5)
	assert(p:Get() == 0.5)
	local c = t:CreateConsole({ Name = "Log", Height = 100, MaxLines = 3 })
	for i = 1, 5 do c:Log("line " .. i) end
	assert(#c._lines == 3)
	c:Clear()
	assert(#c._lines == 0)
	local hit = 0
	local row = t:CreateButtonRow({ Buttons = { { Name = "A", Callback = function() hit += 1 end }, { Name = "B" } } })
	row._buttons[1].Activated:Fire()
	assert(hit == 1)
	local s = t:CreateStats({ Items = { "FPS", "Players", { Name = "Custom", Get = function() return 42 end } } })
	assert(s._valueLabels[3].Text == "42")
	s:Destroy()
	w:Destroy()
end)

check("Tab:Add and CreateMany", function()
	local w = newWin()
	local t = w:CreateTab({ Name = "Main" })
	local made = t:CreateMany({
		{ Type = "Heading", Text = "Hi" },
		{ Type = "Button", Name = "Go" },
		{ Type = "Toggle", Name = "On?", Default = true, Flag = "on" },
	})
	assert(#made == 3 and w.Flags.on:Get() == true)
	H.expectError(function() t:Add("Nope", {}) end)
	w:Destroy()
end)

check("button callback is optional", function()
	local w = newWin()
	local t = w:CreateTab({ Name = "Main" })
	local b = t:CreateButton({ Name = "No callback" })
	b._interaction.Activated:Fire()
	w:Destroy()
end)

check("dialog and settings tab", function()
	local w = newWin({ ConfigFolder = "X" })
	w:CreateTab({ Name = "Main" })
	local got = false
	local d = w:Dialog({ Title = "T", Content = "C", Buttons = { { Name = "No" }, { Name = "Yes", Callback = function() got = true end } } })
	assert(d._gui.Parent ~= nil)
	d:Close()
	local st = w:AddSettingsTab()
	assert(w:GetTab("Settings") == st)
	w:SelectTab("Settings")
	w:Destroy()
end)

H.finish()
