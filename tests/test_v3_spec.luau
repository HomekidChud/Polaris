-- v3: Spec (validate + build), Imagine, Imaginer.
local H = require("./harness")
local check = H.check
local tasklib = require("@lune/task")
local Polaris, env = H.load()
local JSON = Polaris.Util.JSON

local function findAll(root, pred)
	local out = {}
	for _, d in root:GetDescendants() do if pred(d) then out[#out + 1] = d end end
	return out
end
local function press(app, text)
	for _, d in findAll(app.Window._screenGui, function(x) return x._className == "TextButton" and x.Text == text end) do
		d.Activated:Fire()
		return true
	end
	for _, l in findAll(app.Window._screenGui, function(x) return x._className == "TextLabel" and x.Text == text end) do
		if l.Parent and l.Parent._className == "TextButton" then
			l.Parent.Activated:Fire()
			return true
		end
	end
	return false
end
local function hasText(app, text)
	return #findAll(app.Window._screenGui, function(d) return d._className == "TextLabel" and d.Text == text end) > 0
end

local COUNTER = { Name = "Clicker", State = { count = 0 }, Tabs = { { Name = "Play", Items = {
	{ Type = "Label", Text = "Clicks: {count}" },
	{ Type = "Button", Name = "Click me", Action = { Do = "Add", Key = "count", Value = 1 } },
	{ Type = "Button", Name = "Zero", Action = { Do = "Reset", Key = "count" } },
	{ Type = "Progress", Name = "Goal", Value = 0, Max = 10, Key = "count" },
} } } }

check("Validate: drops code, unknown types and unsafe things, reports why", function()
	local clean, problems = Polaris.Spec.Validate({ Name = "X", State = { n = 0, ["bad key!"] = 1, t = { 1 } }, Tabs = { { Name = "T", Items = {
		{ Type = "Script", Code = "print('hi')" },
		{ Type = "Button", Name = "ok", Action = { Do = "loadstring", Text = "x" } },
		{ Type = "Button", Name = "ok2", Action = { Do = "Run", Script = "NotAHubScript" } },
		{ Type = "Image", Image = "https://evil.example/x.png" },
		{ Type = "Label", Text = "fine", Code = "os.exit()", Url = "https://x" },
		{ Type = "Toggle", Name = "t", Key = "missing" },
	} } } })
	assert(clean, "should still produce a spec")
	local items = clean.Tabs[1].Items
	local kinds = {}
	for _, it in items do kinds[#kinds + 1] = it.Type end
	assert(table.concat(kinds, ",") == "Button,Button,Label,Toggle", table.concat(kinds, ","))
	assert(items[1].Action == nil and items[2].Action == nil, "bad actions must be dropped")
	assert(items[3].Code == nil and items[3].Url == nil, "extra keys must not survive")
	assert(items[4].Key == nil)
	assert(clean.State["bad key!"] == nil and clean.State.t == nil and clean.State.n == 0)
	assert(#problems >= 6, #problems)
	local blob = JSON.encode(clean)
	assert(not blob:find("print") and not blob:find("loadstring") and not blob:find("evil"))
end)

check("Validate: limits, nothing-to-build, non-table", function()
	local items = {}
	for i = 1, 400 do items[i] = { Type = "Label", Text = "x" } end
	local clean = Polaris.Spec.Validate({ Tabs = { { Name = "T", Items = items } } })
	assert(#clean.Tabs[1].Items == Polaris.Spec.Limits.Items, #clean.Tabs[1].Items)
	local none, problems = Polaris.Spec.Validate({ Tabs = {} })
	assert(none == nil and problems[1]:find("tab"))
	assert(Polaris.Spec.Validate("nope") == nil)
	local long = Polaris.Spec.Validate({ Name = string.rep("x", 500), Tabs = { { Name = "t", Items = { { Type = "Label", Text = string.rep("y", 9000) } } } } })
	assert(#long.Name == 80 and #long.Tabs[1].Items[1].Text == 2000)
	local deep = { Type = "Label", Text = "x" }
	for _ = 1, 8 do deep = { Type = "Group", Items = { deep } } end
	local d = Polaris.Spec.Validate({ Tabs = { { Name = "t", Items = { deep } } } })
	assert(d, "deep nesting is trimmed, not fatal")
end)

check("Build: counter app reacts to buttons, label and progress follow state", function()
	local app = Polaris.Spec.Build(COUNTER)
	assert(hasText(app, "Clicks: 0"))
	assert(press(app, "Click me")); assert(press(app, "Click me")); assert(press(app, "Click me"))
	assert(app:GetState("count") == 3)
	assert(hasText(app, "Clicks: 3"), "label did not update")
	assert(press(app, "Zero"))
	assert(hasText(app, "Clicks: 0"))
	app:SetState("count", 7)
	assert(hasText(app, "Clicks: 7"))
	app:Destroy()
end)

check("Build: keyed inputs link both ways, theme dropdown and notify actions", function()
	local app = Polaris.Spec.Build({ Name = "S", State = { vol = 20, on = false }, Tabs = { { Name = "T", Items = {
		{ Type = "Slider", Name = "Vol", Min = 0, Max = 100, Key = "vol" },
		{ Type = "Toggle", Name = "On", Key = "on" },
		{ Type = "Label", Text = "{vol}/{on}" },
		{ Type = "Dropdown", Name = "Theme", Options = { "Default", "Midnight" }, Action = { Do = "Theme", FromValue = true } },
	} } } })
	assert(hasText(app, "20/false"), "initial")
	app.Elements[2]:Set(true)
	assert(app:GetState("on") == true and hasText(app, "20/true"))
	app:SetState("vol", 55)
	assert(app.Elements[1]:Get() == 55)
	app.Elements[4]:Set("Midnight")
	assert(Polaris.CurrentThemeName == "Midnight", tostring(Polaris.CurrentThemeName))
	Polaris:SetTheme("Default")
	app:Destroy()
end)

check("Build: form feeds a table through AddRow, ClearTable empties it", function()
	local app = Polaris.Spec.Build({ Name = "T", State = {}, Tabs = { { Name = "T", Items = {
		{ Type = "Form", Name = "Add", Fields = { { Name = "Item", Type = "Textbox", Required = true }, { Name = "Qty", Type = "Number", Default = 2 } },
			Action = { Do = "AddRow", Table = "list", FromForm = true } },
		{ Type = "Table", Id = "list", Columns = { "Item", "Qty" }, Rows = {} },
		{ Type = "Button", Name = "Wipe", Action = { Do = "ClearTable", Table = "list" } },
	} } } })
	local tbl = app.Ids.list
	assert(tbl and tbl:Count() == 0)
	press(app, "Submit")
	assert(tbl:Count() == 0, "required field blocks")
	local form = app.Elements[1]
	form.Fields.Item:Set("Bow", true)
	press(app, "Submit")
	assert(tbl:Count() == 1 and tbl:GetRows()[1].Item == "Bow" and tbl:GetRows()[1].Qty == 2)
	press(app, "Wipe")
	assert(tbl:Count() == 0)
	app:Destroy()
end)

check("Build: layout items (Group, Columns, Pages, Chart, HubScripts) and Goto", function()
	local app = Polaris.Spec.Build({ Name = "L", State = {}, Tabs = {
		{ Name = "One", Items = {
			{ Type = "Group", Name = "G", Card = true, Items = { { Type = "Label", Text = "inside" } } },
			{ Type = "Columns", Count = 2, Columns = { { Items = { { Type = "Label", Text = "left" } } }, { Items = { { Type = "Chart", Values = { 1, 2 }, Labels = { "a", "b" } } } } } },
			{ Type = "Pages", Pages = { { Name = "P1", Items = { { Type = "Label", Text = "page one" } } }, { Name = "P2", Items = { { Type = "Label", Text = "page two" } } } } },
			{ Type = "HubScripts", Only = { "Fullbright" } },
			{ Type = "Button", Name = "Go", Action = { Do = "Goto", Tab = "Two" } },
		} },
		{ Name = "Two", Items = { { Type = "Label", Text = "second" } } },
	} })
	assert(hasText(app, "inside") and hasText(app, "left") and hasText(app, "page one"))
	assert(#app.Problems == 0, table.concat(app.Problems, ";"))
	press(app, "Go")
	assert(app.Tabs.Two._content.Visible == true)
	app:Destroy()
end)

check("Actions: custom registry works, names must be registered first", function()
	local got
	local _, before = Polaris.Spec.Validate({ Tabs = { { Name = "t", Items = { { Type = "Button", Name = "b", Action = { Do = "Ping", Msg = "hi" } } } } } })
	assert(#before == 1)
	Polaris.Actions.Ping = function(args, ctx) got = args.Msg end
	local app = Polaris.Spec.Build({ Tabs = { { Name = "t", Items = { { Type = "Button", Name = "b", Action = { Do = "Ping", Msg = "hi" } } } } } })
	press(app, "b")
	assert(got == "hi", tostring(got))
	Polaris.Actions.Ping = nil
	app:Destroy()
end)

check("Validate is idempotent: a clean spec validates to itself, even after JSON", function()
	for _, text in { "a clicker game", "a game with a dashboard, a tracker and settings", "a script hub" } do
		local a = Polaris.Spec.Validate(Polaris.Spec.FromWords(text))
		local b, problems = Polaris.Spec.Validate(JSON.decode(JSON.encode(a)))
		assert(b and #problems == 0, text .. ": " .. tostring(problems[1]))
		assert(JSON.encode(a) == JSON.encode(b), "changed on second pass: " .. text)
	end
end)

check("Describe lists every allowed type and action", function()
	local d = Polaris.Spec.Describe()
	for kind in Polaris.Spec.ItemTypes do assert(d:find(kind, 1, true), kind) end
	for act in Polaris.Spec.BuiltinActions do assert(d:find(act, 1, true), act) end
	assert(d:find("no code", 1, true))
end)

check("FromWords: keywords pick tabs, anything validates, empty prompt still works", function()
	for _, text in { "a clicker game", "dashboard with charts", "inventory tracker", "settings panel", "script hub", "a game with a dashboard, a tracker and settings", "banana", "" } do
		local spec = Polaris.Spec.FromWords(text)
		local clean, problems = Polaris.Spec.Validate(spec)
		assert(clean and #problems == 0, text .. ": " .. tostring(problems and problems[1]))
		assert(#clean.Tabs >= 1 and #clean.Tabs <= 4)
	end
	assert(Polaris.Spec.FromWords("a tracker").Tabs[1].Name == "Tracker")
	assert(#Polaris.Spec.FromWords("game dashboard tracker settings hub").Tabs == 4)
end)

check("Imagine with the Demo provider builds a real window", function()
	local app, problems, spec = Polaris.Imagine("a clicker game with a score")
	assert(app and app.Window and spec.Tabs[1].Name == "Play")
	assert(#problems == 0, problems[1])
	press(app, "Tap!")
	assert(app:GetState("count") == 1)
	app:Destroy()
	assert(Polaris.Imagine("   ") == nil)
	local none, _, only = Polaris.Imagine("a tracker", { Build = false })
	assert(none == nil and only and only.Tabs[1].Name == "Tracker")
end)

check("Imagine with a custom provider: fences, chatter, retry with feedback, errors", function()
	local calls, seenFeedback = 0, false
	local provider = function(system, user)
		calls += 1
		assert(system:find("ONE JSON object", 1, true))
		if calls == 1 then return "Sure! here you go:\n```json\n{ not valid json ]\n```" end
		if user:find("last reply had these problems", 1, true) then seenFeedback = true end
		return "Here is your app:\n```json\n" .. JSON.encode(COUNTER) .. "\n```\nEnjoy!"
	end
	local app, problems = Polaris.Imagine("anything", { Provider = provider })
	assert(app and calls == 2 and seenFeedback, "retry with feedback")
	app:Destroy()
	local bad, p2 = Polaris.Imagine("x", { Provider = function() return "no json here" end })
	assert(bad == nil and #p2 >= 1)
	local boom, p3 = Polaris.Imagine("x", { Provider = function() error("service down") end })
	assert(boom == nil and tostring(p3[1]):find("service down"))
	local tableReply = Polaris.Imagine("x", { Provider = function() return COUNTER end })
	assert(tableReply) tableReply:Destroy()
	local evil = Polaris.Imagine("x", { Provider = function() return JSON.encode({ Tabs = { { Name = "t", Items = { { Type = "Script", Code = "error('pwned')" }, { Type = "Label", Text = "kept" } } } } }) end })
	assert(evil and hasText(evil, "kept") and #evil.Problems >= 1)
	evil:Destroy()
	assert(not pcall(Polaris.Imagine, "x", { Provider = "NoSuchProvider" }))
end)

check("Perplexity provider needs a key and HTTP, and never leaks the key", function()
	local app, problems = Polaris.Imagine("x", { Provider = "Perplexity" })
	assert(app == nil and problems[1]:find("key"), problems[1])
	local app2, p2 = Polaris.Imagine("x", { Provider = "Perplexity", ApiKey = "pplx-1234567890" })
	assert(app2 == nil and p2[1] and not tostring(p2[1]):find("pplx-1234567890"), tostring(p2[1]))
end)

check("Imaginer window: Make it, Show spec, ideas", function()
	local m = Polaris.Imaginer({ Prompt = "a settings panel" })
	m:Make()
	tasklib.wait(0.3)
	assert(m.LastApp and m.LastSpec.Tabs[1].Name == "Settings", "no app")
	m:ShowSpec()
	assert(#m.Console._lines > 3)
	m:Make("a clicker game")
	tasklib.wait(0.3)
	assert(m.LastSpec.Tabs[1].Name == "Play")
	m.LastApp:Destroy()
	m.Window:Destroy()
end)

H.finish()
