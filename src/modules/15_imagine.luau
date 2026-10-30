-- imagine: describe an app in words -> a validated spec -> a real window.
--   Polaris.Imagine("a clicker game with a score chart")            offline Demo provider (keywords, no AI)
--   Polaris.Imagine(prompt, { Provider = "Perplexity", ApiKey = k })  asks Perplexity for a spec (needs your key + HTTP)
--   Polaris.Imagine(prompt, { Provider = function(system, user) return jsonText end })   any AI you like
-- Whatever comes back is checked by Polaris.Spec.Validate first: unknown things are dropped and no code is ever run.

local Util = Polaris.Util
local JSON, Http = Util.JSON, Util.Http
local Spec = Polaris.Spec

local Imagine = {}
Polaris.ImagineProviders = {}

----------------------------------------------------------------
-- Offline generator: keywords -> spec pieces
----------------------------------------------------------------
local PIECES = {}
local ORDER = {}
local function piece(name, words, build)
	PIECES[name] = { Words = words, Build = build }
	table.insert(ORDER, name)
end

piece("counter", { "count", "click", "tap", "score", "game", "clicker", "tycoon", "points" }, function(spec)
	spec.State.count = spec.State.count or 0
	spec.State.perClick = spec.State.perClick or 1
	table.insert(spec.Tabs, { Name = "Play", Items = {
		{ Type = "Label", Text = "Score: {count}", Size = 26, Color = "Accent" },
		{ Type = "Button", Name = "Tap!", Action = { Do = "Add", Key = "count", Value = 1 } },
		{ Type = "Slider", Name = "Points per tap", Min = 1, Max = 10, Default = 1, Key = "perClick" },
		{ Type = "Button", Name = "Bonus tap (uses the slider)", Action = { Do = "Add", Key = "count", Value = 5 } },
		{ Type = "Progress", Name = "Goal: 100", Value = 0, Max = 100, Key = "count" },
		{ Type = "Button", Name = "Start again", Action = { { Do = "Reset", Key = "count" }, { Do = "Notify", Title = "Reset", Text = "Score is back to 0." } } },
	} })
end)

piece("dashboard", { "dashboard", "stats", "chart", "graph", "analytics", "monitor", "report", "overview" }, function(spec)
	table.insert(spec.Tabs, { Name = "Overview", Items = {
		{ Type = "Stats", Items = { "FPS", "Ping", "Players", "Memory" } },
		{ Type = "Columns", Count = 2, Columns = {
			{ Items = { { Type = "Chart", Title = "This week", Labels = { "Mon", "Tue", "Wed", "Thu", "Fri" }, Values = { 4, 7, 5, 9, 6 }, Height = 170 } } },
			{ Items = { { Type = "Chart", Style = "line", Title = "Trend", Labels = { "1", "2", "3", "4", "5", "6" }, Values = { 2, 4, 3, 6, 5, 8 }, Height = 170 } } },
		} },
		{ Type = "Table", Columns = { "Name", "Score", "Rank" }, Rows = { { "Ada", 92, 1 }, { "Bo", 85, 2 }, { "Cy", 77, 3 } }, Height = 150, Search = true },
	} })
end)

piece("tracker", { "track", "tracker", "list", "todo", "to-do", "inventory", "log", "notes", "tasks", "shop", "items", "collection" }, function(spec)
	table.insert(spec.Tabs, { Name = "Tracker", Items = {
		{ Type = "Form", Name = "Add an entry", Submit = "Add", Fields = {
			{ Name = "Item", Type = "Textbox", Required = true, Placeholder = "What is it?" },
			{ Name = "Amount", Type = "Number", Required = true, Min = 0, Max = 9999, Default = 1 },
			{ Name = "Done", Type = "Toggle" },
		}, Action = { { Do = "AddRow", Table = "entries", FromForm = true }, { Do = "Notify", Title = "Saved", Text = "Entry added." } } },
		{ Type = "Table", Id = "entries", Columns = { "Item", "Amount", "Done" }, Rows = {}, Height = 200, Search = true },
		{ Type = "Button", Name = "Clear all", Action = { Do = "ClearTable", Table = "entries" } },
	} })
end)

piece("settings", { "settings", "options", "preferences", "config", "menu", "panel", "control" }, function(spec)
	spec.State.sound = spec.State.sound == nil and true or spec.State.sound
	spec.State.volume = spec.State.volume or 50
	spec.State.name = spec.State.name or "Player"
	table.insert(spec.Tabs, { Name = "Settings", Items = {
		{ Type = "Section", Name = "You" },
		{ Type = "Textbox", Name = "Your name", Key = "name" },
		{ Type = "Label", Text = "Hello {name}. Sound is {sound}, volume {volume}." },
		{ Type = "Section", Name = "Sound" },
		{ Type = "Toggle", Name = "Sound on", Key = "sound" },
		{ Type = "Slider", Name = "Volume", Min = 0, Max = 100, Key = "volume" },
		{ Type = "Section", Name = "Look" },
		{ Type = "Dropdown", Name = "Theme", Options = { "Default", "Midnight" }, Action = { Do = "Theme", FromValue = true } },
	} })
end)

piece("hub", { "hub", "scripts", "script", "library", "loader" }, function(spec)
	table.insert(spec.Tabs, { Name = "Scripts", Items = {
		{ Type = "Label", Text = "Safe built-in scripts. Tap one to run it.", Size = 13, Color = "SubText" },
		{ Type = "HubScripts", Height = 320 },
	} })
end)

piece("about", { "about", "info", "help", "welcome", "guide" }, function(spec)
	table.insert(spec.Tabs, { Name = "About", Items = {
		{ Type = "Group", Name = "What is this", Card = true, Items = { { Type = "Label", Text = "Made with Polaris from a few words.", Wrap = true } } },
		{ Type = "Group", Name = "Open for more", Collapsible = true, Open = false, Items = { { Type = "Label", Text = "Everything here came from a plain description." } } },
	} })
end)

local function titleFrom(prompt)
	local words = {}
	for w in tostring(prompt):gmatch("[%a%d']+") do
		if #words < 3 and #w > 2 and not ({ the = true, and_ = true, with = true, for_ = true, make = true, create = true, build = true, that = true })[w:lower()] then
			table.insert(words, w:sub(1, 1):upper() .. w:sub(2):lower())
		end
	end
	return #words > 0 and table.concat(words, " ") or "My App"
end

function Spec.FromWords(prompt)
	local text = " " .. tostring(prompt or ""):lower() .. " "
	local spec = { Name = titleFrom(prompt), State = {}, Tabs = {} }
	for _, name in ipairs(ORDER) do
		local p = PIECES[name]
		local hit = false
		for _, w in ipairs(p.Words) do
			if text:find(w, 1, true) then hit = true break end
		end
		if hit and name ~= "about" or (name == "about" and text:find("about", 1, true)) then
			p.Build(spec)
		end
	end
	if #spec.Tabs == 0 then
		PIECES.about.Build(spec)
		PIECES.counter.Build(spec)
	end
	if #spec.Tabs > 4 then
		for i = #spec.Tabs, 5, -1 do table.remove(spec.Tabs, i) end
	end
	return spec
end

----------------------------------------------------------------
-- Providers
----------------------------------------------------------------
Polaris.ImagineProviders.Demo = function()
	return function(_, user)
		return Spec.FromWords(user)
	end
end

-- Perplexity Agent API. Your own API key; kept in memory only. Untested against the live service.
Polaris.ImagineProviders.Perplexity = function(opts)
	opts = opts or {}
	local base = opts.BaseUrl or "https://api.perplexity.ai"
	local parser = Polaris.Research.Providers.Perplexity({}).parse
	return function(system, user)
		local key = opts.ApiKey
		if type(key) ~= "string" or #key < 8 then error("Paste your Perplexity API key first.", 0) end
		if not Http.Available() then error("This place cannot make HTTP requests (needs an executor with request() or HttpService).", 0) end
		local headers = { ["Authorization"] = "Bearer " .. key, ["Content-Type"] = "application/json" }
		local res = Http.Request({ Url = base .. "/v1/agent", Method = "POST", Headers = headers, Body = {
			effort = opts.Effort or "fast", input = user, instructions = system,
		} })
		if not res.Success then
			error(("Perplexity said no (HTTP %s): %s"):format(tostring(res.StatusCode), tostring(res.Body):sub(1, 160)), 0)
		end
		local resp = JSON.decode(res.Body)
		if type(resp) ~= "table" then error("Perplexity sent back something that is not JSON.", 0) end
		local terminal = { completed = true, failed = true, cancelled = true, incomplete = true }
		local started = os.clock()
		while resp.status and not terminal[resp.status] do
			if os.clock() - started > (opts.Timeout or 120) then error("Timed out waiting for Perplexity.", 0) end
			task.wait(2)
			local poll = Http.Request({ Url = base .. "/v1/agent/" .. tostring(resp.id), Method = "GET", Headers = headers })
			if not poll.Success then error("Could not read the answer from Perplexity.", 0) end
			resp = JSON.decode(poll.Body) or resp
		end
		if resp.status == "failed" or resp.status == "cancelled" then error("Perplexity could not finish: " .. tostring(resp.status), 0) end
		local text = parser(resp)
		if text == "" then error("Perplexity returned no text.", 0) end
		return text
	end
end

local function resolveProvider(p, opts)
	p = p or "Demo"
	if type(p) == "function" then return p end
	if type(p) == "table" and type(p.Complete) == "function" then
		return function(...) return p:Complete(...) end
	end
	if type(p) == "string" then
		local make = Polaris.ImagineProviders[p]
		assert(make, "[Polaris] Imagine: unknown provider '" .. p .. "'. Built in: Demo, Perplexity")
		return make(opts)
	end
	error("[Polaris] Imagine: Provider must be a name, a function(system, user) or a table with Complete", 0)
end

-- pull a JSON object out of an AI reply (fences, chatter before/after)
function Spec.Extract(reply)
	if type(reply) == "table" then return reply end
	if type(reply) ~= "string" then return nil, "no reply" end
	local text = reply:gsub("```%w*", "")
	local first, last = text:find("{"), nil
	for i = #text, 1, -1 do
		if text:sub(i, i) == "}" then last = i break end
	end
	if not first or not last or last < first then return nil, "no JSON object in the reply" end
	local ok, value, err = pcall(JSON.decode, text:sub(first, last))
	if not ok then return nil, tostring(value) end
	if type(value) ~= "table" then return nil, tostring(err or "reply was not a JSON object") end
	return value
end

-- Polaris.Imagine(prompt, opts) -> app, problems, spec     (yields while it waits for an AI)
-- opts: Provider, ApiKey, Build (false = only return the checked spec), Attempts (default 2), Size
function Polaris.Imagine(prompt, opts)
	opts = opts or {}
	prompt = tostring(prompt or "")
	if prompt:match("^%s*$") then return nil, { "Say what you want to make first." } end
	if #prompt > 1500 then prompt = prompt:sub(1, 1500) end
	local provider = resolveProvider(opts.Provider, opts)
	local system = Spec.Describe()
	local ask, clean, problems, last = prompt, nil, {}, nil
	for attempt = 1, math.max(1, opts.Attempts or 2) do
		local ok, reply = pcall(provider, system, ask)
		if not ok then return nil, { tostring(reply) } end
		local raw, err = Spec.Extract(reply)
		if raw then
			clean, problems = Spec.Validate(raw)
			last = clean or last
			if clean then break end
		else
			problems = { "could not read the reply: " .. tostring(err) }
		end
		ask = prompt .. "\n\nYour last reply had these problems, please fix them and answer with only the JSON object:\n- " .. table.concat(problems, "\n- ")
	end
	if not clean then return nil, problems end
	if opts.Build == false then return nil, problems, clean end
	local app = Spec.Build(clean, opts)
	for _, p in ipairs(problems) do table.insert(app.Problems, p) end
	return app, app.Problems, clean
end

----------------------------------------------------------------
-- The Make Anything window
----------------------------------------------------------------
local IDEAS = {
	{ "A clicker game with a score bar", "a clicker game with a score" },
	{ "A dashboard with charts and a table", "a dashboard with charts and a table" },
	{ "A tracker for items I own", "an inventory tracker with a form" },
	{ "A settings panel", "a settings panel with sound and volume" },
	{ "A script hub", "a script hub" },
	{ "Everything at once", "a game with a dashboard, a tracker and settings" },
}

function Polaris.Imaginer(opts)
	opts = opts or {}
	local window = Polaris:CreateWindow({ Name = opts.Name or "Make Anything", Size = Vector2.new(560, 500) })
	local self = { Window = window, Busy = false }
	local tab = window:CreateTab({ Name = "Describe" })
	tab:CreateLabel({ Text = "Say what you want to make. Polaris builds a real window from it.", Size = 14 })
	local prompt = tab:CreateCodeEditor({ Height = 84, LineNumbers = false, Default = opts.Prompt or "a clicker game with a score", Placeholder = "for example: a tracker for my items" })
	local provider = tab:CreateDropdown({ Name = "Who builds it", Options = { "Demo", "Perplexity" }, Default = opts.Provider or "Demo" })
	local key = tab:CreateTextbox({ Name = "Perplexity key", Default = opts.ApiKey or "" })
	tab:CreateLabel({ Text = "Demo works offline from keywords. Perplexity needs your own key (kept in memory only) and HTTP.", Size = 12, Color = "SubText" })
	local console = tab:CreateConsole({ Name = "What happened", Height = 130 })
	self.Console, self.Prompt = console, prompt

	function self:Make(text)
		if self.Busy then return end
		if text then prompt:Set(text, true) end
		self.Busy = true
		console:Log("Making it ...", "dim")
		task.spawn(function()
			local app, problems, spec = Polaris.Imagine(prompt:Get(), { Provider = provider:Get(), ApiKey = key:Get() })
			self.Busy = false
			if not app then
				for _, p in ipairs(problems or {}) do console:Log(p, "error") end
				return
			end
			if self.LastApp then pcall(function() self.LastApp:Destroy() end) end
			self.LastApp, self.LastSpec = app, spec
			console:Log("Done: " .. spec.Name .. " (" .. #spec.Tabs .. " tabs).", "ok")
			for _, p in ipairs(problems or {}) do console:Log("Skipped: " .. p, "warn") end
		end)
	end
	function self:ShowSpec()
		if not self.LastSpec then console:Log("Make something first.", "warn") return end
		for line in (JSON.encode(self.LastSpec, true) .. "\n"):gmatch("(.-)\n") do console:Log(line, "dim") end
	end
	function self:CopySpec()
		if not self.LastSpec then console:Log("Make something first.", "warn") return end
		if type(setclipboard) == "function" then
			setclipboard(JSON.encode(self.LastSpec, true))
			console:Log("Spec copied. Feed it to Polaris.Spec.Build(...) anywhere.", "ok")
		else
			console:Log("No clipboard here. Use Show spec instead.", "warn")
		end
	end
	tab:CreateButtonRow({ Buttons = {
		{ Name = "Make it", Color = "Success", Callback = function() self:Make() end },
		{ Name = "Show spec", Callback = function() self:ShowSpec() end },
		{ Name = "Copy spec", Callback = function() self:CopySpec() end },
		{ Name = "Close it", Callback = function() if self.LastApp then self.LastApp:Destroy() self.LastApp = nil end end },
	} })

	local ideas = window:CreateTab({ Name = "Ideas" })
	ideas:CreateLabel({ Text = "Tap an idea to build it.", Size = 14 })
	for _, idea in ipairs(IDEAS) do
		ideas:CreateButton({ Name = idea[1], Callback = function() self:Make(idea[2]) end })
	end
	return self
end
