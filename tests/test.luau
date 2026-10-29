-- Polaris logic tests, run with Lune.
-- Verifies API behavior, validation, config round-trips, and cleanup using mocks.
-- Does NOT verify visual rendering or real input handling (see README).

local luau = require("@lune/luau")
local fs = require("@lune/fs")
local mock = require("./mock")
local tasklib = require("@lune/task")

----------------------------------------------------------------
-- Load the library into the mocked environment
----------------------------------------------------------------

local source
if fs.isFile("Polaris.luau") then
	-- run from the project root: lune run tests/test.luau
	source = fs.readFile("Polaris.luau")
else
	-- run from tests/: lune run test.luau
	source = fs.readFile("../Polaris.luau")
end
local env = mock.buildEnv()
setmetatable(env, { __index = _G })
env.task = require("@lune/task")

local chunk = luau.load(source, { debugName = "Polaris.luau", environment = env })
local Polaris = chunk()

----------------------------------------------------------------
-- Mini test framework
----------------------------------------------------------------

local passed, failed = 0, 0
local failures = {}

local function check(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(("PASS  %s"):format(name))
	else
		failed += 1
		table.insert(failures, { name = name, err = tostring(err) })
		print(("FAIL  %s\n        %s"):format(name, tostring(err)))
	end
end

local function expectError(fn)
	local ok, err = pcall(fn)
	assert(not ok, "expected an error, but none was raised")
	return err
end

----------------------------------------------------------------
-- Tests
----------------------------------------------------------------

check("library loads and exposes API", function()
	assert(type(Polaris) == "table", "Polaris is not a table")
	assert(Polaris.Version == "1.0.0", "wrong version")
	assert(type(Polaris.CreateWindow) == "function")
	assert(type(Polaris.Themes.Default) == "table")
	assert(type(Polaris.Notify) == "function")
end)

local window
local tab

check("window and tab creation", function()
	window = Polaris:CreateWindow({
		Name = "TestHub",
		Theme = "Midnight",
		ToggleKey = env.Enum.KeyCode.RightControl,
	})
	assert(type(window) == "table")
	assert(type(window.CreateTab) == "function")
	assert(window._screenGui ~= nil, "screen gui missing")
	tab = window:CreateTab({ Name = "Main" })
	assert(type(tab) == "table")
	assert(#window._tabs == 1)
end)

local toggle, slider, dropdown, multiDropdown, colorPicker, keybind, textbox, paragraph

check("element creation", function()
	window:CreateTab({ Name = "Second" })
	assert(#window._tabs == 2, "second tab not created")
	-- first tab of the first window is auto-selected
	assert(window._tabs[1]._content.Visible == true, "first tab not selected")
	assert(window._tabs[2]._content.Visible == false, "second tab wrongly visible")

	toggle = tab:CreateToggle({ Name = "Toggle", Default = false, Flag = "tg1" })
	slider = tab:CreateSlider({ Name = "Slider", Min = 0, Max = 100, Default = 50, Increment = 5, Flag = "sl1" })
	dropdown = tab:CreateDropdown({ Name = "Dropdown", Options = { "a", "b", "c" }, Default = "a", Flag = "dd1" })
	multiDropdown = tab:CreateDropdown({ Name = "Multi", Options = { "x", "y", "z" }, Multiple = true, Flag = "dd2" })
	colorPicker = tab:CreateColorPicker({ Name = "Color", Default = env.Color3.fromRGB(255, 0, 0), Flag = "cp1" })
	keybind = tab:CreateKeybind({ Name = "Key", Default = env.Enum.KeyCode.E, Flag = "kb1" })
	textbox = tab:CreateTextbox({ Name = "Text", Default = "hello", Flag = "tb1" })
	paragraph = tab:CreateParagraph({ Text = "some text" })
	tab:CreateDivider({})
	tab:CreateSection({ Name = "Section" })
	local btn = tab:CreateButton({ Name = "Button", Callback = function() end })
	assert(btn ~= nil)
	assert(#tab._elements == 10, ("expected 10 elements, got %d"):format(#tab._elements))
end)

check("toggle Set/Get and callbacks", function()
	local firedWith = nil
	toggle._config.Callback = function(v) firedWith = v end
	toggle:Set(true)
	assert(toggle:Get() == true)
	assert(firedWith == true, "callback did not fire on Set")
	firedWith = nil
	toggle:Set(false, true) -- silent
	assert(toggle:Get() == false)
	assert(firedWith == nil, "silent Set should not fire callback")
	-- click simulation via Activated
	firedWith = nil
	toggle._interaction.Activated:FireOnce()
	assert(toggle:Get() == true, "click did not toggle")
	assert(firedWith == true)
end)

check("slider clamping and stepping", function()
	slider:Set(500) -- above max
	assert(slider:Get() == 100, ("clamp to max failed: %s"):format(tostring(slider:Get())))
	slider:Set(-20) -- below min
	assert(slider:Get() == 0, "clamp to min failed")
	slider:Set(52) -- with increment 5 should round to 50
	assert(slider:Get() == 50, ("step rounding failed: %s"):format(tostring(slider:Get())))
	local got = nil
	slider._config.Callback = function(v) got = v end
	slider:Set(75)
	assert(got == 75, "slider callback did not fire")
end)

check("slider drag simulation", function()
	-- track AbsolutePosition (0,0), AbsoluteSize (500,500) in mock
	slider._interaction.InputBegan:FireOnce(mock.makeInput(mock.Enum.UserInputType.MouseButton1, nil, 250, 0))
	mock.UIS().InputChanged:FireOnce(mock.mouseInput(250, 0))
	assert(slider:Get() == 50, ("drag to center failed: %s"):format(tostring(slider:Get())))
	mock.UIS().InputEnded:FireOnce(mock.makeInput(mock.Enum.UserInputType.MouseButton1, nil, 0, 0))
end)

check("slider step normalization on unaligned ranges", function()
	local t = tab:CreateSlider({ Name = "Odd", Min = 1, Max = 9, Default = 1, Increment = 5, Flag = "odd" })
	t:Set(9) -- naive floor-to-step would give 1+2*5=11, out of range
	assert(t:Get() == 9, ("expected clamp to 9, got %s"):format(tostring(t:Get())))
	t:Set(5) -- nearest step from 1 with inc 5 is 6
	assert(t:Get() == 6, ("expected 6, got %s"):format(tostring(t:Get())))
	t:Destroy()
	window.Flags["odd"] = nil
end)

check("dropdown option highlights refresh on Set", function()
	dropdown:Set("b")
	-- selected options get a "  -" suffix in their text label
	local found = false
	for _, btn in dropdown._optionButtons do
		local label = btn:FindFirstChild("TextLabel")
		if label and label._props.Text == "b  -" then
			found = true
		end
	end
	assert(found, "selected option highlight not refreshed after Set")
end)

check("theme colors applied to elements", function()
	-- themed() must apply colors immediately, not only on switch
	local theme = Polaris.Themes[Polaris.CurrentThemeName]
	assert(theme, "no current theme")
	local got = toggle._label._props.TextColor3
	assert(got and got.R == theme.Text.R and got.G == theme.Text.G, "toggle label color not applied")
end)

check("in-memory save -> change -> load restores values", function()
	toggle:Set(true)
	slider:Set(80)
	window:SaveConfig("mem")
	toggle:Set(false)
	slider:Set(10)
	window:LoadConfig("mem")
	assert(toggle:Get() == true, "toggle not restored from in-memory config")
	assert(slider:Get() == 80, "slider not restored from in-memory config")
end)

check("SetTitle updates the title label", function()
	window:SetTitle("Renamed")
	assert(window._title._props.Text == "Renamed", "title label not updated")
end)

check("SetToggleKey works after creation without initial key", function()
	local w = Polaris:CreateWindow({ Name = "NoKeyWindow" })
	local t = w:CreateTab({ Name = "Main" })
	w:SetToggleKey(env.Enum.KeyCode.RightShift)
	local before = w._screenGui._props.Enabled
	mock.fireInput(mock.Enum.UserInputType.Keyboard, env.Enum.KeyCode.RightShift, 0, 0)
	assert(w._screenGui._props.Enabled ~= before, "late toggle key did not flip visibility")
	w:Destroy()
end)

check("notifications are parented under a ScreenGui", function()
	Polaris:Notify({ Title = "ParentTest", Content = "x" })
	-- notification container's parent must be a ScreenGui, not CoreGui directly
	local manager = Polaris._notifications
	assert(manager, "notification manager not exposed")
	local container = manager._container
	assert(container, "notification container missing")
	local parent = container._props.Parent
	assert(parent ~= nil, "notification container has no parent")
	assert(parent._className == "ScreenGui", ("parent is %s, expected ScreenGui"):format(tostring(parent._className)))
end)

check("deferred config load applies to late-flagged elements", function()
	local w = Polaris:CreateWindow({ Name = "DeferredLoad", SaveConfig = true })
	local t = w:CreateTab({ Name = "Main" })
	-- value saved for a flag whose element is created after the window
	w._savedConfigs = { default = { ["dfly"] = true } }
	local el = t:CreateToggle({ Name = "T", Default = false, Flag = "dfly" })
	assert(el:Get() == false, "sanity: default should be false before deferred load")
	-- yield to the scheduler so the deferred load actually runs
	tasklib.wait()
	assert(el:Get() == true, "deferred load did not restore the element")
	w:Destroy()
end)

check("window drag from a centered (scaled) position clamps in pixel space", function()
	local w = Polaris:CreateWindow({ Name = "DragTest", Size = env.Vector2.new(580, 400) })
	-- simulate a centered window: AbsolutePosition (670, 340), viewport 1920x1080
	w._frame._props.AbsolutePosition = env.Vector2.new(670, 340)
	w._titleBar.InputBegan:FireOnce(mock.makeInput(mock.Enum.UserInputType.MouseButton1, nil, 800, 400))
	-- drag far past the right/bottom edge: should clamp to viewport bounds
	mock.UIS().InputChanged:FireOnce(mock.mouseInput(5000, 5000))
	local pos = w._frame._props.Position
	assert(pos.X.Scale == 0 and pos.Y.Scale == 0, "drag result should be zero-scale")
	assert(pos.X.Offset == 1920 - 100, ("X not clamped: %s"):format(tostring(pos.X.Offset)))
	assert(pos.Y.Offset == 1080 - 36, ("Y not clamped: %s"):format(tostring(pos.Y.Offset)))
	mock.UIS().InputEnded:FireOnce(mock.makeInput(mock.Enum.UserInputType.MouseButton1, nil, 0, 0))
	w:Destroy()
end)

check("disabling a slider stops an in-progress drag", function()
	local t = tab:CreateSlider({ Name = "DisSlider", Min = 0, Max = 100, Default = 50, Flag = "dsl" })
	-- start dragging
	t._interaction.InputBegan:FireOnce(mock.makeInput(mock.Enum.UserInputType.MouseButton1, nil, 250, 0))
	mock.UIS().InputChanged:FireOnce(mock.mouseInput(250, 0))
	assert(t:Get() == 50)
	-- disable mid-drag, then keep moving: value must not change
	t:SetDisabled(true)
	local seen = t:Get()
	mock.UIS().InputChanged:FireOnce(mock.mouseInput(400, 0))
	assert(t:Get() == seen, ("drag continued while disabled: %s"):format(tostring(t:Get())))
	t:Destroy()
	window.Flags["dsl"] = nil
end)

check("theme switch recolors an enabled toggle's track", function()
	toggle:Set(true)
	Polaris:SetTheme("Light")
	local light = Polaris.Themes.Light
	local got = toggle._trackFrame._props.BackgroundColor3
	assert(got and got.R == light.Accent.R and got.G == light.Accent.G and got.B == light.Accent.B,
		("enabled toggle track not recolored on theme switch: %s"):format(tostring(got)))
	Polaris:SetTheme("Midnight")
end)

check("dropdown validation and selection", function()
	dropdown:Set("b")
	assert(dropdown:Get() == "b")
	local err = expectError(function()
		dropdown:Set("nope")
	end)
	assert(err:find("not a valid option"), ("unexpected error message: %s"):format(err))

	multiDropdown:Set({ "x", "z" })
	local value = multiDropdown:Get()
	assert(type(value) == "table", "multi dropdown Get should return table")
	assert(value["x"] and value["z"] and not value["y"], "multi selection wrong")
	local err2 = expectError(function()
		multiDropdown:Set({ "bad" })
	end)
	assert(err2:find("not a valid option"))
end)

check("color picker round trip", function()
	assert(mock.typeof(colorPicker:Get()) == "Color3")
	local c = colorPicker:Get()
	assert(math.abs(c.R - 1) < 0.01 and c.G < 0.01, "default color wrong")
	colorPicker:Set(env.Color3.fromRGB(0, 128, 255))
	local c2 = colorPicker:Get()
	assert(math.abs(c2.G - 128 / 255) < 0.01, "Set color wrong")
end)

check("keybind callback on input", function()
	local pressed = false
	keybind._config.Callback = function() pressed = true end
	mock.fireInput(mock.Enum.UserInputType.Keyboard, env.Enum.KeyCode.E, 0, 0)
	assert(pressed, "keybind callback did not fire")
end)

check("textbox value", function()
	assert(textbox:Get() == "hello")
	textbox:Set("changed")
	assert(textbox:Get() == "changed")
end)

check("paragraph text update", function()
	paragraph:SetText("updated text")
	assert(paragraph:Get() == "updated text")
end)

check("duplicate flag detection", function()
	local err = expectError(function()
		tab:CreateToggle({ Name = "Dup", Flag = "tg1" })
	end)
	assert(err:find("Duplicate flag"), ("unexpected error: %s"):format(err))
end)

check("SetVisible / SetDisabled / Destroy on elements", function()
	local t2 = tab:CreateToggle({ Name = "Temp" })
	t2:SetVisible(false)
	assert(t2._container.Visible == false, "SetVisible failed")
	t2:SetDisabled(true)
	assert(t2._disabled == true)
	t2:Destroy()
	assert(t2._destroyed)
	-- flag registry cleaned
	local t3 = tab:CreateToggle({ Name = "Temp2", Flag = "tmp" })
	t3:Destroy()
	assert(window.Flags["tmp"] == nil, "flag not cleaned up on destroy")
end)

check("config export/import round trip", function()
	toggle:Set(true)
	slider:Set(75)
	dropdown:Set("c")
	multiDropdown:Set({ "y" })
	colorPicker:Set(env.Color3.fromRGB(10, 20, 30))
	keybind:Set(env.Enum.KeyCode.F)

	local json = window:ExportConfig()
	assert(type(json) == "string" and #json > 0, "export produced nothing")

	-- fresh window with same flags
	local w2 = Polaris:CreateWindow({ Name = "TestHub2" })
	local t2 = w2:CreateTab({ Name = "Main" })
	local tg2 = t2:CreateToggle({ Name = "T", Default = false, Flag = "tg1" })
	local sl2 = t2:CreateSlider({ Name = "S", Min = 0, Max = 100, Default = 0, Increment = 5, Flag = "sl1" })
	local dd2 = t2:CreateDropdown({ Name = "D", Options = { "a", "b", "c" }, Flag = "dd1" })
	local md2 = t2:CreateDropdown({ Name = "M", Options = { "x", "y", "z" }, Multiple = true, Flag = "dd2" })
	local cp2 = t2:CreateColorPicker({ Name = "C", Flag = "cp1" })
	local kb2 = t2:CreateKeybind({ Name = "K", Flag = "kb1" })

	w2:ImportConfig(json)

	assert(tg2:Get() == true, "toggle not restored")
	assert(sl2:Get() == 75, "slider not restored")
	assert(dd2:Get() == "c", "dropdown not restored")
	local mv = md2:Get()
	assert(mv["y"] and not mv["x"], "multi dropdown not restored")
	local col = cp2:Get()
	assert(math.abs(col.R - 10 / 255) < 0.01 and math.abs(col.G - 20 / 255) < 0.01, "color not restored")
	assert(kb2:Get().Name == "F", "keybind not restored")

	w2:Destroy()
end)

check("SaveConfig returns data table", function()
	local data = window:SaveConfig("default")
	assert(type(data) == "table")
	assert(data["tg1"] ~= nil, "saved config missing flags")
end)

check("theme switching", function()
	window._frame._props.BackgroundColor3 = nil -- will be re-set by SetTheme
	Polaris:SetTheme("Light")
	assert(Polaris.CurrentThemeName == "Light")
	local err = expectError(function()
		Polaris:SetTheme("NonexistentTheme")
	end)
	assert(err:find("Unknown theme"), ("unexpected error: %s"):format(err))
	Polaris:AddTheme("Custom", { Accent = env.Color3.fromRGB(1, 2, 3) })
	Polaris:SetTheme("Custom")
	assert(Polaris.Themes.Custom.Accent.R < 0.01)
	Polaris:SetTheme("Midnight")
end)

check("search filtering", function()
	-- all elements visible initially (tab 1 selected)
	assert(toggle._container.Visible == true)
	window._searchBox.Text = "slid" -- fires Property:Text -> filter handler
	assert(toggle._container.Visible == false, "non-matching element should be hidden")
	assert(slider._container.Visible == true, "matching element should stay visible")
	window._searchBox.Text = "" -- clear filter
	assert(toggle._container.Visible == true, "clearing search should restore visibility")
end)

check("notifications do not error", function()
	Polaris:Notify({ Title = "Hello", Content = "World", Duration = 5 })
	Polaris:Notify({ Title = "Typed", Content = "!", Type = "success" })
	local err = expectError(function()
		Polaris:Notify({ Content = "no title" })
	end)
	assert(err:find("Title"), "Notify should validate Title")
end)

check("window toggle keybind", function()
	local enabledBefore = window._screenGui._props.Enabled
	mock.fireInput(mock.Enum.UserInputType.Keyboard, env.Enum.KeyCode.RightControl, 0, 0)
	assert(window._screenGui._props.Enabled ~= enabledBefore, "toggle key did not flip visibility")
end)

check("window destroy cleans up", function()
	local gui = window._screenGui
	window:Destroy()
	assert(window._destroyed)
	assert(gui._destroyed, "ScreenGui not destroyed")
	assert(gui._props.Parent == nil, "ScreenGui still parented")
	for flag in window.Flags do
		error("flags not cleared: " .. flag)
	end
	assert(#Polaris._windows == 0, "window still in registry")
end)

check("tab destroy cleans up", function()
	local w = Polaris:CreateWindow({ Name = "TabDestroyTest" })
	local t = w:CreateTab({ Name = "Main" })
	local el = t:CreateToggle({ Name = "T", Flag = "td1" })
	assert(w.Flags["td1"] == el)
	t:Destroy()
	assert(w.Flags["td1"] == nil, "element flags not removed with tab")
	w:Destroy()
end)

check("cross-window flag registry lookup", function()
	local w = Polaris:CreateWindow({ Name = "FlagLookup" })
	local t = w:CreateTab({ Name = "Main" })
	local el = t:CreateToggle({ Name = "T", Flag = "sharedflag" })
	assert(Polaris.WindowFlags["sharedflag"] == el, "WindowFlags lookup failed")
	w:Destroy()
	assert(Polaris.WindowFlags["sharedflag"] == nil, "WindowFlags should be empty after destroy")
end)

check("textbox disabling blocks editing and releases focus", function()
	local t = tab:CreateTextbox({ Name = "DisBox", Default = "" })
	t:SetDisabled(true)
	assert(t._box._props.TextEditable == false, "TextEditable not disabled")
	assert(t._box._props._releasedFocus == true, "focus not released on disable")
	t:SetDisabled(false)
	assert(t._box._props.TextEditable == true, "TextEditable not restored")
	t:Destroy()
end)

check("config restore does not fire keybind activation callbacks", function()
	local w = Polaris:CreateWindow({ Name = "KeybindRestore" })
	local t = w:CreateTab({ Name = "Main" })
	local presses = 0
	local kb = t:CreateKeybind({
		Name = "K",
		Default = env.Enum.KeyCode.F,
		Flag = "kbr",
		Callback = function() presses += 1 end,
	})
	local tg = t:CreateToggle({ Name = "T", Default = false, Flag = "kbrt" })
	tg:Set(true) -- toggle restore should still work via callbacks
	w:SaveConfig("default")
	local json = w:ExportConfig() -- capture while toggle is on
	tg:Set(false)
	presses = 0
	w:ImportConfig(json)
	assert(presses == 0, ("keybind activation fired during config restore: %d"):format(presses))
	assert(tg:Get() == true, "toggle not restored")
	assert(kb:Get().Name == "F", "keybind value not restored")
	w:Destroy()
end)

----------------------------------------------------------------
-- Summary
----------------------------------------------------------------

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	for _, f in failures do
		print(("  FAIL: %s -> %s"):format(f.name, f.err))
	end
	require("@lune/process").exit(1)
end
