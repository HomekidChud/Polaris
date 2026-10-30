-- data widgets: Table, Chart, Form.

local Create, themed, Element, Tab = I.Create, I.themed, I.Element, I.Tab
local Kit = Polaris.Kit
local scaffold, newClass = Polaris._scaffold, Polaris._newClass

local function clampInt(v, lo, hi, default)
	v = tonumber(v) or default
	return math.max(lo, math.min(hi, math.floor(v)))
end

local function copyRow(r)
	local out = {}
	for k, v in pairs(r) do out[k] = v end
	return out
end

----------------------------------------------------------------
-- Table
----------------------------------------------------------------
local TableEl = newClass()

local function colName(c) return type(c) == "table" and tostring(c.Name) or tostring(c) end

local function cellValue(row, colIndex, cols)
	local v = row[colIndex]
	if v == nil then v = row[colName(cols[colIndex])] end
	return v
end

function TableEl:_rebuild()
	if self._destroyed or not self._body then return end
	local cols = self._cols
	local view = {}
	local filter = self._filter and self._filter:lower() or ""
	for i, row in ipairs(self._rows) do
		local keep = filter == ""
		if not keep then
			for c = 1, #cols do
				if tostring(cellValue(row, c, cols) or ""):lower():find(filter, 1, true) then keep = true break end
			end
		end
		if keep then table.insert(view, i) end
	end
	if self._sortCol then
		local c, asc = self._sortCol, self._sortAsc
		table.sort(view, function(a, b)
			local x, y = cellValue(self._rows[a], c, cols), cellValue(self._rows[b], c, cols)
			local nx, ny = tonumber(x), tonumber(y)
			local less
			if nx and ny then
				if nx == ny then return a < b end
				less = nx < ny
			else
				local sx, sy = tostring(x or ""):lower(), tostring(y or ""):lower()
				if sx == sy then return a < b end
				less = sx < sy
			end
			if asc then return less end
			return not less
		end)
	end
	self._view = view
	Kit.clear(self._body)
	local shown = math.min(#view, self._maxRows)
	local total = 0
	for pos = 1, shown do
		local idx = view[pos]
		local row = self._rows[idx]
		local selected = self._selected == idx
		local b = Create("TextButton", {
			Name = "Row", Size = UDim2.new(1, -6, 0, 26), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
			AutoButtonColor = false, Text = "", LayoutOrder = pos, Parent = self._body,
		})
		Kit.paint(b, "BackgroundColor3", selected and "Accent" or ((self._zebra and pos % 2 == 0) and "Primary" or "Secondary"))
		b.BackgroundTransparency = selected and 0.55 or 0
		local x = 0
		for c = 1, #cols do
			local w = self._widths[c]
			Kit.label(b, tostring(cellValue(row, c, cols) == nil and "" or cellValue(row, c, cols)), {
				Name = "Cell", Size = 13, Truncate = true, Height = 26, Width = w, WidthOffset = -8,
				Position = UDim2.new(x, 8, 0, 0),
			})
			x += w
		end
		b.Activated:Connect(function()
			self._selected = idx
			self:_rebuild()
			if self._config.Callback then I.invokeCallback(self._config.Callback, idx, copyRow(row)) end
		end)
		total += 28
	end
	if shown == 0 then
		Kit.label(self._body, self._config.Empty or "No rows", { Name = "Empty", Size = 13, Color = "SubText", Align = "Center", Height = 30 })
	end
	if #view > shown then
		Kit.label(self._body, ("Showing the first %d of %d rows. Use the search box."):format(shown, #view), { Name = "More", Size = 12, Color = "SubText", Align = "Center", Height = 20, LayoutOrder = 100000 })
	end
	self._body.CanvasSize = UDim2.new(0, 0, 0, total + 24)
	for c, btn in ipairs(self._headerButtons) do
		local arrow = ""
		if self._sortCol == c then arrow = self._sortAsc and "  ^" or "  v" end
		btn.Text = colName(cols[c]) .. arrow
	end
end

-- config: Columns = { "Name", "Qty" } or { { Name = "Name", Width = 2 }, ... }, Rows = { { "Sword", 3 }, { Name = "Bow", Qty = 1 } },
--         Height (default 200), Sortable (default true), Search (default false), Zebra (default true), MaxRows (default 300),
--         Callback(index, row) when a row is tapped, Empty (text)
function Tab:CreateTable(config)
	config = config or {}
	assert(type(config.Columns) == "table" and #config.Columns > 0, "[Polaris] Table: Columns must be a non-empty list")
	local h = tonumber(config.Height) or 200
	local el, row = scaffold(TableEl, self._window, self, config, "Table", h)
	el._cols = config.Columns
	el._zebra = config.Zebra ~= false
	el._maxRows = clampInt(config.MaxRows, 10, 2000, 300)
	el._rows, el._headerButtons = {}, {}
	local weights, sum = {}, 0
	for i, c in ipairs(el._cols) do
		weights[i] = type(c) == "table" and tonumber(c.Width) or 1
		sum += weights[i]
	end
	el._widths = {}
	for i, w in ipairs(weights) do el._widths[i] = w / sum end

	local y = 0
	if config.Search then
		local box = Kit.input(row, { Name = "TableSearch", Placeholder = "Search ...", Size = UDim2.new(1, -6, 0, 28) })
		el._search = box
		el:_track(box:GetPropertyChangedSignal("Text"):Connect(function()
			el._filter = box.Text
			el:_rebuild()
		end))
		y = 32
	end
	local header = Kit.frame(row, { Name = "TableHeader", Color = "Primary", Radius = 6, Size = UDim2.new(1, -6, 0, 28), Position = UDim2.new(0, 0, 0, y) })
	local x = 0
	for c = 1, #el._cols do
		local w = el._widths[c]
		local btn = Create("TextButton", {
			Name = "HeaderCell", Size = UDim2.new(w, -8, 1, 0), Position = UDim2.new(x, 8, 0, 0), BackgroundTransparency = 1,
			Text = colName(el._cols[c]), Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left, Parent = header,
		})
		themed(btn, "TextColor3", "Text")
		if config.Sortable ~= false then
			btn.Activated:Connect(function()
				if el._sortCol == c then el._sortAsc = not el._sortAsc else el._sortCol, el._sortAsc = c, true end
				el:_rebuild()
			end)
		end
		el._headerButtons[c] = btn
		x += w
	end
	el._body = Kit.scroll(row, { Name = "TableBody", Size = UDim2.new(1, 0, 0, math.max(40, h - y - 32)), Position = UDim2.new(0, 0, 0, y + 32), Padding = 2 })
	el:SetRows(config.Rows or {})
	return el
end

function TableEl:SetRows(rows)
	self._rows = {}
	for _, r in ipairs(rows or {}) do
		if type(r) == "table" then table.insert(self._rows, copyRow(r)) end
	end
	self._selected = nil
	self._value = self._rows
	self:_rebuild()
end
function TableEl:_setValue(v) self:SetRows(v) end
function TableEl:AddRow(r)
	table.insert(self._rows, copyRow(r))
	self._value = self._rows
	self:_rebuild()
	return #self._rows
end
function TableEl:RemoveRow(i)
	if self._rows[i] then
		table.remove(self._rows, i)
		if self._selected == i then self._selected = nil elseif self._selected and self._selected > i then self._selected -= 1 end
		self:_rebuild()
		return true
	end
	return false
end
function TableEl:Clear() self:SetRows({}) end
function TableEl:GetRows()
	local out = {}
	for i, r in ipairs(self._rows) do out[i] = copyRow(r) end
	return out
end
function TableEl:Count() return #self._rows end
function TableEl:GetSelected()
	if self._selected and self._rows[self._selected] then return self._selected, copyRow(self._rows[self._selected]) end
	return nil
end
function TableEl:Sort(column, ascending)
	for i, c in ipairs(self._cols) do
		if colName(c) == tostring(column) or i == column then
			self._sortCol, self._sortAsc = i, ascending ~= false
			self:_rebuild()
			return true
		end
	end
	return false
end
function TableEl:SetFilter(text)
	self._filter = tostring(text or "")
	if self._search then self._search.Text = self._filter end
	self:_rebuild()
end
function TableEl:GetView()
	local out = {}
	for pos, idx in ipairs(self._view or {}) do out[pos] = copyRow(self._rows[idx]) end
	return out
end

----------------------------------------------------------------
-- Chart: bar and line charts drawn with plain Frames
----------------------------------------------------------------
local Chart = newClass()
local PALETTE = {
	Color3.fromRGB(100, 140, 255), Color3.fromRGB(255, 140, 90), Color3.fromRGB(100, 210, 150),
	Color3.fromRGB(230, 110, 190), Color3.fromRGB(240, 200, 80), Color3.fromRGB(150, 110, 255),
}

local function seriesOf(config)
	local list = {}
	if type(config.Series) == "table" then
		for i, s in ipairs(config.Series) do
			table.insert(list, { Name = tostring(s.Name or ("Series " .. i)), Values = s.Values or {}, Color = s.Color })
		end
	elseif type(config.Values) == "table" then
		table.insert(list, { Name = tostring(config.SeriesName or "Value"), Values = config.Values, Color = config.Color })
	end
	return list
end

function Chart:_draw()
	if self._destroyed or not self._plot then return end
	local plot = self._plot
	Kit.clear(plot)
	local series, labels = self._series, self._labels
	local n = 0
	for _, s in ipairs(series) do n = math.max(n, #s.Values) end
	n = math.max(n, #labels)
	local lo, hi = self._min, self._max
	if hi == nil then
		hi = 0
		for _, s in ipairs(series) do for _, v in ipairs(s.Values) do hi = math.max(hi, tonumber(v) or 0) end end
		if hi <= lo then hi = lo + 1 end
	end
	self._scaleMax = hi
	local span = hi - lo
	local kind = self._type
	local ns = math.max(1, #series)
	local showValues = self._showValues ~= false and n <= 12
	local function ratio(v) return math.max(0, math.min(1, ((tonumber(v) or 0) - lo) / span)) end
	-- baseline
	Kit.frame(plot, { Name = "Baseline", Color = "Stroke", Radius = 0, Size = UDim2.new(1, 0, 0, 1), Position = UDim2.new(0, 0, 1, 0) })
	if n == 0 then
		Kit.label(plot, self._config.Empty or "No data", { Name = "Empty", Size = 13, Color = "SubText", Align = "Center", Height = 30, Position = UDim2.new(0, 0, 0.5, -15) })
		return
	end
	if kind == "line" then
		local abs = plot.AbsoluteSize
		local W = (abs and abs.X and abs.X > 10) and abs.X or 400
		local H = (abs and abs.Y and abs.Y > 10) and abs.Y or 120
		for si, s in ipairs(series) do
			local color = s.Color or PALETTE[(si - 1) % #PALETTE + 1]
			local prev
			for i = 1, #s.Values do
				local fx = n == 1 and 0.5 or (i - 1) / (n - 1)
				local px, py = fx * W, (1 - ratio(s.Values[i])) * H
				if prev then
					local dx, dy = px - prev[1], py - prev[2]
					local len = math.sqrt(dx * dx + dy * dy)
					local seg = Create("Frame", {
						Name = "Segment", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0,
						Size = UDim2.new(0, len + 1, 0, 2), Position = UDim2.new(0, (px + prev[1]) / 2, 0, (py + prev[2]) / 2),
						Rotation = math.deg(math.atan2(dy, dx)), Parent = plot,
					})
				end
				Create("Frame", { Name = "Point", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = color, BorderSizePixel = 0,
					Size = UDim2.new(0, 7, 0, 7), Position = UDim2.new(0, px, 0, py), Parent = plot })
				if showValues and ns == 1 then
					Kit.label(plot, tostring(s.Values[i]), { Name = "Value", Size = 11, Color = "SubText", Align = "Center", Width = 0, WidthOffset = 40, Height = 14,
						Position = UDim2.new(0, px - 20, 0, math.max(0, py - 18)) })
				end
				prev = { px, py }
			end
		end
	else
		local slot = 1 / n
		local barW = slot * 0.7 / ns
		for si, s in ipairs(series) do
			local color = s.Color or PALETTE[(si - 1) % #PALETTE + 1]
			for i = 1, #s.Values do
				local r = ratio(s.Values[i])
				local x = (i - 1) * slot + slot * 0.15 + (si - 1) * barW
				local bar = Create("Frame", {
					Name = "Bar", BackgroundColor3 = color, BorderSizePixel = 0,
					Size = UDim2.new(barW, 0, r, 0), Position = UDim2.new(x, 0, 1 - r, 0), Parent = plot,
				})
				Create("UICorner", { CornerRadius = UDim.new(0, 3), Parent = bar })
				if showValues and ns == 1 then
					Kit.label(plot, tostring(s.Values[i]), { Name = "Value", Size = 11, Color = "SubText", Align = "Center", Width = barW, Height = 14,
						Position = UDim2.new(x, 0, 1 - r, -15) })
				end
			end
		end
	end
	-- x labels (under the plot, in the row container)
	if self._labelHost then
		Kit.clear(self._labelHost)
		for i = 1, n do
			local text = labels[i]
			if text ~= nil and (n <= 14 or i % math.ceil(n / 14) == 1) then
				local fx = (kind == "line") and (n == 1 and 0.5 or (i - 1) / (n - 1)) or ((i - 0.5) / n)
				Kit.label(self._labelHost, tostring(text), { Name = "XLabel", Size = 11, Color = "SubText", Align = "Center", Width = 0, WidthOffset = 60, Height = 16,
					Position = UDim2.new(fx, -30, 0, 0), Truncate = true })
			end
		end
	end
end

-- config: Type ("bar" or "line"), Title, Labels = {...}, Values = {...} or Series = { { Name, Values, Color } },
--         Height (default 180), Min (default 0), Max (default: biggest value), ShowValues (default true), MaxPoints (default 60)
function Tab:CreateChart(config)
	config = config or {}
	local h = tonumber(config.Height) or 180
	local titleH = config.Title and 22 or 0
	local legendH = (type(config.Series) == "table" and #config.Series > 1) and 18 or 0
	local el, row = scaffold(Chart, self._window, self, config, "Chart", h)
	el._type = config.Type == "line" and "line" or "bar"
	el._min, el._max = tonumber(config.Min) or 0, tonumber(config.Max)
	el._showValues = config.ShowValues
	el._maxPoints = clampInt(config.MaxPoints, 5, 500, 60)
	el._series, el._labels = seriesOf(config), config.Labels or {}
	if config.Title then
		Kit.label(row, config.Title, { Name = "ChartTitle", Bold = true, Size = 14, Height = 20 })
	end
	if legendH > 0 then
		local parts = {}
		for i, s in ipairs(el._series) do
			local c = s.Color or PALETTE[(i - 1) % #PALETTE + 1]
			table.insert(parts, ('<font color="#%s">\u{25CF}</font> %s'):format(string.format("%02x%02x%02x", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)), s.Name))
		end
		Kit.label(row, table.concat(parts, "   "), { Name = "Legend", Rich = true, Size = 12, Color = "SubText", Height = 16, Position = UDim2.new(0, 0, 0, titleH) })
	end
	local top = titleH + legendH + 4
	local plot = Create("Frame", { Name = "Plot", Size = UDim2.new(1, -12, 0, math.max(30, h - top - 20)), Position = UDim2.new(0, 6, 0, top + 14),
		BackgroundTransparency = 1, Parent = row })
	el._plot = plot
	el._labelHost = Create("Frame", { Name = "XLabels", Size = UDim2.new(1, -12, 0, 16), Position = UDim2.new(0, 6, 1, -18), BackgroundTransparency = 1, Parent = row })
	plot.Position = UDim2.new(0, 6, 0, top)
	plot.Size = UDim2.new(1, -12, 0, math.max(30, h - top - 22))
	el._value = { Labels = el._labels, Series = el._series }
	el:_track(plot:GetPropertyChangedSignal("AbsoluteSize"):Connect(function() el:_draw() end))
	el:_draw()
	return el
end

function Chart:SetData(labels, values)
	self._labels = labels or {}
	self._series = { { Name = self._series[1] and self._series[1].Name or "Value", Values = values or {}, Color = self._series[1] and self._series[1].Color } }
	self._value = { Labels = self._labels, Series = self._series }
	self:_draw()
end
function Chart:SetSeries(list, labels)
	self._series = seriesOf({ Series = list })
	if labels then self._labels = labels end
	self._value = { Labels = self._labels, Series = self._series }
	self:_draw()
end
function Chart:_setValue(v)
	if type(v) == "table" and v.Series then self:SetSeries(v.Series, v.Labels)
	elseif type(v) == "table" then self:SetData(self._labels, v) end
end
function Chart:AddPoint(label, value)
	local s = self._series[1]
	if not s then
		s = { Name = "Value", Values = {} }
		self._series[1] = s
	end
	table.insert(self._labels, label ~= nil and tostring(label) or "")
	table.insert(s.Values, tonumber(value) or 0)
	while #s.Values > self._maxPoints do
		table.remove(s.Values, 1)
		table.remove(self._labels, 1)
	end
	self:_draw()
end

----------------------------------------------------------------
-- Form: labelled fields + validation + Submit.   Returns a Group with extra methods.
----------------------------------------------------------------
-- config: Name, Fields = { { Name, Type = "Textbox"|"Number"|"Toggle"|"Dropdown"|"Slider", Default, Options, Min, Max, Required, Placeholder } },
--         Submit (button text, default "Submit"), Callback(values) only when everything is valid, Card (default true)
function Tab:CreateForm(config)
	config = config or {}
	assert(type(config.Fields) == "table" and #config.Fields > 0, "[Polaris] Form: Fields must be a non-empty list")
	local g = self:CreateGroup({ Name = config.Name, Card = config.Card ~= false })
	g.Fields, g._fieldDefs = {}, {}
	local errorLabel
	for _, f in ipairs(config.Fields) do
		local kind = f.Type or "Textbox"
		local el
		if kind == "Number" then
			el = g:CreateTextbox({ Name = f.Name, Default = f.Default ~= nil and tostring(f.Default) or "", Placeholder = f.Placeholder or "number" })
		elseif kind == "Toggle" then
			el = g:CreateToggle({ Name = f.Name, Default = f.Default == true })
		elseif kind == "Dropdown" then
			el = g:CreateDropdown({ Name = f.Name, Options = f.Options, Default = f.Default or (f.Options and f.Options[1]) })
		elseif kind == "Slider" then
			el = g:CreateSlider({ Name = f.Name, Min = f.Min or 0, Max = f.Max or 100, Default = f.Default, Increment = f.Increment or 1 })
		else
			el = g:CreateTextbox({ Name = f.Name, Default = f.Default ~= nil and tostring(f.Default) or "", Placeholder = f.Placeholder })
		end
		g.Fields[f.Name] = el
		table.insert(g._fieldDefs, { Def = f, Kind = kind, El = el })
	end
	errorLabel = g:CreateLabel({ Text = "", Size = 13, Color = Color3.fromRGB(255, 107, 120) })

	function g:GetValues()
		local out = {}
		for _, fd in ipairs(self._fieldDefs) do
			local v = fd.El:Get()
			if fd.Kind == "Number" then v = tonumber(v) end
			out[fd.Def.Name] = v
		end
		return out
	end
	function g:SetValues(t)
		for _, fd in ipairs(self._fieldDefs) do
			local v = t[fd.Def.Name]
			if v ~= nil then fd.El:Set(fd.Kind == "Number" and tostring(v) or v, true) end
		end
	end
	function g:Reset()
		for _, fd in ipairs(self._fieldDefs) do
			local d = fd.Def.Default
			if fd.Kind == "Toggle" then d = d == true elseif d == nil then d = (fd.Kind == "Slider") and (fd.Def.Min or 0) or "" end
			if fd.Kind == "Dropdown" and (d == "" or d == nil) then d = fd.Def.Options and fd.Def.Options[1] end
			if d ~= nil then fd.El:Set(fd.Kind == "Number" and tostring(d) or d, true) end
		end
		errorLabel:SetText("")
	end
	function g:Validate()
		local problems = {}
		for _, fd in ipairs(self._fieldDefs) do
			local f, v = fd.Def, fd.El:Get()
			if fd.Kind == "Number" then
				local num = tonumber(v)
				if (v == nil or tostring(v) == "") then
					if f.Required then table.insert(problems, f.Name .. " is required") end
				elseif not num then
					table.insert(problems, f.Name .. " must be a number")
				elseif f.Min and num < f.Min then
					table.insert(problems, f.Name .. " must be at least " .. f.Min)
				elseif f.Max and num > f.Max then
					table.insert(problems, f.Name .. " must be at most " .. f.Max)
				end
			elseif fd.Kind == "Textbox" and f.Required and tostring(v):match("^%s*$") then
				table.insert(problems, f.Name .. " is required")
			end
		end
		return #problems == 0, problems
	end
	function g:Submit()
		local ok, problems = self:Validate()
		if not ok then
			errorLabel:SetText(problems[1])
			return false, problems
		end
		errorLabel:SetText("")
		local values = self:GetValues()
		if config.Callback then I.invokeCallback(config.Callback, values) end
		return true, values
	end
	g:CreateButton({ Name = config.Submit or "Submit", Callback = function() g:Submit() end })
	return g
end

Polaris.ElementTypes = Polaris.ElementTypes or {}
Polaris.ElementTypes.Table = function(t, c) return t:CreateTable(c) end
Polaris.ElementTypes.Chart = function(t, c) return t:CreateChart(c) end
Polaris.ElementTypes.Form = function(t, c) return t:CreateForm(c) end
