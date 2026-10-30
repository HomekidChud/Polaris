-- Runs the code samples from GUIDE.md so the guide cannot drift from the library.
local H = require("./harness")
local check = H.check
local tasklib = require("@lune/task")
local Polaris, env = H.load()

check("Start with custom tiles and options", function()
	local h = Polaris.Start({ Title = "Kai's Games", Subtitle = "Tap a picture!", Theme = "Midnight", Keep = true, Tiles = {
		{ Name = "Hello", Icon = "rainbow", Color = env.Color3.fromRGB(255, 120, 80), Action = function() end },
		{ Name = "Scripts", Icon = "list", Action = function() end },
	} })
	h:Close()
	Polaris:SetTheme("Default")
end)

check("ScriptLibrary template sample", function()
	local w, lib = Polaris.Templates.ScriptLibrary({ Name = "My Scripts", Scripts = {
		{ Name = "Hello", Description = "Says hello", Tags = { "fun" }, Run = function() end },
		{ Name = "Remote tool", Url = "https://raw.githubusercontent.com/you/repo/main/tool.lua", Tags = { "tools" } },
	}, TrustedHosts = { "raw.githubusercontent.com" } })
	lib:Add({ Name = "New", Run = function() end })
	lib:AddMany({ { Name = "A", Run = function() end } })
	assert(#lib:Query({ Text = "hello", Tag = "fun" }) == 1)
	lib:Favourite("hello", true)
	assert(lib:Run("hello") == true)
	lib:Remove("new")
	assert(type(lib:Export()) == "string")
	w:Destroy()
end)

check("manifest json sample", function()
	local lib = Polaris.Library.new({})
	local n = lib:LoadManifest('{ "scripts": [ { "Name": "Hello", "Url": "https://example.com/hello.lua", "Description": "Says hello", "Tags": ["fun"] } ] }')
	assert(n == 1)
end)

check("research samples", function()
	local w = Polaris.Templates.DeepResearch({ Provider = function(ctx)
		ctx:SetPlan({ "Think", "Write" })
		ctx:Step(1, "running")
		ctx:Source({ Title = "My notes", Url = "https://example.com" })
		ctx:Step(1, "done")
		ctx:Step(2, "running")
		ctx:Text("The answer to " .. ctx.Query .. " is 42 [1].")
		ctx:Done()
	end })
	w:Destroy()
	local session = Polaris.Research.new({ Provider = "Demo" })
	local done
	session:On("done", function(state) done = state end)
	session:Run("How do tides work?", { Depth = "Quick" })
	for _ = 1, 100 do if done then break end tasklib.wait(0.1) end
	assert(done and #done.Report > 0)
	assert(#session:ExportMarkdown() > 0 and #session:GetReport() > 0)
	local p = Polaris.Research.Providers.HTTP({ Url = "https://your-server.example/research", Headers = { ["X-Token"] = "x" } })
	assert(p.Run)
end)

check("RobloxHub sample", function()
	local w, made = Polaris.Templates.RobloxHub({ Name = "My Hub",
		Buttons = { ["Say hi"] = function() end }, Toggles = { ["Cool mode"] = function() end },
		Sliders = { Speed = { Min = 0, Max = 100, Default = 16 } }, Stats = { "FPS", "Ping", "Players", "Memory" } })
	assert(made.Tabs.Home and made.Tabs.Features and made.Tabs.Tools and made.Tabs.Settings and made.Tabs.Scripts)
	w:Destroy()
end)

check("Make samples", function()
	local expect = { ["a research tool"] = "DeepResearch", ["my script list"] = "ScriptLibrary", ["roblox hub"] = "RobloxHub", ["let me design my own"] = "Builder", ["banana"] = "Everything" }
	for words, kind in expect do assert(Polaris.Classify(words) == kind, words .. " -> " .. Polaris.Classify(words)) end
	local w = Polaris.Make("a research tool")
	w:Destroy()
end)

check("Hub sample", function()
	local window, made = Polaris.Hub({
		Name = "Kai's Hub", Theme = "Midnight", Text = "Welcome!",
		Buttons = { Wave = function() end }, Toggles = { Sparkle = function() end },
		Sliders = { Speed = { Min = 0, Max = 10, Default = 3 } },
		Dropdowns = { Colour = { Options = { "Red", "Blue" } } },
		Inputs = { Name = function() end },
		Scripts = { { Name = "Hi", Run = function() end } }, Research = true,
		Tabs = { Fun = { Buttons = { Jump = function() end } } },
	})
	assert(made.Tabs.Main and made.Tabs.Fun and made.Tabs.Scripts and made.Tabs.Research and made.Tabs.Settings)
	window:Destroy()
	local w2 = Polaris.Quick("Title", { "Say hi", function() end })
	w2:Destroy()
	Polaris:SetTheme("Default")
end)

check("Toy and element samples", function()
	Polaris.Toy():Destroy()
	local w = Polaris:CreateWindow({ Name = "E" })
	local tab = w:CreateTab({ Name = "T" })
	tab:CreateLabel({ Text = "x" }); tab:CreateProgress({ Name = "p", Max = 10, Value = 3 })
	tab:CreateConsole({ Name = "c" }):Log("hi"); tab:CreateButtonRow({ Buttons = { { Name = "a", Callback = function() end } } })
	tab:CreateStats({ Items = { "FPS", { Name = "Coins", Get = function() return 5 end } } })
	tab:Add("Label", { Text = "via Add" })
	assert(w:GetTab("T") and w:SelectTab("T") ~= false)
	w:Destroy()
end)

H.finish()
