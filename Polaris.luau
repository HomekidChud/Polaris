--[[
	Polaris UI Library v1.0.0
	--------------------------
	A modern, single-file UI library for Roblox Luau.

	Highlights over Orion:
	  - No :Init() needed - everything works the moment you create it
	  - Every element has :Get(), :Set(value, silent?), :SetVisible(), :SetDisabled(), :Destroy()
	  - Live theme switching + fully custom themes
	  - Search bar to filter elements
	  - Multi-select dropdowns
	  - Resizable + minimizable windows, toggle keybind
	  - Config save/load + JSON export/import (gracefully falls back when no filesystem exists)
	  - Duplicate-flag detection, slider clamping, clear error messages
	  - Touch support and clean teardown (no leaked connections)

	Usage (executor):
		local Polaris = loadstring(game:HttpGet("https://raw.githubusercontent.com/YOURNAME/YOURREPO/main/Polaris.luau"))()
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

local PolarisVersion = "1.0.0"

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

return Polaris
