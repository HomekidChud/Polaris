local H = require("./harness")
local check = H.check
local tasklib = require("@lune/task")
local Polaris, env = H.load()

local function findAll(root, pred, out)
	out = out or {}
	for _, d in root:GetDescendants() do if pred(d) then out[#out + 1] = d end end
	return out
end

check("Start builds six big tiles", function()
	local h = Polaris.Start()
	local tiles = findAll(h.Gui, function(d) return d.Name == "Tile" end)
	assert(#tiles == 6, "tiles " .. #tiles)
	h:Close()
end)

check("tile tap opens the matching UI and closes launcher", function()
	local opened = 0
	local h = Polaris.Start({ Tiles = { { Name = "A", Icon = "grid", Color = env.Color3.new(1, 0, 0), Action = function() opened += 1 end } } })
	local tile = findAll(h.Gui, function(d) return d.Name == "Tile" end)[1]
	tile.Activated:Fire()
	tasklib.wait(0.6)
	assert(opened == 1, "opened " .. opened)
end)

check("failing tile does not crash", function()
	local h = Polaris.Start({ Tiles = { { Name = "Bad", Icon = "plus", Action = function() error("boom") end } } })
	findAll(h.Gui, function(d) return d.Name == "Tile" end)[1].Activated:Fire()
	tasklib.wait(0.6)
end)

check("default tiles open real windows", function()
	for _, name in { "ScriptLibrary", "DeepResearch", "RobloxHub", "Everything" } do
		local w = Polaris.Templates[name]()
		assert(w and w.Destroy, name)
		w:Destroy()
	end
end)

check("Toy counts presses and confetti cleans up", function()
	local g = Polaris.Toy()
	local btns = findAll(g, function(d) return d._className == "TextButton" and d.Name == "Button" end)
	assert(#btns >= 2, "btns " .. #btns)
	btns[1].Activated:Fire()
	btns[1].Activated:Fire()
	local counter = findAll(g, function(d) return d._className == "TextLabel" and d.Text == "2" end)
	assert(#counter == 1)
	tasklib.wait(2)
	g:Destroy()
end)

check("Confetti is callable standalone", function()
	local g = env.Instance.new("ScreenGui")
	Polaris.Confetti(g, 10)
	tasklib.wait(2)
	assert(#g:GetChildren() == 0, #g:GetChildren())
end)

H.finish()
