-- Runs the v3 code samples from GUIDE.md so the guide cannot drift from the library.
local H = require("./harness")
local check = H.check
local Polaris, env = H.load()

local Window, tab, table1
check("Layout sample", function()
	Window = Polaris:CreateWindow({ Name = "Layouts" })
	tab = Window:CreateTab({ Name = "Home" })
	local card = tab:CreateGroup({ Name = "Player", Card = true })
	card:CreateLabel({ Text = "Hello" })
	local more = tab:CreateGroup({ Name = "More", Collapsible = true, Open = false })
	more:CreateToggle({ Name = "Extra", Default = true })
	local cols = tab:CreateColumns({ Count = 2 })
	cols[1]:CreateButton({ Name = "Left" })
	cols[2]:CreateButton({ Name = "Right" })
	local pages = tab:CreatePages({ Names = { "One", "Two" }, Default = "One" })
	pages.Pages.Two:CreateLabel({ Text = "Second page" })
	pages:Select("Two")
	tab:CreateSpacer({ Height = 8 })
	tab:CreateImage({ Image = "rbxassetid://123456", Height = 100, Caption = "Logo" })
	local c = tab:CreateCustom({ Height = 60, Build = function(frame, ctx)
		ctx.Create("Frame", { Size = env.UDim2.new(1, 0, 1, 0), BackgroundColor3 = ctx.Theme().Accent, Parent = frame })
	end })
	assert(c.BuildError == nil, tostring(c.BuildError))
end)

check("Data sample", function()
	table1 = tab:CreateTable({ Columns = { "Name", "Score" }, Rows = { { "Ada", 92 }, { "Bo", 85 } }, Sortable = true, Search = true, Height = 180 })
	table1:AddRow({ "Cy", 77 })
	assert(table1:Count() == 3)
	tab:CreateChart({ Type = "bar", Title = "Week", Labels = { "Mon", "Tue", "Wed" }, Values = { 4, 7, 5 } })
	local live = tab:CreateChart({ Type = "line", Title = "FPS", MaxPoints = 30 })
	live:AddPoint(60)
	local form = tab:CreateForm({ Name = "New player", Fields = {
		{ Name = "Player", Type = "Textbox", Required = true },
		{ Name = "Score", Type = "Slider", Min = 0, Max = 100, Default = 50 },
	}, Submit = "Add", Callback = function(values) table1:AddRow({ values.Player, values.Score }) end })
	form:SetValues({ Player = "Dee" })
	assert(form:Submit() ~= false)
	assert(table1:Count() == 4, tostring(table1:Count()))
end)

check("State sample", function()
	local score = Polaris.State(0, { Persist = true, Folder = "MyGame" })
	local label = tab:CreateLabel({ Text = "Score: 0" })
	label:Bind(score, function(v) return "Score: " .. v end)
	score:Update(function(v) return v + 1 end)
	assert(score:Get() == 1)
	local slider = tab:CreateSlider({ Name = "Volume", Min = 0, Max = 10, Default = 5 })
	local volume = Polaris.State(5)
	slider:Link(volume)
	slider:Set(8)
	assert(volume:Get() == 8)
	local double = Polaris.Computed({ score }, function(s) return s * 2 end)
	assert(double:Get() == 2)
end)

check("Plugin sample", function()
	Polaris.DefineElement("Badge", { Height = 28, Default = "New", Build = function(frame, config, element, ctx)
		ctx.Create("TextLabel", { Text = config.Text or "x", Parent = frame })
	end, Set = function(self, value) end })
	local b = tab:CreateBadge({ Text = "Hot" })
	assert(b and b.BuildError == nil, tostring(b and b.BuildError))
	assert(tab:Add("Badge", { Text = "Hot" }))
	Polaris.Use(function(P) P.DefineElement("Another", { Build = function() end }) end)
	assert(Polaris.ElementTypes.Another)
end)

check("Spec sample", function()
	local app = Polaris.Spec.Build({
		Name = "Clicker", State = { count = 0 },
		Tabs = { { Name = "Play", Items = {
			{ Type = "Label", Text = "Clicks: {count}" },
			{ Type = "Progress", Name = "Goal", Max = 10, Key = "count" },
			{ Type = "Button", Name = "Click me", Action = { Do = "Add", Key = "count", Value = 1 } },
			{ Type = "Button", Name = "Reset", Action = { Do = "Reset", Key = "count" } },
		} } },
	})
	assert(#app.Problems == 0, tostring(app.Problems[1]))
	app:RunAction({ Do = "Add", Key = "count", Value = 1 })
	assert(app:GetState("count") == 1)
	assert(type(app:ToJSON()) == "string")
	local hit
	Polaris.Actions.Ping = function(args) hit = args.Who end
	local a2 = Polaris.Spec.Build({ Name = "P", Tabs = { { Name = "T", Items = { { Type = "Button", Name = "Go", Action = { Do = "Ping", Args = { Who = "me" } } } } } } })
	a2:RunAction({ Do = "Ping", Args = { Who = "me" } })
	assert(hit == "me", tostring(hit))
	assert(#Polaris.Spec.Describe() > 200)
	app:Destroy(); a2:Destroy()
end)

check("Imagine sample", function()
	local app, problems, spec = Polaris.Imagine("a tracker", { Build = false })
	assert(app == nil and spec and #problems == 0)
	local built = Polaris.Imagine("a dashboard with a chart and a settings tab")
	assert(built and built.Window)
	built:Destroy()
end)

H.finish()
