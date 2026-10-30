-- research: a "deep research" engine (plan -> steps -> sources -> cited report)
-- with pluggable providers, plus the Research Panel widget.
--
--   local session = Polaris.Research.new({ Provider = "Demo" })
--   session:On("done", function(state) print(state.Report) end)
--   session:Run("How do ocean tides work?", { Depth = "Standard" })

local Create, Element, Tab = I.Create, I.Element, I.Tab
local Kit, Util = Polaris.Kit, Polaris.Util
local JSON, Markdown, Http = Util.JSON, Util.Markdown, Util.Http

local Research = {}
Research.__index = Research
Polaris.Research = Research

Research.Depths = {
	Quick = { Name = "Quick", Effort = "fast", Timeout = 120 },
	Standard = { Name = "Standard", Effort = "medium", Timeout = 420 },
	Deep = { Name = "Deep", Effort = "high", Timeout = 900 },
	Max = { Name = "Max", Effort = "xhigh", Timeout = 1800 },
}
Research.DepthOrder = { "Quick", "Standard", "Deep" }

Research.Providers = {}

----------------------------------------------------------------
-- Session
----------------------------------------------------------------

local function blankState()
	return { Status = "idle", Query = "", Depth = "Standard", Plan = {}, Sources = {}, Report = "", Error = nil, Log = {} }
end

function Research.resolve(spec)
	if spec == nil then
		spec = "Demo"
	end
	if type(spec) == "string" then
		local make = Research.Providers[spec]
		assert(make, ("[Polaris] Research: unknown provider '%s'. Built in: Demo, Perplexity, HTTP"):format(spec))
		return make({})
	elseif type(spec) == "function" then
		return { Name = "Custom", Run = function(_, ctx)
			return spec(ctx)
		end }
	elseif type(spec) == "table" and type(spec.Run) == "function" then
		return spec
	end
	error("[Polaris] Research: Provider must be a name, a function(ctx), or a table with a Run method", 0)
end

function Research.new(opts)
	opts = opts or {}
	local self = setmetatable({}, Research)
	self.Provider = Research.resolve(opts.Provider)
	self.State = blankState()
	self.Depth = opts.Depth or "Standard"
	self._events = Util.Events()
	self._token = 0
	return self
end

function Research:On(name, fn)
	return self._events:On(name, fn)
end

function Research:SetProvider(spec)
	self.Provider = Research.resolve(spec)
	self._events:Emit("provider", self.Provider)
end

function Research:IsRunning()
	return self.State.Status == "running"
end

function Research:Cancel()
	if self:IsRunning() then
		self._token += 1
		self.State.Status = "cancelled"
		for _, step in ipairs(self.State.Plan) do
			if step.Status == "running" then
				step.Status = "pending"
			end
		end
		self._events:Emit("status", self.State)
		self._events:Emit("cancelled", self.State)
	end
end

function Research:Reset()
	self._token += 1
	self.State = blankState()
	self._events:Emit("reset", self.State)
end

local function makeContext(self, token, query, depthName)
	local state = self.State
	local ev = self._events
	local ctx = { Query = query, Depth = depthName, DepthInfo = Research.Depths[depthName] or Research.Depths.Standard }
	local function live()
		return self._token == token
	end
	function ctx:IsCancelled()
		return not live()
	end
	function ctx:Wait(seconds)
		local t = 0
		while t < seconds do
			if not live() then
				return false
			end
			local dt = math.min(0.1, seconds - t)
			task.wait(dt)
			t += dt
		end
		return live()
	end
	function ctx:SetPlan(titles)
		if not live() then return end
		state.Plan = {}
		for _, t in ipairs(titles) do
			table.insert(state.Plan, { Title = t, Status = "pending" })
		end
		ev:Emit("plan", state.Plan)
	end
	function ctx:AddStep(title)
		if not live() then return end
		table.insert(state.Plan, { Title = title, Status = "pending" })
		ev:Emit("plan", state.Plan)
		return #state.Plan
	end
	function ctx:Step(i, status, note)
		if not live() or not state.Plan[i] then return end
		state.Plan[i].Status = status or "running"
		if note ~= nil then
			state.Plan[i].Note = note
		end
		ev:Emit("step", i, state.Plan[i])
	end
	function ctx:Source(src)
		if not live() or type(src) ~= "table" then return end
		local url = src.Url or src.url
		for i, s in ipairs(state.Sources) do
			if url and s.Url == url then
				return i
			end
		end
		table.insert(state.Sources, {
			Title = tostring(src.Title or src.title or Util.hostOf(url or "") or "Source"),
			Url = url,
			Snippet = src.Snippet or src.snippet,
			Host = Util.hostOf(url or ""),
		})
		ev:Emit("source", state.Sources[#state.Sources], #state.Sources)
		return #state.Sources
	end
	function ctx:Text(chunk)
		if not live() then return end
		state.Report ..= tostring(chunk)
		ev:Emit("text", state.Report, tostring(chunk))
	end
	function ctx:SetText(full)
		if not live() then return end
		state.Report = tostring(full)
		ev:Emit("text", state.Report, state.Report)
	end
	function ctx:Log(msg)
		if not live() then return end
		table.insert(state.Log, tostring(msg))
		ev:Emit("log", tostring(msg))
	end
	function ctx:Done()
		if not live() or state.Status ~= "running" then return end
		for _, step in ipairs(state.Plan) do
			if step.Status ~= "failed" then
				step.Status = "done"
			end
		end
		state.Status = "done"
		ev:Emit("plan", state.Plan)
		ev:Emit("status", state)
		ev:Emit("done", state)
	end
	function ctx:Fail(message)
		if not live() or state.Status ~= "running" then return end
		state.Status = "error"
		state.Error = tostring(message)
		for _, step in ipairs(state.Plan) do
			if step.Status == "running" then
				step.Status = "failed"
			end
		end
		ev:Emit("plan", state.Plan)
		ev:Emit("status", state)
		ev:Emit("error", state.Error)
	end
	return ctx
end

function Research:Run(query, opts)
	opts = opts or {}
	query = tostring(query or ""):match("^%s*(.-)%s*$")
	if query == "" then
		self._events:Emit("error", "Type a question first.")
		return false, "Type a question first."
	end
	if self:IsRunning() then
		self:Cancel()
	end
	local depthName = opts.Depth or self.Depth
	if not Research.Depths[depthName] then
		depthName = "Standard"
	end
	self._token += 1
	local token = self._token
	self.State = blankState()
	self.State.Status = "running"
	self.State.Query = query
	self.State.Depth = depthName
	self.State.StartedAt = os.clock()
	self._events:Emit("reset", self.State)
	self._events:Emit("status", self.State)
	local ctx = makeContext(self, token, query, depthName)
	task.spawn(function()
		local ok, err = pcall(function()
			return self.Provider:Run(ctx)
		end)
		if not ok then
			ctx:Fail("The research provider crashed: " .. tostring(err))
		elseif self._token == token and self.State.Status == "running" and not self.Provider.Async then
			ctx:Done()
		end
	end)
	return true
end

function Research:GetReport()
	return self.State.Report
end

-- Report + numbered source list as plain Markdown (for copy / save)
function Research:ExportMarkdown()
	local s = self.State
	local out = { "# " .. (s.Query ~= "" and s.Query or "Research"), "", s.Report }
	if #s.Sources > 0 then
		table.insert(out, "")
		table.insert(out, "## Sources")
		for i, src in ipairs(s.Sources) do
			table.insert(out, ("%d. %s%s"):format(i, src.Title, src.Url and (" - " .. src.Url) or ""))
		end
	end
	return table.concat(out, "\n")
end

----------------------------------------------------------------
-- Providers
----------------------------------------------------------------

-- Demo: runs offline, no key, no internet.  Output is clearly marked as a demo.
Research.Providers.Demo = function(opts)
	opts = opts or {}
	local speed = opts.Speed or 1
	return {
		Name = "Demo",
		Run = function(_, ctx)
			local steps = {
				"Understand the question",
				"Plan the search",
				"Find sources",
				"Read and compare sources",
				"Check the facts",
				"Write the report",
			}
			if ctx.Depth == "Quick" then
				steps = { "Understand the question", "Find sources", "Write the answer" }
			end
			ctx:SetPlan(steps)
			for i, title in ipairs(steps) do
				ctx:Step(i, "running")
				if not ctx:Wait(0.5 / speed) then return end
				if title == "Find sources" then
					for n = 1, (ctx.Depth == "Quick" and 2 or (ctx.Depth == "Deep" and 6 or 4)) do
						ctx:Source({ Title = "Demo source " .. n .. " (not a real page)", Url = "https://example.com/demo-source-" .. n, Snippet = "Placeholder text." })
						if not ctx:Wait(0.2 / speed) then return end
					end
				end
				ctx:Step(i, "done")
			end
			local words = {}
			for word in ctx.Query:gmatch("%S+") do
				table.insert(words, word)
			end
			ctx:SetText(table.concat({
				"# Demo report: " .. ctx.Query,
				"",
				"> This is **demo output**. Nothing was searched and nothing below is a real fact about your question.",
				"",
				"## What a real report looks like",
				"- A short answer first, then the evidence [1].",
				"- Every claim points at a numbered source [2][3].",
				"- Disagreements between sources are called out instead of hidden.",
				"",
				"## How to get real answers",
				"1. Pick a provider: `Provider = \"Perplexity\"` (needs your own API key) or `Provider = \"HTTP\"` (your own server).",
				"2. Or write one: `Provider = function(ctx) ... end` and call `ctx:Text(...)`.",
				"3. See GUIDE.md, chapter \"Deep research UI\".",
				"",
				("Depth used: **%s**. Question length: %d words."):format(ctx.Depth, #words),
			}, "\n"))
		end,
	}
end

-- Perplexity Agent API (https://docs.perplexity.ai).  You must supply your own API key.
-- Needs an HTTP-capable environment (an executor's request(), or HttpService on a server).
Research.Providers.Perplexity = function(opts)
	opts = opts or {}
	local provider = { Name = "Perplexity", NeedsKey = true, Async = true }
	local key = opts.ApiKey
	function provider:SetKey(k)
		key = k
	end
	function provider:HasKey()
		return type(key) == "string" and #key > 8
	end
	local base = opts.BaseUrl or "https://api.perplexity.ai"

	local function headers()
		return { ["Authorization"] = "Bearer " .. tostring(key), ["Content-Type"] = "application/json" }
	end

	local function explain(res)
		local status = res.StatusCode
		if status == 401 or status == 403 then
			return "Perplexity rejected the API key. Check that it is correct and has credit."
		elseif status == 429 then
			return "Too many requests or out of quota (HTTP 429). Wait a bit and try again."
		elseif status == 0 then
			return "Could not reach Perplexity: " .. tostring(res.Error) .. ". This place may block HTTP requests."
		end
		return "Perplexity returned an error: " .. tostring(res.Error) .. " " .. tostring(res.Body):sub(1, 160)
	end

	-- Pull text + sources out of an Agent API response (tolerant of shape differences)
	function provider.parse(resp)
		local text, sources = {}, {}
		if type(resp.output) == "table" then
			for _, item in ipairs(resp.output) do
				if item.type == "message" then
					for _, part in ipairs(item.content or {}) do
						if part.type == "output_text" and part.text then
							table.insert(text, part.text)
							for _, a in ipairs(part.annotations or {}) do
								if a.url then
									table.insert(sources, { Title = a.title, Url = a.url })
								end
							end
						end
					end
				elseif item.type == "search_results" then
					for _, r in ipairs(item.results or {}) do
						table.insert(sources, { Title = r.title, Url = r.url, Snippet = r.snippet })
					end
				end
			end
		end
		if #text == 0 and type(resp.output_text) == "string" then
			table.insert(text, resp.output_text)
		end
		for _, c in ipairs(resp.citations or {}) do
			if type(c) == "string" then
				table.insert(sources, { Url = c })
			elseif type(c) == "table" then
				table.insert(sources, { Title = c.title, Url = c.url })
			end
		end
		return table.concat(text, "\n"), sources
	end

	function provider:Run(ctx)
		if not self:HasKey() then
			return ctx:Fail("Paste your Perplexity API key first (it is only kept in memory).")
		end
		if not Http.Available() then
			return ctx:Fail("This place cannot make HTTP requests, so it cannot reach Perplexity. Use an executor with request() or a server script with HttpService enabled.")
		end
		ctx:SetPlan({ "Send the question", "Research (the agent searches and reads)", "Collect the sources", "Show the report" })
		ctx:Step(1, "running")
		local body = {
			effort = opts.Effort or ctx.DepthInfo.Effort,
			input = ctx.Query,
			background = true,
		}
		if opts.Instructions then
			body.instructions = opts.Instructions
		end
		local res = Http.Request({ Url = base .. "/v1/agent", Method = "POST", Headers = headers(), Body = body })
		if ctx:IsCancelled() then return end
		if not res.Success then
			return ctx:Fail(explain(res))
		end
		local resp = JSON.decode(res.Body)
		if type(resp) ~= "table" then
			return ctx:Fail("Perplexity sent back something that is not JSON.")
		end
		ctx:Step(1, "done")
		ctx:Step(2, "running")
		local started = os.clock()
		local timeout = opts.Timeout or ctx.DepthInfo.Timeout
		local terminal = { completed = true, failed = true, cancelled = true, incomplete = true }
		while resp.status and not terminal[resp.status] do
			if os.clock() - started > timeout then
				return ctx:Fail("Timed out after " .. timeout .. " seconds. Try a lighter depth.")
			end
			if not ctx:Wait(opts.PollEvery or 3) then return end
			ctx:Step(2, "running", ("%s, %ds"):format(tostring(resp.status), math.floor(os.clock() - started)))
			local poll = Http.Request({ Url = base .. "/v1/agent/" .. tostring(resp.id), Method = "GET", Headers = headers() })
			if ctx:IsCancelled() then return end
			if not poll.Success then
				return ctx:Fail(explain(poll))
			end
			resp = JSON.decode(poll.Body) or resp
		end
		if resp.status == "failed" then
			local msg = type(resp.error) == "table" and (resp.error.message or JSON.encode(resp.error)) or tostring(resp.error)
			return ctx:Fail("The research run failed: " .. msg)
		elseif resp.status == "cancelled" then
			return ctx:Fail("The research run was cancelled.")
		end
		ctx:Step(2, "done")
		ctx:Step(3, "running")
		local text, sources = provider.parse(resp)
		for _, s in ipairs(sources) do
			ctx:Source(s)
		end
		ctx:Step(3, "done")
		ctx:Step(4, "running")
		if text == "" then
			return ctx:Fail("The run finished but returned no text.")
		end
		if resp.status == "incomplete" then
			text ..= "\n\n> The run stopped before finishing, so this report may be incomplete."
		end
		ctx:SetText(text)
		ctx:Step(4, "done")
		ctx:Done()
	end
	return provider
end

-- Generic HTTP provider: POST { query, depth } to your own endpoint.
-- Expected JSON reply: { "report": "markdown", "sources": [ { "title": "", "url": "" } ] }
-- Keeping the real API key on your own server is the safest setup.
Research.Providers.HTTP = function(opts)
	opts = opts or {}
	assert(type(opts.Url) == "string", "[Polaris] Research HTTP provider needs Url = \"https://...\"")
	return {
		Name = "HTTP",
		Async = true,
		Run = function(_, ctx)
			if not Http.Available() then
				return ctx:Fail("This place cannot make HTTP requests.")
			end
			ctx:SetPlan({ "Ask the server", "Show the report" })
			ctx:Step(1, "running")
			local payload = opts.BuildBody and opts.BuildBody(ctx) or { query = ctx.Query, depth = ctx.Depth, effort = ctx.DepthInfo.Effort }
			local res = Http.Request({ Url = opts.Url, Method = opts.Method or "POST", Headers = opts.Headers, Body = payload })
			if ctx:IsCancelled() then return end
			if not res.Success then
				return ctx:Fail("The server answered with an error: " .. tostring(res.Error))
			end
			local text, sources
			if opts.Parse then
				text, sources = opts.Parse(res.Body)
			else
				local data = JSON.decode(res.Body)
				if type(data) ~= "table" then
					text, sources = res.Body, {}
				else
					text = data.report or data.answer or data.text or data.output_text or ""
					sources = data.sources or data.citations or {}
				end
			end
			for _, s in ipairs(sources or {}) do
				ctx:Source(type(s) == "string" and { Url = s } or s)
			end
			ctx:Step(1, "done")
			ctx:Step(2, "running")
			ctx:SetText(text or "")
			ctx:Step(2, "done")
			ctx:Done()
		end,
	}
end

----------------------------------------------------------------
-- Widget: Tab:CreateResearch
----------------------------------------------------------------

local ResEl = setmetatable({}, { __index = Element })
ResEl.__index = ResEl

local STEP_GLYPH = { pending = "\u{25CB}", running = "\u{25D4}", done = "\u{2713}", failed = "\u{2715}" }
local STEP_COLOR = { pending = "SubText", running = "Accent", done = "Success", failed = "Danger" }

function ResEl:_create(window, tab, config)
	local self = Element._new(window, tab, config, "Research")
	setmetatable(self, ResEl)

	local session = config.Session or Research.new({ Provider = config.Provider, Depth = config.Depth })
	self.Session = session
	self._depths = config.Depths or Research.DepthOrder
	self._depth = config.Depth or "Standard"
	session.Depth = self._depth

	local height = type(config.Height) == "number" and config.Height or 380
	local row = Create("Frame", { Name = "Research", Size = UDim2.new(1, 0, 0, height), BackgroundTransparency = 1, Parent = tab._content })
	self._container = row
	local holder = Create("Frame", { Name = "Holder", Size = UDim2.new(1, -16, 1, 0), Position = UDim2.new(0, 8, 0, 0), BackgroundTransparency = 1, Parent = row })

	-- ask row
	local ask = Kit.input(holder, { Placeholder = config.Placeholder or "Ask anything...", Size = UDim2.new(1, -104, 0, 34), TextSize = 15, Name = "Question" })
	self._ask = ask
	self._go = Kit.button(holder, "Research", { Color = "Accent", Size = UDim2.new(0, 98, 0, 34), Position = UDim2.new(1, -98, 0, 0), TextSize = 14 })

	-- depth + status row
	local meta = Create("Frame", { Name = "Meta", Size = UDim2.new(1, 0, 0, 26), Position = UDim2.new(0, 0, 0, 40), BackgroundTransparency = 1, Parent = holder })
	Create("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = meta })
	self._depthButtons = {}
	for i, d in ipairs(self._depths) do
		local b = Kit.button(meta, d, { Color = "Secondary", TextColor = "SubText", Size = UDim2.new(0, #d * 8 + 24, 0, 24), TextSize = 12, Radius = 12 })
		b.LayoutOrder = i
		b.Activated:Connect(function()
			self:SetDepth(d)
		end)
		self._depthButtons[d] = b
	end
	self._statusLbl = Kit.label(meta, "", { Size = 12, Color = "SubText", Width = 0, WidthOffset = 260, Height = 24, Truncate = true })
	self._statusLbl.LayoutOrder = 99

	-- key row (only for providers that need a key)
	local keyTop = 70
	self._keyRow = Create("Frame", { Name = "KeyRow", Size = UDim2.new(1, 0, 0, 32), Position = UDim2.new(0, 0, 0, keyTop), BackgroundTransparency = 1, Visible = false, Parent = holder })
	self._keyBox = Kit.input(self._keyRow, { Placeholder = "Paste your API key (kept in memory only)", Size = UDim2.new(1, 0, 0, 30), TextSize = 13, Name = "Key" })

	-- body
	self._body, self._bodyLayout = Kit.scroll(holder, { Padding = 8, Size = UDim2.new(1, 0, 1, -72), Position = UDim2.new(0, 0, 0, 70), Name = "Body" })
	self._planBox = Create("Frame", { Name = "Plan", Size = UDim2.new(1, -4, 0, 0), BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1, Parent = self._body })
	Create("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self._planBox })
	self._report = Kit.label(self._body, "", { Size = config.TextSize or 15, Wrap = true, Rich = true, Auto = true, VAlign = "Top", Height = 10, Width = 1, WidthOffset = -4, Name = "Report" })
	self._report.LayoutOrder = 2
	self._srcBox = Create("Frame", { Name = "Sources", Size = UDim2.new(1, -4, 0, 0), BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = self._body })
	Create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = self._srcBox })
	self._actions = Create("Frame", { Name = "Actions", Size = UDim2.new(1, -4, 0, 32), BackgroundTransparency = 1, LayoutOrder = 4, Visible = false, Parent = self._body })

	local copy = Kit.button(self._actions, "Copy report", { Color = "Secondary", TextColor = "Text", Size = UDim2.new(0.5, -4, 0, 30), TextSize = 13 })
	local save = Kit.button(self._actions, "Save to file", { Color = "Secondary", TextColor = "Text", Size = UDim2.new(0.5, -4, 0, 30), Position = UDim2.new(0.5, 4, 0, 0), TextSize = 13 })
	self:_track(copy.Activated:Connect(function()
		self:Copy()
	end))
	self:_track(save.Activated:Connect(function()
		self:Save()
	end))

	-- wiring
	self:_track(self._go.Activated:Connect(function()
		if session:IsRunning() then
			session:Cancel()
		else
			self:Start()
		end
	end))
	self:_track(ask.FocusLost:Connect(function(enter)
		if enter and not session:IsRunning() then
			self:Start()
		end
	end))
	self:_track(self._keyBox.FocusLost:Connect(function()
		local text = self._keyBox.Text
		if text ~= "" and text:gsub("\u{2022}", "") ~= "" then
			if session.Provider.SetKey then
				session.Provider:SetKey(text)
			end
			self._keyBox.Text = string.rep("\u{2022}", math.min(#text, 24))
		end
	end))
	local subs = {
		session:On("reset", function() self:_renderAll() end),
		session:On("plan", function() self:_renderPlan() end),
		session:On("step", function() self:_renderPlan() end),
		session:On("source", function() self:_renderSources() end),
		session:On("text", function(full) self:_renderReport(full) end),
		session:On("status", function() self:_renderStatus() end),
		session:On("error", function(msg)
			if session.State.Status ~= "error" then
				Polaris:Notify({ Title = "Research", Content = tostring(msg), Type = "warning", Duration = 4 })
			end
			self:_renderStatus()
		end),
		session:On("provider", function() self:_renderStatus() end),
	}
	self._subs = subs

	if config.ApiKey and session.Provider.SetKey then
		session.Provider:SetKey(config.ApiKey)
	end
	if config.Height == nil or config.Height == "Fill" then
		Polaris._bindFill(self, 260, 8)
	end
	self._value = ""
	self:SetDepth(self._depth)
	self:_renderAll()
	return self
end

function ResEl:SetDepth(d)
	if not Research.Depths[d] then
		return
	end
	self._depth = d
	self.Session.Depth = d
	for name, b in pairs(self._depthButtons) do
		Kit.paint(b, "BackgroundColor3", name == d and "Accent" or "Secondary")
		if name == d then
			b.TextColor3 = Color3.new(1, 1, 1)
		else
			Kit.paint(b, "TextColor3", "SubText")
		end
	end
end

function ResEl:Start(query)
	if query then
		self._ask.Text = query
	end
	local prov = self.Session.Provider
	if prov.NeedsKey and prov.HasKey and not prov:HasKey() then
		self._keyRow.Visible = true
		self:_layoutBody()
		Polaris:Notify({ Title = "API key needed", Content = "Paste your key in the box, then press Research again.", Type = "warning", Duration = 4 })
		return false
	end
	return self.Session:Run(self._ask.Text, { Depth = self._depth })
end

function ResEl:_layoutBody()
	local keyShown = self._keyRow.Visible
	local top = keyShown and 106 or 70
	self._body.Position = UDim2.new(0, 0, 0, top)
	self._body.Size = UDim2.new(1, 0, 1, -(top + 2))
end

function ResEl:_renderStatus()
	if self._destroyed then return end
	local s = self.Session.State
	local prov = self.Session.Provider
	local label = ({
		idle = "Ready", running = "Researching...", done = "Done", error = "Problem", cancelled = "Stopped",
	})[s.Status] or s.Status
	local text = prov.Name .. "  \u{2022}  " .. label
	if s.Status == "error" and s.Error then
		text = s.Error
	end
	self._statusLbl.Text = text
	Kit.paint(self._statusLbl, "TextColor3", s.Status == "error" and "Danger" or (s.Status == "done" and "Success" or "SubText"))
	self._go.Text = s.Status == "running" and "Stop" or "Research"
	Kit.paint(self._go, "BackgroundColor3", s.Status == "running" and "Danger" or "Accent")
	self._keyRow.Visible = (prov.NeedsKey == true) and not (prov.HasKey and prov:HasKey())
	self:_layoutBody()
	self._actions.Visible = s.Status == "done" and s.Report ~= ""
end

function ResEl:_renderPlan()
	if self._destroyed then return end
	Kit.clear(self._planBox)
	for i, step in ipairs(self.Session.State.Plan) do
		local line = Kit.label(self._planBox, ("%s  %s%s"):format(STEP_GLYPH[step.Status] or "?", step.Title, step.Note and ("  (" .. step.Note .. ")") or ""), {
			Size = 13, Color = STEP_COLOR[step.Status] or "SubText", Height = 18, Name = "Step",
		})
		line.LayoutOrder = i
	end
end

function ResEl:_renderReport(full)
	if self._destroyed then return end
	local theme = Kit.theme()
	self._report.Text = Markdown.toRichText(full or "", { Accent = Util.hex(theme.Accent), BaseSize = self._config.TextSize or 15 })
end

function ResEl:_renderSources()
	if self._destroyed then return end
	Kit.clear(self._srcBox)
	local sources = self.Session.State.Sources
	if #sources == 0 then
		return
	end
	local head = Kit.label(self._srcBox, "Sources (" .. #sources .. ")", { Size = 14, Bold = true, Height = 22, Name = "Head" })
	head.LayoutOrder = 0
	for i, src in ipairs(sources) do
		local b = Kit.button(self._srcBox, ("[%d]  %s%s"):format(i, src.Title, src.Host ~= "" and ("  \u{2022}  " .. src.Host) or ""), {
			Color = "Secondary", TextColor = "Text", Size = UDim2.new(1, 0, 0, 30), TextSize = 12, Bold = false,
		})
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.TextTruncate = Enum.TextTruncate.AtEnd
		Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), Parent = b })
		b.LayoutOrder = i
		b.Activated:Connect(function()
			if src.Url and I.copyText(src.Url) then
				Polaris:Notify({ Title = "Link copied", Content = src.Url, Type = "success", Duration = 2.5 })
			else
				Polaris:Notify({ Title = src.Title, Content = tostring(src.Url or "No link"), Duration = 5 })
			end
		end)
	end
end

function ResEl:_renderAll()
	self:_renderPlan()
	self:_renderReport(self.Session.State.Report)
	self:_renderSources()
	self:_renderStatus()
end

function ResEl:Copy()
	local md = self.Session:ExportMarkdown()
	if I.copyText(md) then
		Polaris:Notify({ Title = "Copied", Content = "The report is on your clipboard.", Type = "success", Duration = 2.5 })
	else
		Polaris:Notify({ Title = "Cannot copy here", Content = "This place has no clipboard. Use Save to file, or print the report from your script.", Type = "warning", Duration = 4 })
	end
end

function ResEl:Save()
	local name = "research_" .. I.slugify(self.Session.State.Query):sub(1, 30) .. ".md"
	if I.saveFile and I.saveFile(name, self.Session:ExportMarkdown()) then
		Polaris:Notify({ Title = "Saved", Content = "Saved as " .. name .. " in your executor's workspace folder.", Type = "success", Duration = 4 })
	else
		Polaris:Notify({ Title = "Cannot save here", Content = "This place cannot write files. Use Copy report instead.", Type = "warning", Duration = 4 })
	end
end

function ResEl:_setValue(v)
	if type(v) == "string" then
		self._ask.Text = v
	end
end

function ResEl:Destroy()
	if self._subs then
		for _, s in ipairs(self._subs) do
			s.Disconnect()
		end
	end
	if self.Session and self.Session:IsRunning() then
		self.Session:Cancel()
	end
	Element.Destroy(self)
end

function Tab:CreateResearch(config)
	if type(config) == "string" then
		config = { Provider = config }
	end
	return ResEl:_create(self._window, self, config or {})
end
Polaris.ElementTypes.Research = function(t, c) return t:CreateResearch(c) end
