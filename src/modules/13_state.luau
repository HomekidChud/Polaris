-- state + storage + plugins: reactive values, saved settings, and a way to define brand new element types.

local Element, Tab = I.Element, I.Tab
local Kit = Polaris.Kit
local JSON = Polaris.Util.JSON or I.JSON

----------------------------------------------------------------
-- Storage: tiny key/value store. Files where the executor allows it, memory otherwise.
----------------------------------------------------------------
local memoryStores = {}
local Storage = {}
Storage.__index = Storage

function Polaris.Storage(folder)
	folder = tostring(folder or "Polaris_data")
	if memoryStores[folder] then
		return memoryStores[folder]
	end
	local self = setmetatable({ _folder = folder, _data = {} }, Storage)
	self._path = I.FS and (folder .. "/storage.json") or nil
	if self._path then
		pcall(function()
			if I.FS.isfile(self._path) then
				local data = JSON.decode(I.FS.read(self._path))
				if type(data) == "table" then self._data = data end
			end
		end)
	end
	memoryStores[folder] = self
	return self
end

function Storage:_save()
	if not self._path then return false end
	local ok = pcall(function()
		if not I.FS.isfile(self._folder .. "/.keep") then
			pcall(I.FS.mkdir, self._folder)
			pcall(I.FS.write, self._folder .. "/.keep", "")
		end
		I.FS.write(self._path, JSON.encode(self._data))
	end)
	return ok
end
function Storage:Get(key, default)
	local v = self._data[tostring(key)]
	if v == nil then return default end
	return v
end
function Storage:Set(key, value)
	self._data[tostring(key)] = value
	return self:_save()
end
function Storage:Delete(key)
	self._data[tostring(key)] = nil
	return self:_save()
end
function Storage:Keys()
	local out = {}
	for k in pairs(self._data) do table.insert(out, k) end
	table.sort(out)
	return out
end
function Storage:IsPersistent() return self._path ~= nil end

----------------------------------------------------------------
-- State
----------------------------------------------------------------
local State = {}
State.__index = State

-- opts: Persist = "key" (saved in Storage), Folder
function Polaris.State(initial, opts)
	opts = opts or {}
	local self = setmetatable({ _value = initial, _subs = {}, _next = 0 }, State)
	if opts.Persist then
		self._store = Polaris.Storage(opts.Folder or "Polaris_state")
		self._key = tostring(opts.Persist)
		local saved = self._store:Get(self._key)
		if saved ~= nil then self._value = saved end
	end
	return self
end

function State:Get() return self._value end

function State:_notify()
	local snapshot = {}
	for id, fn in pairs(self._subs) do table.insert(snapshot, { id, fn }) end
	table.sort(snapshot, function(a, b) return a[1] < b[1] end)
	for _, pair in ipairs(snapshot) do
		if self._subs[pair[1]] then
			local ok, err = pcall(pair[2], self._value)
			if not ok then warn("[Polaris] State subscriber error: " .. tostring(err)) end
		end
	end
end

function State:Set(v)
	if v == self._value and type(v) ~= "table" then return end
	self._value = v
	if self._store then self._store:Set(self._key, v) end
	self:_notify()
end

function State:Update(fn)
	self:Set(fn(self._value))
end

-- returns an object with :Disconnect()
function State:Subscribe(fn, immediate)
	self._next += 1
	local id = self._next
	self._subs[id] = fn
	if immediate then pcall(fn, self._value) end
	local subs = self._subs
	return { Disconnect = function() subs[id] = nil end }
end

function State:Map(fn)
	local derived = Polaris.State(fn(self._value))
	derived._source = self:Subscribe(function(v) derived:Set(fn(v)) end)
	return derived
end

function State:Destroy()
	self._subs = {}
	if self._source then self._source:Disconnect() end
end

-- Computed value from several states: Polaris.Computed({ a, b }, function(av, bv) return av + bv end)
function Polaris.Computed(states, fn)
	local function values()
		local vals = {}
		for i, s in ipairs(states) do vals[i] = s:Get() end
		return table.unpack(vals)
	end
	local derived = Polaris.State(fn(values()))
	derived._sources = {}
	for _, s in ipairs(states) do
		table.insert(derived._sources, s:Subscribe(function() derived:Set(fn(values())) end))
	end
	return derived
end

-- element:Bind(state, transform?)  state -> element (one way)
function Element:Bind(state, transform)
	local function apply(v)
		if self._destroyed then return end
		local out = v
		if transform then
			local ok, res = pcall(transform, v)
			if not ok then warn("[Polaris] Bind transform error: " .. tostring(res)) return end
			out = res
		end
		local ok, err = pcall(self.Set, self, out, true)
		if not ok then warn("[Polaris] Bind could not set the element: " .. tostring(err)) end
	end
	apply(state:Get())
	self:_track(state:Subscribe(apply))
	return self
end

-- element:Link(state)  two way: the element writes to the state and follows it
function Element:Link(state)
	local previous = self._config.Callback
	self._config.Callback = function(v, ...)
		state:Set(v)
		if previous then I.invokeCallback(previous, v, ...) end
	end
	return self:Bind(state)
end

----------------------------------------------------------------
-- Plugins: define a new element type once, use it everywhere (Tab:CreateX, Tab:Add, specs, JSON)
----------------------------------------------------------------
Polaris.PluginList = {}
Polaris.Elements = {}

-- def: Height (number or function(config)), Build = function(frame, config, element, ctx), Set = function(element, value), Default
function Polaris.DefineElement(kind, def)
	assert(type(kind) == "string" and kind:match("^%u[%w]*$"), "[Polaris] DefineElement: kind must be a CapitalisedWord")
	assert(type(def) == "table" and type(def.Build) == "function", "[Polaris] DefineElement: def.Build(frame, config, element, ctx) is required")
	local existing = Polaris.ElementTypes[kind]
	assert(not existing or Polaris.Elements[kind], "[Polaris] DefineElement: '" .. kind .. "' is a built in element type")
	local Class = Polaris._newClass()
	function Class:_setValue(v)
		self._value = v
		if def.Set then
			local ok, err = pcall(def.Set, self, v)
			if not ok then warn("[Polaris] " .. kind .. " Set error: " .. tostring(err)) end
		end
	end
	function Class:SetHeight(h) Polaris._setHeight(self, h) end
	Tab["Create" .. kind] = function(self, config)
		config = config or {}
		local h = type(def.Height) == "function" and def.Height(config) or def.Height or 60
		local el, row = Polaris._scaffold(Class, self._window, self, config, kind, h)
		el.Frame = row
		if config.Default ~= nil then el._value = config.Default elseif def.Default ~= nil then el._value = def.Default end
		local ctx = {
			Frame = row, Window = self._window, Create = I.Create, Kit = Kit, Polaris = Polaris,
			Theme = function() return Kit.theme() end,
			SetHeight = function(newH) Polaris._setHeight(el, newH) end,
		}
		local ok, err = pcall(def.Build, row, config, el, ctx)
		if not ok then
			el.BuildError = tostring(err)
			Kit.label(row, kind .. " error: " .. tostring(err), { Name = "BuildError", Color = Color3.fromRGB(255, 107, 120), Size = 13, Wrap = true, Height = h })
			warn("[Polaris] " .. kind .. " Build error: " .. tostring(err))
		end
		return el
	end
	Polaris.ElementTypes[kind] = function(t, c) return t["Create" .. kind](t, c) end
	Polaris.Elements[kind] = def
	return Class
end

-- Polaris.Use(function(Polaris) ... end)  or  Polaris.Use({ Name = "x", Install = function(Polaris) end })
function Polaris.Use(plugin, ...)
	local name, fn = "plugin", nil
	if type(plugin) == "function" then
		fn = plugin
	elseif type(plugin) == "table" and type(plugin.Install) == "function" then
		fn, name = plugin.Install, tostring(plugin.Name or name)
	else
		error("[Polaris] Use expects a function or a table with an Install function", 2)
	end
	local ok, err = pcall(fn, Polaris, ...)
	if not ok then
		error("[Polaris] plugin '" .. name .. "' failed to install: " .. tostring(err), 2)
	end
	table.insert(Polaris.PluginList, name)
	return Polaris
end

-- A new Builder block: Polaris.DefineBlock("Thing", { Label, Color, new, emit, apply, item, props, validate })
function Polaris.DefineBlock(kind, def)
	local B = I.Builder
	assert(type(kind) == "string" and type(def) == "table", "[Polaris] DefineBlock(kind, def)")
	for _, f in ipairs({ "new", "emit", "apply", "props" }) do
		assert(type(def[f]) == "function", "[Polaris] DefineBlock: def." .. f .. " must be a function")
	end
	def.Label = def.Label or kind
	def.Color = def.Color or Color3.fromRGB(120, 120, 140)
	B.Kinds[kind] = def
	for _, b in ipairs(B.BlockDefs) do
		if b.Kind == kind then
			b.Label, b.Color = def.Label, def.Color
			return def
		end
	end
	table.insert(B.BlockDefs, { Kind = kind, Label = def.Label, Color = def.Color })
	return def
end
