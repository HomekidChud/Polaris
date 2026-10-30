-- v3: Group, Columns, Pages, Spacer, Image, Custom, DefineElement, State.
local H = require("./harness")
local check = H.check
local tasklib = require("@lune/task")
local Polaris, env = H.load()

local function findAll(root, pred)
	local out = {}
	for _, d in root:GetDescendants() do if pred(d) then out[#out + 1] = d end end
	return out
end
local function newTab(name)
	local w = Polaris:CreateWindow({ Name = name or "L" })
	return w, w:CreateTab({ Name = "t" })
end

check("Group: elements nest, height follows content, Card and title", function()
	local w, t = newTab()
	local g = t:CreateGroup({ Name = "Box", Card = true })
	local b1 = g:CreateButton({ Name = "One", Callback = function() end })
	local before = g._container.Size.Y.Offset
	g:CreateLabel({ Text = "hello" })
	assert(g._container.Size.Y.Offset > before, "group did not grow")
	assert(#g._elements == 2)
	b1:SetVisible(false)
	local after = g._container.Size.Y.Offset
	assert(after < before + 30, "hidden element should shrink the group")
	w:Destroy()
end)

check("Group: nesting and Add work, destroy cleans flags", function()
	local w, t = newTab()
	local outer = t:CreateGroup({ Name = "Outer" })
	local inner = outer:CreateGroup({ Name = "Inner", Card = true })
	inner:Add("Toggle", { Name = "Deep", Flag = "deep" })
	assert(w.Flags.deep, "flag missing")
	local h1 = outer._container.Size.Y.Offset
	assert(h1 > 26, h1)
	outer:Destroy()
	assert(w.Flags.deep == nil, "flag should be released")
	w:Destroy()
end)

check("Group: collapsible hides content and shrinks", function()
	local w, t = newTab()
	local g = t:CreateGroup({ Name = "Fold", Card = true, Collapsible = true })
	g:CreateLabel({ Text = "a" })
	g:CreateLabel({ Text = "b" })
	local open = g._container.Size.Y.Offset
	g:SetOpen(false)
	assert(g._container.Size.Y.Offset < open, "did not collapse")
	assert(g._content.Visible == false)
	g:SetOpen(true)
	assert(g._container.Size.Y.Offset == open)
	w:Destroy()
end)

check("Columns: side by side, height is the tallest column", function()
	local w, t = newTab()
	local cols = t:CreateColumns({ Count = 3 })
	assert(#cols.Columns == 3)
	cols[1]:CreateButton({ Name = "a", Callback = function() end })
	cols[2]:CreateButton({ Name = "b", Callback = function() end })
	cols[2]:CreateButton({ Name = "c", Callback = function() end })
	local tall = cols._container.Size.Y.Offset
	cols[3]:CreateLabel({ Text = "x" })
	assert(cols._container.Size.Y.Offset == tall, "tallest column should decide")
	assert(cols[1]:_updateCanvas() == nil)
	w:Destroy()
end)

check("Pages: switching shows one group and reports the choice", function()
	local w, t = newTab()
	local got
	local p = t:CreatePages({ Names = { "A", "B" }, Callback = function(n) got = n end })
	p.Pages.A:CreateLabel({ Text = "in a" })
	p.Pages.B:CreateButton({ Name = "in b", Callback = function() end })
	assert(p:Get() == "A")
	assert(p.Pages.A._host.Visible and not p.Pages.B._host.Visible)
	p:Set("B")
	assert(got == "B", tostring(got))
	assert(p.Pages.B._host.Visible and not p.Pages.A._host.Visible)
	w:Destroy()
end)

check("Spacer, Image and Custom blocks", function()
	local w, t = newTab()
	local sp = t:CreateSpacer(30)
	assert(sp._container.Size.Y.Offset == 30)
	local im = t:CreateImage({ Image = "rbxassetid://123", Height = 80, Caption = "pic" })
	assert(im:Get() == "rbxassetid://123")
	im:Set("rbxassetid://456")
	assert(im._picture.Image == "rbxassetid://456")
	local built
	local c = t:CreateCustom({ Height = 70, Build = function(frame, ctx)
		built = true
		assert(ctx.Create and ctx.Kit and ctx.Theme().Accent)
		ctx.Create("Frame", { Name = "Mine", Parent = frame })
	end })
	assert(built and #findAll(c.Frame, function(d) return d.Name == "Mine" end) == 1)
	local bad = t:CreateCustom({ Build = function() error("kaboom") end })
	assert(bad.BuildError and bad.BuildError:find("kaboom"))
	assert(#findAll(bad.Frame, function(d) return d.Name == "BuildError" end) == 1)
	w:Destroy()
end)

check("DefineElement adds a new element everywhere", function()
	Polaris.DefineElement("Rating", {
		Height = 40, Default = 0,
		Build = function(frame, config, el, ctx)
			el._lbl = ctx.Kit.label(frame, "stars " .. (config.Max or 5), { Name = "Stars" })
		end,
		Set = function(el, v) el._lbl.Text = "value " .. tostring(v) end,
	})
	local w, t = newTab()
	local r = t:CreateRating({ Max = 7, Flag = "rate" })
	assert(r._lbl.Text == "stars 7")
	r:Set(4, true)
	assert(r._lbl.Text == "value 4" and r:Get() == 4)
	local viaAdd = t:Add("Rating", {})
	assert(viaAdd and viaAdd._className == "Rating")
	local ok = pcall(Polaris.DefineElement, "Button", { Build = function() end })
	assert(not ok, "must not override built ins")
	w:Destroy()
end)

check("Use installs a plugin function and a plugin table", function()
	local hits = 0
	Polaris.Use(function(P) hits += 1 assert(P == Polaris) end)
	Polaris.Use({ Name = "demo", Install = function() hits += 1 end })
	assert(hits == 2)
	assert(not pcall(Polaris.Use, 42))
	assert(not pcall(Polaris.Use, function() error("nope") end))
end)

check("State: set, subscribe, map, computed, bind, link", function()
	local s = Polaris.State(1)
	local seen = {}
	local sub = s:Subscribe(function(v) table.insert(seen, v) end)
	s:Set(2); s:Set(2); s:Set(3)
	assert(#seen == 2 and seen[2] == 3, #seen)
	sub:Disconnect()
	s:Set(9)
	assert(#seen == 2)
	local double = s:Map(function(v) return v * 2 end)
	s:Set(10)
	assert(double:Get() == 20)
	local a, b = Polaris.State(2), Polaris.State(3)
	local sum = Polaris.Computed({ a, b }, function(x, y) return x + y end)
	a:Set(10)
	assert(sum:Get() == 13)
	local w, t = newTab()
	local lbl = t:CreateLabel({ Text = "x" })
	lbl:Bind(s, function(v) return "n=" .. v end)
	s:Set(5)
	assert(lbl._value == "n=5" or tostring(lbl:Get()) == "n=5", tostring(lbl:Get()))
	local tg = t:CreateToggle({ Name = "T", Default = false })
	local flag = Polaris.State(false)
	tg:Link(flag)
	tg:Set(true)
	assert(flag:Get() == true, "toggle should write the state")
	flag:Set(false)
	assert(tg:Get() == false, "state should move the toggle")
	w:Destroy()
	s:Set(6) -- element destroyed: must not error
end)

check("Storage keeps values in memory and State can persist", function()
	local st = Polaris.Storage("test_store")
	st:Set("a", { 1, 2 })
	assert(st:Get("a")[2] == 2 and st:Get("zzz", "d") == "d")
	local p = Polaris.State(5, { Persist = "score", Folder = "test_store" })
	p:Set(8)
	local again = Polaris.State(0, { Persist = "score", Folder = "test_store" })
	assert(again:Get() == 8, again:Get())
	assert(#st:Keys() == 2)
end)

check("DefineBlock adds a Builder block that exports and applies", function()
	local B = Polaris.Builder
	local applied = false
	Polaris.DefineBlock("Banner", {
		Label = "Banner",
		new = function() return { Kind = "Banner", Name = "Hi" } end,
		emit = function(v, n, _, L) table.insert(L, v .. ":CreateLabel({ Text = " .. string.format("%q", n.Name) .. " })") end,
		apply = function(tab, n) applied = true tab:CreateLabel({ Text = n.Name }) end,
		item = function(n) return { Type = "Label", Text = n.Name } end,
		props = function() end,
	})
	assert(B.Kinds.Banner and B.Kinds.Banner.Label == "Banner")
	local count = 0
	for _, b in B.BlockDefs do if b.Kind == "Banner" then count += 1 end end
	Polaris.DefineBlock("Banner", B.Kinds.Banner)
	for _, b in B.BlockDefs do if b.Kind == "Banner" then count += 1 end end
	assert(count == 2, "defining twice must not duplicate the palette entry: " .. count)
	assert(not pcall(Polaris.DefineBlock, "Bad", { new = function() end }))
end)

H.finish()
