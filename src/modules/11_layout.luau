-- layout: Group / Card / Accordion, Columns, Pages, Spacer, Image and Custom (raw Instances).
-- A Group behaves like a Tab: every tab:CreateX / tab:Add works on it, and groups nest.

local Create, themed, Element, Tab = I.Create, I.themed, I.Element, I.Tab
local Kit = Polaris.Kit
local GAP = 4

-- Group objects inherit the element methods first (Get, SetVisible, Destroy ...) and the Tab methods second (CreateX ...).
local GroupClass = setmetatable({}, { __index = function(_, k)
	local v = Element[k]
	if v ~= nil then return v end
	return Tab[k]
end })
GroupClass.__index = GroupClass

local function sumHeight(self)
	local total = 0
	for _, el in self._elements do
		if el._container and el._container.Visible then
			total += el._container.Size.Y.Offset + GAP
		end
	end
	for _, s in self._sections do
		if s._container and s._container.Visible then
			total += s._container.Size.Y.Offset + GAP
		end
	end
	return math.max(0, total - GAP)
end

function GroupClass:_updateCanvas()
	if self._destroyed then return end
	local h = sumHeight(self)
	self._contentH = h
	if self._content then
		self._content.Size = UDim2.new(1, self._contentInset or 0, 0, h)
	end
	if self._onResize then
		self._onResize(h)
	end
end

-- A bare group (no element container of its own). Used inside Columns and Pages.
local function bareGroup(window, host, inset)
	local self = setmetatable({ _window = window, _elements = {}, _sections = {}, _isGroup = true, _destroyed = false }, GroupClass)
	self._content = Create("Frame", { Name = "GroupContent", Size = UDim2.new(1, inset or 0, 0, 0), BackgroundTransparency = 1, Parent = host })
	self._contentInset = inset or 0
	Create("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self._content })
	return self
end

function GroupClass:Destroy()
	if self._destroyed then return end
	for i = #self._elements, 1, -1 do
		local el = self._elements[i]
		if el and el.Destroy then pcall(el.Destroy, el) end
	end
	Element.Destroy(self)
	self._destroyed = true
end

function GroupClass:SetOpen(open)
	if not self._collapsible then return end
	self._open = open == true
	if self._content then self._content.Visible = self._open end
	if self._chevron then self._chevron.Text = self._open and "v" or ">" end
	self:_updateCanvas()
end

function GroupClass:IsOpen()
	return self._open ~= false
end

-- config: Name (title), Card (rounded panel), Collapsible (needs Name), Open (default true)
function Tab:CreateGroup(config)
	if type(config) == "string" then config = { Name = config } end
	config = config or {}
	local parent = self
	local el = Element._new(parent._window, parent, config, "Group")
	setmetatable(el, GroupClass)
	el._elements, el._sections, el._isGroup = {}, {}, true
	local card = config.Card == true
	local title = config.Name and tostring(config.Name) or nil
	local pad = card and 8 or 0
	local headerH = title and 26 or 0
	el._collapsible = config.Collapsible == true and title ~= nil
	el._open = config.Open ~= false
	el._title = title

	local container = Kit.frame(parent._content, {
		Name = "Group", Color = "Secondary", Radius = card and 8 or 0, Stroke = card, Transparency = card and 0 or 1,
		Size = UDim2.new(1, 0, 0, headerH),
	})
	el._container = container
	if title then
		if el._collapsible then
			el._header = Kit.button(container, (el._open and "v  " or ">  ") .. title, {
				Name = "GroupHeader", Color = "Primary", TextColor = "Text", Size = UDim2.new(1, -pad * 2, 0, headerH),
				Position = UDim2.new(0, pad, 0, card and 8 or 0), TextSize = 14,
				OnClick = function() el:SetOpen(not el._open) end,
			})
			el._header.TextXAlignment = Enum.TextXAlignment.Left
		else
			el._header = Kit.label(container, title, { Name = "GroupTitle", Bold = true, Size = 15, Height = headerH,
				Position = UDim2.new(0, pad, 0, card and 8 or 0), WidthOffset = -pad * 2 })
		end
	end
	local top = (card and 8 or 0) + (title and headerH + GAP or 0)
	local content = Create("Frame", { Name = "GroupContent", Size = UDim2.new(1, -pad * 2, 0, 0), Position = UDim2.new(0, pad, 0, top),
		BackgroundTransparency = 1, Visible = el._open, Parent = container })
	Create("UIListLayout", { Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = content })
	el._content, el._contentInset = content, -pad * 2

	el._onResize = function(h)
		local bottom = card and 8 or 0
		local total
		if el._open then
			total = top + h + bottom
		else
			total = (card and 8 or 0) + headerH + bottom
		end
		container.Size = UDim2.new(1, 0, 0, total)
		parent:_updateCanvas()
	end
	function el:SetOpen(open)
		if not self._collapsible then return end
		self._open = open == true
		self._content.Visible = self._open
		self._header.Text = (self._open and "v  " or ">  ") .. self._title
		self:_updateCanvas()
	end
	function el:SetTitle(text)
		self._title = tostring(text)
		if self._header then
			self._header.Text = (self._collapsible and ((self._open and "v  ") or ">  ") or "") .. self._title
		end
	end
	el:_updateCanvas()
	return el
end

----------------------------------------------------------------
-- Columns: side-by-side groups.  cols[1], cols[2] ... or cols.Columns[i]
----------------------------------------------------------------
local ColumnsClass = Polaris._newClass()

function ColumnsClass:Destroy()
	if self._destroyed then return end
	for _, col in ipairs(self.Columns or {}) do
		for i = #col._elements, 1, -1 do
			local el = col._elements[i]
			if el and el.Destroy then pcall(el.Destroy, el) end
		end
	end
	Element.Destroy(self)
end

function Tab:CreateColumns(config)
	if type(config) == "number" then config = { Count = config } end
	config = config or {}
	local parent = self
	local n = math.max(1, math.min(6, math.floor(tonumber(config.Count) or 2)))
	local gap = tonumber(config.Gap) or 8
	local el = Element._new(parent._window, parent, config, "Columns")
	setmetatable(el, ColumnsClass)
	local container = Create("Frame", { Name = "Columns", Size = UDim2.new(1, 0, 0, 0), BackgroundTransparency = 1, Parent = parent._content })
	el._container = container
	el.Columns = {}
	local hosts = {}
	local function recompute()
		local tallest = 0
		for _, col in ipairs(el.Columns) do
			tallest = math.max(tallest, col._contentH or 0)
		end
		for _, host in ipairs(hosts) do
			host.Size = UDim2.new(1 / n, -gap * (n - 1) / n, 0, tallest)
		end
		container.Size = UDim2.new(1, 0, 0, tallest)
		parent:_updateCanvas()
	end
	for i = 1, n do
		local host = Create("Frame", {
			Name = "Column" .. i, BackgroundTransparency = 1,
			Size = UDim2.new(1 / n, -gap * (n - 1) / n, 0, 0),
			Position = UDim2.new((i - 1) / n, (i - 1) * gap / n, 0, 0), Parent = container,
		})
		hosts[i] = host
		local col = bareGroup(parent._window, host, 0)
		col._onResize = recompute
		el.Columns[i] = col
		el[i] = col
	end
	recompute()
	return el
end

----------------------------------------------------------------
-- Pages: a row of buttons that switches between groups
----------------------------------------------------------------
local PagesClass = Polaris._newClass()

function PagesClass:Destroy()
	if self._destroyed then return end
	for _, g in pairs(self.Pages or {}) do
		for i = #g._elements, 1, -1 do
			local el = g._elements[i]
			if el and el.Destroy then pcall(el.Destroy, el) end
		end
	end
	Element.Destroy(self)
end

function PagesClass:_setValue(name)
	name = tostring(name)
	if not self.Pages[name] then return end
	self._value = name
	for pageName, g in pairs(self.Pages) do
		g._host.Visible = pageName == name
		local b = self._buttons[pageName]
		if b then
			Kit.paint(b, "BackgroundColor3", pageName == name and "Accent" or "Primary")
		end
	end
	self:_recompute()
end

function PagesClass:Select(name, silent)
	self:Set(name, silent)
end

-- config: Names = { "One", "Two" }, Default
function Tab:CreatePages(config)
	config = config or {}
	local names = config.Names or {}
	assert(#names > 0, "[Polaris] CreatePages needs Names = { ... }")
	local parent = self
	local el = Element._new(parent._window, parent, config, "Pages")
	setmetatable(el, PagesClass)
	local container = Create("Frame", { Name = "Pages", Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, Parent = parent._content })
	el._container = container
	el.Pages, el._buttons = {}, {}
	local n = #names
	for i, name in ipairs(names) do
		name = tostring(name)
		el._buttons[name] = Kit.button(container, name, {
			Name = "PageButton", Color = "Primary", TextColor = "Text", Size = UDim2.new(1 / n, -4 * (n - 1) / n, 0, 30),
			Position = UDim2.new((i - 1) / n, (i - 1) * 4 / n, 0, 0), OnClick = function() el:Set(name) end,
		})
		local host = Create("Frame", { Name = "Page_" .. name, Size = UDim2.new(1, 0, 0, 0), Position = UDim2.new(0, 0, 0, 36),
			BackgroundTransparency = 1, Visible = false, Parent = container })
		local g = bareGroup(parent._window, host, 0)
		g._host = host
		g._onResize = function(h)
			host.Size = UDim2.new(1, 0, 0, h)
			if el._value == name then
				el:_recompute()
			end
		end
		el.Pages[name] = g
		el[name] = g
	end
	function el:_recompute()
		local g = self.Pages[self._value]
		container.Size = UDim2.new(1, 0, 0, 36 + (g and g._contentH or 0))
		parent:_updateCanvas()
	end
	el:_setValue(config.Default or names[1])
	return el
end

----------------------------------------------------------------
-- Spacer, Image, Custom
----------------------------------------------------------------
local SpacerClass = Polaris._newClass()
function Tab:CreateSpacer(config)
	local h = type(config) == "number" and config or (type(config) == "table" and config.Height) or 12
	local el = Polaris._scaffold(SpacerClass, self._window, self, type(config) == "table" and config or {}, "Spacer", h)
	return el
end

local ImageClass = Polaris._newClass()

-- config: Image ("rbxassetid://123"), Height (default 120), Fit ("Fit"|"Crop"|"Stretch"), Caption, Rounded (default true)
function Tab:CreateImage(config)
	if type(config) == "string" then config = { Image = config } end
	config = config or {}
	local h = tonumber(config.Height) or 120
	local capH = config.Caption and 20 or 0
	local el, row = Polaris._scaffold(ImageClass, self._window, self, config, "Image", h + capH)
	local img = Create("ImageLabel", {
		Name = "Picture", Size = UDim2.new(1, 0, 0, h), BackgroundTransparency = 1, Image = tostring(config.Image or ""),
		ScaleType = Enum.ScaleType[config.Fit or "Fit"] or Enum.ScaleType.Fit, Parent = row,
	})
	if config.Rounded ~= false then
		Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = img })
	end
	if config.Caption then
		el._caption = Kit.label(row, config.Caption, { Name = "Caption", Size = 13, Color = "SubText", Align = "Center", Height = 18, Position = UDim2.new(0, 0, 0, h + 2) })
	end
	el._picture = img
	el._value = img.Image
	return el
end

function ImageClass:_setValue(v)
	self._value = tostring(v or "")
	self._picture.Image = self._value
end

-- config: Height, Build = function(frame, ctx).  The escape hatch: draw anything with raw Instances inside the frame.
-- ctx: Frame, Window, Create, Kit, Theme() (current theme table), SetHeight(h), Polaris
local CustomClass = Polaris._newClass()

function Tab:CreateCustom(config)
	if type(config) == "function" then config = { Build = config } end
	config = config or {}
	local h = tonumber(config.Height) or 120
	local el, row = Polaris._scaffold(CustomClass, self._window, self, config, "Custom", h)
	el.Frame = row
	local ctx = {
		Frame = row, Window = self._window, Create = Create, Kit = Kit, Polaris = Polaris,
		Theme = function() return Kit.theme() end,
		SetHeight = function(newH) Polaris._setHeight(el, newH) end,
	}
	if type(config.Build) == "function" then
		local ok, err = pcall(config.Build, row, ctx)
		if not ok then
			el.BuildError = tostring(err)
			Kit.label(row, "Custom block error: " .. tostring(err), { Name = "BuildError", Color = Color3.fromRGB(255, 107, 120), Size = 13, Wrap = true, Height = h })
			warn("[Polaris] Custom block error: " .. tostring(err))
		end
	end
	return el
end
function CustomClass:SetHeight(newH) Polaris._setHeight(self, newH) end

Polaris.ElementTypes = Polaris.ElementTypes or {}
local ET = Polaris.ElementTypes
ET.Group = function(t, c)
	local g = t:CreateGroup(c)
	if type(c.Items) == "table" then
		for _, item in ipairs(c.Items) do g:Add(item.Type or item.Kind, item) end
	end
	return g
end
ET.Columns = function(t, c)
	local cols = t:CreateColumns(c)
	for i, list in ipairs(c.Columns or {}) do
		if cols[i] then
			for _, item in ipairs(list.Items or list) do cols[i]:Add(item.Type or item.Kind, item) end
		end
	end
	return cols
end
ET.Pages = function(t, c)
	local names = c.Names
	if not names and type(c.Pages) == "table" then
		names = {}
		for _, p in ipairs(c.Pages) do table.insert(names, p.Name) end
	end
	local pages = t:CreatePages({ Names = names, Default = c.Default, Flag = c.Flag, Callback = c.Callback })
	for _, p in ipairs(c.Pages or {}) do
		local g = pages.Pages[tostring(p.Name)]
		if g then
			for _, item in ipairs(p.Items or {}) do g:Add(item.Type or item.Kind, item) end
		end
	end
	return pages
end
ET.Spacer = function(t, c) return t:CreateSpacer(c) end
ET.Image = function(t, c) return t:CreateImage(c) end
ET.Custom = function(t, c) return t:CreateCustom(c) end
