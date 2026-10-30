local H = require("./harness")
local check = H.check
local luau = require("@lune/luau")
local Polaris, env = H.load()
local B = Polaris.Builder

check("templates exist and validate", function()
	local names = B:GetTemplateNames()
	assert(#names == 4)
	for _, n in names do
		B:NewProject()
		B:LoadTemplate(n)
		local ok, why = B:Validate()
		assert(ok, n .. ": " .. tostring(why))
	end
	H.expectError(function() B:LoadTemplate("nope") end)
end)

check("new kinds are in the palette", function()
	local seen = {}
	for _, d in B.BlockDefs do seen[d.Kind] = true end
	for _, k in { "Label", "Progress", "Console", "Stats", "ScriptLibrary", "Research" } do assert(seen[k], k) end
end)

check("AddBlock creates each new kind", function()
	B:NewProject()
	for _, k in { "Label", "Progress", "Console", "Stats", "ScriptLibrary", "Research" } do
		local node = B:AddBlock(k)
		assert(node and node.Kind == k, k)
	end
	assert(B:Validate())
end)

check("validation catches bad new-kind input", function()
	B:NewProject()
	B:SetProject({ window = { Name = "x", Theme = "Default", ConfigFolder = "x", SaveConfig = false }, tabs = { { Name = "T", Icon = "", nodes = {
		{ Kind = "ScriptLibrary", Name = "S", Height = 100, Scripts = "A | d | http://insecure" },
		{ Kind = "Progress", Name = "P", Value = 1, Max = 0 },
		{ Kind = "Research", Name = "R", Provider = "Nope", Depth = "Standard", Height = 100 },
	} } } })
	local ok, why = B:Validate()
	assert(not ok and why:find("https"), tostring(why))
end)

for _, tname in { "Script Library", "Deep Research", "Roblox Hub", "Everything" } do
	check("generated code runs: " .. tname, function()
		local Pol, e = H.load()
		local b = Pol.Builder
		b:NewProject()
		b:LoadTemplate(tname)
		b.PolarisURL = nil
		local code = b:Generate()
		assert(not code:find("pplx") and not code:lower():find("api_key"))
		local chunk = luau.load(code, { debugName = "gen", environment = e })
		local win = chunk(Pol)
		assert(win == nil or win.Destroy)
		-- also round-trips through FromProject
		local w2 = Pol.FromProject(b:ExportJSON())
		w2:Destroy()
		if win then win:Destroy() end
	end)
end

check("preview of a template opens and closes", function()
	local Pol = H.load()
	Pol.Builder:NewProject()
	Pol.Builder:LoadTemplate("Everything")
	local p = Pol.Builder:OpenPreview()
	Pol.Builder:ClosePreview()
end)

H.finish()
