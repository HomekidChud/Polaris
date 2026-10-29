--[[
	Polaris UI Library v1.2.0
	--------------------------
	A modern, single-file UI library for Roblox Luau, plus a visual
	Polaris Builder: run it on its own and get an animated splash
	followed by a block editor that exports a ready-to-paste hub script.

	Highlights over Orion:
	  - No :Init() needed - everything works the moment you create it
	  - Every element has :Get(), :Set(value, silent?), :SetVisible(), :SetDisabled(), :Destroy()
	  - Live theme switching + fully custom themes
	  - Search bar to filter elements
	  - Multi-select dropdowns
	  - Resizable + minimizable windows, toggle keybind
	  - Config save/load + JSON export/import (gracefully falls back when no filesystem exists)
	  - Duplicate-flag detection, slider clamping, clear error messages
	  - Visual Builder (Polaris.Builder:Open()) with splash, live preview and code export
	  - Touch support and clean teardown (no leaked connections)

	Usage (executor):
		local Polaris = loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"))()
	Usage (Studio / ModuleScript):
		local Polaris = require(script.Parent.Polaris)

	MIT licensed. Do whatever you want with it.
]]

--!nonstrict

local Polaris = {}

----------------------------------------------------------------
-- Services & constants
----------------------------------------------------------------

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
	error("[Polaris] This library must run on the client (LocalPlayer is nil)", 0)
end

local PolarisVersion = "1.2.0"

-- Optional executor filesystem API (only used if present)
local FS = nil
do
	local ok = pcall(function()
		if type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function" and type(makefolder) == "function" then
			FS = { write = writefile, read = readfile, isfile = isfile, mkdir = makefolder }
		end
	end)
	if not ok then FS = nil end
end

----------------------------------------------------------------
-- Small utilities
----------------------------------------------------------------

local function Create(className: string, props: { [any]: any }?, children: { Instance }?): Instance
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				inst[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent ~= nil then
		inst.Parent = parent
	end
	return inst
end

local function round(n: number, inc: number): number
	if inc <= 0 then return n end
	return math.floor(n / inc + 0.5) * inc
end

local function clamp(n: number, min: number, max: number): number
	if n < min then return min end
	if n > max then return max end
	return n
end

local function formatNumber(n: number): string
	if math.abs(n % 1) < 1e-9 then
		return tostring(math.floor(n))
	end
	return string.format("%.2f", n):gsub("%.?0+$", "")
end

-- Safe callback invoker: user code errors can't break the UI
local function invokeCallback(callback: any, ...)
	if type(callback) ~= "function" then return end
	local ok, err = pcall(callback, ...)
	if not ok then
		warn("[Polaris] Callback error:", err)
	end
end

local function deepCopy(t: any): any
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in t do
		out[k] = deepCopy(v)
	end
	return out
end

local function safeTween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tween = TweenService:Create(
		inst,
		TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out),
		goal
	)
	tween:Play()
	return tween
end

----------------------------------------------------------------
-- Themes
----------------------------------------------------------------

Polaris.Themes = {
	Default = {
		Name = "Default",
		Background = Color3.fromRGB(24, 24, 28),
		Secondary = Color3.fromRGB(32, 32, 38),
		Primary = Color3.fromRGB(45, 45, 52),
		Accent = Color3.fromRGB(120, 130, 255),
		Stroke = Color3.fromRGB(55, 55, 64),
		Text = Color3.fromRGB(235, 235, 240),
		SubText = Color3.fromRGB(160, 160, 170),
		Success = Color3.fromRGB(90, 200, 130),
		Warning = Color3.fromRGB(240, 180, 90),
		Danger = Color3.fromRGB(235, 90, 100),
	},
	Midnight = {
		Name = "Midnight",
		Background = Color3.fromRGB(12, 14, 24),
		Secondary = Color3.fromRGB(18, 21, 34),
		Primary = Color3.fromRGB(26, 30, 48),
		Accent = Color3.fromRGB(80, 150, 255),
		Stroke = Color3.fromRGB(38, 44, 70),
		Text = Color3.fromRGB(225, 230, 245),
		SubText = Color3.fromRGB(140, 150, 180),
		Success = Color3.fromRGB(80, 190, 140),
		Warning = Color3.fromRGB(240, 190, 100),
		Danger = Color3.fromRGB(240, 100, 110),
	},
	Light = {
		Name = "Light",
		Background = Color3.fromRGB(242, 242, 246),
		Secondary = Color3.fromRGB(252, 252, 255),
		Primary = Color3.fromRGB(228, 228, 235),
		Accent = Color3.fromRGB(90, 100, 220),
		Stroke = Color3.fromRGB(200, 200, 210),
		Text = Color3.fromRGB(35, 35, 42),
		SubText = Color3.fromRGB(110, 110, 125),
		Success = Color3.fromRGB(50, 160, 100),
		Warning = Color3.fromRGB(190, 130, 30),
		Danger = Color3.fromRGB(200, 60, 70),
	},
}

local ThemeBindings: { { inst: Instance, prop: string, key: string } } = {}

local function themed(inst: Instance, prop: string, key: string)
	-- apply the current theme color right away, and re-apply on every theme switch
	local theme = Polaris.Themes[Polaris.CurrentThemeName or "Default"]
	if theme then
		pcall(function()
			inst[prop] = theme[key]
		end)
	end
	table.insert(ThemeBindings, { inst = inst, prop = prop, key = key })
	return inst
end

function Polaris:SetTheme(name: string)
	local theme = self.Themes[name]
	if not theme then
		error(("[Polaris] Unknown theme '%s' (available: %s)"):format(name, table.concat(self:GetThemeNames(), ", ")), 2)
	end
	self.CurrentThemeName = name
	for _, binding in ThemeBindings do
		local value = theme[binding.key]
		if value ~= nil then
			pcall(function()
				binding.inst[binding.prop] = value
			end)
		end
	end
	-- re-render state-dependent visuals (toggle accent, dropdown highlights, ...)
	for _, window in self._windows or {} do
		for _, tab in window._tabs do
			for _, el in tab._elements do
				if type(el._render) == "function" then
					pcall(function() el:_render(false) end)
				end
				if type(el._refreshOptions) == "function" then
					pcall(function() el:_refreshOptions() end)
				end
			end
		end
	end
end

function Polaris:GetThemeNames(): { string }
	local names = {}
	for name in self.Themes do
		table.insert(names, name)
	end
	table.sort(names)
	return names
end

function Polaris:AddTheme(name: string, theme: { [string]: Color3 })
	assert(type(name) == "string", "[Polaris] AddTheme: name must be a string")
	assert(type(theme) == "table", "[Polaris] AddTheme: theme must be a table")
	local base = self.Themes.Default
	local merged = { Name = name }
	for key, value in base do
		merged[key] = value
	end
	for key, value in theme do
		merged[key] = value
	end
	self.Themes[name] = merged
	return merged
end

----------------------------------------------------------------
-- GUI parenting (CoreGui when possible, PlayerGui fallback)
----------------------------------------------------------------

local function getGuiParent(): Instance
	-- CoreGui works from executors; regular scripts get a permission error, so probe it
	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and coreGui then
		local probeOk = pcall(function()
			local probe = Instance.new("ScreenGui")
			probe.Parent = coreGui
			probe:Destroy()
		end)
		if probeOk then
			return coreGui
		end
	end
	local playerGui = LocalPlayer:FindFirstChild("PlayerGui")
	if playerGui then
		return playerGui
	end
	error("[Polaris] No CoreGui or PlayerGui available", 0)
end

----------------------------------------------------------------
-- Element base class
----------------------------------------------------------------

local Element = {}
Element.__index = Element

function Element._new(window, tab, config, className)
	local self = setmetatable({}, Element)
	self._window = window
	self._tab = tab
	self._config = config
	self._className = className or "Element"
	self._value = nil
	self._visible = true
	self._disabled = false
	self._destroyed = false

	if config.Flag then
		if window.Flags[config.Flag] then
			error(("[Polaris] Duplicate flag '%s' - flags must be unique within a window"):format(config.Flag), 3)
		end
		window.Flags[config.Flag] = self
	end

	table.insert(tab._elements, self)
	return self
end

function Element:Get()
	return deepCopy(self._value)
end

function Element:GetFlag()
	return self._config.Flag
end

-- :Set(value, silent?) -> each element type implements _setValue
function Element:Set(value, silent: boolean?)
	if self._destroyed then
		warn("[Polaris] Set called on destroyed element")
		return
	end
	self:_setValue(value)
	if not silent and self._config.Callback then
		invokeCallback(self._config.Callback, self._value)
	end
end

function Element:SetVisible(visible: boolean)
	self._visible = visible
	if self._container then
		self._container.Visible = visible
	end
	self._tab:_updateCanvas()
end

function Element:SetDisabled(disabled: boolean)
	self._disabled = disabled
	if self._dim then
		self._dim.BackgroundTransparency = disabled and 0.5 or 1
	end
	if self._interaction then
		self._interaction.Active = not disabled
	end
	if self._box then
		-- TextBox: .Active alone does not stop typing; TextEditable does
		self._box.TextEditable = not disabled
		if disabled then
			pcall(function() self._box:ReleaseFocus() end)
		end
	end
end

function Element:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	if self._config.Flag then
		self._window.Flags[self._config.Flag] = nil
	end
	local list = self._tab._elements
	for i, el in list do
		if el == self then
			table.remove(list, i)
			break
		end
	end
	if self._container then
		self._container:Destroy()
		self._container = nil
	end
	if self._connections then
		for _, conn in self._connections do
			pcall(function() conn:Disconnect() end)
		end
		self._connections = nil
	end
	self._tab:_updateCanvas()
end

function Element:_track(conn)
	self._connections = self._connections or {}
	table.insert(self._connections, conn)
	return conn
end

-- Serialize/deserialize for configs
function Element:_serialize(value)
	if typeof(value) == "Color3" then
		return { __type = "Color3", R = math.floor(value.R * 1000) / 1000, G = math.floor(value.G * 1000) / 1000, B = math.floor(value.B * 1000) / 1000 }
	elseif typeof(value) == "EnumItem" then
		return { __type = "EnumItem", Name = value.Name }
	elseif type(value) == "table" then
		local out = {}
		for k, v in value do
			out[k] = Element:_serialize(v)
		end
		return out
	end
	return value
end

function Element:_deserialize(value)
	if type(value) == "table" then
		if value.__type == "Color3" then
			return Color3.new(value.R, value.G, value.B)
		elseif value.__type == "EnumItem" then
			return Enum.KeyCode[value.Name] or Enum.UserInputType[value.Name]
		end
		local out = {}
		for k, v in value do
			out[k] = Element:_deserialize(v)
		end
		return out
	end
	return value
end

----------------------------------------------------------------
-- Shared row scaffolding
----------------------------------------------------------------

-- Builds the standard element row: [Frame container] > [label + right-side content]
function Element:_buildRow(name: string, height: number): (Instance, Instance)
	local row = Create("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 1,
		Parent = self._tab._content,
	})
	self._container = row

	local pad = Create("UIPadding", {
		Parent = row,
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	})

	local label = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -16, 1, 0),
		BackgroundTransparency = 1,
		Text = tostring(name),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Parent = row,
	})
	themed(label, "TextColor3", "Text")
	self._label = label

	-- dim overlay used by SetDisabled (covers label + controls, ignores clicks)
	local dim = Create("Frame", {
		Name = "Dim",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Visible = true,
		ZIndex = 50, -- above the controls created later in this row
		Parent = row,
	})
	self._dim = dim
	self._tab:_updateCanvas()

	return row, label
end

function Element:_fireClick(target: Instance, callback: any)
	local btn = target
	self:_track(btn.Activated:Connect(function()
		if self._disabled then return end
		invokeCallback(callback)
	end))
end

----------------------------------------------------------------
-- Button
----------------------------------------------------------------

local Button = setmetatable({}, { __index = Element })
Button.__index = Button

function Button:_create(window, tab, config)
	local self = Element._new(window, tab, config, "Button")
	setmetatable(self, Button)

	assert(type(config.Name) == "string", "[Polaris] Button: Name must be a string")
	assert(type(config.Callback) == "function", "[Polaris] Button: Callback must be a function")

	local row = self:_buildRow(config.Name, 34)

	local btn = Create("TextButton", {
		Name = "Button",
		Size = UDim2.new(1, 0, 0, 30),
		Position = UDim2.new(0, 0, 0, 2),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})
	self._interaction = btn

	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = btn,
	})
	themed(fill, "BackgroundColor3", "Secondary")
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = fill })
	themed(Create("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Transparency = 0.85,
		Parent = fill,
	}), "Color", "Stroke")

	local label = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Text = config.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})
	themed(label, "TextColor3", "Text")

	btn.MouseEnter:Connect(function()
		if not self._disabled then
			safeTween(fill, 0.15, { BackgroundTransparency = 0.4 })
		end
	end)
	btn.MouseLeave:Connect(function()
		safeTween(fill, 0.15, { BackgroundTransparency = 0 })
	end)

	self:_fireClick(btn, config.Callback)

	self._value = true
	return self
end

function Button:_setValue(_value)
	self._value = true
end

----------------------------------------------------------------
-- Toggle
----------------------------------------------------------------

local Toggle = setmetatable({}, { __index = Element })
Toggle.__index = Toggle

function Toggle:_create(window, tab, config)
	local self = Element._new(window, tab, config, "Toggle")
	setmetatable(self, Toggle)

	assert(type(config.Name) == "string", "[Polaris] Toggle: Name must be a string")

	local row, label = self:_buildRow(config.Name, 34)
	label.Size = UDim2.new(1, -70, 1, 0)

	local switch = Create("TextButton", {
		Name = "Switch",
		Size = UDim2.new(0, 42, 0, 22),
		Position = UDim2.new(1, -42, 0.5, -11),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})
	self._interaction = switch

	local track = Create("Frame", {
		Name = "Track",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = switch,
	})
	-- NOTE: no themed() binding here - render() colors the track based on state
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })

	local knob = Create("Frame", {
		Name = "Knob",
		Size = UDim2.new(0, 16, 0, 16),
		Position = UDim2.new(0, 3, 0.5, -8),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	})
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

	self._trackFrame = track
	self._knobFrame = knob
	self._value = config.Default == true

	local function render(instant: boolean?)
		local theme = Polaris.Themes[Polaris.CurrentThemeName or "Default"]
		if self._value then
			if theme then track.BackgroundColor3 = theme.Accent end
			local goal = { Position = UDim2.new(1, -19, 0.5, -8) }
			if instant then knob.Position = goal.Position else safeTween(knob, 0.18, goal) end
		else
			if theme then track.BackgroundColor3 = theme.Primary end
			local goal = { Position = UDim2.new(0, 3, 0.5, -8) }
			if instant then knob.Position = goal.Position else safeTween(knob, 0.18, goal) end
		end
	end
	self._render = render

	self:_track(switch.Activated:Connect(function()
		if self._disabled then return end
		self:Set(not self._value)
	end))

	render(true)
	return self
end

function Toggle:_setValue(value)
	self._value = value == true
	if self._render then self._render(false) end
end

----------------------------------------------------------------
-- Slider
----------------------------------------------------------------

local Slider = setmetatable({}, { __index = Element })
Slider.__index = Slider

function Slider:_create(window, tab, config)
	local self = Element._new(window, tab, config, "Slider")
	setmetatable(self, Slider)

	assert(type(config.Name) == "string", "[Polaris] Slider: Name must be a string")
	local min = config.Min or 0
	local max = config.Max or 100
	assert(type(min) == "number" and type(max) == "number" and max > min, "[Polaris] Slider: Max must be greater than Min")
	local increment = config.Increment or 1
	assert(increment > 0, "[Polaris] Slider: Increment must be > 0")

	self._min, self._max, self._increment = min, max, increment

	local row = self:_buildRow(config.Name, 52)
	self._label.Size = UDim2.new(1, -16, 0, 22)

	local valueLabel = Create("TextLabel", {
		Name = "Value",
		Size = UDim2.new(0, 80, 0, 22),
		Position = UDim2.new(1, -80, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})
	themed(valueLabel, "TextColor3", "SubText")
	self._valueLabel = valueLabel

	local bar = Create("TextButton", {
		Name = "Bar",
		Size = UDim2.new(1, -16, 0, 8),
		Position = UDim2.new(0, 8, 0, 34),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})
	self._interaction = bar

	local track = Create("Frame", {
		Name = "Track",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = bar,
	})
	themed(track, "BackgroundColor3", "Primary")
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = track })

	local fill = Create("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = track,
	})
	themed(fill, "BackgroundColor3", "Accent")
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = fill })

	local knob = Create("Frame", {
		Name = "Knob",
		Size = UDim2.new(0, 14, 0, 14),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = bar,
	})
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = knob })

	self._bar = bar
	self._fill = fill
	self._knob = knob

	-- normalize relative to Min so ranges not aligned to the step still land inside [Min, Max]
	local function normalize(v: number): number
		v = clamp(v, min, max)
		local steps = math.floor((v - min) / increment + 0.5)
		return clamp(min + steps * increment, min, max)
	end

	local function percentToValue(p: number): number
		local v = min + (max - min) * clamp(p, 0, 1)
		return normalize(v)
	end

	local function render()
		local v = self._value
		local p = (v - min) / (max - min)
		fill.Size = UDim2.new(p, 0, 1, 0)
		knob.Position = UDim2.new(p, 0, 0.5, 0)
		local suffix = config.ValueName and (" " .. tostring(config.ValueName)) or ""
		valueLabel.Text = formatNumber(v) .. suffix
	end
	self._render = render

	local dragging = false

	local function setFromAlpha(alpha: number)
		self._value = percentToValue(alpha)
		render()
		if self._config.Callback then
			invokeCallback(self._config.Callback, self._value)
		end
	end

	self:_track(bar.InputBegan:Connect(function(input)
		if self._disabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromAlpha((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1))
		end
	end))

	self:_track(UserInputService.InputChanged:Connect(function(input)
		if not dragging or self._disabled then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			setFromAlpha((input.Position.X - track.AbsolutePosition.X) / math.max(track.AbsoluteSize.X, 1))
		end
	end))

	self:_track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	self._value = normalize(config.Default or min)
	render()
	return self
end

function Slider:_setValue(value)
	assert(type(value) == "number", "[Polaris] Slider:Set expects a number")
	-- normalize relative to Min so the result always stays within [Min, Max]
	local v = clamp(value, self._min, self._max)
	local steps = math.floor((v - self._min) / self._increment + 0.5)
	self._value = clamp(self._min + steps * self._increment, self._min, self._max)
	if self._render then self._render() end
end

----------------------------------------------------------------
-- Dropdown (single or multi select)
----------------------------------------------------------------

local Dropdown = setmetatable({}, { __index = Element })
Dropdown.__index = Dropdown

function Dropdown:_create(window, tab, config)
	local self = Element._new(window, tab, config, "Dropdown")
	setmetatable(self, Dropdown)

	assert(type(config.Name) == "string", "[Polaris] Dropdown: Name must be a string")
	assert(type(config.Options) == "table" and #config.Options > 0, "[Polaris] Dropdown: Options must be a non-empty table")
	self._multiple = config.Multiple == true
	self._options = deepCopy(config.Options)

	-- row is 48px tall: 16px label + 24px header + padding (expands when open)
	local row = self:_buildRow(config.Name, 48)
	self._label.Size = UDim2.new(1, -16, 0, 16)
	self._label.Position = UDim2.new(0, 8, 0, 0)

	local header = Create("TextButton", {
		Name = "Header",
		Size = UDim2.new(1, -16, 0, 24),
		Position = UDim2.new(0, 8, 0, 20),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})
	self._interaction = header

	local headerBg = Create("Frame", {
		Name = "HeaderBg",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = header,
	})
	themed(headerBg, "BackgroundColor3", "Secondary")
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = headerBg })

	local headerText = Create("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, -24, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})
	themed(headerText, "TextColor3", "Text")
	self._headerText = headerText

	local arrow = Create("TextLabel", {
		Name = "Arrow",
		Size = UDim2.new(0, 16, 1, 0),
		Position = UDim2.new(1, -20, 0, 0),
		BackgroundTransparency = 1,
		Text = "v",
		Parent = header,
	})
	themed(arrow, "TextColor3", "SubText")

	local optionsFrame = Create("Frame", {
		Name = "Options",
		Size = UDim2.new(1, -16, 0, 0),
		Position = UDim2.new(0, 8, 0, 48),
		BackgroundTransparency = 1,
		ClipsDescendants = true,
		Visible = false,
		Parent = row,
	})
	self._optionsFrame = optionsFrame

	Create("UIListLayout", { Padding = UDim.new(0, 2), Parent = optionsFrame })

	self._optionButtons = {}
	self._open = false
	self._value = nil

	if self._multiple then
		self._value = {}
		if type(config.Default) == "table" then
			for _, v in config.Default do
				self._value[v] = true
			end
		end
	else
		self._value = config.Default
	end

	local function renderHeader()
		if self._multiple then
			local selected = {}
			for _, opt in self._options do
				if self._value[opt] then table.insert(selected, tostring(opt)) end
			end
			headerText.Text = #selected > 0 and table.concat(selected, ", ") or "None"
		else
			headerText.Text = self._value ~= nil and tostring(self._value) or "None"
		end
	end
	self._renderHeader = renderHeader

	local function updateHeight()
		local extra = self._open and (#self._options * 26 + 6) or 0
		row.Size = UDim2.new(1, 0, 0, 48 + extra)
		optionsFrame.Size = UDim2.new(1, -16, 0, self._open and (#self._options * 26 + 4) or 0)
		self._tab:_updateCanvas()
	end
	self._updateHeight = updateHeight

	local refreshers = {}

	local function refreshAll()
		for _, f in refreshers do
			f()
		end
	end
	self._refreshOptions = refreshAll

	local function rebuildOptions()
		for _, btn in self._optionButtons do
			btn:Destroy()
		end
		self._optionButtons = {}
		refreshers = {}
		for i, opt in self._options do
			local optBtn = Create("TextButton", {
				Name = "Option" .. i,
				Size = UDim2.new(1, 0, 0, 24),
				BackgroundColor3 = Color3.new(1, 1, 1),
				BorderSizePixel = 0,
				Text = "",
				Parent = optionsFrame,
			})
			themed(optBtn, "BackgroundColor3", "Secondary")
			Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = optBtn })

			local optText = Create("TextLabel", {
				Size = UDim2.new(1, -16, 1, 0),
				Position = UDim2.new(0, 8, 0, 0),
				BackgroundTransparency = 1,
				Text = tostring(opt),
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = optBtn,
			})
			themed(optText, "TextColor3", "Text")

			local function isSelected(): boolean
				return self._multiple and self._value[opt] == true or (not self._multiple and self._value == opt)
			end

			local function refresh()
				local theme = Polaris.Themes[Polaris.CurrentThemeName or "Default"]
				if isSelected() then
					optText.Text = tostring(opt) .. "  -"
					if theme then optText.TextColor3 = theme.Accent end
				else
					optText.Text = tostring(opt)
					if theme then optText.TextColor3 = theme.Text end
				end
			end

			optBtn.Activated:Connect(function()
				if self._disabled then return end
				if self._multiple then
					if self._value[opt] then
						self._value[opt] = nil
					else
						self._value[opt] = true
					end
				else
					self._value = opt
				end
				refreshAll()
				renderHeader()
				if self._config.Callback then
					invokeCallback(self._config.Callback, self:Get())
				end
			end)

			refresh()
			table.insert(refreshers, refresh)
			table.insert(self._optionButtons, optBtn)
		end
	end

	self:_track(header.Activated:Connect(function()
		if self._disabled then return end
		self._open = not self._open
		optionsFrame.Visible = self._open
		arrow.Text = self._open and "^" or "v"
		updateHeight()
	end))

	rebuildOptions()
	renderHeader()
	self._rebuildOptions = rebuildOptions
	return self
end

function Dropdown:_setValue(value)
	if self._multiple then
		assert(type(value) == "table", "[Polaris] Dropdown:Set expects a table for multi-select dropdowns")
		-- accept both array form {"a","b"} and map form {a=true, b=true}
		-- (map form is what JSON round-trips produce)
		local items = value
		local isMap = false
		for _, v in value do
			if v == true then
				isMap = true
			end
		end
		if isMap then
			items = {}
			for k in value do
				table.insert(items, k)
			end
		end
		local newValue = {}
		for _, v in items do
			local found = false
			for _, opt in self._options do
				if opt == v then found = true end
			end
			assert(found, ("[Polaris] Dropdown:Set - '%s' is not a valid option"):format(tostring(v)))
			newValue[v] = true
		end
		self._value = newValue
	else
		local found = false
		for _, opt in self._options do
			if opt == value then found = true end
		end
		assert(found, ("[Polaris] Dropdown:Set - '%s' is not a valid option"):format(tostring(value)))
		self._value = value
	end
	if self._renderHeader then self._renderHeader() end
	if self._refreshOptions then self:_refreshOptions() end
end

-- Refresh the option list at runtime. If keepSelection, tries to keep current values.
function Dropdown:Refresh(options: { any }, keepSelection: boolean?)
	assert(type(options) == "table", "[Polaris] Refresh expects a table of options")
	self._options = deepCopy(options)
	if not keepSelection then
		self._value = self._multiple and {} or nil
	end
	if self._multiple then
		local cleaned = {}
		for v in self._value do
			for _, opt in self._options do
				if opt == v then cleaned[v] = true end
			end
		end
		self._value = cleaned
	else
		if self._value ~= nil then
			local stillThere = false
			for _, opt in self._options do
				if opt == self._value then stillThere = true end
			end
			if not stillThere then self._value = nil end
		end
	end
	-- rebuild buttons and re-sync highlight states + row height
	if self._rebuildOptions then self._rebuildOptions() end
	if self._renderHeader then self._renderHeader() end
	if self._updateHeight then self:_updateHeight() end
end

----------------------------------------------------------------
-- ColorPicker
----------------------------------------------------------------

local ColorPicker = setmetatable({}, { __index = Element })
ColorPicker.__index = ColorPicker

function ColorPicker:_create(window, tab, config)
	local self = Element._new(window, tab, config, "ColorPicker")
	setmetatable(self, ColorPicker)

	assert(type(config.Name) == "string", "[Polaris] ColorPicker: Name must be a string")

	local row = self:_buildRow(config.Name, 34)
	self._label.Size = UDim2.new(1, -66, 1, 0)

	local swatch = Create("TextButton", {
		Name = "Swatch",
		Size = UDim2.new(0, 42, 0, 22),
		Position = UDim2.new(1, -42, 0.5, -11),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		Parent = row,
	})
	self._interaction = swatch
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = swatch })

	local defaultColor = config.Default
	if typeof(defaultColor) ~= "Color3" then
		defaultColor = Color3.fromRGB(255, 255, 255)
	end
	self._value = defaultColor
	swatch.BackgroundColor3 = defaultColor

	-- HSV popup
	local popup = Create("Frame", {
		Name = "Popup",
		Size = UDim2.new(0, 180, 0, 160),
		Position = UDim2.new(1, -180, 0, 40),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Visible = false,
		Parent = row,
	})
	themed(popup, "BackgroundColor3", "Secondary")
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = popup })

	local svFrame = Create("TextButton", {
		Name = "SV",
		Size = UDim2.new(1, -16, 0, 110),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundColor3 = Color3.fromRGB(255, 0, 0),
		BorderSizePixel = 0,
		Text = "",
		Parent = popup,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = svFrame })

	-- saturation axis: white overlay fading left -> right
	local whiteOverlay = Create("Frame", {
		Name = "WhiteOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = svFrame,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = whiteOverlay })
	Create("UIGradient", {
		Rotation = 0,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(1, 1),
		}),
		Parent = whiteOverlay,
	})

	-- value axis: black overlay fading top -> bottom
	local blackOverlay = Create("Frame", {
		Name = "BlackOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = svFrame,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = blackOverlay })
	Create("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0),
		}),
		Parent = blackOverlay,
	})

	local hueBar = Create("TextButton", {
		Name = "Hue",
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 8, 0, 128),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		Parent = popup,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = hueBar })
	local hueGradient = Create("UIGradient", { Parent = hueBar })
	hueGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
		ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
		ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
		ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
		ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
		ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
	})

	local function hsvToColor(h: number, s: number, v: number): Color3
		return Color3.fromHSV(h, s, v)
	end

	local function render()
		swatch.BackgroundColor3 = self._value
		local h, s, v = self._value:ToHSV()
		svFrame.BackgroundColor3 = hsvToColor(h, 1, 1)
	end
	self._render = render

	local function setColorFromHSV(h: number, s: number, v: number)
		self._value = hsvToColor(h, s, v)
		render()
		if self._config.Callback then
			invokeCallback(self._config.Callback, self._value)
		end
	end

	local svDragging = false
	self:_track(svFrame.InputBegan:Connect(function(input)
		if self._disabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			svDragging = true
			local h = self._value:ToHSV()
			local relX = clamp((input.Position.X - svFrame.AbsolutePosition.X) / math.max(svFrame.AbsoluteSize.X, 1), 0, 1)
			local relY = clamp((input.Position.Y - svFrame.AbsolutePosition.Y) / math.max(svFrame.AbsoluteSize.Y, 1), 0, 1)
			setColorFromHSV(h, relX, 1 - relY)
		end
	end))

	self:_track(UserInputService.InputChanged:Connect(function(input)
		if not svDragging or self._disabled then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local h = self._value:ToHSV()
			local relX = clamp((input.Position.X - svFrame.AbsolutePosition.X) / math.max(svFrame.AbsoluteSize.X, 1), 0, 1)
			local relY = clamp((input.Position.Y - svFrame.AbsolutePosition.Y) / math.max(svFrame.AbsoluteSize.Y, 1), 0, 1)
			setColorFromHSV(h, relX, 1 - relY)
		end
	end))

	self:_track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			svDragging = false
		end
	end))

	local hueDragging = false
	self:_track(hueBar.InputBegan:Connect(function(input)
		if self._disabled then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			hueDragging = true
			local _, s, v = self._value:ToHSV()
			local relX = clamp((input.Position.X - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 1)
			setColorFromHSV(relX, s, v)
		end
	end))

	self:_track(UserInputService.InputChanged:Connect(function(input)
		if not hueDragging or self._disabled then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local _, s, v = self._value:ToHSV()
			local relX = clamp((input.Position.X - hueBar.AbsolutePosition.X) / math.max(hueBar.AbsoluteSize.X, 1), 0, 1)
			setColorFromHSV(relX, s, v)
		end
	end))

	self:_track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			hueDragging = false
		end
	end))

	self:_track(swatch.Activated:Connect(function()
		if self._disabled then return end
		popup.Visible = not popup.Visible
	end))

	render()
	return self
end

function ColorPicker:_setValue(value)
	assert(typeof(value) == "Color3", "[Polaris] ColorPicker:Set expects a Color3")
	self._value = value
	if self._render then self._render() end
end

----------------------------------------------------------------
-- Keybind
----------------------------------------------------------------

local Keybind = setmetatable({}, { __index = Element })
Keybind.__index = Keybind

function Keybind:_create(window, tab, config)
	local self = Element._new(window, tab, config, "Keybind")
	setmetatable(self, Keybind)

	assert(type(config.Name) == "string", "[Polaris] Keybind: Name must be a string")

	local row = self:_buildRow(config.Name, 34)
	self._label.Size = UDim2.new(1, -90, 1, 0)

	local keyBtn = Create("TextButton", {
		Name = "KeyButton",
		Size = UDim2.new(0, 82, 0, 24),
		Position = UDim2.new(1, -82, 0.5, -12),
		BackgroundTransparency = 1,
		Text = "",
		Parent = row,
	})
	self._interaction = keyBtn

	local keyBg = Create("Frame", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = keyBtn,
	})
	themed(keyBg, "BackgroundColor3", "Secondary")
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = keyBg })

	local keyText = Create("TextLabel", {
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = keyBtn,
	})
	themed(keyText, "TextColor3", "Text")
	self._keyText = keyText

	self._value = config.Default or Enum.KeyCode.Unknown
	self._hold = config.Hold == true
	self._listening = false

	local function render()
		keyText.Text = typeof(self._value) == "EnumItem" and self._value.Name or tostring(self._value)
	end
	self._render = render

	self:_track(keyBtn.Activated:Connect(function()
		if self._disabled then return end
		self._listening = true
		keyText.Text = "..."
	end))

	self:_track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if self._disabled then return end
		if self._listening then
			if input.UserInputType == Enum.UserInputType.Keyboard then
				self._value = input.KeyCode
				self._listening = false
				render()
			end
			return
		end
		if gameProcessed then return end
		if self._hold then
			if input.KeyCode == self._value then
				invokeCallback(self._config.Callback, true)
			end
		else
			if input.KeyCode == self._value then
				invokeCallback(self._config.Callback)
			end
		end
	end))

	if self._hold then
		self:_track(UserInputService.InputEnded:Connect(function(input)
			if self._hold and input.KeyCode == self._value then
				invokeCallback(self._config.Callback, false)
			end
		end))
	end

	render()
	return self
end

function Keybind:_setValue(value)
	assert(typeof(value) == "EnumItem", "[Polaris] Keybind:Set expects an EnumItem (e.g. Enum.KeyCode.E)")
	self._value = value
	if self._render then self._render() end
end

----------------------------------------------------------------
-- Textbox
----------------------------------------------------------------

local Textbox = setmetatable({}, { __index = Element })
Textbox.__index = Textbox

function Textbox:_create(window, tab, config)
	local self = Element._new(window, tab, config, "Textbox")
	setmetatable(self, Textbox)

	assert(type(config.Name) == "string", "[Polaris] Textbox: Name must be a string")

	local row = self:_buildRow(config.Name, 34)
	self._label.Size = UDim2.new(1, -140, 1, 0)

	local box = Create("TextBox", {
		Name = "Box",
		Size = UDim2.new(0, 132, 0, 24),
		Position = UDim2.new(1, -132, 0.5, -12),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = tostring(config.Default or ""),
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = config.TextDisappear ~= true,
		Parent = row,
	})
	themed(box, "BackgroundColor3", "Secondary")
	themed(box, "TextColor3", "Text")
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = box })
	Create("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = box })

	self._value = tostring(config.Default or "")
	self._interaction = box

	self:_track(box.FocusLost:Connect(function(enterPressed)
		if self._disabled then return end
		self._value = box.Text
		if self._config.Callback then
			invokeCallback(self._config.Callback, self._value, enterPressed)
		end
	end))

	self._box = box
	return self
end

function Textbox:_setValue(value)
	self._value = tostring(value)
	if self._box then
		self._box.Text = self._value
	end
end

----------------------------------------------------------------
-- Paragraph / Label / Divider / Section
----------------------------------------------------------------

local Paragraph = setmetatable({}, { __index = Element })
Paragraph.__index = Paragraph

function Paragraph:_create(window, tab, config)
	local self = Element._new(window, tab, config, "Paragraph")
	setmetatable(self, Paragraph)

	local row = Create("Frame", {
		Name = "Paragraph",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Parent = self._tab._content,
	})
	self._container = row

	local text = Create("TextLabel", {
		Name = "Text",
		Size = UDim2.new(1, -16, 0, 30),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = tostring(config.Text or ""),
		Parent = row,
	})
	themed(text, "TextColor3", "SubText")
	self._text = text
	self._label = text -- so search filtering covers paragraphs

	self._value = tostring(config.Text or "")
	self:_syncHeight()
	return self
end

function Paragraph:_syncHeight()
	local content = tostring(self._value or "")
	local fontSize = 14
	-- approximate wrapped height: ~40 chars per line at default width
	local lines = 1
	local width = 460
	local perLine = math.floor(width / (fontSize * 0.55))
	lines = math.max(1, math.ceil(#content / math.max(perLine, 1)))
	local h = 6 + lines * (fontSize + 4)
	self._container.Size = UDim2.new(1, 0, 0, h)
	self._text.Size = UDim2.new(1, -16, 0, h)
	self._tab:_updateCanvas()
end

function Paragraph:_setValue(value)
	self._value = tostring(value)
	if self._text then
		self._text.Text = self._value
	end
	self:_syncHeight()
end

function Paragraph:SetText(text: string)
	self:Set(text)
end

local Divider = setmetatable({}, { __index = Element })
Divider.__index = Divider

function Divider:_create(window, tab, config)
	local self = Element._new(window, tab, config, "Divider")
	setmetatable(self, Divider)

	local row = Create("Frame", {
		Name = "Divider",
		Size = UDim2.new(1, 0, 0, 10),
		BackgroundTransparency = 1,
		Parent = self._tab._content,
	})
	self._container = row

	local line = Create("Frame", {
		Name = "Line",
		Size = UDim2.new(1, -16, 0, 1),
		Position = UDim2.new(0, 8, 0.5, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = row,
	})
	themed(line, "BackgroundColor3", "Stroke")

	self._value = nil
	return self
end

function Divider:_setValue(_value) end

----------------------------------------------------------------
-- Section
----------------------------------------------------------------

local Section = {}
Section.__index = Section

function Section:_create(tab, config)
	local self = setmetatable({}, Section)
	self._tab = tab
	self._elements = {}

	assert(type(config.Name) == "string", "[Polaris] Section: Name must be a string")

	local row = Create("Frame", {
		Name = "Section",
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundTransparency = 1,
		Parent = tab._content,
	})
	self._container = row

	local label = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 8, 0, 0),
		BackgroundTransparency = 1,
		Text = tostring(config.Name),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
	themed(label, "TextColor3", "Text")

	local line = Create("Frame", {
		Name = "Line",
		Size = UDim2.new(1, -16, 0, 1),
		Position = UDim2.new(0, 8, 1, -2),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = row,
	})
	themed(line, "BackgroundColor3", "Stroke")

	table.insert(tab._sections, self)
	tab:_updateCanvas()
	return self
end

-- Elements added to a section simply appear below it in the tab flow.
-- For precise grouping, create elements between sections.
function Section:Destroy()
	local list = self._tab._sections
	for i, s in list do
		if s == self then
			table.remove(list, i)
			break
		end
	end
	if self._container then
		self._container:Destroy()
		self._container = nil
	end
	self._tab:_updateCanvas()
end

----------------------------------------------------------------
-- Tab
----------------------------------------------------------------

local Tab = {}
Tab.__index = Tab

function Tab:_create(window, config)
	local self = setmetatable({}, Tab)
	self._window = window
	self._elements = {}
	self._sections = {}
	self._name = config.Name

	assert(type(config.Name) == "string", "[Polaris] Tab: Name must be a string")

	-- Tab button in sidebar
	local btn = Create("TextButton", {
		Name = "TabButton",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		Text = "",
		Parent = window._tabHolder,
	})
	self._button = btn

	local btnBg = Create("Frame", {
		Name = "Bg",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = btn,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = btnBg })

	local btnLabel = Create("TextLabel", {
		Name = "Label",
		Size = UDim2.new(1, -12, 1, 0),
		Position = UDim2.new(0, 6, 0, 0),
		BackgroundTransparency = 1,
		Text = config.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = btn,
	})
	themed(btnLabel, "TextColor3", "SubText")
	self._buttonLabel = btnLabel

	if config.Icon then
		local icon = Create("ImageLabel", {
			Name = "Icon",
			Size = UDim2.new(0, 16, 0, 16),
			Position = UDim2.new(1, -22, 0.5, -8),
			BackgroundTransparency = 1,
			Image = config.Icon,
			Parent = btn,
		})
	end

	-- Content page
	local page = Create("ScrollingFrame", {
		Name = "Page",
		Size = UDim2.new(1, -16, 1, -16),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Visible = false,
		Parent = window._content,
	})
	self._content = page

	Create("UIListLayout", { Padding = UDim.new(0, 4), Parent = page })

	btn.Activated:Connect(function()
		window:_selectTab(self)
	end)

	table.insert(window._tabs, self)
	window:_updateTabLayout()
	return self
end

function Tab:_select()
	for _, el in self._elements do
		if el._container then el._container.Visible = el._visible end
	end
	for _, s in self._sections do
		if s._container then s._container.Visible = true end
	end
	local theme = Polaris.Themes[Polaris.CurrentThemeName or "Default"]
	if self._buttonLabel and theme then
		self._buttonLabel.TextColor3 = theme.Text
	end
	self._content.Visible = true
	self._window:_updateCanvasFor(self)
end

function Tab:_deselect()
	for _, el in self._elements do
		if el._container then el._container.Visible = false end
	end
	for _, s in self._sections do
		if s._container then s._container.Visible = false end
	end
	local theme = Polaris.Themes[Polaris.CurrentThemeName or "Default"]
	if self._buttonLabel and theme then
		self._buttonLabel.TextColor3 = theme.SubText
	end
	self._content.Visible = false
end

function Tab:_updateCanvas()
	self._window:_updateCanvasFor(self)
end

-- Element factory methods
function Tab:CreateSection(config)
	return Section:_create(self, config)
end

function Tab:CreateButton(config)
	return Button:_create(self._window, self, config)
end

function Tab:CreateToggle(config)
	return Toggle:_create(self._window, self, config)
end

function Tab:CreateSlider(config)
	return Slider:_create(self._window, self, config)
end

function Tab:CreateDropdown(config)
	return Dropdown:_create(self._window, self, config)
end

function Tab:CreateColorPicker(config)
	return ColorPicker:_create(self._window, self, config)
end

function Tab:CreateKeybind(config)
	return Keybind:_create(self._window, self, config)
end

function Tab:CreateTextbox(config)
	return Textbox:_create(self._window, self, config)
end

function Tab:CreateParagraph(config)
	return Paragraph:_create(self._window, self, config)
end

function Tab:CreateDivider(config)
	return Divider:_create(self._window, self, config or {})
end

function Tab:GetElements()
	return self._elements
end

function Tab:Destroy()
	-- iterate over a shallow copy: Destroy mutates the list
	local elements = table.clone(self._elements)
	for _, el in elements do
		pcall(function() el:Destroy() end)
	end
	local sections = table.clone(self._sections)
	for _, s in sections do
		pcall(function() s:Destroy() end)
	end
	local list = self._window._tabs
	for i, t in list do
		if t == self then
			table.remove(list, i)
			break
		end
	end
	if self._button then self._button:Destroy() end
	if self._content then self._content:Destroy() end
	self._window:_updateTabLayout()
end

----------------------------------------------------------------
-- Window
----------------------------------------------------------------

local Window = {}
Window.__index = Window

function Window:_create(config)
	local self = setmetatable({}, Window)
	self._config = config
	self._tabs = {}
	self._elements = {}
	self.Flags = {}
	self._connections = {}
	self._destroyed = false

	assert(type(config.Name) == "string", "[Polaris] Window: Name must be a string")

	local themeName = config.Theme or "Default"
	if not Polaris.Themes[themeName] then
		error(("[Polaris] Unknown theme '%s'"):format(themeName), 0)
	end

	local screenGui = Create("ScreenGui", {
		Name = "Polaris_" .. config.Name,
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = getGuiParent(),
	})
	self._screenGui = screenGui

	local size = config.Size or Vector2.new(580, 400)
	local position = config.Position or UDim2.new(0.5, -size.X / 2, 0.5, -size.Y / 2)

	local frame = Create("Frame", {
		Name = "Window",
		Size = UDim2.new(0, size.X, 0, size.Y),
		Position = position,
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = screenGui,
	})
	themed(frame, "BackgroundColor3", "Background")
	self._frame = frame
	Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = frame })
	local stroke = Create("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.85, Parent = frame })
	themed(stroke, "Color", "Stroke")

	-- Title bar
	local titleBar = Create("Frame", {
		Name = "TitleBar",
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	self._titleBar = titleBar

	local title = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -120, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		BackgroundTransparency = 1,
		Text = config.Name,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = titleBar,
	})
	themed(title, "TextColor3", "Text")
	self._title = title

	-- Search bar
	local searchBox = Create("TextBox", {
		Name = "Search",
		Size = UDim2.new(0, 130, 0, 22),
		Position = UDim2.new(1, -180, 0, 7),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = "",
		PlaceholderText = "Search...",
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = titleBar,
	})
	themed(searchBox, "BackgroundColor3", "Secondary")
	themed(searchBox, "TextColor3", "Text")
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = searchBox })
	Create("UIPadding", { PaddingLeft = UDim.new(0, 6), Parent = searchBox })
	self._searchBox = searchBox

	-- Minimize / Close buttons
	local function makeControlButton(text: string, x: number, themeKey: string)
		local b = Create("TextButton", {
			Name = text,
			Size = UDim2.new(0, 22, 0, 22),
			Position = UDim2.new(1, x, 0, 7),
			BackgroundTransparency = 1,
			Text = text,
			Parent = titleBar,
		})
		themed(b, "TextColor3", themeKey)
		return b
	end

	local minimizeBtn = makeControlButton("-", -46, "SubText")
	local closeBtn = makeControlButton("X", -22, "Danger")

	-- Sidebar
	local sidebar = Create("Frame", {
		Name = "Sidebar",
		Size = UDim2.new(0, 150, 1, -36),
		Position = UDim2.new(0, 0, 0, 36),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	self._sidebar = sidebar

	local tabHolder = Create("ScrollingFrame", {
		Name = "TabHolder",
		Size = UDim2.new(1, -16, 1, -16),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = sidebar,
	})
	self._tabHolder = tabHolder
	Create("UIListLayout", { Padding = UDim.new(0, 2), Parent = tabHolder })

	local sidebarLine = Create("Frame", {
		Name = "Line",
		Size = UDim2.new(0, 1, 1, 0),
		Position = UDim2.new(0, 150, 0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = frame,
	})
	themed(sidebarLine, "BackgroundColor3", "Stroke")

	-- Content
	local content = Create("Frame", {
		Name = "Content",
		Size = UDim2.new(1, -158, 1, -44),
		Position = UDim2.new(0, 158, 0, 40),
		BackgroundTransparency = 1,
		Parent = frame,
	})
	self._content = content

	-- Resize grip
	local grip = Create("TextButton", {
		Name = "ResizeGrip",
		Size = UDim2.new(0, 18, 0, 18),
		Position = UDim2.new(1, -16, 1, -16),
		BackgroundTransparency = 1,
		Text = "",
		Parent = frame,
	})
	self._grip = grip
	local gripIcon = Create("TextLabel", {
		Name = "Icon",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Text = "/",
		Parent = grip,
	})
	themed(gripIcon, "TextColor3", "SubText")

	------------------------------------------------------------
	-- Behavior: drag, resize, minimize, close, search, keybind
	------------------------------------------------------------

	local function getViewport(): Vector2
		local camera = workspace.CurrentCamera
		if camera then
			return camera.ViewportSize
		end
		return Vector2.new(1920, 1080)
	end

	-- Dragging (pixel space, so centered/scaled default positions clamp correctly)
	local dragging = false
	local dragStart, startPos

	titleBar.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.AbsolutePosition -- Vector2 in pixels
		end
	end)

	self:_track(UserInputService.InputChanged:Connect(function(input)
		if dragging and not self._destroyed and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			local vp = getViewport()
			local newX = clamp(startPos.X + delta.X, -size.X + 100, vp.X - 100)
			local newY = clamp(startPos.Y + delta.Y, 0, vp.Y - 36)
			frame.Position = UDim2.new(0, newX, 0, newY)
		end
	end))

	self:_track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end))

	-- Resizing
	local resizing = false
	local resizeStart, resizeStartSize

	grip.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = true
			resizeStart = input.Position
			resizeStartSize = frame.Size
		end
	end)

	self:_track(UserInputService.InputChanged:Connect(function(input)
		if resizing and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - resizeStart
			local newW = math.max(400, resizeStartSize.X.Offset + delta.X)
			local newH = math.max(280, resizeStartSize.Y.Offset + delta.Y)
			frame.Size = UDim2.new(0, newW, 0, newH)
			size = Vector2.new(newW, newH)
		end
	end))

	self:_track(UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			resizing = false
		end
	end))

	-- Minimize
	local minimized = false
	minimizeBtn.Activated:Connect(function()
		minimized = not minimized
		sidebar.Visible = not minimized
		content.Visible = not minimized
		grip.Visible = not minimized
		sidebarLine.Visible = not minimized
		frame.Size = minimized and UDim2.new(0, size.X, 0, 36) or UDim2.new(0, size.X, 0, size.Y)
	end)

	-- Close
	closeBtn.Activated:Connect(function()
		self:Destroy()
	end)

	-- Search filtering
	searchBox:GetPropertyChangedSignal("Text"):Connect(function()
		local query = searchBox.Text:lower()
		for _, tab in self._tabs do
			for _, el in tab._elements do
				if el._label then
					local name = tostring(el._config.Name or el._className)
					local match = query == "" or string.find(name:lower(), query, 1, true) ~= nil
					if el._container then
						el._container.Visible = el._visible and match and tab._content.Visible
					end
				end
			end
			tab:_updateCanvas()
		end
	end)

	-- Window toggle keybind (listener is always installed so SetToggleKey works later)
	self._toggleKey = config.ToggleKey
	self:_track(UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if self._toggleKey and input.KeyCode == self._toggleKey then
			screenGui.Enabled = not screenGui.Enabled
		end
	end))

	self:_updateTabLayout()
	return self
end

function Window:_track(conn)
	table.insert(self._connections, conn)
	return conn
end

function Window:_updateTabLayout()
	local total = 0
	for _, tab in self._tabs do
		total += 30 + 2
	end
	self._tabHolder.CanvasSize = UDim2.new(0, 0, 0, total)
end

function Window:_updateCanvasFor(tab)
	local total = 0
	for _, el in tab._elements do
		if el._container and el._container.Visible then
			total += el._container.Size.Y.Offset + 4
		end
	end
	for _, s in tab._sections do
		if s._container and s._container.Visible then
			total += s._container.Size.Y.Offset + 4
		end
	end
	tab._content.CanvasSize = UDim2.new(0, 0, 0, total)
end

function Window:_selectTab(tab)
	for _, t in self._tabs do
		t:_deselect()
	end
	tab:_select()
end

function Window:CreateTab(config)
	local tab = Tab:_create(self, config)
	if #self._tabs == 1 then
		self:_selectTab(tab)
	end
	return tab
end

function Window:SetTitle(title: string)
	if self._title then
		self._title.Text = title
	end
end

function Window:SetToggleKey(keycode: EnumItem)
	assert(typeof(keycode) == "EnumItem", "[Polaris] SetToggleKey expects an EnumItem")
	self._toggleKey = keycode
end

function Window:SetVisible(visible: boolean)
	self._screenGui.Enabled = visible
end

function Window:GetVisible(): boolean
	return self._screenGui.Enabled
end

----------------------------------------------------------------
-- Config system
----------------------------------------------------------------

function Window:_configPath(name: string): string?
	if not FS or not self._config.ConfigFolder then return nil end
	return ("Polaris/%s/%s.json"):format(self._config.ConfigFolder, name or "default")
end

function Window:_collectConfig(): { [string]: any }
	local data = {}
	for flag, el in self.Flags do
		data[flag] = Element._serialize(el, el._value)
	end
	return data
end

function Window:SaveConfig(name: string?)
	local data = self:_collectConfig()
	local path = self:_configPath(name)
	if path and FS then
		local ok, err = pcall(function()
			FS.mkdir("Polaris")
			FS.mkdir(("Polaris/%s"):format(self._config.ConfigFolder))
			FS.write(path, HttpService:JSONEncode(data))
		end)
		if not ok then
			warn("[Polaris] Could not write config file:", err)
		end
	end
	-- keep an in-memory copy too, so LoadConfig works even without file APIs
	self._savedConfigs = self._savedConfigs or {}
	self._savedConfigs[name or "default"] = data
	return data
end

function Window:LoadConfig(name: string?)
	local path = self:_configPath(name)
	local data = nil
	if path and FS then
		local ok, result = pcall(function()
			if FS.isfile(path) then
				return HttpService:JSONDecode(FS.read(path))
			end
			return nil
		end)
		if ok then data = result end
	end
	if data == nil then
		-- try built-in saved config
		local saved = self._savedConfigs and self._savedConfigs[name or "default"]
		if saved then data = saved end
	end
	if data == nil then
		return nil
	end
	local applied, skipped = 0, 0
	for flag, value in data do
		local el = self.Flags[flag]
		if el and not el._destroyed then
			local deserialized = Element._deserialize(el, value)
			-- keybind callbacks mean "key pressed", not "binding changed":
			-- restore them silently so loading a config never fires actions
			local silent = el._className == "Keybind"
			local ok = pcall(function()
				el:Set(deserialized, silent)
			end)
			if ok then
				applied += 1
			else
				skipped += 1
			end
		else
			skipped += 1
		end
	end
	if skipped > 0 then
		warn(("[Polaris] LoadConfig: applied %d value(s), skipped %d (unknown flag or invalid value)"):format(applied, skipped))
	end
	return data
end

function Window:ExportConfig(): string
	return HttpService:JSONEncode(self:_collectConfig())
end

function Window:ImportConfig(json: string)
	local data = HttpService:JSONDecode(json)
	assert(type(data) == "table", "[Polaris] ImportConfig: invalid JSON")
	local applied, skipped = 0, 0
	for flag, value in data do
		local el = self.Flags[flag]
		if el and not el._destroyed then
			local silent = el._className == "Keybind"
			local ok = pcall(function()
				el:Set(Element._deserialize(el, value), silent)
			end)
			if ok then
				applied += 1
			else
				skipped += 1
			end
		else
			skipped += 1
		end
	end
	if skipped > 0 then
		warn(("[Polaris] ImportConfig: applied %d value(s), skipped %d (unknown flag or invalid value)"):format(applied, skipped))
	end
	self._savedConfigs = self._savedConfigs or {}
	self._savedConfigs["default"] = data
	return true
end

function Window:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	for _, conn in self._connections do
		pcall(function() conn:Disconnect() end)
	end
	self._connections = {}
	local tabs = table.clone(self._tabs)
	for _, tab in tabs do
		pcall(function() tab:Destroy() end)
	end
	if self._screenGui then
		self._screenGui:Destroy()
		self._screenGui = nil
	end
	for flag in self.Flags do
		self.Flags[flag] = nil
	end
	-- remove theme bindings belonging to this window
	local i = 1
	while i <= #ThemeBindings do
		local binding = ThemeBindings[i]
		if not binding.inst.Parent or binding.inst.Parent == nil then
			table.remove(ThemeBindings, i)
		else
			i += 1
		end
	end
end

----------------------------------------------------------------
-- Notifications
----------------------------------------------------------------

local NotificationManager = {}
NotificationManager.__index = NotificationManager

function NotificationManager:_create()
	local self = setmetatable({}, NotificationManager)
	self._active = {}
	local screenGui = Create("ScreenGui", {
		Name = "PolarisNotifications",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		Parent = getGuiParent(),
	})
	self._screenGui = screenGui
	self._container = Create("Frame", {
		Name = "Container",
		Position = UDim2.new(1, -260, 1, -10),
		Size = UDim2.new(0, 240, 1, 0),
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Parent = screenGui,
	})
	-- notifications stack upward from the bottom
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding = UDim.new(0, 4),
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Bottom,
		Parent = self._container,
	})
	self._connections = {}
	return self
end

function NotificationManager:_notify(config)
	assert(type(config.Title) == "string", "[Polaris] Notify: Title must be a string")
	local duration = config.Duration or config.Time or 5

	local notif = Create("Frame", {
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 64),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = self._container,
	})
	themed(notif, "BackgroundColor3", "Secondary")
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = notif })

	Create("UIStroke", {
		Color = Color3.new(1, 1, 1),
		Transparency = 0.85,
		Parent = notif,
	})

	local accentBar = Create("Frame", {
		Name = "AccentBar",
		Size = UDim2.new(0, 3, 1, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Parent = notif,
	})
	local accentKey = "Accent"
	if config.Type == "success" then accentKey = "Success" end
	if config.Type == "warning" then accentKey = "Warning" end
	if config.Type == "error" then accentKey = "Danger" end
	themed(accentBar, "BackgroundColor3", accentKey)

	local title = Create("TextLabel", {
		Name = "Title",
		Size = UDim2.new(1, -20, 0, 20),
		Position = UDim2.new(0, 12, 0, 8),
		BackgroundTransparency = 1,
		Text = config.Title,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 14,
		Parent = notif,
	})
	themed(title, "TextColor3", "Text")

	local body = Create("TextLabel", {
		Name = "Body",
		Size = UDim2.new(1, -20, 0, 30),
		Position = UDim2.new(0, 12, 0, 28),
		BackgroundTransparency = 1,
		Text = tostring(config.Content or ""),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		TextSize = 12,
		Parent = notif,
	})
	themed(body, "TextColor3", "SubText")

	local conn = notif.InputBegan:Connect(function()
		self:_dismiss(notif)
	end)
	table.insert(self._connections, conn)

	task.delay(duration, function()
		if notif.Parent then
			self:_dismiss(notif)
		end
	end)
end

function NotificationManager:_dismiss(notif: Instance)
	if not notif.Parent then return end
	notif:Destroy()
end

local Notifications = NotificationManager:_create()
Polaris._notifications = Notifications -- exposed for tests / power users

function Polaris:Notify(config)
	Notifications:_notify(config)
end

----------------------------------------------------------------
-- Top-level API
----------------------------------------------------------------

function Polaris:CreateWindow(config)
	local themeName = config.Theme or "Default"
	if not self.Themes[themeName] then
		error(("[Polaris] Unknown theme '%s'"):format(themeName), 0)
	end
	self.CurrentThemeName = themeName
	Polaris._windows = Polaris._windows or {}
	local window = Window:_create(config)
	table.insert(Polaris._windows, window)
	if config.SaveConfig then
		window:_loadOnCreate()
	end
	return window
end

function Window:_loadOnCreate()
	-- deferred so the caller's script can finish building flagged elements first
	task.defer(function()
		if self._destroyed then return end
		local ok, err = pcall(function()
			self:LoadConfig("default")
		end)
		if not ok then
			warn("[Polaris] Failed to load config:", err)
		end
	end)
end

-- Element-level shortcuts (create on the most recent window's first tab? no - keep explicit)

Polaris.Version = PolarisVersion

-- Flags registry across windows (per-window flags live in window.Flags)
Polaris.WindowFlags = setmetatable({}, {
	__index = function(t, key)
		for _, w in Polaris._windows or {} do
			if w.Flags[key] then return w.Flags[key] end
		end
		return nil
	end,
})

-- remove destroyed windows from the registry
local _origWindowDestroy = Window.Destroy
function Window:Destroy()
	local list = Polaris._windows
	if list then
		for i, w in list do
			if w == self then
				table.remove(list, i)
				break
			end
		end
	end
	return _origWindowDestroy(self)
end

----------------------------------------------------------------
-- Builder (visual hub maker, built with Polaris itself)
----------------------------------------------------------------
-- Open with Polaris.Builder:Open(). Users who run the published
-- Builder.luau launcher get an animated splash followed by this
-- editor; the library itself never opens anything on its own.

local Builder = {}
Builder.__index = Builder

Polaris.Builder = Builder

-- public knobs
Builder.SplashDuration = 1.6 -- seconds; 0 disables the splash
Builder.PolarisURL = "https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"

local KEY_OPTIONS = {
	"RightControl", "LeftControl", "RightAlt", "LeftAlt", "RightShift", "LeftShift",
	"Tab", "CapsLock", "F1", "F2", "F3", "F4", "F", "G", "H", "J", "K", "L",
	"Insert", "Delete", "End", "Home", "One", "Two", "Three",
}

local BLOCK_KINDS = {
	"Section", "Button", "Toggle", "Slider", "Dropdown",
	"ColorPicker", "Keybind", "Textbox", "Paragraph", "Divider",
}

local function indexOf(list, item)
	for i, v in list do
		if v == item then
			return i
		end
	end
	return nil
end

local function slugify(name)
	local s = tostring(name or ""):lower()
	s = s:gsub("[^%w_]", "")
	if s == "" then
		return "flag"
	end
	return s
end

local function quote(s)
	s = tostring(s or "")
	s = s:gsub("\\", "\\\\")
	s = s:gsub("\n", "\\n")
	s = s:gsub("\r", "\\r")
	s = s:gsub("\t", "\\t")
	s = s:gsub('"', '\\"')
	-- escape any remaining control characters as \ddd
	s = s:gsub("[%z\1-\8\11\12\14-\31]", function(c)
		return ("\\%03d"):format(c:byte())
	end)
	return '"' .. s .. '"'
end

local function splitOptions(str)
	local out = {}
	for part in tostring(str or ""):gmatch("[^,]+") do
		local trimmed = part:match("^%s*(.-)%s*$")
		if trimmed ~= "" then
			table.insert(out, trimmed)
		end
	end
	if #out == 0 then
		table.insert(out, "Option1")
	end
	return out
end

local function newProject()
	return {
		window = {
			Name = "My Hub",
			Theme = "Default",
			ConfigFolder = "MyHub",
			SaveConfig = true,
		},
		tabs = {
			{
				Name = "Main",
				Icon = "",
				nodes = {
					{ Kind = "Section", Name = "Actions" },
					{ Kind = "Toggle", Name = "Fly", Default = false, Flag = "fly" },
				},
			},
		},
	}
end

local function newBlock(kind, autoFlag)
	if kind == "Section" then
		return { Kind = "Section", Name = "New Section" }
	elseif kind == "Button" then
		return { Kind = "Button", Name = "New Button" }
	elseif kind == "Toggle" then
		return { Kind = "Toggle", Name = "New Toggle", Default = false, Flag = autoFlag("New Toggle") }
	elseif kind == "Slider" then
		return { Kind = "Slider", Name = "New Slider", Min = 0, Max = 100, Default = 50, Increment = 1, ValueName = "", Flag = autoFlag("New Slider") }
	elseif kind == "Dropdown" then
		return { Kind = "Dropdown", Name = "New Dropdown", Options = "Option1, Option2", Multiple = false, Flag = autoFlag("New Dropdown") }
	elseif kind == "ColorPicker" then
		return { Kind = "ColorPicker", Name = "New Color", R = 120, G = 130, B = 255, Flag = autoFlag("New Color") }
	elseif kind == "Keybind" then
		return { Kind = "Keybind", Name = "New Keybind", Key = "RightControl", Hold = false, Flag = autoFlag("New Keybind") }
	elseif kind == "Textbox" then
		return { Kind = "Textbox", Name = "New Textbox", Default = "", TextDisappear = false, Flag = autoFlag("New Textbox") }
	elseif kind == "Paragraph" then
		return { Kind = "Paragraph", Text = "Your text here..." }
	elseif kind == "Divider" then
		return { Kind = "Divider" }
	end
	return nil
end

----------------------------------------------------------------
-- Project model operations (UI-independent, unit-testable)
----------------------------------------------------------------

function Builder:NewProject()
	self._project = newProject()
	self._selected = nil
	return self._project
end

function Builder:GetProject()
	if not self._project then
		self._project = newProject()
	end
	return deepCopy(self._project)
end

function Builder:SetProject(t)
	assert(type(t) == "table", "[Polaris] Builder: project must be a table")
	assert(type(t.window) == "table", "[Polaris] Builder: project.window must be a table")
	assert(type(t.tabs) == "table", "[Polaris] Builder: project.tabs must be a table")
	self._project = deepCopy(t)
	self._selected = nil
	return self._project
end

function Builder:ExportJSON()
	return HttpService:JSONEncode(self:GetProject())
end

function Builder:ImportJSON(json)
	assert(type(json) == "string", "[Polaris] Builder: JSON must be a string")
	local data = HttpService:JSONDecode(json)
	return self:SetProject(data)
end

function Builder:_currentProject()
	if not self._project then
		self._project = newProject()
	end
	return self._project
end

function Builder:_collectFlags(out)
	local proj = self:_currentProject()
	for _, tab in proj.tabs do
		for _, node in tab.nodes do
			if node.Flag and node.Flag ~= "" then
				out[node.Flag] = true
			end
		end
	end
end

function Builder:_autoFlag(base)
	local taken = {}
	self:_collectFlags(taken)
	local stem = slugify(base)
	local name = stem
	local i = 2
	while taken[name] do
		name = stem .. i
		i = i + 1
	end
	return name
end

function Builder:_selectedTab()
	local proj = self:_currentProject()
	local sel = self._selected
	if sel and sel.tab and indexOf(proj.tabs, sel.tab) then
		return sel.tab
	end
	return proj.tabs[#proj.tabs]
end

function Builder:AddTab(name)
	local proj = self:_currentProject()
	local tab = { Name = tostring(name or "Tab"), Icon = "", nodes = {} }
	table.insert(proj.tabs, tab)
	self._selected = { tab = tab, node = nil }
	return tab
end

function Builder:AddBlock(kind)
	local tab = self:_selectedTab()
	if not tab then
		tab = self:AddTab("Main")
	end
	local node = newBlock(kind, function(base)
		return self:_autoFlag(base)
	end)
	if not node then
		return nil
	end
	local sel = self._selected
	local idx = nil
	if sel and sel.tab == tab and sel.node and indexOf(tab.nodes, sel.node) then
		idx = indexOf(tab.nodes, sel.node) + 1
		table.insert(tab.nodes, idx, node)
	else
		table.insert(tab.nodes, node)
	end
	self._selected = { tab = tab, node = node }
	return node
end

function Builder:MoveSelected(delta)
	local sel = self._selected
	if not sel or not sel.node or not sel.tab then
		return false
	end
	local nodes = sel.tab.nodes
	local i = indexOf(nodes, sel.node)
	if not i then
		return false
	end
	local j = i + delta
	if j < 1 or j > #nodes then
		return false
	end
	nodes[i] = nodes[j]
	nodes[j] = sel.node
	return true
end

function Builder:DeleteSelected()
	local sel = self._selected
	if not sel then
		return false
	end
	local proj = self:_currentProject()
	if sel.node and sel.tab then
		local i = indexOf(sel.tab.nodes, sel.node)
		if i then
			table.remove(sel.tab.nodes, i)
			self._selected = { tab = sel.tab, node = nil }
			return true
		end
	elseif sel.tab then
		local i = indexOf(proj.tabs, sel.tab)
		if i then
			table.remove(proj.tabs, i)
			self._selected = nil
			return true
		end
	end
	self._selected = nil
	return false
end

function Builder:DuplicateSelected()
	local sel = self._selected
	if not sel or not sel.node or not sel.tab then
		return nil
	end
	local i = indexOf(sel.tab.nodes, sel.node)
	if not i then
		return nil
	end
	local copy = deepCopy(sel.node)
	if copy.Flag and copy.Flag ~= "" then
		copy.Flag = self:_autoFlag(copy.Name or copy.Flag)
	end
	table.insert(sel.tab.nodes, i + 1, copy)
	self._selected = { tab = sel.tab, node = copy }
	return copy
end

function Builder:DuplicateSelectedTab()
	local sel = self._selected
	if not sel or not sel.tab then
		return nil
	end
	local proj = self:_currentProject()
	local i = indexOf(proj.tabs, sel.tab)
	if not i then
		return nil
	end
	local copy = deepCopy(sel.tab)
	for _, node in copy.nodes do
		if node.Flag and node.Flag ~= "" then
			node.Flag = self:_autoFlag(node.Name or node.Flag)
		end
	end
	table.insert(proj.tabs, i + 1, copy)
	self._selected = { tab = copy, node = nil }
	return copy
end

function Builder:Select(tab, node)
	if tab == nil then
		self._selected = nil
	else
		self._selected = { tab = tab, node = node }
	end
end

----------------------------------------------------------------
-- Project validation
----------------------------------------------------------------

function Builder:Validate()
	local problems = {}
	local function problem(msg)
		table.insert(problems, msg)
	end
	local proj = self:_currentProject()
	local seenFlags = {}
	for ti, tab in proj.tabs do
		if type(tab.Name) ~= "string" or tab.Name == "" then
			problem(("Tab %d has no name"):format(ti))
		end
		for ni, node in tab.nodes do
			local label = ("Tab %d block %d (%s)"):format(ti, ni, tostring(node.Kind))
			if node.Kind == "Section" or node.Kind == "Button" or node.Kind == "Toggle"
				or node.Kind == "Slider" or node.Kind == "Dropdown" or node.Kind == "ColorPicker"
				or node.Kind == "Keybind" or node.Kind == "Textbox" then
				if type(node.Name) ~= "string" or node.Name == "" then
					problem(label .. " has no name")
				end
			end
			if node.Kind == "Paragraph" and (type(node.Text) ~= "string" or node.Text == "") then
				problem(label .. " has no text")
			end
			if node.Flag and node.Flag ~= "" then
				if seenFlags[node.Flag] then
					problem(label .. (" reuses flag '%s'"):format(tostring(node.Flag)))
				end
				seenFlags[node.Flag] = true
			end
			if node.Kind == "Slider" then
				local min = tonumber(node.Min) or 0
				local max = tonumber(node.Max) or 0
				local inc = tonumber(node.Increment) or 1
				if max <= min then
					problem(label .. " slider Max must be greater than Min")
				end
				if inc <= 0 then
					problem(label .. " slider step size must be positive")
				end
			end
			if node.Kind == "Dropdown" then
				if #splitOptions(node.Options) == 0 then
					problem(label .. " dropdown has no options")
				end
			end
		end
	end
	if #problems == 0 then
		return true, nil
	end
	local shown = {}
	for i = 1, math.min(#problems, 5) do
		table.insert(shown, problems[i])
	end
	local extra = #problems - #shown
	local msg = table.concat(shown, "; ")
	if extra > 0 then
		msg = msg .. (" (+%d more)"):format(extra)
	end
	return false, msg
end

----------------------------------------------------------------
-- Code generation
----------------------------------------------------------------

local function emitWindowCfg(proj, L)
	table.insert(L, "local Window = Polaris:CreateWindow({")
	table.insert(L, "\tName = " .. quote(proj.window.Name) .. ",")
	if proj.window.Theme and proj.window.Theme ~= "Default" then
		table.insert(L, "\tTheme = " .. quote(proj.window.Theme) .. ",")
	end
	table.insert(L, "\tToggleKey = Enum.KeyCode.RightControl, -- hide/show the UI")
	if proj.window.SaveConfig then
		table.insert(L, "\tSaveConfig = true, -- auto-load the saved config")
		table.insert(L, "\tConfigFolder = " .. quote(proj.window.ConfigFolder or "MyHub") .. ",")
	end
	table.insert(L, "})")
	table.insert(L, "")
end

local function emitNode(varName, node, winName, L)
	local kind = node.Kind
	if kind == "Section" then
		table.insert(L, varName .. ":CreateSection({ Name = " .. quote(node.Name) .. " })")
	elseif kind == "Button" then
		table.insert(L, varName .. ":CreateButton({")
		table.insert(L, "\tName = " .. quote(node.Name) .. ",")
		table.insert(L, "\tCallback = function()")
		table.insert(L, "\t\tprint(" .. quote("[" .. tostring(winName) .. "] " .. tostring(node.Name)) .. ")")
		table.insert(L, "\tend,")
		table.insert(L, "})")
	elseif kind == "Toggle" then
		table.insert(L, varName .. ":CreateToggle({")
		table.insert(L, "\tName = " .. quote(node.Name) .. ",")
		table.insert(L, "\tDefault = " .. tostring(node.Default == true) .. ",")
		if node.Flag and node.Flag ~= "" then
			table.insert(L, "\tFlag = " .. quote(node.Flag) .. ",")
		end
		table.insert(L, "\tCallback = function(value)")
		table.insert(L, "\t\tprint(" .. quote("[" .. tostring(winName) .. "] " .. tostring(node.Name) .. ":") .. ", value)")
		table.insert(L, "\tend,")
		table.insert(L, "})")
	elseif kind == "Slider" then
		local sMin = tonumber(node.Min) or 0
		local sMax = tonumber(node.Max) or (sMin + 100)
		local sInc = tonumber(node.Increment) or 1
		if sInc <= 0 then
			sInc = 1
		end
		if sMax <= sMin then
			sMax = sMin + sInc
		end
		local sDef = tonumber(node.Default) or sMin
		if sDef < sMin then
			sDef = sMin
		end
		if sDef > sMax then
			sDef = sMax
		end
		table.insert(L, varName .. ":CreateSlider({")
		table.insert(L, "\tName = " .. quote(node.Name) .. ",")
		table.insert(L, "\tMin = " .. tostring(sMin) .. ",")
		table.insert(L, "\tMax = " .. tostring(sMax) .. ",")
		table.insert(L, "\tDefault = " .. tostring(sDef) .. ",")
		table.insert(L, "\tIncrement = " .. tostring(sInc) .. ",")
		if node.ValueName and node.ValueName ~= "" then
			table.insert(L, "\tValueName = " .. quote(node.ValueName) .. ",")
		end
		if node.Flag and node.Flag ~= "" then
			table.insert(L, "\tFlag = " .. quote(node.Flag) .. ",")
		end
		table.insert(L, "\tCallback = function(value)")
		table.insert(L, "\t\tprint(" .. quote("[" .. tostring(winName) .. "] " .. tostring(node.Name) .. ":") .. ", value)")
		table.insert(L, "\tend,")
		table.insert(L, "})")
	elseif kind == "Dropdown" then
		local opts = splitOptions(node.Options)
		local optStrs = {}
		for _, o in opts do
			table.insert(optStrs, quote(o))
		end
		table.insert(L, varName .. ":CreateDropdown({")
		table.insert(L, "\tName = " .. quote(node.Name) .. ",")
		table.insert(L, "\tOptions = { " .. table.concat(optStrs, ", ") .. " },")
		if node.Multiple then
			table.insert(L, "\tMultiple = true,")
		end
		if node.Flag and node.Flag ~= "" then
			table.insert(L, "\tFlag = " .. quote(node.Flag) .. ",")
		end
		table.insert(L, "\tCallback = function(selected)")
		table.insert(L, "\t\tprint(" .. quote("[" .. tostring(winName) .. "] " .. tostring(node.Name) .. ":") .. ", selected)")
		table.insert(L, "\tend,")
		table.insert(L, "})")
	elseif kind == "ColorPicker" then
		table.insert(L, varName .. ":CreateColorPicker({")
		table.insert(L, "\tName = " .. quote(node.Name) .. ",")
		table.insert(L, "\tDefault = Color3.fromRGB(" .. tostring(tonumber(node.R) or 0) .. ", " .. tostring(tonumber(node.G) or 0) .. ", " .. tostring(tonumber(node.B) or 0) .. "),")
		if node.Flag and node.Flag ~= "" then
			table.insert(L, "\tFlag = " .. quote(node.Flag) .. ",")
		end
		table.insert(L, "\tCallback = function(color)")
		table.insert(L, "\t\tprint(" .. quote("[" .. tostring(winName) .. "] " .. tostring(node.Name) .. ":") .. ", color)")
		table.insert(L, "\tend,")
		table.insert(L, "})")
	elseif kind == "Keybind" then
		table.insert(L, varName .. ":CreateKeybind({")
		table.insert(L, "\tName = " .. quote(node.Name) .. ",")
		local keyName = tostring(node.Key or "RightControl")
		local keyOk = pcall(function()
			return Enum.KeyCode[keyName].Name
		end)
		if keyOk then
			table.insert(L, "\tDefault = Enum.KeyCode." .. keyName .. ",")
		end
		if node.Hold then
			table.insert(L, "\tHold = true,")
		end
		if node.Flag and node.Flag ~= "" then
			table.insert(L, "\tFlag = " .. quote(node.Flag) .. ",")
		end
		table.insert(L, "\tCallback = function()")
		table.insert(L, "\t\tprint(" .. quote("[" .. tostring(winName) .. "] " .. tostring(node.Name) .. " pressed") .. ")")
		table.insert(L, "\tend,")
		table.insert(L, "})")
	elseif kind == "Textbox" then
		table.insert(L, varName .. ":CreateTextbox({")
		table.insert(L, "\tName = " .. quote(node.Name) .. ",")
		table.insert(L, "\tDefault = " .. quote(node.Default) .. ",")
		if node.TextDisappear then
			table.insert(L, "\tTextDisappear = true,")
		end
		if node.Flag and node.Flag ~= "" then
			table.insert(L, "\tFlag = " .. quote(node.Flag) .. ",")
		end
		table.insert(L, "\tCallback = function(text, enterPressed)")
		table.insert(L, "\t\tprint(" .. quote("[" .. tostring(winName) .. "] " .. tostring(node.Name) .. ":") .. ", text)")
		table.insert(L, "\tend,")
		table.insert(L, "})")
	elseif kind == "Paragraph" then
		table.insert(L, varName .. ":CreateParagraph({ Text = " .. quote(node.Text) .. " })")
	elseif kind == "Divider" then
		table.insert(L, varName .. ":CreateDivider()")
	end
	table.insert(L, "")
end

function Builder:Generate()
	local proj = self:_currentProject()
	local L = {}

	local valid, why = self:Validate()
	if not valid then
		table.insert(L, "-- WARNING: this project has problems that were auto-corrected below:")
		table.insert(L, "-- " .. tostring(why))
	end
	table.insert(L, "-- Generated with Polaris Builder")
	table.insert(L, "-- Polaris: https://github.com/HomekidChud/Polaris")
	table.insert(L, "")
	if Builder.PolarisURL and Builder.PolarisURL ~= "" then
		table.insert(L, "local Polaris = loadstring(game:HttpGet(" .. quote(Builder.PolarisURL) .. "))()")
	else
		table.insert(L, "local Polaris = ... -- Polaris library table")
	end
	table.insert(L, "")

	emitWindowCfg(proj, L)

	for i, tab in proj.tabs do
		local varName = "Tab" .. tostring(i)
		local tabCfg = "Tab" .. tostring(i) .. " = Window:CreateTab({ Name = " .. quote(tab.Name)
		if tab.Icon and tab.Icon ~= "" then
			tabCfg = tabCfg .. ", Icon = " .. quote(tab.Icon)
		end
		tabCfg = tabCfg .. " })"
		table.insert(L, "local " .. tabCfg)
		table.insert(L, "")
		for _, node in tab.nodes do
			emitNode(varName, node, proj.window.Name, L)
		end
	end

	table.insert(L, "print(" .. quote("[" .. tostring(proj.window.Name) .. "] loaded") .. ")")
	return table.concat(L, "\n")
end

----------------------------------------------------------------
-- Live preview
----------------------------------------------------------------

function Builder:_applyNode(tab, node)
	local kind = node.Kind
	if kind == "Section" then
		tab:CreateSection({ Name = node.Name })
	elseif kind == "Button" then
		tab:CreateButton({
			Name = node.Name,
			Callback = function()
				Polaris:Notify({ Title = node.Name, Content = "Button clicked", Duration = 3 })
			end,
		})
	elseif kind == "Toggle" then
		tab:CreateToggle({
			Name = node.Name,
			Default = node.Default == true,
			Flag = node.Flag ~= "" and node.Flag or nil,
			Callback = function(value)
				print("[Preview] " .. tostring(node.Name) .. ":", value)
			end,
		})
	elseif kind == "Slider" then
		tab:CreateSlider({
			Name = node.Name,
			Min = tonumber(node.Min) or 0,
			Max = tonumber(node.Max) or 100,
			Default = tonumber(node.Default) or 0,
			Increment = tonumber(node.Increment) or 1,
			ValueName = node.ValueName ~= "" and node.ValueName or nil,
			Flag = node.Flag ~= "" and node.Flag or nil,
			Callback = function(value)
				print("[Preview] " .. tostring(node.Name) .. ":", value)
			end,
		})
	elseif kind == "Dropdown" then
		tab:CreateDropdown({
			Name = node.Name,
			Options = splitOptions(node.Options),
			Multiple = node.Multiple == true,
			Flag = node.Flag ~= "" and node.Flag or nil,
			Callback = function(selected)
				print("[Preview] " .. tostring(node.Name) .. ":", selected)
			end,
		})
	elseif kind == "ColorPicker" then
		tab:CreateColorPicker({
			Name = node.Name,
			Default = Color3.fromRGB(
				tonumber(node.R) or 0,
				tonumber(node.G) or 0,
				tonumber(node.B) or 0
			),
			Flag = node.Flag ~= "" and node.Flag or nil,
			Callback = function(color)
				print("[Preview] " .. tostring(node.Name) .. ":", color)
			end,
		})
	elseif kind == "Keybind" then
		local keyName = tostring(node.Key or "RightControl")
		local keyItem = nil
		pcall(function()
			keyItem = Enum.KeyCode[keyName]
		end)
		tab:CreateKeybind({
			Name = node.Name,
			Default = keyItem,
			Hold = node.Hold == true,
			Flag = node.Flag ~= "" and node.Flag or nil,
			Callback = function()
				print("[Preview] " .. tostring(node.Name) .. " pressed")
			end,
		})
	elseif kind == "Textbox" then
		tab:CreateTextbox({
			Name = node.Name,
			Default = node.Default,
			TextDisappear = node.TextDisappear == true,
			Flag = node.Flag ~= "" and node.Flag or nil,
			Callback = function(text)
				print("[Preview] " .. tostring(node.Name) .. ":", text)
			end,
		})
	elseif kind == "Paragraph" then
		tab:CreateParagraph({ Text = node.Text })
	elseif kind == "Divider" then
		tab:CreateDivider()
	end
end

function Builder:OpenPreview()
	self:ClosePreview()
	local proj = self:_currentProject()
	local valid, why = self:Validate()
	if not valid then
		Polaris:Notify({
			Title = "Preview failed",
			Content = "Fix these first: " .. tostring(why),
			Type = "error",
			Duration = 7,
		})
		return nil
	end
	local cfg = {
		Name = tostring(proj.window.Name) .. " (preview)",
		ToggleKey = Enum.KeyCode.RightControl,
		SaveConfig = false,
	}
	if proj.window.Theme and proj.window.Theme ~= "Default" then
		cfg.Theme = proj.window.Theme
	end
	local win = Polaris:CreateWindow(cfg)
	self._previewWindow = win -- registered before building so failures can clean it up
	local ok, err = pcall(function()
		for _, tab in proj.tabs do
			local t = win:CreateTab({ Name = tab.Name })
			for _, node in tab.nodes do
				self:_applyNode(t, node)
			end
		end
	end)
	if not ok then
		self:ClosePreview()
		Polaris:Notify({
			Title = "Preview failed",
			Content = tostring(err),
			Type = "error",
			Duration = 7,
		})
		return nil
	end
	return win
end

function Builder:ClosePreview()
	if self._previewWindow and not self._previewWindow._destroyed then
		self._previewWindow:Destroy()
	end
	self._previewWindow = nil
end

----------------------------------------------------------------
-- Splash screen
----------------------------------------------------------------

function Builder:_splash(duration)
	local gui = Create("ScreenGui", { Name = "PolarisSplash" })
	local parent = getGuiParent()
	if parent then
		gui.Parent = parent
	end
	self._splashGui = gui

	local dim = Create("Frame", {
		Name = "Dim",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(9, 11, 18),
		BorderSizePixel = 0,
		Parent = gui,
	})

	-- expanding accent ring
	local ring = Create("Frame", {
		Name = "Ring",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, 24, 0, 24),
		BackgroundTransparency = 1,
		Parent = dim,
	})
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
	local stroke = Create("UIStroke", {
		Color = Color3.fromRGB(120, 130, 255),
		Thickness = 2,
		Parent = ring,
	})

	-- title + subtitle
	local title = Create("TextLabel", {
		Name = "Title",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(1, 0, 0, 60),
		BackgroundTransparency = 1,
		Text = "POLARIS",
		TextColor3 = Color3.fromRGB(235, 238, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 44,
		TextTransparency = 1,
		Parent = dim,
	})
	local sub = Create("TextLabel", {
		Name = "Sub",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.42, 40),
		Size = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text = "visual hub builder",
		TextColor3 = Color3.fromRGB(140, 148, 180),
		Font = Enum.Font.Gotham,
		TextSize = 16,
		TextTransparency = 1,
		Parent = dim,
	})

	-- progress bar
	local barBg = Create("Frame", {
		Name = "BarBg",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -60),
		Size = UDim2.new(0, 220, 0, 4),
		BackgroundColor3 = Color3.fromRGB(30, 34, 50),
		BorderSizePixel = 0,
		Parent = dim,
	})
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = barBg })
	local bar = Create("Frame", {
		Name = "Bar",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(120, 130, 255),
		BorderSizePixel = 0,
		Parent = barBg,
	})
	Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = bar })

	-- animate
	local function cancelled()
		return self._splashGui ~= gui
	end

	safeTween(ring, duration * 0.9, { Size = UDim2.new(0, 240, 0, 240) })
	safeTween(stroke, duration * 0.9, { Thickness = 8, Transparency = 1 })
	safeTween(title, duration * 0.45, { TextTransparency = 0 })
	task.wait(duration * 0.35)
	if cancelled() then
		return
	end
	safeTween(sub, duration * 0.3, { TextTransparency = 0.15 })
	safeTween(bar, duration * 0.6, { Size = UDim2.new(1, 0, 1, 0) })
	task.wait(duration * 0.6)
	if cancelled() then
		return
	end
	safeTween(dim, 0.25, { BackgroundTransparency = 1 })
	safeTween(title, 0.25, { TextTransparency = 1 })
	safeTween(sub, 0.25, { TextTransparency = 1 })
	task.wait(0.25)
	if cancelled() then
		return
	end

	if self._splashGui == gui then
		self._splashGui = nil
	end
	gui:Destroy()
end

----------------------------------------------------------------
-- Builder UI (fullscreen Scratch-style block canvas)
----------------------------------------------------------------

local function clipboardAvailable()
	return type(setclipboard) == "function"
end

local function copyText(text)
	local ok = pcall(function()
		setclipboard(text)
	end)
	return ok
end

local function saveFile(path, content)
	if not FS then
		return false
	end
	local ok = pcall(function()
		FS.mkdir("PolarisBuilder")
		FS.write(path, content)
	end)
	return ok
end

-- visual definitions for palette and canvas blocks
local BLOCK_DEFS = {
	{ Kind = "Section", Label = "Section", Color = Color3.fromRGB(120, 128, 148) },
	{ Kind = "Button", Label = "Button", Color = Color3.fromRGB(235, 145, 55) },
	{ Kind = "Toggle", Label = "Toggle", Color = Color3.fromRGB(76, 175, 110) },
	{ Kind = "Slider", Label = "Slider", Color = Color3.fromRGB(150, 105, 225) },
	{ Kind = "Dropdown", Label = "Dropdown", Color = Color3.fromRGB(38, 160, 172) },
	{ Kind = "Keybind", Label = "Keybind", Color = Color3.fromRGB(225, 90, 90) },
	{ Kind = "Textbox", Label = "Textbox", Color = Color3.fromRGB(215, 180, 70) },
	{ Kind = "ColorPicker", Label = "Color", Color = Color3.fromRGB(230, 105, 170) },
	{ Kind = "Paragraph", Label = "Paragraph", Color = Color3.fromRGB(140, 148, 170) },
	{ Kind = "Divider", Label = "Divider", Color = Color3.fromRGB(80, 86, 102) },
}

local function blockDefFor(kind)
	for _, def in BLOCK_DEFS do
		if def.Kind == kind then
			return def
		end
	end
	return { Kind = kind, Label = tostring(kind), Color = Color3.fromRGB(100, 105, 125) }
end

local DRAG_THRESHOLD = 6

function Builder:IsOpen()
	return self._gui ~= nil and not self._gui._destroyed
end

function Builder:Close()
	if self._splashGui then
		self._splashToken = (self._splashToken or 0) + 1
		pcall(function()
			self._splashGui:Destroy()
		end)
		self._splashGui = nil
	end
	if self._inputConns then
		for _, c in self._inputConns do
			pcall(function()
				c:Disconnect()
			end)
		end
		self._inputConns = nil
	end
	self._drag = nil
	if self._ghost then
		pcall(function()
			self._ghost:Destroy()
		end)
		self._ghost = nil
	end
	self:ClosePreview()
	if self._gui and not self._gui._destroyed then
		self._gui:Destroy()
	end
	self._gui = nil
end

function Builder:Open()
	if self:IsOpen() then
		return
	end
	if self._splashGui then
		return -- a splash is already running
	end
	self:_currentProject()
	local dur = tonumber(self.SplashDuration) or 0
	local token = (self._splashToken or 0) + 1
	self._splashToken = token
	if dur > 0 then
		self:_splash(dur)
	end
	if self._splashToken ~= token then
		return -- closed while the splash was playing
	end
	self:_build()
end

----------------------------------------------------------------
-- Drag and drop (works with mouse and touch)
----------------------------------------------------------------

function Builder:_beginDragGhost(input, def, labelText)
	if self._ghost then
		pcall(function()
			self._ghost:Destroy()
		end)
	end
	local ghost = Create("TextButton", {
		Name = "DragGhost",
		Position = UDim2.new(0, input.Position.X - 70, 0, input.Position.Y - 18),
		Size = UDim2.new(0, 150, 0, 38),
		BackgroundColor3 = def.Color,
		BackgroundTransparency = 0.25,
		Text = tostring(labelText),
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = false,
		Active = false,
		ZIndex = 100,
		Parent = self._gui,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = ghost })
	self._ghost = ghost
end

function Builder:_onDragInput(input)
	local drag = self._drag
	if not drag then
		return
	end
	if input.UserInputType ~= drag.inputType and input.UserInputType ~= Enum.UserInputType.MouseMovement then
		return
	end
	local dx = input.Position.X - drag.startX
	local dy = input.Position.Y - drag.startY
	if not drag.dragging then
		if math.abs(dx) < DRAG_THRESHOLD and math.abs(dy) < DRAG_THRESHOLD then
			return
		end
		drag.dragging = true
		local def = blockDefFor(drag.defKind)
		self:_beginDragGhost(input, def, drag.label)
		if self._canvas then
			pcall(function()
				self._canvas.ScrollingEnabled = false
			end)
		end
		if drag.frame then
			pcall(function()
				drag.frame.BackgroundTransparency = 0.6
			end)
		end
	end
	if self._ghost then
		self._ghost.Position = UDim2.new(0, input.Position.X - 70, 0, input.Position.Y - 18)
	end
end

function Builder:_pointIn(inst, x, y)
	local ok, inside = pcall(function()
		local pos = inst.AbsolutePosition
		local size = inst.AbsoluteSize
		return x >= pos.X and x <= pos.X + size.X and y >= pos.Y and y <= pos.Y + size.Y
	end)
	return ok and inside == true
end

function Builder:_moveNode(node, toTab, index)
	local proj = self:_currentProject()
	local fromTab = nil
	local removedAt = nil
	for _, tab in proj.tabs do
		local i = indexOf(tab.nodes, node)
		if i then
			fromTab = tab
			removedAt = i
			table.remove(tab.nodes, i)
			break
		end
	end
	if not fromTab then
		return false
	end
	if toTab then
		local idx = index
		if fromTab == toTab and removedAt and removedAt < idx then
			idx = idx - 1
		end
		if idx < 1 then
			idx = 1
		end
		if idx > #toTab.nodes + 1 then
			idx = #toTab.nodes + 1
		end
		table.insert(toTab.nodes, idx, node)
		self._selected = { tab = toTab, node = node }
	end
	return true
end

function Builder:_onDragEnd(input)
	local drag = self._drag
	self._drag = nil
	if not drag then
		return
	end
	if self._ghost then
		pcall(function()
			self._ghost:Destroy()
		end)
		self._ghost = nil
	end
	if self._canvas then
		pcall(function()
			self._canvas.ScrollingEnabled = true
		end)
	end
	if drag.frame then
		pcall(function()
			drag.frame.BackgroundTransparency = 0
		end)
	end
	if not drag.dragging then
		-- a simple tap
		if drag.onTap then
			drag.onTap()
		else
			self._selected = drag.selection
			self:_refreshCanvas()
			self:_refreshProperties()
		end
		return
	end
	-- dropped somewhere: work out the target column
	local x = input.Position.X
	local y = input.Position.Y
	-- dropping a block back onto the palette deletes it (Scratch-style)
	if self._palette and self:_pointIn(self._palette, x, y) then
		if drag.data and drag.data.node then
			self:Select(drag.data.tab, drag.data.node)
			self:DeleteSelected()
		end
		self:_refreshAll()
		return
	end
	local targetTab = nil
	local targetIndex = nil
	for _, col in self._columns do
		if self:_pointIn(col.frame, x, y) then
			targetTab = col.tab
			targetIndex = #targetTab.nodes + 1
			for i, bf in col.blockFrames do
				local ok, cy = pcall(function()
					local pos = bf.AbsolutePosition
					local size = bf.AbsoluteSize
					return pos.Y + size.Y * 0.5
				end)
				if ok and y < cy then
					targetIndex = i
					break
				end
			end
			break
		end
	end
	if targetTab == nil then
		-- dropped in empty space: keep the current selection
		if drag.selection then
			self._selected = drag.selection
		end
		self:_refreshAll()
		return
	end
	if drag.data and drag.data.node then
		self:_moveNode(drag.data.node, targetTab, targetIndex)
	elseif drag.paletteKind then
		local node = newBlock(drag.paletteKind, function(base)
			return self:_autoFlag(base)
		end)
		if node then
			table.insert(targetTab.nodes, targetIndex, node)
			self._selected = { tab = targetTab, node = node }
		end
	end
	self:_refreshAll()
end

----------------------------------------------------------------
-- Fullscreen editor
----------------------------------------------------------------

function Builder:_build()
	self._columns = {}
	self._inputConns = {}
	self._drag = nil
	self._ghost = nil
	self._propRows = {}

	local gui = Create("ScreenGui", { Name = "PolarisBuilder", IgnoreGuiInset = true })
	local parent = getGuiParent()
	if parent then
		gui.Parent = parent
	end
	self._gui = gui

	local root = Create("Frame", {
		Name = "Root",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(15, 17, 24),
		BorderSizePixel = 0,
		Parent = gui,
	})

	------------------------------------------------------------
	-- Top bar
	------------------------------------------------------------
	local topBar = Create("Frame", {
		Name = "TopBar",
		Size = UDim2.new(1, 0, 0, 52),
		BackgroundColor3 = Color3.fromRGB(21, 24, 34),
		BorderSizePixel = 0,
		Parent = root,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		HorizontalAlignment = Enum.HorizontalAlignment.Right,
		VerticalAlignment = Enum.VerticalAlignment.Center,
		Padding = UDim.new(0, 6),
		Parent = topBar,
	})
	Create("UIPadding", {
		PaddingRight = UDim.new(0, 10),
		Parent = topBar,
	})

	Create("TextLabel", {
		Name = "Logo",
		Position = UDim2.new(0, 12, 0, 0),
		Size = UDim2.new(0, 170, 1, 0),
		BackgroundTransparency = 1,
		Text = "POLARIS BUILDER",
		TextColor3 = Color3.fromRGB(120, 130, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = topBar,
	})

	self._hubNameBox = Create("TextBox", {
		Name = "HubName",
		Position = UDim2.new(0, 190, 0, 9),
		Size = UDim2.new(0, 180, 0, 34),
		BackgroundColor3 = Color3.fromRGB(30, 34, 48),
		Text = tostring(self._project.window.Name),
		TextColor3 = Color3.fromRGB(235, 238, 255),
		PlaceholderText = "Hub name",
		Font = Enum.Font.Gotham,
		TextSize = 14,
		ClearTextOnFocus = false,
		Parent = topBar,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = self._hubNameBox })
	self._hubNameBox:GetPropertyChangedSignal("Text"):Connect(function()
		self._project.window.Name = tostring(self._hubNameBox.Text)
		self:_refreshExport()
	end)

	local function topButton(text, width, color)
		local b = Create("TextButton", {
			Size = UDim2.new(0, width, 0, 34),
			BackgroundColor3 = color or Color3.fromRGB(38, 43, 62),
			Text = text,
			TextColor3 = Color3.fromRGB(235, 238, 255),
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			AutoButtonColor = true,
			Parent = topBar,
		})
		Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = b })
		return b
	end

	local addTabBtn = topButton("+ Tab", 80, Color3.fromRGB(66, 133, 244))
	addTabBtn.Activated:Connect(function()
		self:AddTab("Tab" .. tostring(#self._project.tabs + 1))
		self:_refreshAll()
	end)
	local previewBtn = topButton("Preview", 92, Color3.fromRGB(76, 175, 110))
	previewBtn.Activated:Connect(function()
		self:OpenPreview()
	end)
	local exportBtn = topButton("Export", 92, Color3.fromRGB(120, 130, 255))
	exportBtn.Activated:Connect(function()
		self:_openExportPanel()
	end)
	local newBtn = topButton("New", 64)
	newBtn.Activated:Connect(function()
		self:NewProject()
		self:_refreshAll()
		Polaris:Notify({ Title = "Polaris Builder", Content = "Started a new project", Duration = 3 })
	end)
	local closeBtn = topButton("X", 34, Color3.fromRGB(225, 90, 90))
	closeBtn.Activated:Connect(function()
		self:Close()
	end)

	------------------------------------------------------------
	-- Palette (left)
	------------------------------------------------------------
	local palette = Create("ScrollingFrame", {
		Name = "Palette",
		Position = UDim2.new(0, 0, 0, 58),
		Size = UDim2.new(0, 150, 1, -58),
		BackgroundColor3 = Color3.fromRGB(20, 23, 32),
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 3,
		Parent = root,
	})
	self._palette = palette
	Create("UIListLayout", { Padding = UDim.new(0, 6), Parent = palette })
	Create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = palette,
	})

	Create("TextLabel", {
		Size = UDim2.new(1, -8, 0, 20),
		BackgroundTransparency = 1,
		Text = "BLOCKS",
		TextColor3 = Color3.fromRGB(140, 148, 180),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		Parent = palette,
	})

	self._paletteButtons = {}
	for _, def in BLOCK_DEFS do
		local chip = Create("TextButton", {
			Size = UDim2.new(1, -8, 0, 38),
			BackgroundColor3 = def.Color,
			Text = def.Label,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBold,
			TextSize = 13,
			AutoButtonColor = true,
			Parent = palette,
		})
		Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = chip })
		table.insert(self._paletteButtons, chip)
		chip.InputBegan:Connect(function(input)
			if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
				return
			end
			self._drag = {
				inputType = input.UserInputType,
				startX = input.Position.X,
				startY = input.Position.Y,
				paletteKind = def.Kind,
				defKind = def.Kind,
				label = def.Label,
				onTap = function()
					-- tap: add to the selected tab (or the last one)
					local tab = self:_selectedTab()
					if not tab then
						tab = self:AddTab("Main")
					end
					local node = newBlock(def.Kind, function(base)
						return self:_autoFlag(base)
					end)
					if node then
						table.insert(tab.nodes, node)
						self._selected = { tab = tab, node = node }
					end
					self:_refreshAll()
				end,
			}
		end)
	end

	------------------------------------------------------------
	-- Canvas (center) - one column per tab, blocks stacked inside
	------------------------------------------------------------
	self._canvas = Create("ScrollingFrame", {
		Name = "Canvas",
		Position = UDim2.new(0, 158, 0, 58),
		Size = UDim2.new(1, -158 - 240, 1, -58),
		BackgroundColor3 = Color3.fromRGB(13, 15, 22),
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 4,
		Parent = root,
	})
	Create("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 10),
		VerticalAlignment = Enum.VerticalAlignment.Top,
		Parent = self._canvas,
	})

	------------------------------------------------------------
	-- Properties (right)
	------------------------------------------------------------
	local props = Create("ScrollingFrame", {
		Name = "Properties",
		Position = UDim2.new(1, -236, 0, 58),
		Size = UDim2.new(0, 236, 1, -58),
		BackgroundColor3 = Color3.fromRGB(20, 23, 32),
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 3,
		Parent = root,
	})
	self._propList = props
	Create("UIListLayout", { Padding = UDim.new(0, 6), Parent = props })
	Create("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
		Parent = props,
	})

	------------------------------------------------------------
	-- Global drag input tracking (mouse + touch)
	------------------------------------------------------------
	table.insert(self._inputConns, UserInputService.InputChanged:Connect(function(input)
		self:_onDragInput(input)
	end))
	table.insert(self._inputConns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self:_onDragEnd(input)
		end
	end))

	self:_refreshAll()
end

----------------------------------------------------------------
-- Canvas rendering
----------------------------------------------------------------

function Builder:_refreshCanvas()
	if not self._canvas or self._canvas._destroyed then
		return
	end
	for _, col in self._columns do
		if not col.frame._destroyed then
			col.frame:Destroy()
		end
	end
	self._columns = {}

	local proj = self:_currentProject()
	local sel = self._selected
	local totalHeight = 100

	for _, tab in proj.tabs do
		local isSelTab = sel and sel.tab == tab and sel.node == nil
		local col = Create("Frame", {
			Name = "Column",
			Size = UDim2.new(0, 190, 0, 40 + #tab.nodes * 48 + 10),
			BackgroundColor3 = Color3.fromRGB(24, 27, 39),
			BorderSizePixel = 0,
			Parent = self._canvas,
		})
		Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = col })
		Create("UIStroke", {
			Color = isSelTab and Color3.fromRGB(120, 130, 255) or Color3.fromRGB(38, 43, 60),
			Thickness = isSelTab and 2 or 1,
			Parent = col,
		})
		local header = Create("TextButton", {
			Name = "Header",
			Position = UDim2.new(0, 8, 0, 6),
			Size = UDim2.new(1, -16, 0, 26),
			BackgroundTransparency = 1,
			Text = tostring(tab.Name),
			TextColor3 = Color3.fromRGB(200, 206, 230),
			Font = Enum.Font.GothamBold,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = col,
		})
		local colEntry = { frame = col, tab = tab, blockFrames = {} }
		header.Activated:Connect(function()
			self._selected = { tab = tab, node = nil }
			self:_refreshCanvas()
			self:_refreshProperties()
		end)
		local y = 38
		for _, node in tab.nodes do
			local def = blockDefFor(node.Kind)
			local isSel = sel and sel.node == node
			local bf = Create("TextButton", {
				Name = "Block",
				Position = UDim2.new(0, 8, 0, y),
				Size = UDim2.new(1, -16, 0, 42),
				BackgroundColor3 = def.Color,
				BackgroundTransparency = 0.15,
				Text = "",
				AutoButtonColor = false,
				Parent = col,
			})
			if isSel then
				bf.BackgroundTransparency = 0
			end
			Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = bf })
			Create("UIStroke", {
				Color = isSel and Color3.fromRGB(255, 255, 255) or def.Color,
				Thickness = isSel and 2 or 0,
				Parent = bf,
			})
			Create("TextLabel", {
				Name = "Kind",
				Position = UDim2.new(0, 10, 0, 4),
				Size = UDim2.new(1, -20, 0, 12),
				BackgroundTransparency = 1,
				Text = def.Label,
				TextColor3 = Color3.fromRGB(255, 255, 255),
				TextTransparency = 0.35,
				Font = Enum.Font.GothamBold,
				TextSize = 10,
				TextXAlignment = Enum.TextXAlignment.Left,
				Parent = bf,
			})
			Create("TextLabel", {
				Name = "Name",
				Position = UDim2.new(0, 10, 0, 17),
				Size = UDim2.new(1, -20, 0, 18),
				BackgroundTransparency = 1,
				Text = tostring(node.Name or node.Text or ""),
				TextColor3 = Color3.fromRGB(255, 255, 255),
				Font = Enum.Font.GothamBold,
				TextSize = 13,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextTruncate = Enum.TextTruncate.AtEnd,
				Parent = bf,
			})
			bf.InputBegan:Connect(function(input)
				if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then
					return
				end
				self._drag = {
					inputType = input.UserInputType,
					startX = input.Position.X,
					startY = input.Position.Y,
					frame = bf,
					defKind = node.Kind,
					label = def.Label,
					data = { tab = tab, node = node },
					selection = { tab = tab, node = node },
				}
			end)
			table.insert(colEntry.blockFrames, bf)
			y = y + 48
		end
		local colH = 40 + #tab.nodes * 48 + 20
		if colH > totalHeight then
			totalHeight = colH
		end
		table.insert(self._columns, colEntry)
	end

	-- trailing "+ Tab" button
	local addCol = Create("TextButton", {
		Name = "AddTab",
		Size = UDim2.new(0, 190, 0, 42),
		BackgroundTransparency = 1,
		Text = "+ Tab",
		TextColor3 = Color3.fromRGB(140, 148, 180),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		Parent = self._canvas,
	})
	addCol.Activated:Connect(function()
		self:AddTab("Tab" .. tostring(#self._project.tabs + 1))
		self:_refreshAll()
	end)

	self._canvas.CanvasSize = UDim2.new(0, 10 + (#proj.tabs + 1) * 200, 0, totalHeight)
end

----------------------------------------------------------------
-- Properties panel
----------------------------------------------------------------

local function propRow(b, height)
	local row = Create("Frame", {
		Size = UDim2.new(1, -6, 0, height or 34),
		BackgroundColor3 = Color3.fromRGB(28, 32, 46),
		BorderSizePixel = 0,
		Parent = b._propList,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = row })
	table.insert(b._propRows, row)
	return row
end

local function propHeader(b, text)
	local row = propRow(b, 26)
	Create("TextLabel", {
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(1, -16, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(120, 130, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
end

local function propLabel(row, text)
	Create("TextLabel", {
		Position = UDim2.new(0, 8, 0, 0),
		Size = UDim2.new(0, 82, 1, 0),
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = Color3.fromRGB(170, 176, 200),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})
end

local function propTextbox(b, label, value, onChange)
	local row = propRow(b, 34)
	propLabel(row, label)
	local tb = Create("TextBox", {
		Position = UDim2.new(1, -102, 0, 5),
		Size = UDim2.new(0, 96, 0, 24),
		BackgroundColor3 = Color3.fromRGB(18, 20, 30),
		Text = tostring(value),
		TextColor3 = Color3.fromRGB(235, 238, 255),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		ClearTextOnFocus = false,
		Parent = row,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = tb })
	tb.FocusLost:Connect(function()
		onChange(tostring(tb.Text))
	end)
	return tb
end

local function propToggle(b, label, value, onChange)
	local row = propRow(b, 34)
	propLabel(row, label)
	local btn = Create("TextButton", {
		Position = UDim2.new(1, -102, 0, 5),
		Size = UDim2.new(0, 96, 0, 24),
		BackgroundColor3 = value and Color3.fromRGB(76, 175, 110) or Color3.fromRGB(58, 64, 86),
		Text = value and "ON" or "OFF",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		AutoButtonColor = true,
		Parent = row,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = btn })
	local state = value == true
	btn.Activated:Connect(function()
		state = not state
		btn.BackgroundColor3 = state and Color3.fromRGB(76, 175, 110) or Color3.fromRGB(58, 64, 86)
		btn.Text = state and "ON" or "OFF"
		onChange(state)
	end)
	return btn
end

local function propCycle(b, label, options, currentIndex, onChange)
	local row = propRow(b, 34)
	propLabel(row, label)
	local idx = currentIndex or 1
	if idx < 1 then
		idx = 1
	end
	if idx > #options then
		idx = #options
	end
	local btn = Create("TextButton", {
		Position = UDim2.new(1, -102, 0, 5),
		Size = UDim2.new(0, 96, 0, 24),
		BackgroundColor3 = Color3.fromRGB(38, 43, 62),
		Text = tostring(options[idx]),
		TextColor3 = Color3.fromRGB(235, 238, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		AutoButtonColor = true,
		Parent = row,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = btn })
	btn.Activated:Connect(function()
		idx = idx % #options + 1
		btn.Text = tostring(options[idx])
		onChange(options[idx])
	end)
	return btn
end

local function propButton(b, label, color, onClick)
	local row = propRow(b, 34)
	local btn = Create("TextButton", {
		Position = UDim2.new(0, 6, 0, 4),
		Size = UDim2.new(1, -12, 0, 26),
		BackgroundColor3 = color or Color3.fromRGB(38, 43, 62),
		Text = label,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		AutoButtonColor = true,
		Parent = row,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = btn })
	btn.Activated:Connect(onClick)
	return btn
end

function Builder:_refreshProperties()
	if not self._propList or self._propList._destroyed then
		return
	end
	for _, row in self._propRows do
		if not row._destroyed then
			row:Destroy()
		end
	end
	self._propRows = {}

	local proj = self:_currentProject()
	local sel = self._selected
	local b = self

	local function nameBox(node)
		propTextbox(b, "Name", node.Name, function(text)
			node.Name = tostring(text)
			b:_refreshCanvas()
			b:_refreshExport()
		end)
	end
	local function flagBox(node)
		propTextbox(b, "Flag", node.Flag or "", function(text)
			node.Flag = tostring(text)
			b:_refreshExport()
		end)
	end
	local function numberBox(label, node, key)
		propTextbox(b, label, tostring(node[key] or 0), function(text)
			local n = tonumber(tostring(text))
			if n then
				node[key] = n
				b:_refreshExport()
			end
		end)
	end

	if not sel or not sel.tab or not indexOf(proj.tabs, sel.tab) then
		-- window properties
		propHeader(b, "Window")
		propTextbox(b, "Hub name", proj.window.Name, function(text)
			proj.window.Name = tostring(text)
			if b._hubNameBox and not b._hubNameBox._destroyed then
				b._hubNameBox.Text = tostring(text)
			end
			b:_refreshExport()
		end)
		local themeNames = Polaris:GetThemeNames()
		local themeIdx = 1
		for i, name in themeNames do
			if name == proj.window.Theme then
				themeIdx = i
			end
		end
		propCycle(b, "Theme", themeNames, themeIdx, function(name)
			proj.window.Theme = tostring(name)
			b:_refreshExport()
		end)
		propTextbox(b, "Folder", proj.window.ConfigFolder, function(text)
			proj.window.ConfigFolder = tostring(text)
			b:_refreshExport()
		end)
		propToggle(b, "Save config", proj.window.SaveConfig, function(v)
			proj.window.SaveConfig = v
			b:_refreshExport()
		end)
		propHeader(b, "Tip")
		propTextbox(b, "Hint", "Tap a block on the left to add it, then drag blocks to arrange. Drag a block onto the palette to delete it.", function() end)
		return
	end

	local node = sel.node
	if node == nil then
		propHeader(b, "Tab")
		propTextbox(b, "Name", sel.tab.Name, function(text)
			sel.tab.Name = tostring(text)
			b:_refreshCanvas()
			b:_refreshExport()
		end)
		propTextbox(b, "Icon", sel.tab.Icon or "", function(text)
			sel.tab.Icon = tostring(text)
			b:_refreshExport()
		end)
		propButton(b, "Duplicate tab", Color3.fromRGB(66, 133, 244), function()
			if b:DuplicateSelectedTab() then
				b:_refreshAll()
			end
		end)
		propButton(b, "Delete tab", Color3.fromRGB(225, 90, 90), function()
			if b:DeleteSelected() then
				b:_refreshAll()
			end
		end)
		return
	end

	local kind = node.Kind
	propHeader(b, kind)

	if kind == "Section" or kind == "Button" then
		nameBox(node)
	elseif kind == "Toggle" then
		nameBox(node)
		propToggle(b, "Default", node.Default == true, function(v)
			node.Default = v
			b:_refreshExport()
		end)
		flagBox(node)
	elseif kind == "Slider" then
		nameBox(node)
		numberBox("Min", node, "Min")
		numberBox("Max", node, "Max")
		numberBox("Default", node, "Default")
		numberBox("Step", node, "Increment")
		propTextbox(b, "Suffix", node.ValueName or "", function(text)
			node.ValueName = tostring(text)
			b:_refreshExport()
		end)
		flagBox(node)
	elseif kind == "Dropdown" then
		nameBox(node)
		propTextbox(b, "Options", node.Options, function(text)
			node.Options = tostring(text)
			b:_refreshExport()
		end)
		propToggle(b, "Multi", node.Multiple == true, function(v)
			node.Multiple = v
			b:_refreshExport()
		end)
		flagBox(node)
	elseif kind == "ColorPicker" then
		nameBox(node)
		numberBox("Red", node, "R")
		numberBox("Green", node, "G")
		numberBox("Blue", node, "B")
		flagBox(node)
	elseif kind == "Keybind" then
		nameBox(node)
		local keyIdx = 1
		for i, k in KEY_OPTIONS do
			if k == tostring(node.Key) then
				keyIdx = i
			end
		end
		propCycle(b, "Key", KEY_OPTIONS, keyIdx, function(k)
			node.Key = tostring(k)
			b:_refreshExport()
		end)
		propToggle(b, "Hold", node.Hold == true, function(v)
			node.Hold = v
			b:_refreshExport()
		end)
		flagBox(node)
	elseif kind == "Textbox" then
		nameBox(node)
		propTextbox(b, "Default", node.Default, function(text)
			node.Default = tostring(text)
			b:_refreshExport()
		end)
		propToggle(b, "Ghost text", node.TextDisappear == true, function(v)
			node.TextDisappear = v
			b:_refreshExport()
		end)
		flagBox(node)
	elseif kind == "Paragraph" then
		propTextbox(b, "Text", node.Text, function(text)
			node.Text = tostring(text)
			b:_refreshCanvas()
			b:_refreshExport()
		end)
	end

	propButton(b, "Duplicate", Color3.fromRGB(66, 133, 244), function()
		if b:DuplicateSelected() then
			b:_refreshAll()
		end
	end)
	propButton(b, "Delete", Color3.fromRGB(225, 90, 90), function()
		if b:DeleteSelected() then
			b:_refreshAll()
		end
	end)
end

----------------------------------------------------------------
-- Export panel
----------------------------------------------------------------

function Builder:_openExportPanel()
	if self._exportOverlay and not self._exportOverlay._destroyed then
		self._exportOverlay.Visible = true
		self:_refreshExport()
		return
	end

	local overlay = Create("TextButton", {
		Name = "ExportOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 50,
		Parent = self._gui,
	})
	self._exportOverlay = overlay
	overlay.Activated:Connect(function()
		overlay.Visible = false
	end)

	local panel = Create("Frame", {
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.9, 0, 0, 480),
		BackgroundColor3 = Color3.fromRGB(24, 27, 39),
		BorderSizePixel = 0,
		Active = true,
		ZIndex = 51,
		Parent = overlay,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = panel })
	Create("UISizeConstraint", { MaxSize = Vector2.new(620, 480), Parent = panel })

	Create("TextLabel", {
		Position = UDim2.new(0, 14, 0, 10),
		Size = UDim2.new(1, -70, 0, 22),
		BackgroundTransparency = 1,
		Text = "Export",
		TextColor3 = Color3.fromRGB(235, 238, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})
	local closeBtn = Create("TextButton", {
		Position = UDim2.new(1, -40, 0, 8),
		Size = UDim2.new(0, 30, 0, 26),
		BackgroundColor3 = Color3.fromRGB(225, 90, 90),
		Text = "X",
		TextColor3 = Color3.fromRGB(255, 255, 255),
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		AutoButtonColor = true,
		ZIndex = 52,
		Parent = panel,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = closeBtn })
	closeBtn.Activated:Connect(function()
		overlay.Visible = false
	end)

	local codeScroll = Create("ScrollingFrame", {
		Position = UDim2.new(0, 14, 0, 40),
		Size = UDim2.new(1, -28, 0, 180),
		BackgroundColor3 = Color3.fromRGB(16, 18, 26),
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 3,
		ZIndex = 52,
		Parent = panel,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = codeScroll })
	self._codeLabel = Create("TextLabel", {
		Size = UDim2.new(1, -12, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(190, 200, 225),
		Font = Enum.Font.Code,
		TextSize = 12,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 52,
		Parent = codeScroll,
	})

	local function panelButton(text, yPos, color)
		local btn = Create("TextButton", {
			Position = UDim2.new(0, 14, 0, yPos),
			Size = UDim2.new(0, 150, 0, 30),
			BackgroundColor3 = color or Color3.fromRGB(38, 43, 62),
			Text = text,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			Font = Enum.Font.GothamBold,
			TextSize = 12,
			AutoButtonColor = true,
			ZIndex = 52,
			Parent = panel,
		})
		Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = btn })
		return btn
	end

	local copyBtn = panelButton("Copy code", 228, Color3.fromRGB(66, 133, 244))
	copyBtn.Activated:Connect(function()
		local code = self:Generate()
		if clipboardAvailable() and copyText(code) then
			Polaris:Notify({ Title = "Polaris Builder", Content = "Code copied to clipboard", Type = "success", Duration = 3 })
		else
			Polaris:Notify({ Title = "Polaris Builder", Content = "Clipboard not available - the code is shown above", Type = "warning", Duration = 5 })
		end
	end)
	local saveBtn = panelButton("Save .luau file", 228)
	saveBtn.Position = UDim2.new(0, 174, 0, 228)
	saveBtn.Activated:Connect(function()
		local code = self:Generate()
		local name = slugify(self._project.window.Name)
		local path = "PolarisBuilder/" .. name .. ".luau"
		if saveFile(path, code) then
			Polaris:Notify({ Title = "Polaris Builder", Content = "Saved to " .. path, Type = "success", Duration = 4 })
		else
			Polaris:Notify({ Title = "Polaris Builder", Content = "Saving files is not available here (executor only)", Type = "warning", Duration = 4 })
		end
	end)

	local jsonScroll = Create("ScrollingFrame", {
		Position = UDim2.new(0, 14, 0, 268),
		Size = UDim2.new(1, -28, 0, 90),
		BackgroundColor3 = Color3.fromRGB(16, 18, 26),
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 3,
		ZIndex = 52,
		Parent = panel,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = jsonScroll })
	self._jsonLabel = Create("TextLabel", {
		Size = UDim2.new(1, -12, 0, 0),
		BackgroundTransparency = 1,
		Text = "",
		TextColor3 = Color3.fromRGB(150, 158, 185),
		Font = Enum.Font.Code,
		TextSize = 11,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 52,
		Parent = jsonScroll,
	})

	local copyJsonBtn = panelButton("Copy project JSON", 366, Color3.fromRGB(120, 130, 255))
	copyJsonBtn.Activated:Connect(function()
		local json = self:ExportJSON()
		if clipboardAvailable() and copyText(json) then
			Polaris:Notify({ Title = "Polaris Builder", Content = "Project JSON copied to clipboard", Type = "success", Duration = 3 })
		else
			Polaris:Notify({ Title = "Polaris Builder", Content = "Clipboard not available - JSON is shown above", Type = "warning", Duration = 5 })
		end
	end)

	local importBox = Create("TextBox", {
		Position = UDim2.new(0, 14, 0, 404),
		Size = UDim2.new(1, -28, 0, 34),
		BackgroundColor3 = Color3.fromRGB(16, 18, 26),
		Text = "",
		PlaceholderText = "Paste project JSON here, then press Load",
		TextColor3 = Color3.fromRGB(235, 238, 255),
		PlaceholderColor3 = Color3.fromRGB(120, 126, 150),
		Font = Enum.Font.Gotham,
		TextSize = 12,
		ClearTextOnFocus = false,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 52,
		Parent = panel,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = importBox })
	local loadBtn = panelButton("Load JSON", 444, Color3.fromRGB(76, 175, 110))
	loadBtn.Size = UDim2.new(0, 150, 0, 28)
	loadBtn.Activated:Connect(function()
		local ok, err = pcall(function()
			self:ImportJSON(tostring(importBox.Text))
		end)
		if ok then
			self:_refreshAll()
			Polaris:Notify({ Title = "Polaris Builder", Content = "Project imported", Type = "success", Duration = 3 })
		else
			Polaris:Notify({ Title = "Polaris Builder", Content = "Import failed: " .. tostring(err), Type = "error", Duration = 6 })
		end
	end)

	self:_refreshExport()
end

----------------------------------------------------------------
-- Refresh helpers
----------------------------------------------------------------

function Builder:_refreshExport()
	if self._codeLabel and not self._codeLabel._destroyed then
		self._codeLabel.Text = self:Generate()
	end
	if self._jsonLabel and not self._jsonLabel._destroyed then
		self._jsonLabel.Text = self:ExportJSON()
	end
end

function Builder:_refreshAll()
	if self._hubNameBox and not self._hubNameBox._destroyed then
		self._hubNameBox.Text = tostring(self._project.window.Name)
	end
	self:_refreshCanvas()
	self:_refreshProperties()
	self:_refreshExport()
end


return Polaris
