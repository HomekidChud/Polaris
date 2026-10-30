local H = require("./harness")
local check = H.check
local tasklib = require("@lune/task")
local Polaris, env = H.load()

check("Hub from plain tables", function()
	local clicked, toggled = 0, nil
	local win, made = Polaris.Hub({
		Name = "Toddler Hub",
		Buttons = { ["Zebra"] = function() clicked += 1 end, ["Apple"] = function() clicked += 10 end },
		Toggles = { ["Cool mode"] = function(on) toggled = on end },
		Sliders = { Speed = { Min = 0, Max = 10, Default = 3 } },
		Scripts = { { Name = "Hi", Run = function() end } },
		Research = true,
		Text = "Welcome!",
	})
	assert(win:GetTab("Main") and win:GetTab("Scripts") and win:GetTab("Research") and win:GetTab("Settings"))
	local main = win:GetTab("Main")
	local names = {}
	for _, el in main:GetElements() do names[#names + 1] = el._config.Name or "label" end
	-- sorted dictionary order: Apple before Zebra
	local a, z
	for i, n in names do if n == "Apple" then a = i elseif n == "Zebra" then z = i end end
	assert(a and z and a < z, table.concat(names, ","))
	assert(made.Library and made.Research)
	win:Destroy()
end)

check("ordered list form keeps order", function()
	local win = Polaris.Hub({ Name = "Ord", Buttons = { { "Second", function() end }, { "First", function() end } }, Settings = false })
	local main = win:GetTab("Main")
	local els = main:GetElements()
	assert(els[1]._config.Name == "Second" and els[2]._config.Name == "First")
	assert(win:GetTab("Settings") == nil)
	win:Destroy()
end)

check("Polaris.Quick", function()
	local hit = 0
	local win = Polaris.Quick("Quick UI", { "A", function() hit += 1 end }, { "B", function() hit += 2 end })
	local els = win:GetTab("Main"):GetElements()
	els[1]._interaction.Activated:Fire()
	els[2]._interaction.Activated:Fire()
	assert(hit == 3)
	win:Destroy()
end)

check("templates build", function()
	local w1, lib = Polaris.Templates.ScriptLibrary({})
	assert(lib:Count() >= 2 and w1:GetTab("Library"))
	w1:Destroy()
	local w2, session = Polaris.Templates.DeepResearch({ Provider = "Demo", Question = "why is the sky blue" })
	assert(session and w2:GetTab("Research"))
	local t = 0
	while session.State.Status ~= "done" and t < 8 do tasklib.wait(0.1) t += 0.1 end
	assert(session.State.Status == "done")
	w2:Destroy()
	local w3, made = Polaris.Templates.RobloxHub({ Name = "Obby Hub", Buttons = { ["Hello"] = function() end }, Research = false })
	for _, n in { "Home", "Features", "Scripts", "Tools", "Settings" } do assert(w3:GetTab(n), n) end
	assert(w3:GetTab("Research") == nil)
	w3:Destroy()
	local w4 = Polaris.Templates.Everything({})
	assert(w4:GetTab("Research") and w4:GetTab("Scripts"))
	w4:Destroy()
	local w5, tab = Polaris.Templates.Blank({ Name = "Empty" })
	assert(tab)
	w5:Destroy()
end)

check("Polaris.Classify understands plain words", function()
	local c = Polaris.Classify
	assert(c("a script library for my obby") == "ScriptLibrary")
	assert(c("I want to ask questions") == "DeepResearch")
	assert(c("deep research ui") == "DeepResearch")
	assert(c("roblox hub") == "RobloxHub")
	assert(c("let me design my own") == "Builder")
	assert(c("banana") == "Everything")
	assert(c("") == "Everything")
end)

check("Polaris.Make returns a window", function()
	local win, a, b, kind = Polaris.Make("research")
	assert(kind == "DeepResearch" and win:GetTab("Research"))
	win:Destroy()
end)

check("FromProject builds from builder JSON", function()
	local json = '{"window":{"Name":"FromJson","Theme":"Midnight","ConfigFolder":"x","SaveConfig":false},"tabs":[{"Name":"Main","Icon":"","nodes":[{"Kind":"Section","Name":"S"},{"Kind":"Button","Name":"Go"},{"Kind":"Toggle","Name":"T","Default":true,"Flag":"t"},{"Kind":"Slider","Name":"Sl","Min":0,"Max":5,"Default":2,"Increment":1,"ValueName":"","Flag":"sl"},{"Kind":"Dropdown","Name":"D","Options":"a, b","Multiple":false,"Flag":"d"},{"Kind":"Paragraph","Text":"hi"}]}]}'
	local hit = false
	local win = Polaris.FromProject(json, { Go = function() hit = true end })
	assert(win.Flags.t:Get() == true and win.Flags.sl:Get() == 2)
	win:GetTab("Main"):GetElements()[1]._interaction.Activated:Fire()
	assert(hit)
	win:Destroy()
	H.expectError(function() Polaris.FromProject("{}") end)
end)

check("unknown theme falls back instead of crashing", function()
	local win = Polaris.Hub({ Name = "Th", Theme = "Nonexistent", Settings = false })
	win:Destroy()
end)

H.finish()
