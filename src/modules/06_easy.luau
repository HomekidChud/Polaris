-- easy: the "anyone can use it" layer.
--   Polaris.Hub{...}            describe a UI with plain tables, get a working window
--   Polaris.Templates.*         ready-made UIs (ScriptLibrary, DeepResearch, RobloxHub, Everything)
--   Polaris.Make("words")       say what you want, get a matching UI
--   Polaris.FromProject(table)  open a project exported from the Builder

local Create, Window = I.Create, I.Window
local Kit, Util = Polaris.Kit, Polaris.Util

local Easy = {}
Polaris.Easy = Easy
Polaris.Templates = {}
local Templates = Polaris.Templates

----------------------------------------------------------------
-- helpers
----------------------------------------------------------------

local uid = 0
local function uniqueName(base)
	uid += 1
	return uid == 1 and base or (base .. " " .. uid)
end

-- iterate a "name -> value" dictionary (sorted) or an ordered list of { name, value }
local function eachNamed(group)
	local list = {}
	if type(group) ~= "table" then
		return list
	end
	if #group > 0 then
		for _, pair in ipairs(group) do
			if type(pair) == "table" then
				table.insert(list, { pair.Name or pair[1], pair.Value or pair[2] or pair })
			end
		end
	else
		local keys = {}
		for k in pairs(group) do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			table.insert(list, { k, group[k] })
		end
	end
	return list
end

local function asCfg(value, key)
	if type(value) == "table" then
		return value
	elseif type(value) == "function" then
		return { Callback = value }
	elseif value ~= nil then
		return { [key or "Default"] = value }
	end
	return {}
end

-- Convert a friendly group ({ Buttons=, Toggles=, Sliders=, Dropdowns=, Inputs=, Text= }) into element configs.
local function groupItems(group)
	local items = {}
	local function add(kind, name, cfg)
		cfg = table.clone(cfg)
		cfg.Type = kind
		cfg.Name = name
		table.insert(items, cfg)
	end
	for _, t in ipairs(type(group.Text) == "table" and group.Text or (group.Text and { group.Text } or {})) do
		table.insert(items, { Type = "Label", Text = t })
	end
	for _, p in ipairs(eachNamed(group.Buttons)) do
		add("Button", p[1], asCfg(p[2]))
	end
	for _, p in ipairs(eachNamed(group.Toggles)) do
		add("Toggle", p[1], asCfg(p[2], "Default"))
	end
	for _, p in ipairs(eachNamed(group.Sliders)) do
		local cfg = asCfg(p[2])
		cfg.Min, cfg.Max = cfg.Min or 0, cfg.Max or 100
		cfg.Default = cfg.Default or cfg.Min
		add("Slider", p[1], cfg)
	end
	for _, p in ipairs(eachNamed(group.Dropdowns)) do
		add("Dropdown", p[1], asCfg(p[2], "Options"))
	end
	for _, p in ipairs(eachNamed(group.Inputs)) do
		add("Textbox", p[1], asCfg(p[2], "Default"))
	end
	for _, p in ipairs(eachNamed(group.Keybinds)) do
		add("Keybind", p[1], asCfg(p[2], "Default"))
	end
	if type(group.Items) == "table" then
		for _, it in ipairs(group.Items) do
			table.insert(items, it)
		end
	end
	return items
end
Easy.groupItems = groupItems

local function keyCodeOf(v)
	if type(v) == "string" then
		return Enum.KeyCode[v]
	end
	return v
end

local function addAll(tab, items)
	for _, it in ipairs(items) do
		local cfg = it
		if it.Type == "Keybind" and type(it.Default) == "string" then
			cfg = table.clone(it)
			cfg.Default = keyCodeOf(it.Default)
		end
		tab:Add(it.Type or it.Kind, cfg)
	end
end
Easy.addAll = addAll

-- Floating round button that shows/hides a window (phones and tablets have no keyboard toggle key).
function Easy.floatingToggle(window, opts)
	opts = opts or {}
	local uis = I.services.UserInputService
	local gui = Create("ScreenGui", { Name = "PolarisToggle", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = I.getGuiParent() })
	local btn = Kit.button(gui, opts.Text or "P", {
		Color = "Accent", Size = UDim2.new(0, 46, 0, 46), Position = opts.Position or UDim2.new(0, 14, 0.5, -23), TextSize = 20, Radius = 23,
	})
	btn.Active = true
	local dragging, startPos, startInput, moved = false, nil, nil, false
	btn.InputBegan:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging, moved = true, false
			startPos, startInput = btn.Position, input.Position
		end
	end)
	uis.InputChanged:Connect(function(input)
		if dragging and startInput and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - startInput
			if math.abs(delta.X) + math.abs(delta.Y) > 6 then
				moved = true
			end
			if moved then
				btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
			end
		end
	end)
	uis.InputEnded:Connect(function(input)
		local t = input.UserInputType
		if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
	btn.Activated:Connect(function()
		if not moved then
			window:SetVisible(not window:GetVisible())
		end
	end)
	window._extras = window._extras or {}
	table.insert(window._extras, gui)
	return gui
end

local origDestroy = Window.Destroy
function Window:Destroy()
	if self._extras then
		for _, g in ipairs(self._extras) do
			pcall(function()
				g:Destroy()
			end)
		end
		self._extras = nil
	end
	return origDestroy(self)
end

-- Window with friendly defaults (screen-aware size, key to hide it, floating button on touch devices)
function Easy.Window(opts)
	opts = opts or {}
	local size = opts.Size
	if type(size) == "table" then
		size = Vector2.new(size[1] or size.X or 640, size[2] or size.Y or 440)
	end
	size = Kit.fitSize(size and size.X or 660, size and size.Y or 450)
	local name = opts.Name or "Polaris"
	local theme = opts.Theme
	if theme and not Polaris.Themes[theme] then
		warn("[Polaris] Unknown theme '" .. tostring(theme) .. "', using Default. Themes: " .. table.concat(Polaris:GetThemeNames(), ", "))
		theme = nil
	end
	local window = Polaris:CreateWindow({
		Name = name,
		Theme = theme or "Default",
		Size = size,
		ToggleKey = opts.ToggleKey == nil and Enum.KeyCode.RightShift or keyCodeOf(opts.ToggleKey),
		ConfigFolder = opts.ConfigFolder or I.slugify(name),
		SaveConfig = opts.SaveConfig == true,
		Position = opts.Position,
	})
	if opts.FloatingButton == true or (opts.FloatingButton == nil and Kit.isTouch()) then
		Easy.floatingToggle(window)
	end
	return window
end

----------------------------------------------------------------
-- Polaris.Hub / Polaris:Build  - plain tables in, working window out
----------------------------------------------------------------

-- spec: Name, Theme, Size, ToggleKey, Tabs, Buttons/Toggles/Sliders/... (go to a "Main" tab),
--       Scripts / Library (adds a Scripts tab), Research (adds a Research tab), Settings (default true)
function Easy.Hub(spec)
	spec = spec or {}
	local window = spec.Window or Easy.Window(spec)
	local made = { Window = window, Tabs = {} }

	local main = groupItems(spec)
	local tabSpecs = {}
	if #main > 0 then
		table.insert(tabSpecs, { Name = spec.MainTab or "Main", Group = spec })
	end
	for _, p in ipairs(eachNamed(spec.Tabs)) do
		local group = p[2]
		table.insert(tabSpecs, { Name = (type(group) == "table" and group.Name) or p[1], Group = group })
	end
	for _, ts in ipairs(tabSpecs) do
		local tab = window:CreateTab({ Name = ts.Name })
		addAll(tab, groupItems(ts.Group))
		made.Tabs[ts.Name] = tab
	end

	local libSource = spec.Library or spec.Scripts
	if libSource then
		local tab = window:CreateTab({ Name = spec.ScriptsTab or "Scripts" })
		local cfg = { Height = "Fill" }
		if getmetatable(libSource) == Polaris.Library then
			cfg.Library = libSource
		else
			cfg.Scripts = libSource
		end
		cfg.Manifest = spec.Manifest
		cfg.TrustedHosts = spec.TrustedHosts
		made.Library = tab:CreateScriptLibrary(cfg).Library
		made.Tabs.Scripts = tab
	elseif spec.Manifest then
		local tab = window:CreateTab({ Name = "Scripts" })
		made.Library = tab:CreateScriptLibrary({ Manifest = spec.Manifest, Height = "Fill", TrustedHosts = spec.TrustedHosts }).Library
		made.Tabs.Scripts = tab
	end

	if spec.Research then
		local tab = window:CreateTab({ Name = spec.ResearchTab or "Research" })
		local rc = type(spec.Research) == "table" and table.clone(spec.Research) or { Provider = spec.Research == true and "Demo" or spec.Research }
		rc.Height = rc.Height or "Fill"
		made.Research = tab:CreateResearch(rc)
		made.Tabs.Research = tab
	end

	if spec.Settings ~= false then
		made.Tabs.Settings = window:AddSettingsTab()
	end
	if not window._welcomed and spec.Welcome ~= false then
		window._welcomed = true
		Polaris:Notify({ Title = spec.Name or "Polaris", Content = "Ready. Press " .. (window._toggleKey and window._toggleKey.Name or "the button") .. " to hide or show.", Type = "success", Duration = 4 })
	end
	return window, made
end
Polaris.Hub = Easy.Hub

function Polaris:Build(spec)
	return Easy.Hub(spec)
end

-- Quick one-liner:  Polaris.Quick("My UI", { "Say hi", function() print("hi") end }, ...)
function Polaris.Quick(title, ...)
	local buttons = {}
	for _, pair in ipairs({ ... }) do
		table.insert(buttons, { pair[1], pair[2] })
	end
	return Easy.Hub({ Name = title, Buttons = buttons })
end

----------------------------------------------------------------
-- Builder projects -> live windows
----------------------------------------------------------------

local function nodeToItem(node, handlers)
	local k = node.Kind
	local h = handlers and handlers[node.Name]
	local flag = (node.Flag and node.Flag ~= "") and node.Flag or nil
	if k == "Section" then
		return { Type = "Section", Name = node.Name }
	elseif k == "Button" then
		return { Type = "Button", Name = node.Name, Callback = h }
	elseif k == "Toggle" then
		return { Type = "Toggle", Name = node.Name, Default = node.Default == true, Flag = flag, Callback = h }
	elseif k == "Slider" then
		return { Type = "Slider", Name = node.Name, Min = tonumber(node.Min) or 0, Max = tonumber(node.Max) or 100, Default = tonumber(node.Default) or 0, Increment = tonumber(node.Increment) or 1, ValueName = node.ValueName ~= "" and node.ValueName or nil, Flag = flag, Callback = h }
	elseif k == "Dropdown" then
		return { Type = "Dropdown", Name = node.Name, Options = I.splitOptions(node.Options), Multiple = node.Multiple == true, Flag = flag, Callback = h }
	elseif k == "ColorPicker" then
		return { Type = "ColorPicker", Name = node.Name, Default = Color3.fromRGB(tonumber(node.R) or 0, tonumber(node.G) or 0, tonumber(node.B) or 0), Flag = flag, Callback = h }
	elseif k == "Keybind" then
		return { Type = "Keybind", Name = node.Name, Default = Enum.KeyCode[node.Key or "RightControl"], Hold = node.Hold == true, Flag = flag, Callback = h }
	elseif k == "Textbox" then
		return { Type = "Textbox", Name = node.Name, Default = node.Default or "", TextDisappear = node.TextDisappear == true, Flag = flag, Callback = h }
	elseif k == "Paragraph" then
		return { Type = "Paragraph", Text = node.Text }
	elseif k == "Divider" then
		return { Type = "Divider" }
	end
	local K = I.Builder.Kinds[k]
	if K and K.item then
		return K.item(node, handlers)
	end
	return nil
end
Easy.nodeToItem = nodeToItem

-- project: the table from Builder:GetProject() or Builder:ExportJSON() text.
-- handlers: optional { ["Element name"] = function(...) end } to wire up callbacks.
function Polaris.FromProject(project, handlers)
	if type(project) == "string" then
		local data, err = Util.JSON.decode(project)
		assert(data, "[Polaris] FromProject: not valid JSON (" .. tostring(err) .. ")")
		project = data
	end
	assert(type(project) == "table" and type(project.window) == "table" and type(project.tabs) == "table", "[Polaris] FromProject: expected a Builder project with window and tabs")
	local w = project.window
	local window = Easy.Window({ Name = w.Name, Theme = w.Theme, ConfigFolder = w.ConfigFolder, SaveConfig = w.SaveConfig, ToggleKey = w.ToggleKey })
	for _, t in ipairs(project.tabs) do
		local tab = window:CreateTab({ Name = t.Name, Icon = (t.Icon and t.Icon ~= "") and t.Icon or nil })
		for _, node in ipairs(t.nodes or {}) do
			local item = nodeToItem(node, handlers)
			if item then
				tab:Add(item.Type, item)
			end
		end
	end
	return window
end

----------------------------------------------------------------
-- Templates
----------------------------------------------------------------

local function defaultScripts()
	local list = {
		{
			Name = "Hello, Polaris", Description = "A tiny example script. It only shows a message.", Tags = { "example" }, Icon = "Hi",
			Run = function()
				Polaris:Notify({ Title = "Hello!", Content = "Your first script ran. Tap + Add to put in your own.", Type = "success" })
			end,
		},
		{
			Name = "Rainbow theme", Description = "Cycles the window through every theme once.", Tags = { "example", "fun" },
			Run = function()
				task.spawn(function()
					local current = Polaris.CurrentThemeName
					for _, name in ipairs(Polaris:GetThemeNames()) do
						Polaris:SetTheme(name)
						task.wait(0.7)
					end
					Polaris:SetTheme(current or "Default")
				end)
			end,
		},
	}
	if Polaris.HubScripts then
		for _, s in ipairs(Polaris.HubScripts()) do
			table.insert(list, s)
		end
	end
	return list
end
Easy.defaultScripts = defaultScripts

-- A window containing just the script library.
function Templates.ScriptLibrary(opts)
	opts = opts or {}
	local window = Easy.Window({ Name = opts.Name or "Script Library", Theme = opts.Theme, Size = opts.Size or { 640, 470 }, ConfigFolder = opts.ConfigFolder, ToggleKey = opts.ToggleKey, FloatingButton = opts.FloatingButton })
	local tab = window:CreateTab({ Name = "Library" })
	local cfg = {
		Height = "Fill", Manifest = opts.Manifest, TrustedHosts = opts.TrustedHosts, Confirm = opts.Confirm,
		Folder = opts.Folder or opts.Name or "Scripts", Name = opts.LibraryName or "scripts",
	}
	if getmetatable(opts.Library) == Polaris.Library then
		cfg.Library = opts.Library
	else
		cfg.Scripts = opts.Scripts or ((opts.Manifest == nil) and defaultScripts() or nil)
	end
	local el = tab:CreateScriptLibrary(cfg)
	if opts.Settings ~= false then
		window:AddSettingsTab()
	end
	return window, el.Library, el
end

-- A window containing the deep-research panel.
function Templates.DeepResearch(opts)
	opts = opts or {}
	local window = Easy.Window({ Name = opts.Name or "Deep Research", Theme = opts.Theme, Size = opts.Size or { 680, 500 }, ConfigFolder = opts.ConfigFolder, ToggleKey = opts.ToggleKey, FloatingButton = opts.FloatingButton })
	local tab = window:CreateTab({ Name = "Research" })
	local el = tab:CreateResearch({
		Height = "Fill", Provider = opts.Provider or "Demo", ApiKey = opts.ApiKey, Placeholder = opts.Placeholder,
		Depth = opts.Depth, Depths = opts.Depths, TextSize = opts.TextSize,
	})
	if opts.Question then
		el:Start(opts.Question)
	end
	if opts.Settings ~= false then
		window:AddSettingsTab()
	end
	return window, el.Session, el
end

-- A game-style hub: Home (live stats), Features (your buttons/toggles), Scripts, optional Research, Settings.
function Templates.RobloxHub(opts)
	opts = opts or {}
	local window = Easy.Window({ Name = opts.Name or "My Hub", Theme = opts.Theme, Size = opts.Size or { 680, 460 }, ConfigFolder = opts.ConfigFolder, ToggleKey = opts.ToggleKey, FloatingButton = opts.FloatingButton })
	local made = { Window = window, Tabs = {} }

	local home = window:CreateTab({ Name = "Home" })
	local title = home:CreateLabel({ Text = opts.Title or opts.Name or "My Hub", Size = 24, Bold = true })
	local lp = I.LocalPlayer
	home:CreateLabel({ Text = "Welcome, " .. tostring(lp and (lp.DisplayName or lp.Name) or "player") .. ".", Size = 15, Color = "SubText" })
	local gameLabel = home:CreateLabel({ Text = "Loading game info...", Size = 14, Color = "SubText" })
	task.spawn(function()
		local ok, info = pcall(function()
			return Util.svc("MarketplaceService"):GetProductInfo(game.PlaceId)
		end)
		if not gameLabel._destroyed then
			gameLabel:SetText(ok and info and info.Name and ("Game: " .. info.Name) or "Game: unknown (Studio or unpublished place)")
		end
	end)
	home:CreateStats({ Items = opts.Stats or { "FPS", "Ping", "Players", "Memory" } })
	if opts.About then
		home:CreateParagraph({ Text = opts.About })
	end
	home:CreateButton({ Name = "Create your own script hub (blocks)", Callback = function()
		Polaris.MakeHub()
	end })
	home:CreateParagraph({ Text = "Tip: press RightShift to hide or show this window." })
	made.Tabs.Home = home

	-- user features
	local groups = {}
	if #groupItems(opts) > 0 then
		table.insert(groups, { opts.FeaturesTab or "Features", opts })
	end
	for _, p in ipairs(eachNamed(opts.Tabs)) do
		table.insert(groups, { (type(p[2]) == "table" and p[2].Name) or p[1], p[2] })
	end
	for _, g in ipairs(groups) do
		local tab = window:CreateTab({ Name = g[1] })
		addAll(tab, groupItems(g[2]))
		made.Tabs[g[1]] = tab
	end

	local libSource = opts.Library or opts.Scripts or (opts.Manifest == nil and defaultScripts() or nil)
	local stab = window:CreateTab({ Name = "Scripts" })
	local cfg = { Height = "Fill", Manifest = opts.Manifest, TrustedHosts = opts.TrustedHosts, Folder = opts.Name or "Hub", Confirm = opts.Confirm }
	if getmetatable(libSource) == Polaris.Library then
		cfg.Library = libSource
	else
		cfg.Scripts = libSource
	end
	made.Library = stab:CreateScriptLibrary(cfg).Library
	made.Tabs.Scripts = stab

	if opts.Research then
		local rtab = window:CreateTab({ Name = "Research" })
		local rc = type(opts.Research) == "table" and table.clone(opts.Research) or { Provider = opts.Research == true and "Demo" or opts.Research }
		rc.Height = "Fill"
		made.Research = rtab:CreateResearch(rc)
		made.Tabs.Research = rtab
	end

	if opts.Tools ~= false then
		made.Tabs.Tools = Templates._toolsTab(window)
	end
	made.Tabs.Settings = window:AddSettingsTab({ About = opts.Credits })
	return window, made
end

-- Safe developer tools: field of view, time of day, live output log.
function Templates._toolsTab(window)
	local tab = window:CreateTab({ Name = "Tools" })
	tab:CreateSection({ Name = "Look" })
	tab:CreateSlider({
		Name = "Field of view", Min = 40, Max = 120, Default = 70, Increment = 1,
		Callback = function(v)
			pcall(function()
				workspace.CurrentCamera.FieldOfView = v
			end)
		end,
	})
	tab:CreateSlider({
		Name = "Time of day (local)", Min = 0, Max = 24, Default = 14, Increment = 0.5, ValueName = "h",
		Callback = function(v)
			pcall(function()
				Util.svc("Lighting").ClockTime = v
			end)
		end,
	})
	tab:CreateSection({ Name = "Output" })
	local console = tab:CreateConsole({ Name = "Game output", Height = 160, MaxLines = 150 })
	local ok, conn = pcall(function()
		return Util.svc("LogService").MessageOut:Connect(function(message, messageType)
			local kind = "info"
			if messageType == Enum.MessageType.MessageWarning then
				kind = "warn"
			elseif messageType == Enum.MessageType.MessageError then
				kind = "error"
			end
			console:Log(message, kind)
		end)
	end)
	if ok and conn then
		window:_track(conn)
	else
		console:Log("Output is not available in this place.", "dim")
	end
	return tab
end

-- Everything in one window.
function Templates.Everything(opts)
	opts = opts or {}
	local o = table.clone(opts)
	o.Name = o.Name or "Polaris"
	if o.Research == nil then
		o.Research = o.Provider or true
	end
	return Templates.RobloxHub(o)
end

function Templates.Blank(opts)
	opts = opts or {}
	local window = Easy.Window(opts)
	local tab = window:CreateTab({ Name = "Main" })
	tab:CreateHeading(opts.Name or "Polaris")
	tab:CreateParagraph({ Text = "An empty window. Add things with tab:CreateButton({ Name = \"Hi\", Callback = function() end })." })
	return window, tab
end

----------------------------------------------------------------
-- Polaris.Make("what you want")
----------------------------------------------------------------

local KEYWORDS = {
	{ "Builder", { "builder", "design", "drag", "editor", "make my own", "build my" } },
	{ "DeepResearch", { "research", "ask", "question", "answer", "search", "learn", "report", "sources", "study", "homework", "ai" } },
	{ "ScriptLibrary", { "library", "scripts", "script list", "collection", "loader", "list of" } },
	{ "RobloxHub", { "hub", "roblox", "game", "tools", "dashboard", "stats" } },
	{ "Everything", { "everything", "all", "full", "complete", "home", "any" } },
}

function Polaris.Classify(words)
	local text = " " .. tostring(words or ""):lower() .. " "
	for _, entry in ipairs(KEYWORDS) do
		for _, kw in ipairs(entry[2]) do
			if text:find("%f[%w]" .. kw:gsub("%s", "%%s") .. "%f[%W]") then
				return entry[1]
			end
		end
	end
	return "Everything"
end

function Polaris.Make(words, opts)
	local kind = Polaris.Classify(words)
	if kind == "Builder" then
		Polaris.Builder:Open()
		return Polaris.Builder, kind
	end
	local make = Templates[kind]
	local a, b, c = make(opts or {})
	return a, b, c, kind
end
