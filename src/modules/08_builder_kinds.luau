-- builder kinds: teaches the visual Builder about the v2 widgets (Label, Progress, Console,
-- Stats, ScriptLibrary, Research) and ships one-tap project templates.

local Builder = I.Builder
local quote, splitOptions = I.quote, I.splitOptions
local Kinds = Builder.Kinds

local function trim(s)
	return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "Name | description | https://url ; Name2 | desc | https://url2"  ->  list of tables
local function parseScripts(text)
	local out = {}
	for chunk in tostring(text or ""):gmatch("[^;\n]+") do
		local parts = {}
		for piece in (chunk .. "|"):gmatch("(.-)|") do
			table.insert(parts, trim(piece))
		end
		if parts[1] and parts[1] ~= "" then
			local entry = { Name = parts[1] }
			if #parts >= 3 then
				entry.Description = parts[2]
				entry.Url = parts[3]
			elseif parts[2] and parts[2]:find("^https?://") then
				entry.Url = parts[2]
			elseif parts[2] and parts[2] ~= "" then
				entry.Description = parts[2]
			end
			table.insert(out, entry)
		end
	end
	return out
end
Builder.ParseScripts = parseScripts

local PROVIDERS = { "Demo", "Perplexity", "HTTP" }
local DEPTHS = { "Quick", "Standard", "Deep", "Max" }

local function indexIn(list, value)
	return I.indexOf(list, value) or 1
end

----------------------------------------------------------------
-- Label
----------------------------------------------------------------
Kinds.Label = {
	Label = "Label", Color = Color3.fromRGB(110, 150, 200),
	new = function() return { Kind = "Label", Text = "Hello!", TextSize = 16, Bold = false } end,
	emit = function(v, n, _, L)
		table.insert(L, v .. ":CreateLabel({ Text = " .. quote(n.Text) .. ", Size = " .. tostring(tonumber(n.TextSize) or 16) .. ", Bold = " .. tostring(n.Bold == true) .. " })")
	end,
	apply = function(tab, n)
		tab:CreateLabel({ Text = n.Text, Size = tonumber(n.TextSize) or 16, Bold = n.Bold == true })
	end,
	item = function(n)
		return { Type = "Label", Text = n.Text, Size = tonumber(n.TextSize) or 16, Bold = n.Bold == true }
	end,
	props = function(b, n, H)
		H.textbox(b, "Text", n.Text, function(t) n.Text = tostring(t); b:_refreshCanvas(); b:_refreshExport() end)
		H.numberBox("Text size", n, "TextSize")
		H.toggle(b, "Bold", n.Bold == true, function(v) n.Bold = v; b:_refreshExport() end)
	end,
	validate = function(n, problem, label)
		if trim(n.Text) == "" then problem(label .. " label has no text") end
	end,
}

----------------------------------------------------------------
-- Progress
----------------------------------------------------------------
Kinds.Progress = {
	Label = "Progress", Color = Color3.fromRGB(90, 190, 120),
	new = function() return { Kind = "Progress", Name = "Progress", Value = 50, Max = 100 } end,
	emit = function(v, n, _, L)
		table.insert(L, v .. ":CreateProgress({ Name = " .. quote(n.Name) .. ", Max = " .. tostring(tonumber(n.Max) or 100) .. ", Value = " .. tostring(tonumber(n.Value) or 0) .. " })")
	end,
	apply = function(tab, n) tab:CreateProgress({ Name = n.Name, Max = tonumber(n.Max) or 100, Value = tonumber(n.Value) or 0 }) end,
	item = function(n) return { Type = "Progress", Name = n.Name, Max = tonumber(n.Max) or 100, Value = tonumber(n.Value) or 0 } end,
	props = function(b, n, H)
		H.nameBox(n)
		H.numberBox("Value", n, "Value")
		H.numberBox("Max", n, "Max")
	end,
	validate = function(n, problem, label)
		if (tonumber(n.Max) or 0) <= 0 then problem(label .. " progress Max must be above 0") end
	end,
}

----------------------------------------------------------------
-- Console
----------------------------------------------------------------
Kinds.Console = {
	Label = "Console", Color = Color3.fromRGB(80, 90, 110),
	new = function() return { Kind = "Console", Name = "Output", Height = 140 } end,
	emit = function(v, n, _, L)
		table.insert(L, v .. ":CreateConsole({ Name = " .. quote(n.Name) .. ", Height = " .. tostring(tonumber(n.Height) or 140) .. " })")
	end,
	apply = function(tab, n) tab:CreateConsole({ Name = n.Name, Height = tonumber(n.Height) or 140 }) end,
	item = function(n) return { Type = "Console", Name = n.Name, Height = tonumber(n.Height) or 140 } end,
	props = function(b, n, H)
		H.nameBox(n)
		H.numberBox("Height", n, "Height")
	end,
}

----------------------------------------------------------------
-- Stats
----------------------------------------------------------------
local function statItems(n)
	local items = splitOptions(n.Items)
	if #items == 0 then items = { "FPS", "Ping" } end
	return items
end
Kinds.Stats = {
	Label = "Stats", Color = Color3.fromRGB(70, 160, 200),
	new = function() return { Kind = "Stats", Name = "Stats", Items = "FPS, Ping, Players, Memory" } end,
	emit = function(v, n, _, L)
		local q = {}
		for _, s in ipairs(statItems(n)) do table.insert(q, quote(s)) end
		table.insert(L, v .. ":CreateStats({ Items = { " .. table.concat(q, ", ") .. " } })")
	end,
	apply = function(tab, n) tab:CreateStats({ Items = statItems(n) }) end,
	item = function(n) return { Type = "Stats", Items = statItems(n) } end,
	props = function(b, n, H)
		H.textbox(b, "Items", n.Items, function(t) n.Items = tostring(t); b:_refreshCanvas(); b:_refreshExport() end)
	end,
	validate = function(n, problem, label)
		for _, s in ipairs(statItems(n)) do
			if not Polaris.StatsProviders[s] then problem(label .. " stats: unknown item '" .. s .. "'") end
		end
	end,
}

----------------------------------------------------------------
-- ScriptLibrary
----------------------------------------------------------------
Kinds.ScriptLibrary = {
	Label = "Script Library", Color = Color3.fromRGB(66, 133, 244),
	new = function()
		return { Kind = "ScriptLibrary", Name = "Scripts", Height = 320, Scripts = "Example | Shows a hello message | https://example.com/script.lua" }
	end,
	emit = function(v, n, _, L)
		table.insert(L, v .. ":CreateScriptLibrary({")
		table.insert(L, "\tHeight = " .. tostring(tonumber(n.Height) or 320) .. ",")
		table.insert(L, "\tFolder = " .. quote(n.Name) .. ",")
		table.insert(L, "\tScripts = {")
		for _, s in ipairs(parseScripts(n.Scripts)) do
			local line = "\t\t{ Name = " .. quote(s.Name)
			if s.Description then line ..= ", Description = " .. quote(s.Description) end
			if s.Url then line ..= ", Url = " .. quote(s.Url) end
			table.insert(L, line .. " },")
		end
		table.insert(L, "\t},")
		table.insert(L, "})")
	end,
	apply = function(tab, n)
		-- preview: list the scripts but never fetch anything remote
		local scripts = {}
		for _, s in ipairs(parseScripts(n.Scripts)) do
			table.insert(scripts, { Name = s.Name, Description = s.Description, Url = s.Url })
		end
		tab:CreateScriptLibrary({ Height = tonumber(n.Height) or 320, Folder = n.Name, Scripts = scripts, Confirm = true })
	end,
	item = function(n, handlers)
		return { Type = "ScriptLibrary", Height = tonumber(n.Height) or 320, Folder = n.Name, Scripts = parseScripts(n.Scripts) }
	end,
	props = function(b, n, H)
		H.nameBox(n)
		H.numberBox("Height", n, "Height")
		H.textbox(b, "Scripts", n.Scripts, function(t) n.Scripts = tostring(t); b:_refreshCanvas(); b:_refreshExport() end)
	end,
	validate = function(n, problem, label)
		local list = parseScripts(n.Scripts)
		if #list == 0 then problem(label .. " script library has no scripts (use: Name | description | https://url ; ...)") end
		for _, s in ipairs(list) do
			if s.Url and not s.Url:find("^https://") then problem(label .. " script '" .. s.Name .. "' needs an https:// link") end
		end
	end,
}

----------------------------------------------------------------
-- Research (the key is NEVER written into generated code)
----------------------------------------------------------------
Kinds.Research = {
	Label = "Research", Color = Color3.fromRGB(150, 95, 235),
	new = function() return { Kind = "Research", Name = "Research", Provider = "Demo", Depth = "Standard", Height = 380 } end,
	emit = function(v, n, _, L)
		table.insert(L, "-- Research: players paste their own API key into the box at run time; no key is stored in this script.")
		table.insert(L, v .. ":CreateResearch({ Provider = " .. quote(n.Provider or "Demo") .. ", Depth = " .. quote(n.Depth or "Standard") .. ", Height = " .. tostring(tonumber(n.Height) or 380) .. " })")
	end,
	apply = function(tab, n) tab:CreateResearch({ Provider = "Demo", Depth = n.Depth or "Standard", Height = tonumber(n.Height) or 380 }) end,
	item = function(n) return { Type = "Research", Provider = n.Provider or "Demo", Depth = n.Depth or "Standard", Height = tonumber(n.Height) or 380 } end,
	props = function(b, n, H)
		H.cycle(b, "Provider", PROVIDERS, indexIn(PROVIDERS, n.Provider), function(v) n.Provider = v; b:_refreshExport() end)
		H.cycle(b, "Depth", DEPTHS, indexIn(DEPTHS, n.Depth), function(v) n.Depth = v; b:_refreshExport() end)
		H.numberBox("Height", n, "Height")
	end,
	validate = function(n, problem, label)
		if not I.indexOf(PROVIDERS, n.Provider or "Demo") then problem(label .. " research provider must be Demo, Perplexity or HTTP") end
		if not I.indexOf(DEPTHS, n.Depth or "Standard") then problem(label .. " research depth must be Quick, Standard, Deep or Max") end
	end,
}


----------------------------------------------------------------
-- Script: a block that holds real Luau code and runs it when tapped.
-- This is how blocks and scripts mix: blocks make the hub, Script blocks do the work.
----------------------------------------------------------------
local function codeLines(code)
	local out = {}
	for line in (tostring(code or ""):gsub("\r", "") .. "\n"):gmatch("(.-)\n") do
		table.insert(out, line)
	end
	while #out > 0 and trim(out[#out]) == "" do
		table.remove(out)
	end
	return out
end

local function compileProblem(code)
	local loader = loadstring
	if type(loader) ~= "function" then
		return nil -- cannot check here; the exported script will still be checked by Roblox when it loads
	end
	local fn, err = loader("local _ = function()\n" .. tostring(code or "") .. "\nend")
	if not fn then
		return tostring(err)
	end
	return nil
end

Kinds.Script = {
	Label = "Script", Color = Color3.fromRGB(235, 100, 60),
	new = function()
		return { Kind = "Script", Name = "My script", Code = 'Polaris:Notify({ Title = "Hello", Content = "My script ran!", Type = "success" })' }
	end,
	emit = function(v, n, _, L)
		table.insert(L, v .. ":CreateButton({")
		table.insert(L, "\tName = " .. quote(n.Name) .. ",")
		table.insert(L, "\tCallback = function()")
		table.insert(L, "\t\tlocal ok, err = pcall(function()")
		for _, line in ipairs(codeLines(n.Code)) do
			table.insert(L, "\t\t\t" .. line)
		end
		table.insert(L, "\t\tend)")
		table.insert(L, "\t\tif not ok then")
		table.insert(L, "\t\t\tPolaris:Notify({ Title = " .. quote(tostring(n.Name) .. " did not run") .. ", Content = tostring(err), Type = \"error\", Duration = 6 })")
		table.insert(L, "\t\tend")
		table.insert(L, "\tend,")
		table.insert(L, "})")
	end,
	apply = function(tab, n)
		-- the preview never runs your code; the exported hub does
		tab:CreateButton({ Name = n.Name, Callback = function()
			Polaris:Notify({ Title = tostring(n.Name), Content = "Preview only. Your code runs in the exported hub.", Type = "info", Duration = 3 })
		end })
	end,
	item = function(n)
		local code = tostring(n.Code or "")
		return { Type = "Button", Name = n.Name, Callback = function()
			local loader = loadstring
			if type(loader) ~= "function" then
				return Polaris:Notify({ Title = tostring(n.Name), Content = "This place does not allow loadstring, so block code cannot run here. Export the hub as a script instead.", Type = "warning", Duration = 6 })
			end
			local fn, err = loader(code)
			if not fn then
				return Polaris:Notify({ Title = tostring(n.Name) .. " has a mistake", Content = tostring(err), Type = "error", Duration = 6 })
			end
			local ok, runErr = pcall(fn)
			if not ok then
				Polaris:Notify({ Title = tostring(n.Name) .. " did not run", Content = tostring(runErr), Type = "error", Duration = 6 })
			end
		end }
	end,
	props = function(b, n, H)
		H.nameBox(n)
		H.code(b, "Your code (Luau)", n.Code, function(t)
			n.Code = tostring(t)
			b:_refreshExport()
		end)
	end,
	validate = function(n, problem, label)
		if trim(n.Code) == "" then
			problem(label .. " script block has no code")
			return
		end
		local bad = compileProblem(n.Code)
		if bad then
			problem(label .. " script block has a mistake: " .. bad)
		end
	end,
}

for _, def in ipairs({ "Script", "Label", "Progress", "Console", "Stats", "ScriptLibrary", "Research" }) do
	table.insert(Builder.BlockDefs, { Kind = def, Label = Kinds[def].Label, Color = Kinds[def].Color })
end

----------------------------------------------------------------
-- Templates
----------------------------------------------------------------
local function proj(name, tabs)
	return { window = { Name = name, Theme = "Default", ConfigFolder = I.slugify(name), SaveConfig = true }, tabs = tabs }
end

local TEMPLATES = {
	["My Script Hub"] = function()
		return proj("My Script Hub", {
			{ Name = "My Scripts", Icon = "", nodes = {
				{ Kind = "Label", Text = "Welcome to my script hub", TextSize = 22, Bold = true },
				{ Kind = "Section", Name = "Scripts I made with blocks" },
				{ Kind = "Script", Name = "Say hello", Code = 'Polaris:Notify({ Title = "Hello", Content = "My hub works!", Type = "success" })' },
				{ Kind = "Script", Name = "Brighten the world", Code = 'game:GetService("Lighting").Brightness = 3' },
				{ Kind = "Script", Name = "Wide view", Code = 'workspace.CurrentCamera.FieldOfView = 100' },
			} },
			{ Name = "Script Library", Icon = "", nodes = {
				{ Kind = "ScriptLibrary", Name = "My Library", Height = 320, Scripts = "Replace me | Put your own link here | https://example.com/my-script.lua" },
			} },
			{ Name = "Stats", Icon = "", nodes = { { Kind = "Stats", Name = "Stats", Items = "FPS, Ping, Players" } } },
		})
	end,
	["Script Library"] = function()
		return proj("Script Library", { { Name = "Library", Icon = "", nodes = {
			{ Kind = "ScriptLibrary", Name = "Scripts", Height = 340, Scripts = "Hello | A tiny example | https://example.com/hello.lua ; Another | Replace me | https://example.com/another.lua" },
		} } })
	end,
	["Deep Research"] = function()
		return proj("Deep Research", { { Name = "Research", Icon = "", nodes = {
			{ Kind = "Research", Name = "Research", Provider = "Demo", Depth = "Standard", Height = 400 },
		} } })
	end,
	["Roblox Hub"] = function()
		return proj("Roblox Hub", {
			{ Name = "Home", Icon = "", nodes = {
				{ Kind = "Stats", Name = "Stats", Items = "FPS, Ping, Players, Memory" },
				{ Kind = "Section", Name = "Camera" },
				{ Kind = "Slider", Name = "Field of view", Min = 40, Max = 120, Default = 70, Increment = 1, ValueName = "deg", Flag = "fov" },
				{ Kind = "Slider", Name = "Time of day", Min = 0, Max = 24, Default = 14, Increment = 1, ValueName = "h", Flag = "time" },
				{ Kind = "Toggle", Name = "Show output", Default = true, Flag = "output" },
			} },
			{ Name = "Output", Icon = "", nodes = { { Kind = "Console", Name = "Output", Height = 220 } } },
		})
	end,
	["Everything"] = function()
		return proj("Everything Hub", {
			{ Name = "Home", Icon = "", nodes = {
				{ Kind = "Label", Text = "Welcome! Pick a tab.", TextSize = 20, Bold = true },
				{ Kind = "Stats", Name = "Stats", Items = "FPS, Ping, Players" },
				{ Kind = "Button", Name = "Say hello" },
			} },
			{ Name = "Scripts", Icon = "", nodes = { { Kind = "ScriptLibrary", Name = "Scripts", Height = 320, Scripts = "Hello | A tiny example | https://example.com/hello.lua" } } },
			{ Name = "Research", Icon = "", nodes = { { Kind = "Research", Name = "Research", Provider = "Demo", Depth = "Standard", Height = 380 } } },
		})
	end,
}
local TEMPLATE_ORDER = { "My Script Hub", "Script Library", "Deep Research", "Roblox Hub", "Everything" }

function Builder:GetTemplateNames()
	return table.clone(TEMPLATE_ORDER)
end

function Builder:LoadTemplate(name)
	local make = TEMPLATES[name]
	assert(make, "[Polaris] Builder: unknown template '" .. tostring(name) .. "'. Valid: " .. table.concat(TEMPLATE_ORDER, ", "))
	self:SetProject(make())
	return self:GetProject()
end
