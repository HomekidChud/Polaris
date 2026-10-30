-- v3: Table, Chart, Form.
local H = require("./harness")
local check = H.check
local Polaris, env = H.load()

local function findAll(root, pred)
	local out = {}
	for _, d in root:GetDescendants() do if pred(d) then out[#out + 1] = d end end
	return out
end
local function newTab()
	local w = Polaris:CreateWindow({ Name = "D" })
	return w, w:CreateTab({ Name = "t" })
end
local function rowButtons(t) return findAll(t._body, function(d) return d.Name == "Row" end) end

check("Table: rows render, array and map rows both work", function()
	local w, t = newTab()
	local tb = t:CreateTable({ Columns = { "Name", "Qty" }, Rows = { { "Sword", 3 }, { Name = "Bow", Qty = 1 } } })
	assert(tb:Count() == 2 and #rowButtons(tb) == 2)
	local cells = findAll(tb._body, function(d) return d.Name == "Cell" end)
	local texts = {}
	for _, c in cells do texts[c.Text] = true end
	assert(texts.Sword and texts.Bow and texts["3"] and texts["1"])
	w:Destroy()
end)

check("Table: sort by column both ways, numbers sort as numbers", function()
	local w, t = newTab()
	local tb = t:CreateTable({ Columns = { "Name", "Qty" }, Rows = { { "b", 10 }, { "a", 9 }, { "c", 100 } } })
	tb:Sort("Qty", true)
	local v = tb:GetView()
	assert(v[1][2] == 9 and v[3][2] == 100, "numeric asc")
	tb:Sort("Qty", false)
	assert(tb:GetView()[1][2] == 100)
	tb:Sort("Name", true)
	assert(tb:GetView()[1][1] == "a")
	assert(tb:Sort("Nope") == false)
	w:Destroy()
end)

check("Table: filter, add, remove, selection callback, row cap", function()
	local w, t = newTab()
	local picked
	local tb = t:CreateTable({ Columns = { "Name" }, Rows = { { "apple" }, { "banana" }, { "cherry" } }, MaxRows = 10, Callback = function(i, r) picked = r[1] end })
	tb:SetFilter("an")
	assert(#tb:GetView() == 1 and tb:GetView()[1][1] == "banana")
	tb:SetFilter("")
	tb:AddRow({ "date" })
	assert(tb:Count() == 4)
	assert(tb:RemoveRow(1) and tb:Count() == 3)
	rowButtons(tb)[1].Activated:Fire()
	assert(picked == "banana", tostring(picked))
	local idx, row = tb:GetSelected()
	assert(row[1] == "banana")
	local many = {}
	for i = 1, 50 do many[i] = { "r" .. i } end
	tb:SetRows(many)
	assert(#rowButtons(tb) == 10, #rowButtons(tb))
	tb:Clear()
	assert(tb:Count() == 0 and #findAll(tb._body, function(d) return d.Name == "Empty" end) == 1)
	w:Destroy()
end)

check("Table: bad config is rejected, search box filters", function()
	local w, t = newTab()
	assert(not pcall(t.CreateTable, t, { Columns = {} }))
	local tb = t:CreateTable({ Columns = { "A" }, Rows = { { "x" }, { "y" } }, Search = true })
	tb._search.Text = "y"
	assert(#tb:GetView() == 1)
	w:Destroy()
end)

check("Chart: bars scale to the biggest value, empty state", function()
	local w, t = newTab()
	local c = t:CreateChart({ Title = "T", Labels = { "a", "b", "c" }, Values = { 5, 10, 2 } })
	local bars = findAll(c._plot, function(d) return d.Name == "Bar" end)
	assert(#bars == 3)
	assert(math.abs(bars[2].Size.Y.Scale - 1) < 1e-6 and math.abs(bars[1].Size.Y.Scale - 0.5) < 1e-6)
	c:SetData({}, {})
	assert(#findAll(c._plot, function(d) return d.Name == "Bar" end) == 0)
	assert(#findAll(c._plot, function(d) return d.Name == "Empty" end) == 1)
	w:Destroy()
end)

check("Chart: line draws points and segments, AddPoint trims, series and legend", function()
	local w, t = newTab()
	local c = t:CreateChart({ Type = "line", Labels = { "1", "2", "3" }, Values = { 1, 3, 2 }, MaxPoints = 5 })
	assert(#findAll(c._plot, function(d) return d.Name == "Point" end) == 3)
	assert(#findAll(c._plot, function(d) return d.Name == "Segment" end) == 2)
	for i = 1, 10 do c:AddPoint(tostring(i), i) end
	assert(#c:Get().Series[1].Values == 5)
	local two = t:CreateChart({ Series = { { Name = "A", Values = { 1, 2 } }, { Name = "B", Values = { 2, 1 } } }, Labels = { "x", "y" } })
	assert(#findAll(two._plot, function(d) return d.Name == "Bar" end) == 4)
	assert(#findAll(two._container, function(d) return d.Name == "Legend" end) == 1)
	w:Destroy()
end)

check("Form: required fields, number rules, submit callback", function()
	local w, t = newTab()
	local got
	local f = t:CreateForm({ Name = "Add", Fields = {
		{ Name = "Item", Type = "Textbox", Required = true },
		{ Name = "Qty", Type = "Number", Required = true, Min = 1, Max = 10, Default = 1 },
		{ Name = "Done", Type = "Toggle" },
		{ Name = "Kind", Type = "Dropdown", Options = { "a", "b" } },
	}, Callback = function(v) got = v end })
	local ok, problems = f:Submit()
	assert(not ok and problems[1]:find("Item"), problems and problems[1])
	assert(got == nil)
	f.Fields.Item:Set("Sword", true)
	f.Fields.Qty:Set("99", true)
	ok, problems = f:Submit()
	assert(not ok and problems[1]:find("at most"), problems and problems[1])
	f.Fields.Qty:Set("abc", true)
	ok, problems = f:Submit()
	assert(not ok and problems[1]:find("number"))
	f:SetValues({ Qty = 3 })
	ok = f:Submit()
	assert(ok and got.Item == "Sword" and got.Qty == 3, "a")
	assert(got.Done == false, "done " .. tostring(got.Done))
	assert(got.Kind == "a", "kind " .. tostring(got.Kind))
	f:Reset()
	assert(f.Fields.Item:Get() == "")
	assert(not pcall(t.CreateForm, t, { Fields = {} }))
	w:Destroy()
end)

H.finish()
