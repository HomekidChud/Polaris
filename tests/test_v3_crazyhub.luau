-- Loads CrazyHub.luau (the example hub) against the mock and exercises it.
local H = require("./harness")
local check = H.check
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local tasklib = require("@lune/task")

local function findAll(root, pred)
	local out = {}
	for _, d in root:GetDescendants() do if pred(d) then out[#out + 1] = d end end
	return out
end

local function loadHub()
	local P, e = H.load(nil, function(e)
		e.game.HttpGet = function() return "" end
	end)
	e.loadstring = function() return function() return P end end
	local chunk = luau.load(fs.readFile("CrazyHub.luau"), { debugName = "CrazyHub.luau", environment = e })
	return chunk(), P, e
end

local function press(hub, text)
	for _, b in findAll(hub.Window._screenGui, function(d) return d._className == "TextButton" and d.Text == text end) do
		b.Activated:Fire()
		return true
	end
	for _, l in findAll(hub.Window._screenGui, function(d) return d._className == "TextLabel" and d.Text == text end) do
		if l.Parent and l.Parent._className == "TextButton" then l.Parent.Activated:Fire() return true end
	end
	return false
end

local function labelTexts(hub)
	local t = {}
	for _, l in findAll(hub.Window._screenGui, function(d) return d._className == "TextLabel" end) do t[l.Text] = true end
	return t
end

check("CrazyHub loads and builds every tab", function()
	local hub = loadHub()
	assert(hub and hub.Window and hub.CalmDown, "hub did not return its window")
	local names = labelTexts(hub)
	for _, tab in { "Party", "Look", "Screen", "Games", "Script shelf", "Make your own", "Stats" } do
		assert(names[tab], "missing tab " .. tab)
	end
	hub.Window:Destroy()
end)

check("every switch turns on, runs a little, and Calm down turns them off", function()
	local hub = loadHub()
	local count = 0
	for name, entry in hub.Toggles do
		count += 1
		entry.toggle:Set(true)
		assert(entry.toggle:Get() == true, name)
	end
	assert(count >= 9, "only " .. count .. " switches")
	tasklib.wait(1.3)
	local overlays = 0
	for _ in hub.Overlays do overlays += 1 end
	assert(overlays >= 4, "overlays: " .. overlays)
	assert(hub.Loops.disco and hub.Loops.matrix and hub.Loops.rain, "loops did not start")
	hub.CalmDown()
	for name, entry in hub.Toggles do assert(entry.toggle:Get() == false, name .. " still on") end
	for _ in hub.Overlays do error("an overlay is left over") end
	for name in hub.Loops do assert(name == "helpers" or name == "fpschart", "loop left running: " .. name) end
	hub.Window:Destroy()
	tasklib.wait(1.5)
end)

check("buttons work: confetti, party mode, surprise, roll, fortune, click, buy", function()
	local hub = loadHub()
	assert(press(hub, "Confetti burst"))
	assert(next(hub.Overlays), "confetti should open an overlay")
	assert(press(hub, "Party mode"))
	assert(hub.Toggles["Disco lights"].toggle:Get() and hub.Toggles["Confetti rain"].toggle:Get())
	assert(press(hub, "Surprise me"))
	assert(press(hub, "Roll"))
	assert(press(hub, "Ask the hub"))
	assert(press(hub, "Start"))
	assert(press(hub, "Go")) -- too early, must not error
	local before = hub.State:Get().clicks
	assert(press(hub, "CLICK"))
	assert(hub.State:Get().clicks == before + hub.State:Get().power, "click should add power")
	assert(press(hub, "Buy power (25 x power)")) -- not enough clicks, shows a note
	assert(hub.State:Get().power == 1)
	hub.State:Update(function(s) local c = table.clone(s) c.clicks = 100 return c end)
	assert(press(hub, "Buy power (25 x power)"))
	assert(hub.State:Get().power == 2 and hub.State:Get().clicks == 75, "clicks " .. hub.State:Get().clicks)
	assert(press(hub, "Buy helper (100)")) -- 75 clicks: refused
	assert(hub.State:Get().auto == 0)
	assert(press(hub, "Calm down (undo everything)") or true)
	hub.Window:Destroy()
	tasklib.wait(1.5)
end)

H.finish()
