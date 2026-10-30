-- spec: describe an app as plain data (JSON-able), validate it, and build it.
--   Polaris.Spec.Validate(spec)  -> cleanSpec, problems     never throws, drops anything unknown or unsafe
--   Polaris.Spec.Build(spec)     -> app                     real windows, tabs and elements
--   Polaris.Spec.Describe()      -> text that explains the format (used as the prompt for an AI)
--   Polaris.Spec.FromWords(text) -> spec                    offline, keyword based (no AI, no network)
-- A spec can hold layout, data, state and actions from a fixed list.  It can never hold runnable code,
-- so a spec written by an AI or a stranger cannot run anything you did not allow.

local Spec = {}
Polaris.Spec = Spec
Polaris.Actions = {} -- your own named actions: Polaris.Actions.Ping = function(args, ctx) ... end

local LIMITS = { Tabs = 12, Items = 250, Depth = 4, Text = 2000, Name = 80, List = 60, Rows = 200, State = 40, Steps = 8 }
Spec.Limits = LIMITS

local function isNum(v) return type(v) == "number" and v == v and v > -1e15 and v < 1e15 end
local function str(v, max)
	if type(v) ~= "string" and type(v) ~= "number" then return nil end
	v = tostring(v)
	-- no control characters except newline
	v = v:gsub("[%z\1-\8\11\12\14-\31]", "")
	if #v > (max or LIMITS.Name) then v = v:sub(1, max or LIMITS.Name) end
	return v
end
local function num(v, lo, hi, default)
	if type(v) == "string" then v = tonumber(v) end
	if not isNum(v) then return default end
	return math.max(lo, math.min(hi, v))
end
local function bool(v, default)
	if type(v) == "boolean" then return v end
	return default
end
local function list(v, max)
	if type(v) ~= "table" then return nil end
	-- must look like an array
	local n = 0
	for k in pairs(v) do
		if type(k) ~= "number" then return nil end
		n = math.max(n, k)
	end
	local out = {}
	for i = 1, math.min(n, max or LIMITS.List) do out[i] = v[i] end
	return out
end

local BUILTIN_ACTIONS = { Notify = true, Set = true, Add = true, Toggle = true, Reset = true, Copy = true, Goto = true, Theme = true, Run = true, AddRow = true, ClearTable = true }
Spec.BuiltinActions = BUILTIN_ACTIONS

local function hubScriptNames()
	local names = {}
	for _, s in ipairs(Polaris.HubScripts and Polaris.HubScripts() or {}) do names[s.Name] = true end
	return names
end

----------------------------------------------------------------
-- Validation
----------------------------------------------------------------
local function scalar(v)
	if type(v) == "boolean" then return v end
	if isNum(v) then return v end
	if type(v) == "string" then return str(v, LIMITS.Text) end
	return nil
end

local function cleanAction(a, ctx, depth)
	depth = depth or 0
	if a == nil then return nil end
	if type(a) ~= "table" or depth > 2 then ctx.problem("an action must be an object like { \"Do\": \"Notify\", \"Text\": \"Hi\" }") return nil end
	local seq = list(a, LIMITS.Steps)
	if a.Do == "Sequence" and type(a.Steps) == "table" then seq = list(a.Steps, LIMITS.Steps) end
	if seq and #seq > 0 then
		local out = {}
		for _, step in ipairs(seq) do
			local c = cleanAction(step, ctx, depth + 1)
			if c then table.insert(out, c) end
		end
		return #out > 0 and { Do = "Sequence", Steps = out } or nil
	end
	local d = str(a.Do or a.Action, 30)
	if not d or not (BUILTIN_ACTIONS[d] or Polaris.Actions[d]) then
		ctx.problem("unknown action '" .. tostring(d) .. "'")
		return nil
	end
	local out = { Do = d, FromValue = bool(a.FromValue, false), FromForm = bool(a.FromForm, false) }
	if d == "Notify" then
		out.Title = str(a.Title, LIMITS.Name) or "Notice"
		out.Text = str(a.Text, 300) or ""
	elseif d == "Set" or d == "Add" or d == "Toggle" or d == "Reset" then
		out.Key = str(a.Key, 40)
		if not out.Key or not ctx.stateKeys[out.Key] then
			ctx.problem(d .. " needs a Key that is declared in State (got '" .. tostring(a.Key) .. "')")
			return nil
		end
		if d == "Set" then
			out.Value = scalar(a.Value)
			if out.Value == nil and not out.FromValue then ctx.problem("Set needs a Value") return nil end
		elseif d == "Add" then
			out.Value = num(a.Value, -1e9, 1e9, 1)
		end
	elseif d == "Copy" then
		out.Text = str(a.Text, LIMITS.Text) or ""
	elseif d == "Goto" then
		out.Tab = str(a.Tab, LIMITS.Name)
		if not out.Tab then ctx.problem("Goto needs Tab") return nil end
	elseif d == "Theme" then
		out.Value = str(a.Value, 30)
		if not out.FromValue and not (out.Value and Polaris.Themes[out.Value]) then
			ctx.problem("Theme '" .. tostring(a.Value) .. "' does not exist")
			return nil
		end
	elseif d == "Run" then
		out.Script = str(a.Script, LIMITS.Name)
		if not out.Script or not hubScriptNames()[out.Script] then
			ctx.problem("Run can only start the built-in hub scripts (got '" .. tostring(a.Script) .. "')")
			return nil
		end
	elseif d == "AddRow" or d == "ClearTable" then
		out.Table = str(a.Table, 40)
		if not out.Table then ctx.problem(d .. " needs Table (the Id of a Table)") return nil end
		if d == "AddRow" then
			out.Values = {}
			if type(a.Values) == "table" then
				local n = 0
				for k, v in pairs(a.Values) do
					n += 1
					if n <= 20 and (type(k) == "string" or type(k) == "number") and scalar(v) ~= nil then out.Values[k] = scalar(v) end
				end
			end
		end
	else
		-- a custom registered action: pass through plain scalar args only
		out.Args = {}
		for k, v in pairs(a) do
			if type(k) == "string" and k ~= "Do" and k ~= "Action" and scalar(v) ~= nil then out.Args[k] = scalar(v) end
		end
	end
	return out
end

local cleanItems

local function cleanFields(v, ctx)
	local out = {}
	for _, f in ipairs(list(v, 20) or {}) do
		if type(f) == "table" and str(f.Name) then
			local kind = str(f.Type, 12) or "Textbox"
			if kind ~= "Textbox" and kind ~= "Number" and kind ~= "Toggle" and kind ~= "Dropdown" and kind ~= "Slider" then
				ctx.problem("form field type '" .. kind .. "' is not allowed")
			else
				local field = { Name = str(f.Name), Type = kind, Required = bool(f.Required, false) }
				field.Default = scalar(f.Default)
				field.Placeholder = str(f.Placeholder, 80)
				field.Min, field.Max = num(f.Min, -1e9, 1e9, nil), num(f.Max, -1e9, 1e9, nil)
				if kind == "Dropdown" then
					field.Options = {}
					for _, o in ipairs(list(f.Options, 30) or {}) do if str(o) then table.insert(field.Options, str(o)) end end
					if #field.Options == 0 then ctx.problem("Dropdown field '" .. field.Name .. "' needs Options") field = nil end
				end
				if field then
					field.Key = str(f.Key, 40)
					if field.Key and not ctx.stateKeys[field.Key] then field.Key = nil end
					table.insert(out, field)
				end
			end
		end
	end
	return out
end

local ITEM = {}

ITEM.Label = function(it, ctx)
	local color = str(it.Color, 20)
	if color ~= "Accent" and color ~= "SubText" and color ~= "Text" then color = nil end
	return { Text = str(it.Text, LIMITS.Text) or "", Size = num(it.Size, 10, 36, 14), Color = color }
end
ITEM.Section = function(it) return { Name = str(it.Name) or "Section" } end
ITEM.Spacer = function(it) return { Height = num(it.Height, 2, 120, 12) } end
ITEM.Button = function(it, ctx)
	return { Name = str(it.Name) or "Button", Action = cleanAction(it.Action, ctx) }
end
ITEM.Toggle = function(it, ctx)
	local key = str(it.Key, 40)
	if key and not ctx.stateKeys[key] then ctx.problem("Toggle Key '" .. key .. "' is not declared in State") key = nil end
	return { Name = str(it.Name) or "Toggle", Default = bool(it.Default, false), Key = key, Action = cleanAction(it.Action, ctx) }
end
ITEM.Slider = function(it, ctx)
	local lo, hi = num(it.Min, -1e6, 1e6, 0), num(it.Max, -1e6, 1e6, 100)
	if hi <= lo then hi = lo + 1 end
	local key = str(it.Key, 40)
	if key and not ctx.stateKeys[key] then ctx.problem("Slider Key '" .. key .. "' is not declared in State") key = nil end
	return { Name = str(it.Name) or "Slider", Min = lo, Max = hi, Default = num(it.Default, lo, hi, lo), Increment = num(it.Increment, 0.001, 1e6, 1), Key = key, Action = cleanAction(it.Action, ctx) }
end
ITEM.Dropdown = function(it, ctx)
	local opts = {}
	for _, o in ipairs(list(it.Options, 40) or {}) do if str(o) then table.insert(opts, str(o)) end end
	if #opts == 0 then ctx.problem("Dropdown needs Options") return nil end
	local key = str(it.Key, 40)
	if key and not ctx.stateKeys[key] then ctx.problem("Dropdown Key '" .. key .. "' is not declared in State") key = nil end
	return { Name = str(it.Name) or "Choose", Options = opts, Default = str(it.Default), Key = key, Action = cleanAction(it.Action, ctx) }
end
ITEM.Textbox = function(it, ctx)
	local key = str(it.Key, 40)
	if key and not ctx.stateKeys[key] then ctx.problem("Textbox Key '" .. key .. "' is not declared in State") key = nil end
	return { Name = str(it.Name) or "Text", Default = str(it.Default, 200) or "", Placeholder = str(it.Placeholder, 80), Key = key, Action = cleanAction(it.Action, ctx) }
end
ITEM.Progress = function(it, ctx)
	local key = str(it.Key, 40)
	if key and not ctx.stateKeys[key] then ctx.problem("Progress Key '" .. key .. "' is not declared in State") key = nil end
	return { Name = str(it.Name) or "Progress", Max = num(it.Max, 1, 1e9, 100), Value = num(it.Value, 0, 1e9, 0), Key = key }
end
ITEM.Stats = function(it)
	local items = {}
	for _, s in ipairs(list(it.Items, 12) or {}) do
		s = str(s, 30)
		if s and Polaris.StatsProviders[s] then table.insert(items, s) end
	end
	if #items == 0 then items = { "FPS", "Ping", "Players" } end
	return { Items = items }
end
ITEM.Table = function(it, ctx)
	local cols = {}
	for _, c in ipairs(list(it.Columns, 12) or {}) do
		local n = type(c) == "table" and str(c.Name) or str(c)
		if n then table.insert(cols, { Name = n, Width = type(c) == "table" and num(c.Width, 0.2, 10, 1) or 1 }) end
	end
	if #cols == 0 then ctx.problem("Table needs Columns") return nil end
	local rows = {}
	for _, r in ipairs(list(it.Rows, LIMITS.Rows) or {}) do
		if type(r) == "table" then
			local row = {}
			for k, v in pairs(r) do
				if (type(k) == "number" or type(k) == "string") and scalar(v) ~= nil then row[k] = scalar(v) end
			end
			table.insert(rows, row)
		end
	end
	return { Id = str(it.Id, 40), Columns = cols, Rows = rows, Height = num(it.Height, 80, 600, 200), Search = bool(it.Search, false), Sortable = bool(it.Sortable, true) }
end
ITEM.Chart = function(it, ctx)
	local out = { ChartType = (it.Style == "line" or it.ChartType == "line") and "line" or "bar", Title = str(it.Title), Height = num(it.Height, 80, 500, 180), Min = num(it.Min, -1e9, 1e9, 0), Max = num(it.Max, -1e9, 1e9, nil) }
	out.Labels = {}
	for _, l in ipairs(list(it.Labels, 60) or {}) do table.insert(out.Labels, str(l, 30) or "") end
	local function vals(v)
		local o = {}
		for _, x in ipairs(list(v, 60) or {}) do table.insert(o, num(x, -1e9, 1e9, 0)) end
		return o
	end
	if type(it.Series) == "table" then
		out.Series = {}
		for _, s in ipairs(list(it.Series, 6) or {}) do
			if type(s) == "table" then table.insert(out.Series, { Name = str(s.Name) or "Series", Values = vals(s.Values) }) end
		end
	else
		out.Values = vals(it.Values)
	end
	return out
end
ITEM.Image = function(it, ctx)
	local img = str(it.Image, 60) or ""
	if not img:match("^rbxassetid://%d+$") then
		ctx.problem("Image must look like rbxassetid://123456 (links to other sites are not allowed)")
		return nil
	end
	local fit = it.Fit
	if fit ~= "Crop" and fit ~= "Stretch" then fit = "Fit" end
	return { Image = img, Height = num(it.Height, 30, 400, 120), Fit = fit, Caption = str(it.Caption, 120) }
end
ITEM.HubScripts = function(it)
	local only = {}
	for _, n in ipairs(list(it.Only, 20) or {}) do if str(n) then table.insert(only, str(n)) end end
	return { Only = only, Height = num(it.Height, 120, 600, 300) }
end
ITEM.Form = function(it, ctx)
	local fields = cleanFields(it.Fields, ctx)
	if #fields == 0 then ctx.problem("Form needs Fields") return nil end
	return { Name = str(it.Name), Fields = fields, Submit = str(it.Submit, 40) or "Submit", Action = cleanAction(it.Action, ctx) }
end
ITEM.Group = function(it, ctx, depth)
	return { Name = str(it.Name), Card = bool(it.Card, false), Collapsible = bool(it.Collapsible, false), Open = bool(it.Open, true), Items = cleanItems(it.Items, ctx, depth + 1) }
end
ITEM.Columns = function(it, ctx, depth)
	local out = { Count = num(it.Count, 1, 4, 2), Columns = {} }
	for i, c in ipairs(list(it.Columns, 4) or {}) do
		out.Columns[i] = { Items = cleanItems(type(c) == "table" and (c.Items or c) or {}, ctx, depth + 1) }
	end
	if #out.Columns == 0 then ctx.problem("Columns needs Columns = [ {Items}, {Items} ]") return nil end
	out.Count = math.max(out.Count, #out.Columns)
	return out
end
ITEM.Pages = function(it, ctx, depth)
	local out = { Pages = {} }
	for _, p in ipairs(list(it.Pages, 8) or {}) do
		if type(p) == "table" and str(p.Name) then
			table.insert(out.Pages, { Name = str(p.Name), Items = cleanItems(p.Items, ctx, depth + 1) })
		end
	end
	if #out.Pages == 0 then ctx.problem("Pages needs Pages = [ {Name, Items} ]") return nil end
	out.Default = str(it.Default)
	return out
end
Spec.ItemTypes = ITEM

cleanItems = function(items, ctx, depth)
	local out = {}
	if depth > LIMITS.Depth then ctx.problem("nesting is too deep") return out end
	for _, it in ipairs(list(items, LIMITS.Items) or {}) do
		if ctx.count >= LIMITS.Items then ctx.problem("too many items (limit " .. LIMITS.Items .. ")") break end
		if type(it) ~= "table" then
			ctx.problem("an item must be an object")
		else
			local kind = str(it.Type, 20)
			local fn = kind and ITEM[kind]
			if not fn then
				ctx.problem("item type '" .. tostring(kind) .. "' is not allowed. Allowed: " .. Spec.TypeList())
			else
				ctx.count += 1
				local clean = fn(it, ctx, depth)
				if clean then
					clean.Type = kind
					clean.Id = clean.Id or str(it.Id, 40)
					if kind == "Label" then
						-- interpolation keys are validated at build time against State
					end
					table.insert(out, clean)
				end
			end
		end
	end
	return out
end

function Spec.TypeList()
	local names = {}
	for k in pairs(ITEM) do table.insert(names, k) end
	table.sort(names)
	return table.concat(names, ", ")
end

function Spec.Validate(spec)
	local problems = {}
	local ctx = { count = 0, stateKeys = {}, problem = function(msg) if #problems < 30 then table.insert(problems, msg) end end }
	if type(spec) ~= "table" then
		return nil, { "the spec must be a JSON object" }
	end
	local clean = { Name = str(spec.Name) or "My App", State = {}, Tabs = {} }
	local theme = str(spec.Theme, 30)
	if theme and Polaris.Themes[theme] then clean.Theme = theme elseif theme then ctx.problem("theme '" .. theme .. "' does not exist") end
	clean.Persist = bool(spec.Persist, false)
	if type(spec.State) == "table" then
		local n = 0
		for k, v in pairs(spec.State) do
			if type(k) == "string" and k:match("^[%a_][%w_]*$") and #k <= 40 then
				n += 1
				if n > LIMITS.State then ctx.problem("too many State keys") break end
				local val = scalar(v)
				if val == nil then ctx.problem("State '" .. k .. "' must be a number, text or true/false") else clean.State[k] = val; ctx.stateKeys[k] = true end
			else
				ctx.problem("State key '" .. tostring(k) .. "' is not a plain word")
			end
		end
	end
	for _, t in ipairs(list(spec.Tabs, LIMITS.Tabs) or {}) do
		if type(t) == "table" then
			table.insert(clean.Tabs, { Name = str(t.Name) or ("Tab " .. (#clean.Tabs + 1)), Items = cleanItems(t.Items, ctx, 1) })
		end
	end
	if #clean.Tabs == 0 then
		ctx.problem("the spec needs at least one tab: \"Tabs\": [ { \"Name\": \"Home\", \"Items\": [ ... ] } ]")
		return nil, problems
	end
	return clean, problems
end

----------------------------------------------------------------
-- Build
----------------------------------------------------------------
local function interpolateKeys(text)
	local keys = {}
	for k in tostring(text):gmatch("{([%a_][%w_]*)}") do keys[k] = true end
	return keys
end

local function fmt(v)
	if type(v) == "number" then
		if v == math.floor(v) then return tostring(math.floor(v)) end
		return string.format("%.2f", v)
	end
	return tostring(v)
end

function Spec.Build(spec, opts)
	opts = opts or {}
	local clean, problems = Spec.Validate(spec)
	if not clean then error("[Polaris] Spec.Build: " .. table.concat(problems, "; "), 2) end
	local app = { Spec = clean, Problems = problems, States = {}, Tabs = {}, Ids = {}, Elements = {} }

	for k, v in pairs(clean.State) do
		app.States[k] = Polaris.State(v, clean.Persist and { Persist = k, Folder = "Polaris_app_" .. clean.Name:gsub("%W", "") } or nil)
	end

	local window = Polaris:CreateWindow({ Name = clean.Name, Theme = clean.Theme, Size = opts.Size })
	app.Window = window

	local function notify(title, text)
		Polaris:Notify({ Title = title or "Notice", Content = text or "", Duration = 3 })
	end

	local function runAction(a, value, form)
		if not a then return end
		local d = a.Do
		local ok, err = pcall(function()
			if d == "Sequence" then
				for _, step in ipairs(a.Steps) do runAction(step, value, form) end
			elseif d == "Notify" then
				notify(a.Title, a.FromValue and (a.Text .. tostring(value)) or a.Text)
			elseif d == "Set" then
				local v = a.Value
				if a.FromValue then v = value end
				app.States[a.Key]:Set(v)
			elseif d == "Add" then
				local cur = tonumber(app.States[a.Key]:Get()) or 0
				app.States[a.Key]:Set(cur + (a.Value or 1))
			elseif d == "Toggle" then
				app.States[a.Key]:Set(not app.States[a.Key]:Get())
			elseif d == "Reset" then
				app.States[a.Key]:Set(clean.State[a.Key])
			elseif d == "Copy" then
				if type(setclipboard) == "function" then setclipboard(a.Text) notify("Copied", "On your clipboard.") else notify("Cannot copy here", a.Text) end
			elseif d == "Goto" then
				for name, tab in pairs(app.Tabs) do
					if name == a.Tab then window:_selectTab(tab) end
				end
			elseif d == "Theme" then
				local name = a.FromValue and tostring(value) or a.Value
				if Polaris.Themes[name] then Polaris:SetTheme(name) end
			elseif d == "Run" then
				for _, s in ipairs(Polaris.HubScripts()) do
					if s.Name == a.Script and s.Run then s.Run() end
				end
			elseif d == "AddRow" then
				local tbl = app.Ids[a.Table]
				if tbl and tbl.AddRow then
					local row = {}
					if a.FromForm and type(form) == "table" then
						for k, v in pairs(form) do row[k] = v end
					end
					for k, v in pairs(a.Values or {}) do row[k] = v end
					tbl:AddRow(row)
				end
			elseif d == "ClearTable" then
				local tbl = app.Ids[a.Table]
				if tbl and tbl.Clear then tbl:Clear() end
			elseif Polaris.Actions[d] then
				Polaris.Actions[d](a.Args or {}, { App = app, Value = value, Form = form })
			end
		end)
		if not ok then warn("[Polaris] action '" .. tostring(d) .. "' failed: " .. tostring(err)) end
	end
	app.RunAction = function(_, a, v) runAction(a, v) end

	local buildItems

	local function buildItem(target, it)
		local t = it.Type
		local el
		local function register(e)
			if e and it.Id then app.Ids[it.Id] = e end
			if e then table.insert(app.Elements, e) end
			return e
		end
		if t == "Label" then
			local keys = interpolateKeys(it.Text)
			local function render()
				return (it.Text:gsub("{([%a_][%w_]*)}", function(k) local s = app.States[k] return s and fmt(s:Get()) or "{" .. k .. "}" end))
			end
			el = target:CreateLabel({ Text = render(), Size = it.Size, Color = it.Color })
			for k in pairs(keys) do
				if app.States[k] then el:_track(app.States[k]:Subscribe(function() el:SetText(render()) end)) end
			end
		elseif t == "Section" then
			el = target:CreateSection({ Name = it.Name })
		elseif t == "Spacer" then
			el = target:CreateSpacer({ Height = it.Height })
		elseif t == "Button" then
			el = target:CreateButton({ Name = it.Name, Callback = function() runAction(it.Action) end })
		elseif t == "Toggle" then
			local def = it.Default
			if it.Key then def = app.States[it.Key]:Get() == true end
			el = target:CreateToggle({ Name = it.Name, Default = def, Callback = function(v) runAction(it.Action, v) end })
			if it.Key then el:Link(app.States[it.Key]) end
		elseif t == "Slider" then
			local def = it.Default
			if it.Key and tonumber(app.States[it.Key]:Get()) then def = tonumber(app.States[it.Key]:Get()) end
			el = target:CreateSlider({ Name = it.Name, Min = it.Min, Max = it.Max, Default = def, Increment = it.Increment, Callback = function(v) runAction(it.Action, v) end })
			if it.Key then el:Link(app.States[it.Key]) end
		elseif t == "Dropdown" then
			local def = it.Default
			if it.Key then def = tostring(app.States[it.Key]:Get()) end
			local found = false
			for _, o in ipairs(it.Options) do if o == def then found = true end end
			if not found then def = it.Options[1] end
			el = target:CreateDropdown({ Name = it.Name, Options = it.Options, Default = def, Callback = function(v) runAction(it.Action, v) end })
			if it.Key then el:Link(app.States[it.Key]) end
		elseif t == "Textbox" then
			local def = it.Default
			if it.Key then def = tostring(app.States[it.Key]:Get()) end
			el = target:CreateTextbox({ Name = it.Name, Default = def, Placeholder = it.Placeholder, Callback = function(v) runAction(it.Action, v) end })
			if it.Key then el:Link(app.States[it.Key]) end
		elseif t == "Progress" then
			el = target:CreateProgress({ Name = it.Name, Max = it.Max, Value = it.Value })
			if it.Key then el:Bind(app.States[it.Key], function(v) return tonumber(v) or 0 end) end
		elseif t == "Stats" then
			el = target:CreateStats({ Items = it.Items })
		elseif t == "Table" then
			el = target:CreateTable({ Columns = it.Columns, Rows = it.Rows, Height = it.Height, Search = it.Search, Sortable = it.Sortable })
		elseif t == "Chart" then
			el = target:CreateChart({ Type = it.ChartType, Title = it.Title, Labels = it.Labels, Values = it.Values, Series = it.Series, Height = it.Height, Min = it.Min, Max = it.Max })
		elseif t == "Image" then
			el = target:CreateImage({ Image = it.Image, Height = it.Height, Fit = it.Fit, Caption = it.Caption })
		elseif t == "HubScripts" then
			local all, picked = Polaris.HubScripts(), {}
			local only = {}
			for _, n in ipairs(it.Only) do only[n] = true end
			for _, s in ipairs(all) do if #it.Only == 0 or only[s.Name] then table.insert(picked, s) end end
			el = target:CreateScriptLibrary({ Scripts = picked, Height = it.Height, Folder = "app_" .. clean.Name:gsub("%W", "") })
		elseif t == "Form" then
			el = target:CreateForm({ Name = it.Name, Fields = it.Fields, Submit = it.Submit, Callback = function(values)
				for _, f in ipairs(it.Fields) do
					if f.Key and app.States[f.Key] then app.States[f.Key]:Set(values[f.Name]) end
				end
				runAction(it.Action, nil, values)
			end })
		elseif t == "Group" then
			el = target:CreateGroup({ Name = it.Name, Card = it.Card, Collapsible = it.Collapsible, Open = it.Open })
			buildItems(el, it.Items)
		elseif t == "Columns" then
			el = target:CreateColumns({ Count = it.Count })
			for i, c in ipairs(it.Columns) do
				if el[i] then buildItems(el[i], c.Items) end
			end
		elseif t == "Pages" then
			local names = {}
			for _, p in ipairs(it.Pages) do table.insert(names, p.Name) end
			el = target:CreatePages({ Names = names, Default = it.Default })
			for _, p in ipairs(it.Pages) do
				local g = el.Pages[p.Name]
				if g then buildItems(g, p.Items) end
			end
		end
		return register(el)
	end

	buildItems = function(target, items)
		for _, it in ipairs(items) do
			local ok, err = pcall(buildItem, target, it)
			if not ok then
				warn("[Polaris] could not build a " .. tostring(it.Type) .. ": " .. tostring(err))
				table.insert(app.Problems, "could not build a " .. tostring(it.Type) .. ": " .. tostring(err))
			end
		end
	end

	for _, t in ipairs(clean.Tabs) do
		local tab = window:CreateTab({ Name = t.Name })
		app.Tabs[t.Name] = tab
		buildItems(tab, t.Items)
	end

	function app:GetState(key) return self.States[key] and self.States[key]:Get() end
	function app:SetState(key, v) if self.States[key] then self.States[key]:Set(v) end end
	function app:ToJSON(pretty) return Polaris.Util.JSON.encode(self.Spec, pretty) end
	function app:Destroy()
		if self.Window and self.Window.Destroy then pcall(self.Window.Destroy, self.Window) end
		for _, s in pairs(self.States) do s:Destroy() end
	end
	return app
end

----------------------------------------------------------------
-- Describe: the format explained for an AI (or a human)
----------------------------------------------------------------
function Spec.Describe()
	local actions = {}
	for k in pairs(BUILTIN_ACTIONS) do table.insert(actions, k) end
	for k in pairs(Polaris.Actions) do table.insert(actions, k) end
	table.sort(actions)
	return table.concat({
		"You design apps for the Polaris UI framework. Reply with ONE JSON object and nothing else (no markdown, no comments).",
		"Format: { \"Name\": text, \"Theme\": optional theme name, \"State\": { key: number|text|true/false }, \"Tabs\": [ { \"Name\": text, \"Items\": [ item, ... ] } ] }",
		"Every item is an object with a \"Type\" and an optional \"Id\". Allowed Types: " .. Spec.TypeList() .. ".",
		"Label {Text (may use {stateKey}), Size, Color: Accent|SubText|Text}; Section {Name}; Spacer {Height}; Button {Name, Action}; Toggle/Slider/Dropdown/Textbox {Name, Default, Key (a State key), Action; Slider: Min, Max, Increment; Dropdown: Options}; Progress {Name, Value, Max, Key}; Stats {Items from FPS, Ping, Players, Memory};",
		"Table {Id, Columns [text], Rows [[...]], Height, Search}; Chart {Style: bar|line, Title, Labels [text], Values [number] or Series [{Name, Values}], Height}; Image {Image: rbxassetid://123, Height}; HubScripts {Only: [names]};",
		"Form {Name, Fields [{Name, Type: Textbox|Number|Toggle|Dropdown|Slider, Required, Options, Key}], Submit, Action}; Group {Name, Card, Collapsible, Items}; Columns {Count, Columns [{Items}]}; Pages {Pages [{Name, Items}]}.",
		"Actions are objects { \"Do\": name, ... } or an array of up to " .. LIMITS.Steps .. " of them. Names: " .. table.concat(actions, ", ") .. ".",
		"Notify {Title, Text}; Set {Key, Value}; Add {Key, Value}; Toggle {Key}; Reset {Key}; Copy {Text}; Goto {Tab}; Theme {Value}; Run {Script: a built-in hub script name}; AddRow {Table: Id, Values, FromForm: true}; ClearTable {Table}.",
		"FromValue: true makes Set, Theme or Notify use the value the user just picked. Keys in actions must exist in State.",
		"Rules: no code, no URLs, no scripts. Keep it small and useful. Example:",
		'{"Name":"Clicker","State":{"count":0},"Tabs":[{"Name":"Play","Items":[{"Type":"Label","Text":"Clicks: {count}","Size":22},{"Type":"Button","Name":"Click me","Action":{"Do":"Add","Key":"count","Value":1}},{"Type":"Button","Name":"Reset","Action":{"Do":"Reset","Key":"count"}}]}]}',
	}, "\n")
end
