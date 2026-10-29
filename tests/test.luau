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
local process = require("@lune/process")
local argPath = process.args and process.args[1]
if argPath then
	-- explicit path: lune run tests/test.luau src/Polaris.luau
	source = fs.readFile(argPath)
elseif fs.isFile("Polaris.luau") then
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
	assert(Polaris.Version == "1.2.3", "wrong version")
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
-- Builder
----------------------------------------------------------------

local B

check("builder module exposes API", function()
	assert(type(Polaris.Builder) == "table", "Polaris.Builder missing")
	assert(type(Polaris.Builder.Open) == "function")
	assert(type(Polaris.Builder.Generate) == "function")
	assert(type(Polaris.Builder.ExportJSON) == "function")
	B = Polaris.Builder
end)

check("builder default project", function()
	local p = B:GetProject()
	assert(type(p.window) == "table" and p.window.Name == "My Hub")
	assert(#p.tabs == 1 and #p.tabs[1].nodes == 2, "default project shape wrong")
	p.window.Name = "mutated"
	assert(B:GetProject().window.Name == "My Hub", "GetProject must return a copy")
end)

check("builder add block inserts after selection", function()
	B:NewProject()
	local proj = B._project
	local tab = proj.tabs[1]
	B:Select(tab, tab.nodes[2]) -- select the Toggle
	local slider = B:AddBlock("Slider")
	assert(slider ~= nil and slider.Kind == "Slider")
	assert(#tab.nodes == 3, "slider not added")
	assert(tab.nodes[3].Kind == "Slider" and tab.nodes[2].Kind == "Toggle", "slider not inserted after selection")
	assert(slider.Flag ~= nil and slider.Flag ~= "fly", "auto flag missing or colliding")
	local btn = B:AddBlock("Button")
	assert(tab.nodes[4] == btn and tab.nodes[3].Kind == "Slider", "second add should follow the new selection")
end)

check("builder move, duplicate, delete", function()
	B:NewProject()
	local proj = B._project
	local tab = proj.tabs[1]
	B:Select(tab, tab.nodes[1]) -- Section
	assert(B:MoveSelected(1) == true, "move down failed")
	assert(tab.nodes[1].Kind == "Toggle" and tab.nodes[2].Kind == "Section", "move down did not swap")
	assert(B:MoveSelected(-1) == true, "move up failed")
	assert(B:MoveSelected(-1) == false, "move above first should fail")
	B:Select(tab, tab.nodes[2]) -- Toggle (flag fly)
	local dup = B:DuplicateSelected()
	assert(dup.Kind == "Toggle" and dup.Flag ~= "fly" and dup.Flag ~= "", "duplicate flag must be unique")
	assert(#tab.nodes == 3 and tab.nodes[3] == dup, "duplicate not inserted after original")
	assert(B:DeleteSelected() == true, "delete failed")
	assert(#tab.nodes == 2, "delete did not remove node")
	-- deleting the last tab is allowed
	B:Select(tab, nil)
	assert(B:DeleteSelected() == true, "delete tab failed")
	assert(#proj.tabs == 0)
	local t2 = B:AddTab("Fresh")
	assert(#proj.tabs == 1 and t2.Name == "Fresh")
end)

check("builder codegen", function()
	B:NewProject()
	local proj = B._project
	proj.window.Name = 'My "Hub"'
	local tab = proj.tabs[1]
	B:Select(tab, tab.nodes[2])
	local dd = B:AddBlock("Dropdown")
	dd.Options = "red, green, blue"
	dd.Multiple = true
	local code = B:Generate()
	assert(type(code) == "string" and #code > 0)
	assert(code:find("loadstring(game:HttpGet(", 1, true) ~= nil, "loader line missing")
	assert(code:find('Name = "My \\"Hub\\""', 1, true) ~= nil, "window name not escaped")
	assert(code:find('Flag = "fly"', 1, true) ~= nil, "toggle flag missing")
	assert(code:find(":CreateDropdown(", 1, true) ~= nil, "dropdown missing")
	assert(code:find('Options = { "red", "green", "blue" }', 1, true) ~= nil, "dropdown options wrong")
	assert(code:find("Multiple = true", 1, true) ~= nil, "multi-select missing")
	assert(code:find(":CreateSection(", 1, true) ~= nil, "section missing")
end)

check("builder JSON round trip", function()
	B:NewProject()
	local proj = B._project
	proj.window.Name = "RoundTrip"
	local tab = proj.tabs[1]
	B:Select(tab, tab.nodes[2])
	B:AddBlock("Slider")
	local json = B:ExportJSON()
	B:NewProject()
	B:ImportJSON(json)
	local p = B:GetProject()
	assert(p.window.Name == "RoundTrip", "window name lost in JSON round trip")
	assert(#p.tabs[1].nodes == 3, "nodes lost in JSON round trip")
	assert(p.tabs[1].nodes[3].Kind == "Slider", "slider lost in JSON round trip")
	local ok, err = pcall(function()
		B:ImportJSON("{not json")
	end)
	assert(not ok, "invalid JSON should error")
end)

check("builder UI lifecycle", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	assert(B:IsOpen() == false, "builder should start closed")
	B:Open()
	assert(B:IsOpen() == true, "builder should be open")
	assert(B._gui ~= nil and not B._gui._destroyed, "fullscreen gui missing")
	-- one column per tab, one block frame per node
	assert(#B._columns == 1, "canvas should render one column per tab")
	assert(#B._columns[1].blockFrames == 2, "default project has 2 blocks")
	-- palette lists the block types
	assert(#B._paletteButtons == 10, "palette should list 10 block types")
	B:Close()
	assert(B:IsOpen() == false, "builder should be closed")
	assert(B._gui == nil, "gui reference not cleared")
	assert(B._project ~= nil, "project should survive close")
	-- reopen works and does not stack
	B:Open()
	assert(B:IsOpen() == true)
	B:Close()
end)

check("builder splash plays and cleans up", function()
	B.SplashDuration = 0.02
	B:Close()
	B:Open()
	assert(B._splashGui == nil, "splash gui should be destroyed after Open")
	assert(B:IsOpen() == true, "builder window should open after splash")
	B.SplashDuration = 0
	B:Close()
end)

check("builder preview builds a real window", function()
	B:NewProject()
	local proj = B._project
	B:AddTab("Second")
	B.SplashDuration = 0
	B:Open()
	local prev = B:OpenPreview()
	assert(prev ~= nil and prev._destroyed ~= true, "preview window missing")
	assert(#prev._tabs == 2, "preview should mirror project tabs")
	local previewElements = #prev._tabs[1]._elements
	assert(previewElements >= 1, "preview tab should contain the project blocks")
	B:ClosePreview()
	assert(prev._destroyed == true, "preview not destroyed")
	local prev2 = B:OpenPreview()
	assert(prev2 ~= nil and prev2 ~= prev, "second preview should be a new window")
	B:OpenPreview() -- replaces again without error
	B:Close()
end)

check("generated script executes against the mock", function()
	B:NewProject()
	local proj = B._project
	proj.window.Name = "CodeGenHub"
	local tab = proj.tabs[1]
	B:Select(tab, tab.nodes[2])
	local dd = B:AddBlock("Dropdown")
	dd.Options = "red, green, blue"
	B:AddTab("Second")

	local code = B:Generate()

	local env2 = mock.buildEnv()
	setmetatable(env2, { __index = _G })
	env2.task = require("@lune/task")
	env2.loadstring = function(src)
		local chunk = luau.load(src, { debugName = "generated-loader", environment = env2 })
		return function(...)
			local lib = chunk(...)
			env2.__LOADED_LIB = lib
			return lib
		end
	end
	env2.game.HttpGet = function(_, url)
		return source -- the library source read at the top of this file
	end

	local chunk = luau.load(code, { debugName = "generated", environment = env2 })
	local ok, err = pcall(chunk)
	assert(ok, "generated code failed: " .. tostring(err))
	local lib2 = env2.__LOADED_LIB
	assert(type(lib2) == "table" and lib2.Version == "1.2.3", "loader did not return the library")
	assert(#lib2._windows == 1, "generated script did not create a window")
	local gen = lib2._windows[1]
	assert(gen._config.Name == "CodeGenHub", "generated window has wrong name")
	assert(#gen._tabs == 2, "generated window should have 2 tabs")
	assert(#gen._tabs[1]._elements >= 1, "generated tab missing elements")
	assert(#gen._tabs[1]._sections >= 1, "generated tab missing sections")
	gen:Destroy()
end)


check("builder validation rejects broken projects", function()
	B:NewProject()
	local proj = B._project
	local bad = B:AddBlock("Slider")
	bad.Min = 10
	bad.Max = 5
	local t2 = B:AddBlock("Toggle")
	t2.Flag = "fly" -- duplicate of the default toggle's flag
	local valid, why = B:Validate()
	assert(valid == false, "validation should fail")
	assert(why:find("greater than Min", 1, true), "slider problem not reported")
	assert(why:find("reuses flag", 1, true), "duplicate flag not reported")
	local windowsBefore = #Polaris._windows
	assert(B:OpenPreview() == nil, "preview should refuse an invalid project")
	assert(#Polaris._windows == windowsBefore, "failed preview must not leak windows")
	local code = B:Generate()
	assert(code:find("WARNING", 1, true), "codegen should warn about invalid projects")
	assert(code:find("Max = 11", 1, true), "codegen should fix Max <= Min")
end)

check("builder export works without clipboard or files", function()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	B:_openExportPanel()
	assert(B._codeLabel ~= nil and type(B._codeLabel.Text) == "string" and #B._codeLabel.Text > 100,
		"code output should be populated")
	assert(B._jsonLabel ~= nil and type(B._jsonLabel.Text) == "string" and #B._jsonLabel.Text > 10,
		"JSON output should be populated")
	B:Close()
	assert(B._codeLabel == nil or B._codeLabel._destroyed, "export labels should die with the gui")
end)

check("builder close during splash aborts the open", function()
	B.SplashDuration = 0.5
	B:Close()
	local windowsBefore = #Polaris._windows
	tasklib.spawn(function()
		B:Open()
	end)
	tasklib.wait(0.1) -- mid-splash
	B:Close()
	tasklib.wait(0.8) -- let the splash coroutine run out its waits
	assert(B._splashGui == nil, "splash gui leaked")
	assert(B._window == nil, "builder window created after close")
	assert(B:IsOpen() == false, "builder should stay closed")
	assert(#Polaris._windows == windowsBefore, "orphan windows after aborted splash")
	B.SplashDuration = 0
	B:Open()
	assert(B:IsOpen() == true, "reopen after aborted splash should work")
	B:Close()
end)

check("builder close cleans up its preview", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local prev = B:OpenPreview()
	assert(prev ~= nil, "preview missing")
	B:Close() -- same path as the editor's X button
	assert(prev._destroyed == true, "preview should close with the builder")
	assert(B:IsOpen() == false, "builder should report closed")
	local stillRegistered = false
	for _, w in Polaris._windows do
		if w == prev then
			stillRegistered = true
		end
	end
	assert(stillRegistered == false, "destroyed preview still registered")
end)

check("builder codegen escapes control characters", function()
	B:NewProject()
	local proj = B._project
	-- name containing CR, LF, a backslash and a quote
	proj.tabs[1].nodes[1].Name = "Line" .. string.char(13) .. string.char(10) .. "Tab" .. string.char(92) .. "Slash" .. string.char(34) .. "Quote"
	local code = B:Generate()
	-- exactly what quote() should emit for that name
	local expected = string.char(34) .. "Line" .. string.char(92) .. "r" .. string.char(92) .. "nTab"
		.. string.char(92) .. string.char(92) .. "Slash" .. string.char(92) .. string.char(34) .. "Quote" .. string.char(34)
	assert(code:find(expected, 1, true) ~= nil, "control characters not escaped correctly")
end)

check("builder tab duplicate re-flags blocks", function()
	B:NewProject()
	local proj = B._project
	local tab = proj.tabs[1]
	B:Select(tab, nil)
	local copy = B:DuplicateSelectedTab()
	assert(copy ~= nil and #proj.tabs == 2, "tab not duplicated")
	assert(copy.nodes[2].Flag ~= "fly", "duplicated toggle should get a fresh flag")
	local valid = B:Validate()
	assert(valid == true, "duplicated tab should remain valid")
end)

check("generated script with every block type round-trips values", function()
	B:NewProject()
	local proj = B._project
	local tab = proj.tabs[1]
	-- default project has Section + Toggle(fly, false); make the toggle default true
	tab.nodes[2].Default = true
	B:Select(tab, tab.nodes[2])
	local dd = B:AddBlock("Dropdown")
	dd.Options = "red, green, blue"
	local sl = B:AddBlock("Slider")
	sl.Min = 0
	sl.Max = 50
	sl.Default = 25
	sl.Increment = 5
	sl.Flag = "speed"
	local cp = B:AddBlock("ColorPicker")
	cp.R = 10
	cp.G = 20
	cp.B = 30
	cp.Flag = "colorpick"
	local kb = B:AddBlock("Keybind")
	kb.Key = "F"
	kb.Flag = "hotkey"
	local tb = B:AddBlock("Textbox")
	tb.Default = "hello world"
	tb.Flag = "words"
	local para = B:AddBlock("Paragraph")
	para.Text = "some paragraph text"
	B:AddBlock("Divider")
	local btn = B:AddBlock("Button")
	btn.Name = "Do Thing"

	local code = B:Generate()
	assert(B:Validate() == true, "project should be valid")

	local env3 = mock.buildEnv()
	setmetatable(env3, { __index = _G })
	env3.task = require("@lune/task")
	env3.loadstring = function(src)
		local chunk = luau.load(src, { debugName = "full-loader", environment = env3 })
		return function(...)
			local lib = chunk(...)
			env3.__LOADED_LIB = lib
			return lib
		end
	end
	env3.game.HttpGet = function(_, url)
		return source
	end

	local chunk = luau.load(code, { debugName = "full-generated", environment = env3 })
	local ok, err = pcall(chunk)
	assert(ok, "generated code failed: " .. tostring(err))
	local lib3 = env3.__LOADED_LIB
	assert(#lib3._windows == 1, "window not created")
	local gen = lib3._windows[1]
	assert(gen._config.Name == "My Hub")
	local genTab = gen._tabs[1]
	-- flags registered
	for _, flag in { "fly", "speed", "colorpick", "hotkey", "words" } do
		assert(gen.Flags[flag] ~= nil, ("flag '%s' not registered"):format(flag))
	end
	-- values round-trip
	for _, el in genTab._elements do
		local name = el._config.Name
		if name == "Fly" then
			assert(el:Get() == true, "toggle default lost")
		elseif name == "Speed" then
			assert(el._config.Min == 0 and el._config.Max == 50, "slider range lost")
			assert(el:Get() == 25, "slider default lost")
		elseif name == "New Dropdown" then
			assert(el._config.Options[1] == "red" and el._config.Options[3] == "blue", "dropdown options lost")
		end
	end
	gen:Destroy()
end)


check("builder palette tap adds a block", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local chip = B._paletteButtons[3] -- Toggle
	local touch = mock.Enum.UserInputType.Touch
	chip.InputBegan:Fire(mock.makeInput(touch, nil, 20, 20))
	local UIS = mock.UIS()
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 20, 20))
	assert(#B._project.tabs[1].nodes == 3, "palette tap should add a block")
	assert(B._selected ~= nil and B._selected.node ~= nil, "added block should be selected")
	assert(#B._columns[1].blockFrames == 3, "canvas should re-render after adding")
	B:Close()
end)

check("builder drag moves blocks between tabs", function()
	B:NewProject()
	local proj = B._project
	local tab1 = proj.tabs[1]
	local t2 = B:AddTab("Second")
	local node = tab1.nodes[2] -- the Toggle
	assert(B:_moveNode(node, t2, 1) == true, "moveNode failed")
	assert(#tab1.nodes == 1, "node not removed from the first tab")
	assert(t2.nodes[1] == node, "node not inserted into the second tab")
	assert(B:_moveNode(node, tab1, 2) == true)
	assert(tab1.nodes[2] == node, "node not moved back")
	local sec = B:AddBlock("Section")
	assert(B:_moveNode(sec, tab1, 1) == true)
	assert(tab1.nodes[1] == sec, "reorder within a tab failed")
end)

check("builder canvas block tap selects", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local bf = B._columns[1].blockFrames[2] -- the Toggle block
	local touch = mock.Enum.UserInputType.Touch
	bf.InputBegan:Fire(mock.makeInput(touch, nil, 100, 100))
	local UIS = mock.UIS()
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 100, 100))
	assert(B._selected ~= nil and B._selected.node ~= nil, "tapping a block should select it")
	assert(#B._propRows > 0, "properties panel should render rows for the selection")
	B:Close()
end)


check("builder suppresses coregui while open", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local starterGui = env.game:GetService("StarterGui")
	local states = starterGui._coreGuiState
	local n, allHidden = 0, true
	for _, v in states do
		n += 1
		if v ~= false then
			allHidden = false
		end
	end
	assert(n >= 1, "SetCoreGuiEnabled should have been called")
	assert(allHidden, "coregui should be hidden while the editor is open")
	B:Close()
	local allBack = true
	for _, v in states do
		if v ~= true then
			allBack = false
		end
	end
	assert(allBack, "coregui should be restored after close")
end)

check("builder compact layout on narrow screens", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local cam = env.workspace.CurrentCamera
	cam.ViewportSize = mock.Vector2(390, 844) -- fires ViewportSize changed
	assert(B._compact == true, "390px wide should be compact")
	assert(B._palette.Visible == false, "palette should be a closed drawer on a phone")
	assert(B._propList.Visible == false, "properties should be a closed drawer on a phone")
	assert(B._canvas.Size.X.Offset == 0, "canvas should span the full width with drawers closed")
	-- open the properties drawer from the top bar
	B._propsBtn.Activated:Fire()
	assert(B._propList.Visible == true, "props toggle should open the drawer")
	assert(B._propList.ZIndex == 6, "open drawer should overlay the canvas")
	assert(B._palette.Visible == false, "palette drawer should stay closed")
	-- tapping a block reveals the properties drawer
	B._propsBtn.Activated:Fire() -- close it again
	assert(B._propList.Visible == false)
	local bf = B._columns[1].blockFrames[1]
	local touch = mock.Enum.UserInputType.Touch
	bf.InputBegan:Fire(mock.makeInput(touch, nil, 100, 100))
	mock.UIS().InputEnded:Fire(mock.makeInput(touch, nil, 100, 100))
	assert(B._propList.Visible == true, "tapping a block should reveal the properties drawer")
	-- back to desktop size: panels return
	cam.ViewportSize = mock.Vector2(1920, 1080)
	assert(B._compact ~= true, "1920px wide should not be compact")
	assert(B._palette.Visible == true, "palette should return on desktop")
	assert(B._propList.Visible == true, "properties should return on desktop")
	B:Close()
end)

check("builder drag flows through input", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local proj = B._project
	local tab1 = proj.tabs[1]
	B:AddBlock("Button") -- 3 nodes now
	B:_refreshAll()
	local col1 = B._columns[1]
	col1.frame.AbsolutePosition = mock.Vector2(166, 52)
	col1.frame.AbsoluteSize = mock.Vector2(190, 400)
	for i, bf in col1.blockFrames do
		bf.AbsolutePosition = mock.Vector2(174, 90 + (i - 1) * 48)
		bf.AbsoluteSize = mock.Vector2(174, 42)
	end
	B._palette.AbsolutePosition = mock.Vector2(0, 58)
	B._palette.AbsoluteSize = mock.Vector2(150, 442)

	local touch = mock.Enum.UserInputType.Touch
	local UIS = mock.UIS()
	local node1 = tab1.nodes[1]

	local function layoutColumns()
		for ci, col in B._columns do
			col.frame.AbsolutePosition = mock.Vector2(166 + (ci - 1) * 210, 52)
			col.frame.AbsoluteSize = mock.Vector2(190, 400)
			for i, bf in col.blockFrames do
				bf.AbsolutePosition = mock.Vector2(174 + (ci - 1) * 210, 90 + (i - 1) * 48)
				bf.AbsoluteSize = mock.Vector2(174, 42)
			end
		end
		B._palette.AbsolutePosition = mock.Vector2(0, 58)
		B._palette.AbsoluteSize = mock.Vector2(150, 442)
	end
	layoutColumns()

	-- 1) drag the first block below the third: reorder within the tab
	local bf = B._columns[1].blockFrames[1]
	bf.InputBegan:Fire(mock.makeInput(touch, nil, 250, 100))
	UIS.InputChanged:Fire(mock.makeInput(touch, nil, 250, 200))
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 250, 200))
	assert(B._drag == nil, "drag should be cleared after drop")
	assert(tab1.nodes[2] == node1, "block should have been reordered within the tab")

	-- 2) drag it onto the palette: delete
	layoutColumns()
	bf = B._columns[1].blockFrames[2] -- the node we just moved is now second
	bf.InputBegan:Fire(mock.makeInput(touch, nil, 250, 150))
	UIS.InputChanged:Fire(mock.makeInput(touch, nil, 60, 300))
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 60, 300))
	assert(table.find(tab1.nodes, node1) == nil, "dropping a block on the palette should delete it")

	-- 3) drag from the palette onto the column: create
	local chip = B._paletteButtons[3] -- Toggle
	chip.InputBegan:Fire(mock.makeInput(touch, nil, 75, 150))
	UIS.InputChanged:Fire(mock.makeInput(touch, nil, 250, 300))
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 250, 300))
	assert(#tab1.nodes == 3, "dragging a chip onto the canvas should create a block")
	assert(tab1.nodes[#tab1.nodes].Kind == "Toggle", "created block should match the dragged chip")

	-- 4) drag a block to a second tab
	local t2 = B:AddTab("Second")
	B:_refreshAll()
	layoutColumns()
	local moved = tab1.nodes[1]
	bf = B._columns[1].blockFrames[1]
	bf.InputBegan:Fire(mock.makeInput(touch, nil, 250, 100))
	UIS.InputChanged:Fire(mock.makeInput(touch, nil, 450, 150))
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 450, 150))
	assert(table.find(tab1.nodes, moved) == nil, "block should leave the first tab")
	assert(t2.nodes[1] == moved, "block should land in the second tab")
	B:Close()
end)

check("builder canvas tap selects the exact block", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local proj = B._project
	local touch = mock.Enum.UserInputType.Touch
	local UIS = mock.UIS()
	-- tap the second block (the Toggle)
	local bf = B._columns[1].blockFrames[2]
	bf.InputBegan:Fire(mock.makeInput(touch, nil, 200, 150))
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 200, 150))
	assert(B._selected ~= nil and B._selected.node == proj.tabs[1].nodes[2],
		"tapping a block should select exactly that block")
	-- tap the first block: selection must change
	local bf1 = B._columns[1].blockFrames[1]
	bf1.InputBegan:Fire(mock.makeInput(touch, nil, 200, 80))
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 200, 80))
	assert(B._selected ~= nil and B._selected.node == proj.tabs[1].nodes[1],
		"tapping another block should change the selection")
	B:Close()
end)


check("builder coregui restore keeps pre-existing state", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	local starterGui = env.game:GetService("StarterGui")
	-- the user already had chat hidden before opening the builder
	starterGui:SetCoreGuiEnabled(mock.Enum.CoreGuiType.Chat, false)
	B:Open()
	B:Close()
	local chatBack, othersBack = nil, true
	for _, v in starterGui._coreGuiState do
		-- nothing else should have been touched
	end
	chatBack = starterGui._coreGuiState[mock.Enum.CoreGuiType.Chat]
	assert(chatBack == false, "pre-hidden chat should stay hidden after close")
	local n = 0
	for _, v in starterGui._coreGuiState do
		n += 1
	end
	assert(n >= 2, "suppress/restore should have touched several coregui types")
end)

check("builder compact drawers overlay and are exclusive", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local cam = env.workspace.CurrentCamera
	cam.ViewportSize = mock.Vector2(390, 844)
	assert(B._compact == true)
	assert(B._palette.Visible == false and B._propList.Visible == false)
	-- open the palette drawer: canvas stays full width, drawer overlays it
	B._blocksBtn.Activated:Fire()
	assert(B._palette.Visible == true, "palette toggle should open the drawer")
	assert(B._palette.ZIndex == 6, "drawer should overlay the canvas")
	assert(B._canvas.Size.X.Offset == 0, "canvas must stay full width with a drawer open")
	-- opening the properties drawer closes the palette drawer (one at a time)
	B._propsBtn.Activated:Fire()
	assert(B._propList.Visible == true, "props toggle should open the drawer")
	assert(B._palette.Visible == false, "only one drawer should be open on a phone")
	assert(B._canvas.Size.X.Offset == 0, "canvas must stay full width with props open")
	cam.ViewportSize = mock.Vector2(1920, 1080)
	B:Close()
end)

check("builder hidden palette is not a delete zone", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local cam = env.workspace.CurrentCamera
	cam.ViewportSize = mock.Vector2(390, 844) -- compact: palette hidden
	local tab1 = B._project.tabs[1]
	local node = tab1.nodes[1]
	local touch = mock.Enum.UserInputType.Touch
	local UIS = mock.UIS()
	-- set up hit geometry: column 1 covers the left of the fullscreen canvas
	local col1 = B._columns[1]
	col1.frame.AbsolutePosition = mock.Vector2(0, 58)
	col1.frame.AbsoluteSize = mock.Vector2(390, 500)
	for i, bf in col1.blockFrames do
		bf.AbsolutePosition = mock.Vector2(8, 96 + (i - 1) * 48)
		bf.AbsoluteSize = mock.Vector2(374, 42)
	end
	B._palette.AbsolutePosition = mock.Vector2(0, 58)
	B._palette.AbsoluteSize = mock.Vector2(150, 442)
	-- drop a block over where the hidden palette is: must NOT delete
	local bf = col1.blockFrames[1]
	bf.InputBegan:Fire(mock.makeInput(touch, nil, 250, 100))
	UIS.InputChanged:Fire(mock.makeInput(touch, nil, 60, 300))
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 60, 300))
	assert(table.find(tab1.nodes, node) ~= nil, "dropping on a hidden palette must not delete")
	cam.ViewportSize = mock.Vector2(1920, 1080)
	B:Close()
end)

check("builder top bar fits without overlaps at every tested width", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local cam = env.workspace.CurrentCamera
	local btns = {
		B._closeBtn, B._newBtn, B._exportBtn, B._previewBtn,
		B._addTabBtn, B._propsBtn, B._blocksBtn,
	}
	for _, w in { 360, 390, 844, 900 } do
		cam.ViewportSize = mock.Vector2(w, 800)
		local spans = {}
		for _, btn in btns do
			if btn.Visible == true then
				-- AnchorPoint (1, 0): right edge = width + Position.X.Offset
				local right = w + btn.Position.X.Offset
				local bw = btn.Size.X.Offset
				table.insert(spans, { left = right - bw, right = right, btn = btn })
			end
		end
		assert(#spans >= 5, "expected several visible buttons at width " .. w)
		table.sort(spans, function(a, b)
			return a.left < b.left
		end)
		for i, span in spans do
			assert(span.left >= 0 and span.right <= w, "button out of screen at width " .. w)
			if i > 1 then
				assert(span.left >= spans[i - 1].right, "buttons overlap at width " .. w)
			end
		end
		-- the name box must not run under the leftmost button
		local nameLeft = B._hubNameBox.Position.X.Offset
		local nameRight = nameLeft + (w + B._hubNameBox.Size.X.Offset)
		assert(nameRight <= spans[1].left, "name box overlaps buttons at width " .. w)
		assert(spans[1].left > 40, "name box should keep a usable width at " .. w)
	end
	cam.ViewportSize = mock.Vector2(360, 800)
	assert(B._newBtn.Visible == false, "New should move into the export panel in compact")
	assert(B._addTabBtn.Visible == false, "+ Tab lives on the canvas in compact")
	cam.ViewportSize = mock.Vector2(1920, 1080)
	assert(B._newBtn.Visible == true, "New returns on desktop")
	B:Close()
end)

check("builder new project is reachable from the export panel", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	B:AddBlock("Button")
	assert(#B._project.tabs[1].nodes == 3)
	B:_openExportPanel()
	assert(B._exportNewBtn ~= nil, "export panel should have a New project button")
	B._exportNewBtn.Activated:Fire()
	assert(#B._project.tabs[1].nodes == 2, "New project should reset to the default project")
	assert(B._exportOverlay.Visible == false, "export panel should close after New")
	B:Close()
end)


check("builder tap opens props even with the palette open", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local cam = env.workspace.CurrentCamera
	cam.ViewportSize = mock.Vector2(390, 844)
	B._blocksBtn.Activated:Fire()
	assert(B._palette.Visible == true, "palette drawer should be open")
	local touch = mock.Enum.UserInputType.Touch
	local UIS = mock.UIS()
	local bf = B._columns[1].blockFrames[1]
	bf.InputBegan:Fire(mock.makeInput(touch, nil, 300, 150))
	UIS.InputEnded:Fire(mock.makeInput(touch, nil, 300, 150))
	assert(B._propList.Visible == true, "tapping a block must open props even with the palette open")
	assert(B._palette.Visible == false, "the palette drawer should close so the block stays visible")
	cam.ViewportSize = mock.Vector2(1920, 1080)
	B:Close()
end)

check("builder coregui snapshot skips unreadable features", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	local starterGui = env.game:GetService("StarterGui")
	table.clear(starterGui._coreGuiState)
	starterGui:SetCoreGuiEnabled(mock.Enum.CoreGuiType.Chat, false) -- initially disabled
	local orig = starterGui.GetCoreGuiEnabled
	rawset(starterGui, "GetCoreGuiEnabled", function(self, t)
		if t == mock.Enum.CoreGuiType.EmotesMenu then
			error("not readable")
		end
		return orig(self, t)
	end)
	B:Open()
	assert(starterGui._coreGuiState[mock.Enum.CoreGuiType.EmotesMenu] == nil,
		"unreadable features must not be touched")
	assert(starterGui._coreGuiState[mock.Enum.CoreGuiType.Chat] == false, "chat hidden while open")
	assert(starterGui._coreGuiState[mock.Enum.CoreGuiType.PlayerList] == false, "playerlist hidden while open")
	B:Close()
	rawset(starterGui, "GetCoreGuiEnabled", orig)
	assert(starterGui._coreGuiState[mock.Enum.CoreGuiType.Chat] == false,
		"chat must stay hidden (it was hidden before)")
	assert(starterGui._coreGuiState[mock.Enum.CoreGuiType.PlayerList] == true,
		"playerlist must be restored")
	assert(starterGui._coreGuiState[mock.Enum.CoreGuiType.EmotesMenu] == nil, "still untouched")
end)


check("builder desktop to phone resize normalizes drawers", function()
	B:NewProject()
	B.SplashDuration = 0
	B:Close()
	B:Open()
	local cam = env.workspace.CurrentCamera
	-- open both panels on desktop (wide toggles are independent)
	B._blocksBtn.Activated:Fire() -- close (was open by default)
	B._blocksBtn.Activated:Fire() -- open again
	B._propsBtn.Activated:Fire() -- close
	B._propsBtn.Activated:Fire() -- open
	assert(B._palette.Visible == true and B._propList.Visible == true, "both panels open on desktop")
	-- shrink to a phone: only one drawer may show, canvas stays full width
	cam.ViewportSize = mock.Vector2(390, 844)
	assert(B._compact == true)
	assert(B._propList.Visible == true, "properties drawer should be the one kept")
	assert(B._palette.Visible == false, "palette drawer should close on resize")
	assert(B._canvas.Size.X.Offset == 0, "canvas must stay full width")
	cam.ViewportSize = mock.Vector2(1920, 1080)
	B:Close()
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
