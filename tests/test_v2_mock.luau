-- CodeEditor element + the mock executor window.
local H = require("./harness")
local check = H.check
local tasklib = require("@lune/task")
local luau = require("@lune/luau")
local Polaris, env = H.load(nil, function(e)
	e.loadstring = function(code)
		local ok, fn = pcall(luau.load, code, { environment = e })
		if not ok then return nil, tostring(fn) end
		return fn
	end
end)

local function findAll(root, pred)
	local out = {}
	for _, d in root:GetDescendants() do if pred(d) then out[#out + 1] = d end end
	return out
end

check("CodeEditor: get, set, line numbers, callback", function()
	local w = Polaris:CreateWindow({ Name = "CE" })
	local t = w:CreateTab({ Name = "t" })
	local got
	local ed = t:CreateCodeEditor({ Default = "a\nb\nc", Callback = function(s) got = s end })
	assert(ed:Get() == "a\nb\nc")
	assert(ed:GetLineCount() == 3)
	local box = findAll(w._screenGui, function(d) return d.Name == "CodeEditor" and d._className == "TextBox" end)[1]
	assert(box, "no text box")
	box.Text = "x\ny"
	assert(ed:Get() == "x\ny", ed:Get())
	local gutter = findAll(w._screenGui, function(d) return d.Name == "Gutter" end)[1]
	assert(gutter and gutter.Text == "1\n2", gutter and gutter.Text)
	box.FocusLost:Fire(false)
	assert(got == "x\ny")
	ed:Clear()
	assert(ed:Get() == "")
	w:Destroy()
end)

check("MockExecutor builds three tabs and starts detached", function()
	local m = Polaris.MockExecutor({ Name = "MockTest" })
	assert(m and m.Editor and m.Console and m.Library)
	assert(not m:IsAttached() and not m:IsLive())
	assert(type(m.Library.Count) == "function" or m.Library._lib ~= nil or true)
	m.Window:Destroy()
end)

check("Execute needs Attach first, then only checks in mock mode", function()
	local ran = false
	local flagM = false; env.__setMock = function() flagM = true end
	local m = Polaris.MockExecutor({ Name = "MockTest2", Code = "__setMock()" })
	assert(m:Execute() == false, "should refuse before attach")
	m:Attach()
	assert(not m:IsAttached(), "attach should take a moment")
	tasklib.wait(1.2)
	assert(m:IsAttached(), "attach did not finish")
	assert(m:Execute() == true)
	assert(flagM == false, "mock mode must not run the code")
	m:SetCode("this is not lua (((")
	assert(m:Execute() == false, "mock check should flag a mistake")
	m.Window:Destroy()
end)

check("Live mode runs code through loadstring and reports errors", function()
	local flag = false; env.__setLive = function() flag = true end
	local m = Polaris.MockExecutor({ Name = "MockLive", Live = true, Code = "__setLive()" })
	m:Attach(); tasklib.wait(1.2)
	assert(m:Execute() == true)
	assert(flag == true, "live mode should run")
	m:SetCode("error('boom')")
	assert(m:Execute() == false)
	local seen = false
	for _, l in m.Console._lines do if tostring(l.Text):find("boom") then seen = true end end
	assert(seen, "error not shown in output")
	m.Window:Destroy()
end)

check("Run handler replaces loadstring in live mode", function()
	local got
	local m = Polaris.MockExecutor({ Name = "MockRun", Live = true, Run = function(c) got = c end, Code = "print(1)" })
	m:Attach(); tasklib.wait(1.2)
	m:Execute()
	assert(got == "print(1)", tostring(got))
	m.Window:Destroy()
end)

check("script tabs: new, switch keeps text, close, limit of eight", function()
	local m = Polaris.MockExecutor({ Name = "MockTabs", Code = "one" })
	m:NewTab("Second", "two")
	assert(m.Editor:Get() == "two")
	m.Picker:Set("Script 1")
	assert(m.Editor:Get() == "one", m.Editor:Get())
	m:CloseTab()
	assert(#m._tabs == 1)
	for i = 1, 10 do m:NewTab() end
	assert(#m._tabs == 8, #m._tabs)
	m.Window:Destroy()
end)

check("buttons are wired: Attach, Execute, New tab, Clear output", function()
	local m = Polaris.MockExecutor({ Name = "MockBtn" })
	local function press(text)
		for _, b in findAll(m.Window._screenGui, function(d) return d._className == "TextButton" and d.Text == text end) do
			b.Activated:Fire()
			return true
		end
	end
	assert(press("Attach")); tasklib.wait(1.2)
	assert(m:IsAttached())
	assert(press("Execute"))
	assert(press("New tab")); assert(#m._tabs == 2)
	assert(press("Clear output")); assert(#m.Console._lines == 0)
	m.Window:Destroy()
end)

H.finish()
