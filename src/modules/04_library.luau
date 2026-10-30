-- library: a data model for collections of scripts + the Script Library widget.
--
--   local lib = Polaris.Library.new({ Name = "My Scripts" })
--   lib:Add({ Name = "Hello", Description = "Says hi", Run = function() print("hi") end })
--   tab:CreateScriptLibrary({ Library = lib })

local Create, safeTween, Element, Tab = I.Create, I.safeTween, I.Element, I.Tab
local Kit, Util = Polaris.Kit, Polaris.Util
local JSON = Util.JSON

local Library = {}
Library.__index = Library
Polaris.Library = Library

local function asList(v)
	if type(v) == "table" then
		return v
	end
	local out = {}
	if type(v) == "string" then
		for part in v:gmatch("[^,]+") do
			local trimmed = part:match("^%s*(.-)%s*$")
			if trimmed ~= "" then
				table.insert(out, trimmed)
			end
		end
	end
	return out
end

local function isUrl(s)
	return type(s) == "string" and s:match("^https?://") ~= nil
end

-- Turn a user-written script definition into a clean entry (or raise a friendly error).
function Library.normalize(def)
	assert(type(def) == "table", "[Polaris] Library: a script must be a table like { Name = \"...\", Url = \"...\" }")
	assert(type(def.Name) == "string" and def.Name ~= "", "[Polaris] Library: every script needs a Name")
	local entry = {
		Name = def.Name,
		Id = def.Id or I.slugify(def.Name),
		Description = tostring(def.Description or def.Desc or ""),
		Author = def.Author and tostring(def.Author) or nil,
		Version = def.Version and tostring(def.Version) or nil,
		Tags = asList(def.Tags),
		Games = asList(def.Games or def.PlaceIds or def.Game),
		Icon = def.Icon,
		User = def.User == true or nil,
	}
	local src = def.Source
	local fn = def.Run or def.Callback or (type(src) == "function" and src) or nil
	if type(fn) == "function" then
		entry.Run = fn
	end
	local url = def.Url or def.URL or def.Link or (isUrl(src) and src) or nil
	if isUrl(url) then
		entry.Url = url
	end
	local code = def.Code or ((type(src) == "string" and not isUrl(src)) and src) or nil
	if type(code) == "string" and code ~= "" then
		entry.Code = code
	end
	assert(entry.Run or entry.Url or entry.Code, ("[Polaris] Library: script '%s' needs a Run function, a Url, or Code"):format(def.Name))
	return entry
end

function Library.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Library)
	self.Name = opts.Name or "Scripts"
	self.TrustedHosts = opts.TrustedHosts -- optional allow-list of hosts for Url scripts
	self._scripts = {}
	self._order = {}
	self._fav = {}
	self._runs = {}
	self._userDefs = {} -- scripts the player added through the UI (saved when files are available)
	self._events = Util.Events()
	self._folder = opts.Folder and ("Polaris_" .. I.slugify(opts.Folder)) or nil
	self:_load()
	if opts.Scripts then
		self:AddMany(opts.Scripts)
	end
	for _, def in ipairs(self._userDefs) do
		def.User = true
		pcall(self.Add, self, def)
	end
	return self
end

function Library:On(name, fn)
	return self._events:On(name, fn)
end

-- persistence of favourites + run counts (only where the executor offers file access)
function Library:_path()
	if self._folder and I.FS then
		return self._folder .. "/library.json"
	end
	return nil
end

function Library:_load()
	local path = self:_path()
	if not path then
		return
	end
	pcall(function()
		if I.FS.isfile(path) then
			local data = JSON.decode(I.FS.read(path))
			if type(data) == "table" then
				for _, id in ipairs(data.favourites or {}) do
					self._fav[id] = true
				end
				for id, n in pairs(data.runs or {}) do
					self._runs[id] = n
				end
				for _, def in ipairs(data.user or {}) do
					if type(def) == "table" then
						table.insert(self._userDefs, def)
					end
				end
			end
		end
	end)
end

function Library:_save()
	local path = self:_path()
	if not path then
		return
	end
	pcall(function()
		if not I.FS.isfile(self._folder .. "/.keep") then
			pcall(I.FS.mkdir, self._folder)
		end
		local favs = {}
		for id in pairs(self._fav) do
			table.insert(favs, id)
		end
		table.sort(favs)
		I.FS.write(path, JSON.encode({ favourites = favs, runs = self._runs, user = self._userDefs }))
	end)
end

function Library:Add(def)
	local entry = Library.normalize(def)
	if self._scripts[entry.Id] then
		-- replace in place so re-running a script never duplicates cards
		self._scripts[entry.Id] = entry
	else
		self._scripts[entry.Id] = entry
		table.insert(self._order, entry.Id)
	end
	self._events:Emit("change")
	return entry
end

-- A script the player typed in: a name plus a link (https://...) or Luau code.
-- Returns the entry, or nil and a friendly message.
function Library:AddUser(name, linkOrCode, description)
	name = tostring(name or ""):match("^%s*(.-)%s*$")
	local text = tostring(linkOrCode or ""):match("^%s*(.-)%s*$")
	if name == "" then
		return nil, "Give your script a name."
	end
	if text == "" then
		return nil, "Paste a link or some code."
	end
	local def = { Name = name, Description = description or "Added by you", Tags = { "mine" }, Author = "you", User = true }
	if text:find("^https?://") and not text:find("%s") then
		if not text:find("^https://") then
			return nil, "Links must start with https://"
		end
		def.Url = text
	else
		def.Code = text
	end
	local ok, entry = pcall(self.Add, self, def)
	if not ok then
		return nil, tostring(entry)
	end
	for i = #self._userDefs, 1, -1 do
		if I.slugify(self._userDefs[i].Name) == entry.Id then
			table.remove(self._userDefs, i)
		end
	end
	table.insert(self._userDefs, def)
	self:_save()
	return entry
end

function Library:AddMany(list)
	local added = {}
	for _, def in ipairs(list) do
		table.insert(added, self:Add(def))
	end
	return added
end

function Library:Remove(id)
	if self._scripts[id] then
		self._scripts[id] = nil
		table.remove(self._order, I.indexOf(self._order, id))
		for i = #self._userDefs, 1, -1 do
			if I.slugify(self._userDefs[i].Name) == id then
				table.remove(self._userDefs, i)
				self:_save()
			end
		end
		self._events:Emit("change")
		return true
	end
	return false
end

function Library:Get(id)
	return self._scripts[id]
end

function Library:Count()
	return #self._order
end

function Library:IsForThisGame(entry)
	if #entry.Games == 0 then
		return false
	end
	local place, gameId = game.PlaceId, game.GameId
	for _, g in ipairs(entry.Games) do
		local n = tonumber(g)
		if n and (n == place or n == gameId) then
			return true
		end
	end
	return false
end

function Library:Favourite(id, on)
	if on == nil then
		on = not self._fav[id]
	end
	self._fav[id] = on or nil
	self:_save()
	self._events:Emit("change")
	return on
end

function Library:IsFavourite(id)
	return self._fav[id] == true
end

function Library:Tags()
	local seen, out = {}, {}
	for _, id in ipairs(self._order) do
		for _, t in ipairs(self._scripts[id].Tags) do
			local key = t:lower()
			if not seen[key] then
				seen[key] = true
				table.insert(out, t)
			end
		end
	end
	table.sort(out, function(a, b)
		return a:lower() < b:lower()
	end)
	return out
end

-- filter: Text, Tag, Favourites (bool), ThisGame (bool)
function Library:Query(filter)
	filter = filter or {}
	local text = filter.Text and filter.Text:lower() or ""
	local tag = filter.Tag and filter.Tag:lower() or nil
	local out = {}
	for _, id in ipairs(self._order) do
		local e = self._scripts[id]
		local keep = true
		if text ~= "" then
			local hay = (e.Name .. " " .. e.Description .. " " .. (e.Author or "") .. " " .. table.concat(e.Tags, " ")):lower()
			keep = hay:find(text, 1, true) ~= nil
		end
		if keep and tag then
			keep = false
			for _, t in ipairs(e.Tags) do
				if t:lower() == tag then
					keep = true
				end
			end
		end
		if keep and filter.Favourites then
			keep = self._fav[id] == true
		end
		if keep and filter.ThisGame then
			keep = self:IsForThisGame(e)
		end
		if keep then
			table.insert(out, e)
		end
	end
	table.sort(out, function(a, b)
		local ga, gb = self:IsForThisGame(a), self:IsForThisGame(b)
		if ga ~= gb then
			return ga
		end
		local fa, fb = self._fav[a.Id] == true, self._fav[b.Id] == true
		if fa ~= fb then
			return fa
		end
		return a.Name:lower() < b.Name:lower()
	end)
	return out
end

local function hostAllowed(self, url)
	if not self.TrustedHosts or #self.TrustedHosts == 0 then
		return true
	end
	local host = Util.hostOf(url):lower()
	for _, h in ipairs(self.TrustedHosts) do
		if host == h:lower() then
			return true
		end
	end
	return false
end

-- Where would running this script fetch code from? (for confirmation prompts)
function Library:Describe(entry)
	if entry.Run then
		return "a function in this script"
	elseif entry.Code then
		return "code stored in this library"
	end
	return Util.hostOf(entry.Url)
end

function Library:NeedsConfirm(entry)
	return entry.Url ~= nil and entry.Run == nil and entry.Code == nil
end

-- Run a script safely. Returns ok, errorMessage.
function Library:Run(idOrEntry)
	local entry = type(idOrEntry) == "table" and idOrEntry or self._scripts[idOrEntry]
	if not entry then
		return false, "That script is not in the library."
	end
	local ok, err
	if entry.Run then
		ok, err = pcall(entry.Run, entry)
	else
		local code = entry.Code
		if not code then
			if not hostAllowed(self, entry.Url) then
				err = "Blocked: " .. Util.hostOf(entry.Url) .. " is not in this library's TrustedHosts list."
				self._events:Emit("error", entry, err)
				return false, err
			end
			local body, fetchErr = Util.Http.Get(entry.Url)
			if not body then
				err = "Could not download the script (" .. tostring(fetchErr) .. ")."
				self._events:Emit("error", entry, err)
				return false, err
			end
			code = body
		end
		local loader = loadstring
		if type(loader) ~= "function" then
			err = "This place does not allow loadstring, so downloaded scripts cannot run here. Use a Run function instead."
			self._events:Emit("error", entry, err)
			return false, err
		end
		local fn, compileErr = loader(code)
		if not fn then
			err = "The script has a mistake and could not start: " .. tostring(compileErr)
			self._events:Emit("error", entry, err)
			return false, err
		end
		ok, err = pcall(fn)
	end
	if ok then
		self._runs[entry.Id] = (self._runs[entry.Id] or 0) + 1
		self:_save()
		self._events:Emit("run", entry)
		return true
	end
	err = tostring(err)
	self._events:Emit("error", entry, err)
	return false, err
end

-- Add scripts from a manifest: a table, a JSON string, or an https URL to a JSON file.
-- Format: { "scripts": [ { "Name": "...", "Url": "...", "Description": "...", "Tags": ["..."] } ] }
function Library:LoadManifest(source)
	local data = source
	if type(source) == "string" then
		local text = source
		if isUrl(source) then
			local body, err = Util.Http.Get(source)
			if not body then
				return 0, "Could not download the manifest: " .. tostring(err)
			end
			text = body
		end
		local decoded, jerr = JSON.decode(text)
		if not decoded then
			return 0, "The manifest is not valid JSON: " .. tostring(jerr)
		end
		data = decoded
	end
	local list = data.scripts or data
	local added, problems = 0, {}
	for i, def in ipairs(list) do
		local ok, err = pcall(function()
			self:Add(def)
		end)
		if ok then
			added += 1
		else
			table.insert(problems, ("#%d: %s"):format(i, tostring(err):gsub("^.-%[Polaris%] ", "")))
		end
	end
	return added, #problems > 0 and table.concat(problems, "; ") or nil
end

-- JSON text of everything that can be serialised (function-only scripts are skipped)
function Library:Export()
	local out = {}
	for _, id in ipairs(self._order) do
		local e = self._scripts[id]
		if e.Url or e.Code then
			table.insert(out, {
				Name = e.Name, Id = e.Id, Description = e.Description, Author = e.Author, Version = e.Version,
				Tags = e.Tags, Games = e.Games, Url = e.Url, Code = e.Code,
			})
		end
	end
	return JSON.encode({ name = self.Name, scripts = out }, true)
end

----------------------------------------------------------------
-- Widget
----------------------------------------------------------------

local LibEl = setmetatable({}, { __index = Element })
LibEl.__index = LibEl

local function pill(parent, text, active, onClick, width)
	local b = Kit.button(parent, text, {
		Color = active and "Accent" or "Secondary",
		TextColor = (not active) and "SubText" or nil,
		Size = UDim2.new(0, width or (#text * 7 + 22), 0, 24),
		TextSize = 12,
		Radius = 12,
	})
	b.Activated:Connect(onClick)
	return b
end

function LibEl:_create(window, tab, config)
	local self = Element._new(window, tab, config, "ScriptLibrary")
	setmetatable(self, LibEl)

	local lib = config.Library
	if not lib then
		lib = Library.new({ Name = config.Name or "Scripts", Folder = config.Folder, Scripts = config.Scripts, TrustedHosts = config.TrustedHosts })
	end
	if config.Manifest then
		task.spawn(function()
			local n, err = lib:LoadManifest(config.Manifest)
			if err then
				Polaris:Notify({ Title = "Library", Content = err, Type = "warning" })
			end
		end)
	end
	self.Library = lib
	self._filter = { Text = "", Tag = nil, Favourites = false, ThisGame = false }
	self._confirm = config.Confirm == nil and "remote" or config.Confirm

	local height = type(config.Height) == "number" and config.Height or 340
	local row = Create("Frame", { Name = "ScriptLibrary", Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, Parent = tab._content })
	self._container = row
	local holder = Create("Frame", { Name = "Holder", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1, Parent = row })
	self._holder = holder

	-- top bar: search + quick filters
	local bar = Create("Frame", { Name = "Bar", Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 1, Parent = holder })
	local search = Kit.input(bar, { Placeholder = "Search " .. lib.Name .. "...", Size = UDim2.new(1, -236, 0, 30), TextSize = 14 })
	self._search = search
	local addBtn = Kit.button(bar, "+ Add", { Name = "AddScript", Color = "Accent", Size = UDim2.new(0, 62, 0, 30), Position = UDim2.new(1, -232, 0, 0), TextSize = 12 })
	local fav = Kit.button(bar, "Favourites", { Color = "Secondary", TextColor = "SubText", Size = UDim2.new(0, 84, 0, 30), Position = UDim2.new(1, -166, 0, 0), TextSize = 12 })
	local here = Kit.button(bar, "This game", { Color = "Secondary", TextColor = "SubText", Size = UDim2.new(0, 78, 0, 30), Position = UDim2.new(1, -78, 0, 0), TextSize = 12 })
	self._favBtn, self._hereBtn = fav, here

	-- tag chips
	self._tags = Create("ScrollingFrame", {
		Name = "Tags", Size = UDim2.new(1, 0, 0, 28), Position = UDim2.new(0, 0, 0, 36), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 0, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X, Parent = holder,
	})
	Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = self._tags })

	self._list = Kit.scroll(holder, { Padding = 6, Size = UDim2.new(1, 0, 1, -94), Position = UDim2.new(0, 0, 0, 68), Name = "Cards" })
	self._status = Kit.label(holder, "", { Size = 12, Color = "SubText", Position = UDim2.new(0, 0, 1, -20), Height = 18 })

	self:_track(search:GetPropertyChangedSignal("Text"):Connect(function()
		self._filter.Text = search.Text
		self._status.Text = ""
		self:Render()
	end))
	self:_track(addBtn.Activated:Connect(function()
		self:_openAddForm()
	end))
	self:_track(fav.Activated:Connect(function()
		self._filter.Favourites = not self._filter.Favourites
		self._status.Text = ""
		self:Render()
	end))
	self:_track(here.Activated:Connect(function()
		self._filter.ThisGame = not self._filter.ThisGame
		self._status.Text = ""
		self:Render()
	end))
	self._sub = lib:On("change", function()
		if not self._destroyed then
			self:Render()
		end
	end)

	if config.Height == nil or config.Height == "Fill" then
		Polaris._bindFill(self, 240, 8)
	end
	self._value = ""
	self:Render()
	return self
end

-- "+ Add": a small form for your own script (name, then a link or code)
function LibEl:_openAddForm()
	if self._form and self._form.Parent then
		return
	end
	local form = Kit.frame(self._holder, { Color = "Background", Radius = 10, Stroke = "Accent", Size = UDim2.new(1, 0, 1, -4), Position = UDim2.new(0, 0, 0, 0), Name = "AddForm" })
	form.ZIndex = 50
	self._form = form
	Kit.label(form, "Add your own script", { Size = 16, Bold = true, Position = UDim2.new(0, 12, 0, 8), Width = 1, WidthOffset = -24, Height = 22 })
	local name = Kit.input(form, { Name = "NameBox", Placeholder = "Name (for example: My fly script)", Size = UDim2.new(1, -24, 0, 32), Position = UDim2.new(0, 12, 0, 36) })
	local body = Kit.input(form, { Name = "CodeBox", Placeholder = "Paste a link that starts with https:// or paste your code here", MultiLine = true, Size = UDim2.new(1, -24, 1, -128), Position = UDim2.new(0, 12, 0, 76), TextSize = 13 })
	local msg = Kit.label(form, "", { Size = 12, Color = "Warning", Position = UDim2.new(0, 12, 1, -46), Width = 1, WidthOffset = -24, Height = 16 })
	local save = Kit.button(form, "Add it", { Name = "SaveScript", Color = "Accent", Size = UDim2.new(0, 110, 0, 32), Position = UDim2.new(1, -234, 1, -38), TextSize = 14 })
	local cancel = Kit.button(form, "Cancel", { Name = "CancelScript", Color = "Secondary", TextColor = "SubText", Size = UDim2.new(0, 110, 0, 32), Position = UDim2.new(1, -118, 1, -38), TextSize = 14 })
	for _, box in { name, body } do
		box.ZIndex = 51
	end
	save.ZIndex, cancel.ZIndex = 51, 51
	self:_track(cancel.Activated:Connect(function()
		form:Destroy()
	end))
	self:_track(save.Activated:Connect(function()
		local entry, problem = self.Library:AddUser(name.Text, body.Text)
		if not entry then
			msg.Text = problem or "That did not work."
			return
		end
		form:Destroy()
		self._status.Text = "Added " .. entry.Name .. "."
		Polaris:Notify({ Title = "Added", Content = entry.Name .. " is in your library.", Type = "success", Duration = 2.5 })
	end))
end

function LibEl:_runEntry(entry)
	local lib = self.Library
	local function go()
		self._status.Text = "Running " .. entry.Name .. "..."
		local ok, err = lib:Run(entry)
		if self._destroyed then
			return
		end
		if ok then
			self._status.Text = "Ran " .. entry.Name .. " successfully."
			Polaris:Notify({ Title = entry.Name, Content = "Started.", Type = "success", Duration = 2.5 })
		else
			self._status.Text = "Problem with " .. entry.Name
			Polaris:Notify({ Title = entry.Name .. " did not start", Content = tostring(err), Type = "error", Duration = 6 })
		end
		if self._config.OnRun then
			I.invokeCallback(self._config.OnRun, entry, ok, err)
		end
		self:Render()
	end
	local needs = self._confirm == true or (self._confirm == "remote" and lib:NeedsConfirm(entry))
	if needs then
		self._window:Dialog({
			Title = "Run " .. entry.Name .. "?",
			Content = "This will download code from " .. lib:Describe(entry) .. " and run it on your device. Only continue if you trust it.",
			Buttons = { { Name = "Cancel" }, { Name = "Run it", Callback = go } },
		})
	else
		go()
	end
end

function LibEl:_card(entry)
	local lib = self.Library
	local forHere = lib:IsForThisGame(entry)
	local card = Kit.frame(self._list, { Color = "Secondary", Radius = 8, Stroke = forHere and "Accent" or true, Size = UDim2.new(1, -4, 0, 72), Name = "Card" })
	card.LayoutOrder = 0
	local icon = Kit.frame(card, { Color = entry.IconColor or Kit.colorFor(entry.Name), Radius = 8, Size = UDim2.new(0, 44, 0, 44), Position = UDim2.new(0, 10, 0, 14) })
	local glyph = type(entry.Icon) == "string" and not entry.Icon:match("^rbxassetid") and entry.Icon:sub(1, 2) or entry.Name:sub(1, 1):upper()
	local g = Kit.label(icon, glyph, { Size = 22, Bold = true, Align = "Center", Height = 44, Color = Color3.fromRGB(20, 20, 28) })
	if type(entry.Icon) == "string" and entry.Icon:match("^rbxassetid") then
		g.Text = ""
		Create("ImageLabel", { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.new(0, 4, 0, 4), BackgroundTransparency = 1, Image = entry.Icon, Parent = icon })
	end
	local title = entry.Name .. (entry.Version and ("  v" .. entry.Version) or "")
	Kit.label(card, title, { Size = 15, Bold = true, Position = UDim2.new(0, 64, 0, 8), Width = 1, WidthOffset = -64 - 128, Height = 20, Truncate = true })
	Kit.label(card, entry.Description ~= "" and entry.Description or "No description yet.", {
		Size = 12, Color = "SubText", Position = UDim2.new(0, 64, 0, 28), Width = 1, WidthOffset = -64 - 128, Height = 16, Truncate = true,
	})
	local meta = {}
	if forHere then
		table.insert(meta, "FOR THIS GAME")
	end
	if entry.Author then
		table.insert(meta, "by " .. entry.Author)
	end
	if #entry.Tags > 0 then
		table.insert(meta, table.concat(entry.Tags, ", "))
	end
	local runs = lib._runs[entry.Id]
	if runs and runs > 0 then
		table.insert(meta, "ran " .. runs .. "x")
	end
	Kit.label(card, table.concat(meta, "  \u{2022}  "), { Size = 11, Color = forHere and "Accent" or "SubText", Position = UDim2.new(0, 64, 0, 46), Width = 1, WidthOffset = -64 - 128, Height = 16, Truncate = true })

	local isFav = lib:IsFavourite(entry.Id)
	local star = Kit.button(card, isFav and "\u{2605}" or "\u{2606}", {
		Color = "Primary", TextColor = isFav and "Warning" or "SubText", Size = UDim2.new(0, 36, 0, 36), Position = UDim2.new(1, -122, 0, 18), TextSize = 18, Radius = 18,
	})
	star.Activated:Connect(function()
		lib:Favourite(entry.Id)
	end)
	if entry.User then
		local del = Kit.button(card, "remove", { Name = "RemoveScript", Color = "Primary", TextColor = "SubText", Size = UDim2.new(0, 70, 0, 14), Position = UDim2.new(1, -80, 0, 56), TextSize = 10, Radius = 4 })
		del.Activated:Connect(function()
			lib:Remove(entry.Id)
		end)
	end
	local run = Kit.button(card, "Run", { Color = "Accent", Size = UDim2.new(0, 70, 0, 36), Position = UDim2.new(1, -80, 0, 18), TextSize = 14 })
	run.Activated:Connect(function()
		self:_runEntry(entry)
	end)
	return card
end

function LibEl:Render()
	if self._destroyed or not self._list then
		return
	end
	local lib, f = self.Library, self._filter
	-- tag chips
	Kit.clear(self._tags)
	local tags = lib:Tags()
	self._tags.Visible = #tags > 0
	if #tags > 0 then
		local all = pill(self._tags, "All", f.Tag == nil, function()
			f.Tag = nil
			self._status.Text = ""
			self:Render()
		end, 44)
		all.LayoutOrder = 0
		for i, t in ipairs(tags) do
			local p = pill(self._tags, t, f.Tag ~= nil and f.Tag:lower() == t:lower(), function()
				f.Tag = (f.Tag ~= nil and f.Tag:lower() == t:lower()) and nil or t
				self._status.Text = ""
				self:Render()
			end)
			p.LayoutOrder = i
		end
		self._list.Position = UDim2.new(0, 0, 0, 68)
		self._list.Size = UDim2.new(1, 0, 1, -94)
	else
		self._list.Position = UDim2.new(0, 0, 0, 38)
		self._list.Size = UDim2.new(1, 0, 1, -62)
	end
	Kit.paint(self._favBtn, "BackgroundColor3", f.Favourites and "Accent" or "Secondary")
	self._favBtn.TextColor3 = f.Favourites and Color3.new(1, 1, 1) or Kit.theme().SubText
	Kit.paint(self._hereBtn, "BackgroundColor3", f.ThisGame and "Accent" or "Secondary")
	self._hereBtn.TextColor3 = f.ThisGame and Color3.new(1, 1, 1) or Kit.theme().SubText

	-- cards
	Kit.clear(self._list)
	local results = lib:Query(f)
	for i, entry in ipairs(results) do
		local c = self:_card(entry)
		c.LayoutOrder = i
	end
	if #results == 0 then
		local hint = lib:Count() == 0 and "This library is empty. Add scripts with library:Add({ Name = ..., Url = ... })."
			or "Nothing matches. Clear the search or the filters."
		local l = Kit.label(self._list, hint, { Size = 14, Color = "SubText", Align = "Center", Wrap = true, Height = 60, Name = "Empty" })
		l.LayoutOrder = 1
	end
	local favCount = 0
	for _ in pairs(lib._fav) do
		favCount += 1
	end
	if not self._status.Text:match("^Ran ") and not self._status.Text:match("^Problem") and not self._status.Text:match("^Running") then
		self._status.Text = ("%d of %d scripts  \u{2022}  %d favourites"):format(#results, lib:Count(), favCount)
	end
end

function LibEl:_setValue(v)
	if type(v) == "string" and self._search then
		self._search.Text = v
	end
end

function LibEl:Destroy()
	if self._sub then
		self._sub.Disconnect()
	end
	Element.Destroy(self)
end

function Tab:CreateScriptLibrary(config)
	if config and getmetatable(config) == Library then
		config = { Library = config }
	elseif type(config) == "table" and #config > 0 and config.Name == nil then
		config = { Scripts = config }
	end
	return LibEl:_create(self._window, self, config or {})
end
Polaris.ElementTypes.ScriptLibrary = function(t, c) return t:CreateScriptLibrary(c) end
