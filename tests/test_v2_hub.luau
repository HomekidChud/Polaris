-- The real script hub: built-in scripts, "+ Add" form, saved user scripts, Script blocks.
local H = require("./harness")
local check = H.check
local tasklib = require("@lune/task")
local luau = require("@lune/luau")
local files = {}
local Polaris, env = H.load(nil, function(e)
	e.loadstring = function(code)
		local ok, fn = pcall(luau.load, code, { environment = e })
		if not ok then return nil, tostring(fn) end
		return fn
	end
	e.writefile = function(p, c) files[p] = c end
	e.readfile = function(p) return files[p] end
	e.isfile = function(p) return files[p] ~= nil end
	e.makefolder = function() end
end)

local function findAll(root, pred)
	local out = {}
	for _, d in root:GetDescendants() do if pred(d) then out[#out + 1] = d end end
	return out
end

check("hub scripts are real and all run without errors in the mock", function()
	local list = Polaris.HubScripts()
	assert(#list >= 8, "only " .. #list)
	local lib = Polaris.Library.new({ Scripts = list })
	for _, e in lib:Query({}) do
		local ok, err = lib:Run(e)
		-- Rejoin needs a real TeleportService; every other script must work
		if e.Name ~= "Rejoin this server" then assert(ok, e.Name .. ": " .. tostring(err)) end
	end
	-- second run of the toggling ones puts things back
	for _, e in lib:Query({}) do
		if e.Name == "Fullbright" or e.Name == "Wide view" or e.Name == "FPS counter" or e.Name == "Hide chat" then
			assert(lib:Run(e), e.Name .. " second run")
		end
	end
end)

check("script hub window opens with the real scripts", function()
	local w, lib = Polaris.Templates.ScriptLibrary({ Name = "Script Hub" })
	assert(lib:Count() >= 10, lib:Count())
	w:Destroy()
end)

check("AddUser accepts a link or code, rejects bad input", function()
	local lib = Polaris.Library.new({ Folder = "hubtest" })
	assert(lib:AddUser("", "print(1)") == nil)
	assert(lib:AddUser("x", "") == nil)
	local _, why = lib:AddUser("Bad", "http://insecure.example/a.lua")
	assert(why and why:find("https"), tostring(why))
	local a = lib:AddUser("My code", "print('hi')")
	assert(a and a.Code and a.User)
	local b = lib:AddUser("My link", "https://example.com/a.lua")
	assert(b and b.Url and b.User)
	assert(lib:Run(a) == true)
end)

check("user scripts are saved, restored and removable", function()
	local lib = Polaris.Library.new({ Folder = "persist" })
	lib:AddUser("Keep me", "print('kept')")
	local lib2 = Polaris.Library.new({ Folder = "persist" })
	local e = lib2:Get("keepme")
	assert(e and e.Code and e.User, "not restored")
	lib2:Remove("keepme")
	local lib3 = Polaris.Library.new({ Folder = "persist" })
	assert(lib3:Get("keepme") == nil)
end)

check("+ Add form works through the UI", function()
	local w = Polaris:CreateWindow({ Name = "AddUI" })
	local t = w:CreateTab({ Name = "Lib" })
	local el = t:CreateScriptLibrary({ Scripts = { { Name = "A", Run = function() end } }, Folder = "adduitest" })
	local add = findAll(w._gui or w.Gui or el._holder, function(d) return d.Name == "AddScript" end)[1]
	assert(add, "no + Add button")
	add.Activated:Fire()
	local nameBox = findAll(el._holder, function(d) return d.Name == "NameBox" end)[1]
	local codeBox = findAll(el._holder, function(d) return d.Name == "CodeBox" end)[1]
	assert(nameBox and codeBox, "form not shown")
	-- empty save shows a message and keeps the form
	findAll(el._holder, function(d) return d.Name == "SaveScript" end)[1].Activated:Fire()
	assert(#findAll(el._holder, function(d) return d.Name == "AddForm" end) == 1)
	nameBox.Text = "Typed"
	codeBox.Text = "print('typed')"
	findAll(el._holder, function(d) return d.Name == "SaveScript" end)[1].Activated:Fire()
	assert(el.Library:Get("typed"), "script not added")
	assert(#findAll(el._holder, function(d) return d.Name == "AddForm" end) == 0, "form still open")
	assert(#findAll(el._holder, function(d) return d.Name == "RemoveScript" end) == 1, "no remove button for user script")
	w:Destroy()
end)

check("Script block: palette, codegen, validation and run", function()
	local Pol, e = H.load(nil, function(env2)
		env2.loadstring = function(code)
			local ok, fn = pcall(luau.load, code, { environment = env2 })
			if not ok then return nil, tostring(fn) end
			return fn
		end
	end)
	local B = Pol.Builder
	local seen
	for _, d in B.BlockDefs do if d.Kind == "Script" then seen = true end end
	assert(seen, "Script not in palette")
	B:NewProject()
	local node = B:AddBlock("Script")
	assert(node and node.Kind == "Script" and node.Code ~= "")
	node.Code = "local x = 1\nPolaris:Notify({ Title = 'ran', Content = tostring(x) })"
	assert(B:Validate())
	B.PolarisURL = nil
	local code = B:Generate()
	assert(code:find("pcall%(function%(%)"), "no pcall wrapper")
	local win = luau.load(code, { environment = e })(Pol)
	-- bad code is caught by validation
	node.Code = "local = = 1 end end"
	local ok, why = B:Validate()
	assert(not ok and why:find("mistake"), tostring(why))
	node.Code = ""
	ok, why = B:Validate()
	assert(not ok)
	if win then win:Destroy() end
end)

check("My Script Hub template: valid, generates runnable code, mixes blocks and scripts", function()
	local Pol, e = H.load(nil, function(env2)
		env2.loadstring = function(code)
			local ok, fn = pcall(luau.load, code, { environment = env2 })
			if not ok then return nil, tostring(fn) end
			return fn
		end
	end)
	local B = Pol.Builder
	assert(B:GetTemplateNames()[1] == "My Script Hub")
	B:NewProject()
	B:LoadTemplate("My Script Hub")
	local ok, why = B:Validate()
	assert(ok, tostring(why))
	local proj = B:GetProject()
	local kinds = {}
	for _, tab in proj.tabs do for _, n in tab.nodes do kinds[n.Kind] = true end end
	assert(kinds.Script and kinds.ScriptLibrary and kinds.Label, "template does not mix blocks and scripts")
	B.PolarisURL = nil
	local win = luau.load(B:Generate(), { environment = e })(Pol)
	if win then win:Destroy() end
	-- opens straight from JSON too, and a Script button runs its code
	local w2 = Pol.FromProject(B:ExportJSON())
	local tab = w2:GetTab("My Scripts")
	local pressed = false
	for _, el in tab:GetElements() do
		if el._interaction and el._config and el._config.Name == "Say hello" then
			el._interaction.Activated:Fire()
			pressed = true
		end
	end
	assert(pressed, "Say hello button not found")
	w2:Destroy()
end)

check("MakeHub opens the editor and settings tab offers the button", function()
	local B = Polaris.MakeHub()
	assert(B:GetProject().window.Name == "My Script Hub")
	tasklib.wait(0.5)
	B:Close()
	local w = Polaris:CreateWindow({ Name = "S" })
	local st = w:AddSettingsTab()
	local found
	for _, el in st:GetElements() do
		if el._config and el._config.Name == "Create your own script hub (blocks)" then found = true end
	end
	assert(found, "no hub-maker button in Settings")
	w:Destroy()
end)

H.finish()
