-- elements: Label, Progress, Console, ButtonRow, Stats + Window:Dialog / AddSettingsTab / helpers

local Create, themed, safeTween, Element, Tab, Window = I.Create, I.themed, I.safeTween, I.Element, I.Tab, I.Window
local Kit = Polaris.Kit
local svc = Polaris.Util.svc

local function newClass()
	local C = setmetatable({}, { __index = Element })
	C.__index = C
	return C
end

-- Shared scaffold: an element whose container is a plain Frame of a given height.
local function scaffold(Class, window, tab, config, className, height)
	local self = Element._new(window, tab, config, className)
	setmetatable(self, Class)
	local row = Create("Frame", {
		Name = className,
		Size = UDim2.new(1, 0, 0, height),
		BackgroundTransparency = 1,
		Parent = tab._content,
	})
	self._container = row
	tab:_updateCanvas()
	return self, row
end

local function setHeight(self, h)
	if self._container then
		self._container.Size = UDim2.new(1, 0, 0, h)
		self._tab:_updateCanvas()
	end
end
Polaris._setHeight = setHeight

-- Make a container fill the visible page height (re-measured when the window resizes).
local function bindFill(self, minHeight, margin)
	local page = self._tab._content
	local function apply()
		local h = page.AbsoluteSize and page.AbsoluteSize.Y or 0
		if h and h > 0 and self._container then
			setHeight(self, math.max(minHeight, h - (margin or 8)))
		end
	end
	apply()
	self:_track(page:GetPropertyChangedSignal("AbsoluteSize"):Connect(apply))
end
Polaris._bindFill = bindFill
Polaris._scaffold = scaffold
Polaris._newClass = newClass

----------------------------------------------------------------
-- Label: headings, notes, status lines (supports RichText)
----------------------------------------------------------------

local Label = newClass()

function Label:_create(window, tab, config)
	local self, row = scaffold(Label, window, tab, config, "Label", 24)
	local size = config.Size or 14
	local text = Kit.label(row, config.Text or config.Name or "", {
		Size = size,
		Color = config.Color or "Text",
		Bold = config.Bold,
		Align = config.Align or "Left",
		Wrap = true,
		Rich = config.Rich == true,
		Auto = true,
		Height = size + 8,
		Width = 1,
		WidthOffset = -16,
		Position = UDim2.new(0, 8, 0, 0),
	})
	self._text = text
	self._value = tostring(config.Text or config.Name or "")
	self:_sync()
	self:_track(text:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		self:_sync(true)
	end))
	return self
end

function Label:_sync(measured)
	local size = self._config.Size or 14
	local h
	if measured and self._text.AbsoluteSize and self._text.AbsoluteSize.Y > 0 then
		h = self._text.AbsoluteSize.Y + 6
	else
		local perLine = math.max(8, math.floor(460 / (size * 0.62)))
		local lines = math.max(1, math.ceil(#self._value / perLine))
		h = lines * (size + 4) + 6
	end
	if self._container and math.abs(self._container.Size.Y.Offset - h) > 1 then
		setHeight(self, h)
	end
end

function Label:_setValue(v)
	self._value = tostring(v)
	if self._text then
		self._text.Text = self._value
		self:_sync()
	end
end

function Label:SetText(t)
	self:Set(t, true)
end

function Label:SetColor(color)
	if self._text then
		Kit.paint(self._text, "TextColor3", color)
	end
end

function Tab:CreateLabel(config)
	if type(config) == "string" then
		config = { Text = config }
	end
	return Label:_create(self._window, self, config)
end

-- Convenience: big heading
function Tab:CreateHeading(text, size)
	return self:CreateLabel({ Text = text, Size = size or 22, Bold = true })
end

----------------------------------------------------------------
-- Progress bar
----------------------------------------------------------------

local Progress = newClass()

function Progress:_create(window, tab, config)
	local self, row = scaffold(Progress, window, tab, config, "Progress", 44)
	self._max = config.Max or 1
	self._name = tostring(config.Name or "Progress")
	self._label = nil -- progress bars are not part of search filtering
	local title = Kit.label(row, self._name, { Size = 14, Position = UDim2.new(0, 8, 0, 2), WidthOffset = -90, Width = 1 })
	self._title = title
	self._pct = Kit.label(row, "0%", { Size = 13, Color = "SubText", Align = "Right", Width = 0, WidthOffset = 70, Position = UDim2.new(1, -78, 0, 2) })
	local track = Kit.frame(row, { Color = "Secondary", Radius = 4, Size = UDim2.new(1, -16, 0, 10), Position = UDim2.new(0, 8, 0, 28), Stroke = true })
	local fill = Kit.frame(track, { Color = config.Color or "Accent", Radius = 4, Size = UDim2.new(0, 0, 1, 0) })
	self._fill = fill
	self._value = 0
	self:_setValue(config.Value or config.Default or 0)
	return self
end

function Progress:_setValue(v)
	v = tonumber(v) or 0
	local frac = math.clamp(v / self._max, 0, 1)
	self._value = v
	if self._fill then
		safeTween(self._fill, 0.2, { Size = UDim2.new(frac, 0, 1, 0) })
		self._pct.Text = tostring(math.floor(frac * 100 + 0.5)) .. "%"
	end
end

function Progress:SetText(t)
	if self._title then
		self._title.Text = tostring(t)
	end
end

function Tab:CreateProgress(config)
	if type(config) == "string" then
		config = { Name = config }
	end
	return Progress:_create(self._window, self, config or {})
end

----------------------------------------------------------------
-- Console: scrolling log (great for script output and research logs)
----------------------------------------------------------------

local Console = newClass()
local LOG_COLORS = { info = "Text", ok = "Success", warn = "Warning", error = "Danger", dim = "SubText" }

function Console:_create(window, tab, config)
	local height = config.Height or 150
	local self, row = scaffold(Console, window, tab, config, "Console", height + (config.Name and 22 or 0))
	self._max = config.MaxLines or 200
	self._lines = {}
	local top = 0
	if config.Name then
		Kit.label(row, config.Name, { Size = 14, Position = UDim2.new(0, 8, 0, 0), WidthOffset = -16, Height = 20 })
		top = 22
	end
	local box = Kit.frame(row, { Color = "Secondary", Radius = 6, Stroke = true, Size = UDim2.new(1, -16, 0, height), Position = UDim2.new(0, 8, 0, top) })
	local scroll = Kit.scroll(box, { Padding = 2, Size = UDim2.new(1, -12, 1, -12), Position = UDim2.new(0, 6, 0, 6) })
	self._scroll = scroll
	self._order = 0
	self._value = ""
	return self
end

function Console:Log(text, kind)
	if self._destroyed then
		return
	end
	self._order += 1
	local line = Kit.label(self._scroll, tostring(text), {
		Size = 13, Color = LOG_COLORS[kind or "info"] or "Text", Wrap = true, Auto = true, Height = 16, Name = "Line",
	})
	line.LayoutOrder = self._order
	table.insert(self._lines, line)
	while #self._lines > self._max do
		local old = table.remove(self._lines, 1)
		old:Destroy()
	end
	self._value = (self._value ~= "" and (self._value .. "\n") or "") .. tostring(text)
	pcall(function()
		self._scroll.CanvasPosition = Vector2.new(0, 1e6)
	end)
	return line
end

function Console:Clear()
	for _, l in self._lines do
		l:Destroy()
	end
	self._lines = {}
	self._value = ""
end

function Console:_setValue(v)
	self:Clear()
	if v and v ~= "" then
		self:Log(v)
	end
end

function Tab:CreateConsole(config)
	return Console:_create(self._window, self, config or {})
end

----------------------------------------------------------------
-- ButtonRow: several buttons side by side
----------------------------------------------------------------

local ButtonRow = newClass()

function ButtonRow:_create(window, tab, config)
	assert(type(config.Buttons) == "table" and #config.Buttons > 0, "[Polaris] ButtonRow: Buttons must be a non-empty list")
	local self, row = scaffold(ButtonRow, window, tab, config, "ButtonRow", config.Height or 36)
	self._buttons = {}
	local n = #config.Buttons
	local gap = 6
	row = Create("Frame", { Name = "Holder", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1, Parent = row })
	for i, def in ipairs(config.Buttons) do
		local name = def.Name or def[1] or ("Button " .. i)
		local cb = def.Callback or def[2]
		local btn = Kit.button(row, name, {
			Color = def.Color or (i == 1 and "Accent" or "Secondary"),
			TextColor = (i ~= 1 and not def.Color) and "Text" or nil,
			Size = UDim2.new(1 / n, i == n and 0 or -gap, 0, (config.Height or 36) - 4),
			Position = UDim2.new((i - 1) / n, 0, 0, 2),
			TextSize = 13,
		})
		self:_track(btn.Activated:Connect(function()
			if self._disabled then
				return
			end
			I.invokeCallback(cb)
		end))
		table.insert(self._buttons, btn)
	end
	self._value = true
	return self
end

function ButtonRow:_setValue() end

function Tab:CreateButtonRow(config)
	return ButtonRow:_create(self._window, self, config or {})
end

----------------------------------------------------------------
-- Stats: live readout tiles (FPS, ping, players, memory, or your own)
----------------------------------------------------------------

local Stats = newClass()
Polaris.StatsProviders = {}

local function fpsMeter()
	local m = { frames = 0, t = os.clock(), value = 0 }
	local conn
	local ok = pcall(function()
		conn = I.services.RunService.Heartbeat:Connect(function()
			m.frames += 1
			local now = os.clock()
			if now - m.t >= 1 then
				m.value = m.frames / (now - m.t)
				m.frames = 0
				m.t = now
			end
		end)
	end)
	function m:Get()
		return tostring(math.floor(self.value + 0.5))
	end
	function m:Destroy()
		if conn then
			conn:Disconnect()
		end
	end
	if not ok then
		function m:Get()
			return "-"
		end
	end
	return m
end

local BUILTIN = {
	FPS = function(ctx)
		ctx.fps = ctx.fps or fpsMeter()
		return function()
			return ctx.fps:Get()
		end
	end,
	Ping = function()
		return function()
			local ok, v = pcall(function()
				return svc("Stats").Network.ServerStatsItem["Data Ping"]:GetValue()
			end)
			return ok and (tostring(math.floor(v + 0.5)) .. " ms") or "-"
		end
	end,
	Players = function()
		return function()
			local ok, v = pcall(function()
				return #I.services.Players:GetPlayers() .. "/" .. I.services.Players.MaxPlayers
			end)
			return ok and v or "-"
		end
	end,
	Memory = function()
		return function()
			local ok, v = pcall(function()
				return svc("Stats"):GetTotalMemoryUsageMb()
			end)
			return ok and (tostring(math.floor(v)) .. " MB") or "-"
		end
	end,
	Time = function()
		return function()
			return os.date("%H:%M:%S")
		end
	end,
	Server = function()
		return function()
			local ok, v = pcall(function()
				return game.JobId ~= "" and game.JobId:sub(1, 8) or "studio"
			end)
			return ok and v or "-"
		end
	end,
}
Polaris.StatsProviders = BUILTIN

function Stats:_create(window, tab, config)
	local items = config.Items or { "FPS", "Ping", "Players", "Memory" }
	local cols = config.Columns or math.min(#items, 4)
	local rows = math.ceil(#items / cols)
	local tileH = 54
	local self, row = scaffold(Stats, window, tab, config, "Stats", rows * (tileH + 6))
	row = Create("Frame", { Name = "Holder", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1, Parent = row })
	self._ctx = {}
	self._getters = {}
	self._valueLabels = {}
	for i, item in ipairs(items) do
		local name, getter
		if type(item) == "string" then
			name = item
			getter = BUILTIN[item] and BUILTIN[item](self._ctx) or function()
				return "?"
			end
		else
			name = item.Name or item[1] or ("Stat " .. i)
			local g = item.Get or item[2]
			getter = type(g) == "function" and g or function()
				return tostring(g)
			end
		end
		local c = (i - 1) % cols
		local r = math.floor((i - 1) / cols)
		local tile = Kit.frame(row, {
			Color = "Secondary", Radius = 8, Stroke = true,
			Size = UDim2.new(1 / cols, c == cols - 1 and 0 or -6, 0, tileH),
			Position = UDim2.new(c / cols, 0, 0, r * (tileH + 6)),
		})
		Kit.label(tile, string.upper(name), { Size = 11, Color = "SubText", Position = UDim2.new(0, 10, 0, 6), WidthOffset = -20, Height = 14 })
		local val = Kit.label(tile, "-", { Size = 20, Bold = true, Position = UDim2.new(0, 10, 0, 22), WidthOffset = -20, Height = 26 })
		table.insert(self._getters, getter)
		table.insert(self._valueLabels, val)
	end
	self._value = ""
	self:Refresh()
	local interval = config.Interval or 1
	task.spawn(function()
		while not self._destroyed do
			task.wait(interval)
			if self._destroyed then
				break
			end
			self:Refresh()
		end
	end)
	return self
end

function Stats:Refresh()
	for i, getter in ipairs(self._getters) do
		local ok, v = pcall(getter)
		local lbl = self._valueLabels[i]
		if lbl and lbl.Parent then
			lbl.Text = ok and tostring(v) or "-"
		end
	end
end

function Stats:_setValue() end

function Stats:Destroy()
	if self._ctx and self._ctx.fps then
		self._ctx.fps:Destroy()
	end
	Element.Destroy(self)
end

function Tab:CreateStats(config)
	return Stats:_create(self._window, self, config or {})
end

----------------------------------------------------------------
-- Tab:Add(type, config) + Tab:CreateMany(list) - data-driven building
----------------------------------------------------------------

Polaris.ElementTypes = {
	Section = function(t, c) return t:CreateSection(c) end,
	Button = function(t, c) return t:CreateButton(c) end,
	Toggle = function(t, c) return t:CreateToggle(c) end,
	Slider = function(t, c) return t:CreateSlider(c) end,
	Dropdown = function(t, c) return t:CreateDropdown(c) end,
	ColorPicker = function(t, c) return t:CreateColorPicker(c) end,
	Keybind = function(t, c) return t:CreateKeybind(c) end,
	Textbox = function(t, c) return t:CreateTextbox(c) end,
	Paragraph = function(t, c) return t:CreateParagraph(c) end,
	Divider = function(t, c) return t:CreateDivider(c) end,
	Label = function(t, c) return t:CreateLabel(c) end,
	Heading = function(t, c) return t:CreateHeading(c.Text or c.Name) end,
	Progress = function(t, c) return t:CreateProgress(c) end,
	Console = function(t, c) return t:CreateConsole(c) end,
	ButtonRow = function(t, c) return t:CreateButtonRow(c) end,
	Stats = function(t, c) return t:CreateStats(c) end,
}

function Tab:Add(kind, config)
	local make = Polaris.ElementTypes[kind]
	assert(make, "[Polaris] Unknown element type '" .. tostring(kind) .. "'. Valid: " .. table.concat((function()
		local k = {}
		for name in Polaris.ElementTypes do
			table.insert(k, name)
		end
		table.sort(k)
		return k
	end)(), ", "))
	return make(self, config or {})
end

function Tab:CreateMany(list)
	local made = {}
	for _, item in ipairs(list) do
		local kind = item.Type or item.Kind
		table.insert(made, self:Add(kind, item))
	end
	return made
end

----------------------------------------------------------------
-- Window helpers
----------------------------------------------------------------

function Window:GetTab(name)
	for _, t in self._tabs do
		if t._name == name then
			return t
		end
	end
	return nil
end

function Window:SelectTab(name)
	local t = type(name) == "string" and self:GetTab(name) or name
	if t then
		self:_selectTab(t)
	end
	return t
end

-- Modal dialog drawn inside the window.
-- config: Title, Content, Buttons = { {Name, Callback, Color}, ... }
function Window:Dialog(config)
	config = config or {}
	local frame = self._frame
	local overlay = Create("TextButton", {
		Name = "DialogOverlay",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Text = "",
		AutoButtonColor = false,
		ZIndex = 200,
		Parent = frame,
	})
	Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = overlay })
	local buttons = config.Buttons or { { Name = "OK" } }
	local width = math.min(380, math.max(240, (frame.AbsoluteSize and frame.AbsoluteSize.X or 0) - 40))
	if width < 240 then
		width = 340
	end
	local card = Kit.frame(overlay, {
		Color = "Background", Radius = 10, Stroke = "Accent", ZIndex = 201, Anchor = Vector2.new(0.5, 0.5),
		Size = UDim2.new(0, width, 0, 150), Position = UDim2.new(0.5, 0, 0.5, 0),
	})
	local title = Kit.label(card, config.Title or "Are you sure?", { Size = 17, Bold = true, Position = UDim2.new(0, 16, 0, 12), WidthOffset = -32, Height = 24 })
	title.ZIndex = 202
	local body = Kit.label(card, tostring(config.Content or ""), { Size = 14, Color = "SubText", Wrap = true, Position = UDim2.new(0, 16, 0, 40), WidthOffset = -32, Height = 56, VAlign = "Top" })
	body.ZIndex = 202
	local d = { _gui = overlay }
	function d:Close()
		if overlay.Parent then
			overlay:Destroy()
		end
	end
	local n = #buttons
	for i, def in ipairs(buttons) do
		local btn = Kit.button(card, def.Name or def[1] or "OK", {
			Color = def.Color or (i == n and "Accent" or "Secondary"),
			TextColor = (i ~= n and not def.Color) and "Text" or nil,
			Size = UDim2.new(1 / n, -10, 0, 32),
			Position = UDim2.new((i - 1) / n, 8, 1, -44),
			TextSize = 14,
		})
		btn.ZIndex = 203
		btn.Activated:Connect(function()
			d:Close()
			I.invokeCallback(def.Callback or def[2])
		end)
	end
	return d
end

-- Built-in "Settings" tab: theme picker, config buttons, destroy.
function Window:AddSettingsTab(opts)
	opts = opts or {}
	local tab = self:CreateTab({ Name = opts.Name or "Settings" })
	tab:CreateSection({ Name = "Look" })
	local themes = Polaris:GetThemeNames()
	tab:CreateDropdown({
		Name = "Theme",
		Options = themes,
		Default = Polaris.CurrentThemeName or "Default",
		Callback = function(choice)
			local picked = type(choice) == "table" and choice[1] or choice
			if picked then
				Polaris:SetTheme(picked)
			end
		end,
	})
	if self._config.ConfigFolder and I.FS then
		tab:CreateSection({ Name = "Saved settings" })
		tab:CreateButtonRow({
			Buttons = {
				{ Name = "Save settings", Callback = function() self:SaveConfig() Polaris:Notify({ Title = "Saved", Content = "Your settings were saved.", Type = "success" }) end },
				{ Name = "Load settings", Callback = function() self:LoadConfig() end },
			},
		})
	end
	tab:CreateSection({ Name = "Window" })
	tab:CreateButton({
		Name = "Hide window (press the toggle key to bring it back)",
		Callback = function()
			self:SetVisible(false)
		end,
	})
	tab:CreateButton({
		Name = "Close and remove this UI",
		Callback = function()
			self:Dialog({
				Title = "Close this UI?",
				Content = "The window will be removed. Run the script again to open it.",
				Buttons = { { Name = "Keep it" }, { Name = "Close it", Color = "Danger", Callback = function() self:Destroy() end } },
			})
		end,
	})
	tab:CreateParagraph({ Text = "Polaris " .. Polaris.Version .. (opts.About and ("\n" .. opts.About) or "") })
	return tab
end
