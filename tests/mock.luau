-- Roblox environment mock for testing Polaris under Lune.
-- Provides just enough of the Roblox API surface for Polaris's logic tests.
-- This does NOT verify visuals, layout, or real input behavior - see README.

local M = {}

----------------------------------------------------------------
-- Value types
----------------------------------------------------------------

function M.Vector2(x, y)
	return setmetatable({ __TYPE = "Vector2", X = x or 0, Y = y or 0 }, {
		__sub = function(a, b)
			return M.Vector2(a.X - b.X, a.Y - b.Y)
		end,
		__add = function(a, b)
			return M.Vector2(a.X + b.X, a.Y + b.Y)
		end,
	})
end

local Color3 = {}
Color3.__TYPE = "Color3"
M.Color3 = Color3

function Color3.new(r, g, b)
	return {
		__COLOR3 = true,
		R = r or 0, G = g or 0, B = b or 0,
		ToHSV = function(self)
			-- simple rgb->hsv
			local max = math.max(self.R, self.G, self.B)
			local min = math.min(self.R, self.G, self.B)
			local d = max - min
			local h = 0
			if d > 0 then
				if max == self.R then h = ((self.G - self.B) / d) % 6
				elseif max == self.G then h = (self.B - self.R) / d + 2
				else h = (self.R - self.G) / d + 4 end
				h = h / 6
			end
			local s = max == 0 and 0 or d / max
			return h, s, max
		end,
	}
end
function Color3.fromRGB(r, g, b)
	return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	-- hsv->rgb
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p = v * (1 - s)
	local q = v * (1 - f * s)
	local t = v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then return Color3.new(v, t, p)
	elseif i == 1 then return Color3.new(q, v, p)
	elseif i == 2 then return Color3.new(p, v, t)
	elseif i == 3 then return Color3.new(p, q, v)
	elseif i == 4 then return Color3.new(t, p, v)
	else return Color3.new(v, p, q) end
end

function M.UDim(s, o)
	return { __TYPE = "UDim", Scale = s or 0, Offset = o or 0 }
end
function M.UDim2(xs, xo, ys, yo)
	return { __TYPE = "UDim2", X = M.UDim(xs, xo), Y = M.UDim(ys, yo) }
end

-- Enum: Enum.KeyCode.E etc, auto-creates enum items
local function makeEnumItem(name)
	return { __ENUMITEM = true, Name = name, NameString = name }
end
M.Enum = setmetatable({}, {
	__index = function(t, category)
		local cat = setmetatable({}, {
			__index = function(c, itemName)
				local item = makeEnumItem(itemName)
				rawset(c, itemName, item)
				return item
			end,
		})
		rawset(t, category, cat)
		return cat
	end,
})

function M.TweenInfo(_time, _style, _dir)
	return { __TYPE = "TweenInfo" }
end
function M.NumberSequence(v)
	return { __TYPE = "NumberSequence" }
end
function M.ColorSequence(a, b)
	return { __TYPE = "ColorSequence" }
end
function M.NumberSequenceKeypoint(t, v)
	return { __TYPE = "NumberSequenceKeypoint", Time = t, Value = v }
end
function M.ColorSequenceKeypoint(t, c)
	return { __TYPE = "ColorSequenceKeypoint", Time = t, Value = c }
end

----------------------------------------------------------------
-- typeof
----------------------------------------------------------------

function M.typeof(v)
	if type(v) == "table" then
		if v.__COLOR3 then return "Color3" end
		if v.__ENUMITEM then return "EnumItem" end
		if v.__INSTANCE then return "Instance" end
	end
	return type(v)
end

----------------------------------------------------------------
-- Signals
----------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new(name)
	return setmetatable({
		_name = name,
		_handlers = {},
		_fired = {},
	}, Signal)
end

function Signal:Connect(fn)
	local conn = {
		Connected = true,
		_fn = fn,
		Disconnect = function(self)
			self.Connected = false
			for i, h in self._parent._handlers do
				if h == self then
					table.remove(self._parent._handlers, i)
					break
				end
			end
		end,
		_parent = self,
	}
	table.insert(self._handlers, conn)
	return conn
end

function Signal:Fire(...)
	for _, h in self._handlers do
		if h.Connected then
			h._fn(...)
		end
	end
	table.insert(self._fired, { ... })
end

function Signal:FireOnce(...)
	for _, h in self._handlers do
		if h.Connected then
			h._fn(...)
		end
	end
end

----------------------------------------------------------------
-- Instances
----------------------------------------------------------------

local Instance = {}
Instance.__index = Instance

local EVENT_NAMES = {
	InputBegan = true, InputEnded = true, InputChanged = true,
	Activated = true, MouseEnter = true, MouseLeave = true,
	MouseButton1Down = true, MouseButton1Up = true,
	FocusLost = true, FocusEnter = true, AncestryChanged = true,
	Changed = true, Destroying = true, Heartbeat = true,
}

local allInstances = {}

function M.InstanceNew(className)
	local self = setmetatable({
		__INSTANCE = true,
		_className = className,
		_props = {
			Name = className,
			Visible = true,
			AbsolutePosition = M.Vector2(0, 0),
			AbsoluteSize = M.Vector2(500, 500),
		},
		_signals = {},
		_children = {},
		_destroyed = false,
	}, Instance)
	allInstances[self] = true
	return self
end

function Instance:_getSignal(name)
	if not self._signals[name] then
		self._signals[name] = Signal.new(name)
	end
	return self._signals[name]
end

function Instance:Destroy()
	self._destroyed = true
	local par = self._props.Parent
	if par and par._children then
		local i = table.find(par._children, self)
		if i then
			table.remove(par._children, i)
		end
	end
	self._props.Parent = nil
	for _, sig in self._signals do
		for _, h in sig._handlers do
			h.Connected = false
		end
	end
	for _, child in self._children do
		child:Destroy()
	end
	table.clear(self._children)
end

function Instance:GetChildren()
	local out = {}
	for _, c in self._children do
		table.insert(out, c)
	end
	return out
end

function Instance:GetDescendants()
	local out = {}
	local function walk(n)
		for _, c in n._children do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end

function Instance:FindFirstChild(name)
	for _, c in self._children do
		if c._props.Name == name then
			return c
		end
	end
	return nil
end

function Instance:ReleaseFocus()
	self._props._releasedFocus = true
end

function Instance:GetPropertyChangedSignal(prop)
	-- treat as a signal keyed by "Property:" .. prop
	local key = "Property:" .. prop
	if not self._signals[key] then
		self._signals[key] = Signal.new(key)
	end
	return self._signals[key]
end

function Instance:__index(key)
	if Instance[key] then
		return Instance[key]
	end
	if EVENT_NAMES[key] then
		return self:_getSignal(key)
	end
	local prop = self._props[key]
	if prop ~= nil then
		return prop
	end
	return nil
end

function Instance:__newindex(key, value)
	if key == "Parent" then
		local old = self._props.Parent
		self._props.Parent = value
		if old and old ~= value then
			for i, c in old._children do
				if c == self then
					table.remove(old._children, i)
					break
				end
			end
		end
		if value and value ~= old then
			table.insert(value._children, self)
		end
	else
		local sig = self._signals["Property:" .. key]
		self._props[key] = value
		if sig then
			sig:FireOnce(value)
		end
	end
end

-- defaults for properties the library reads
local function withDefaults(inst)
	inst._props.AbsolutePosition = M.Vector2(0, 0)
	inst._props.AbsoluteSize = M.Vector2(500, 500)
	return inst
end

----------------------------------------------------------------
-- game / services
----------------------------------------------------------------

local services = {}

local game = {}
game.__index = game
function game:GetService(name)
	local svc = services[name]
	if not svc then
		error("mock GetService: unknown service " .. tostring(name), 2)
	end
	return svc
end

-- Players
local playerGui = withDefaults(M.InstanceNew("PlayerGui"))
local localPlayer = withDefaults(M.InstanceNew("Player"))
localPlayer._props.Name = "MockPlayer"
localPlayer._children = {}
table.insert(localPlayer._children, playerGui)
playerGui._props.Parent = localPlayer

services.Players = withDefaults(M.InstanceNew("Players"))
services.Players._props.LocalPlayer = localPlayer

-- UserInputService with controllable signals
services.UserInputService = withDefaults(M.InstanceNew("UserInputService"))
local UIS = services.UserInputService

-- TweenService
services.TweenService = withDefaults(M.InstanceNew("TweenService"))
function services.TweenService:Create(inst, info, goal)
	return {
		Play = function() end,
		Cancel = function() end,
		Completed = Signal.new("Completed"),
	}
end

-- HttpService using lune serde
local serdeOk, serde = pcall(require, "@lune/serde")
services.HttpService = withDefaults(M.InstanceNew("HttpService"))
function services.HttpService:JSONEncode(t)
	if serdeOk then
		return serde.encode("json", t, { pretty = false })
	end
	error("mock HttpService: no serde")
end
function services.HttpService:JSONDecode(s)
	if serdeOk then
		return serde.decode("json", s)
	end
	error("mock HttpService: no serde")
end

-- Lighting and TeleportService (used by the hub scripts)
services.Lighting = withDefaults(M.InstanceNew("Lighting"))
services.Lighting._props.Brightness, services.Lighting._props.ClockTime = 1, 14
services.Lighting._props.FogEnd, services.Lighting._props.GlobalShadows = 1000, true
services.Lighting._props.Ambient = M.Color3 and M.Color3.new and M.Color3.new(0, 0, 0) or nil
services.TeleportService = withDefaults(M.InstanceNew("TeleportService"))
function services.TeleportService:TeleportToPlaceInstance() end

-- RunService
services.RunService = withDefaults(M.InstanceNew("RunService"))

-- CoreGui
services.CoreGui = withDefaults(M.InstanceNew("CoreGui"))

-- StarterGui with a recordable SetCoreGuiEnabled
services.StarterGui = withDefaults(M.InstanceNew("StarterGui"))
services.StarterGui._coreGuiState = {}
function services.StarterGui:SetCoreGuiEnabled(coreGuiType, enabled)
	self._coreGuiState[coreGuiType] = (enabled and true) or false
end
function services.StarterGui:GetCoreGuiEnabled(coreGuiType)
	local v = self._coreGuiState[coreGuiType]
	if v == nil then
		return true
	end
	return v
end

----------------------------------------------------------------
-- Env assembly
----------------------------------------------------------------

function M.buildEnv()
	local env = {}
	-- Roblox value types (constructors live behind .new like real datatypes)
	env.Vector2 = { new = M.Vector2 }
	env.Color3 = M.Color3
	env.UDim = { new = M.UDim }
	env.UDim2 = { new = M.UDim2 }
	env.Enum = M.Enum
	env.TweenInfo = { new = M.TweenInfo }
	env.NumberSequence = { new = M.NumberSequence }
	env.ColorSequence = { new = M.ColorSequence }
	env.NumberSequenceKeypoint = { new = M.NumberSequenceKeypoint }
	env.ColorSequenceKeypoint = { new = M.ColorSequenceKeypoint }
	env.typeof = M.typeof
	env.Instance = { new = M.InstanceNew }
	env.game = game
	env.workspace = { CurrentCamera = withDefaults(M.InstanceNew("Camera")) }
	env.workspace.CurrentCamera._props.ViewportSize = M.Vector2(1920, 1080)
	return env
end

-- Test helpers
function M.fireInput(inputType, keyCode, x, y)
	UIS.InputBegan:FireOnce({
		UserInputType = inputType,
		KeyCode = keyCode,
		Position = M.Vector2(x or 0, y or 0),
	})
end

function M.makeInput(inputType, keyCode, x, y)
	return {
		UserInputType = inputType,
		KeyCode = keyCode,
		Position = M.Vector2(x or 0, y or 0),
	}
end

function M.mouseInput(x, y)
	return M.makeInput(M.Enum.UserInputType.MouseMovement, nil, x, y)
end

function M.UIS()
	return UIS
end

function M.instanceCount()
	local n = 0
	for _ in allInstances do
		n += 1
	end
	return n
end

return M
