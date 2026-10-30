local H = require("./harness")
local check = H.check
local tasklib = require("@lune/task")
local Polaris, env = H.load()

local function waitUntil(fn, timeout)
	local t = 0
	while not fn() and t < (timeout or 5) do
		tasklib.wait(0.05)
		t += 0.05
	end
	return fn()
end

check("demo provider runs a full session", function()
	local R = Polaris.Research
	local s = R.new({ Provider = "Demo" })
	local events = {}
	for _, e in { "plan", "step", "source", "text", "done" } do
		s:On(e, function() events[e] = (events[e] or 0) + 1 end)
	end
	assert(s:Run("how do tides work", { Depth = "Quick" }))
	assert(waitUntil(function() return s.State.Status == "done" end, 10), "never finished: " .. s.State.Status)
	assert(#s.State.Plan == 3 and s.State.Plan[3].Status == "done")
	assert(#s.State.Sources == 2)
	assert(s.State.Report:find("Demo report"))
	assert(events.plan and events.step and events.source and events.text and events.done == 1)
	assert(s:ExportMarkdown():find("## Sources"))
end)

check("empty question is rejected, cancel works", function()
	local s = Polaris.Research.new({ Provider = "Demo" })
	local ok = s:Run("   ")
	assert(ok == false)
	assert(s:Run("long question"))
	tasklib.wait(0.2)
	assert(s:IsRunning())
	s:Cancel()
	assert(s.State.Status == "cancelled")
	tasklib.wait(0.8)
	assert(s.State.Status == "cancelled", "stale provider must not resurrect the run")
end)

check("custom function provider + errors", function()
	local s = Polaris.Research.new({ Provider = function(ctx)
		ctx:SetPlan({ "a", "b" })
		ctx:Step(1, "done")
		ctx:Source({ Title = "T", Url = "https://x.y/z" })
		ctx:Source({ Title = "T", Url = "https://x.y/z" }) -- dedupe
		ctx:Text("# Hi\n")
		ctx:Text("body [1]")
	end })
	s:Run("q")
	assert(waitUntil(function() return s.State.Status == "done" end))
	assert(#s.State.Sources == 1 and s.State.Report == "# Hi\nbody [1]")
	local bad = Polaris.Research.new({ Provider = function() error("boom") end })
	bad:Run("q")
	assert(waitUntil(function() return bad.State.Status == "error" end))
	assert(bad.State.Error:find("boom"))
	H.expectError(function() Polaris.Research.new({ Provider = "Nope" }) end)
end)

check("perplexity provider: request shape, polling, parsing", function()
	local R = Polaris.Research
	local calls = {}
	Polaris.Util.Http.Handler = function(req)
		table.insert(calls, req)
		if req.Method == "POST" then
			return { Success = true, StatusCode = 200, Body = '{"id":"resp_1","status":"queued"}' }
		end
		local n = #calls
		if n < 4 then
			return { Success = true, StatusCode = 200, Body = '{"id":"resp_1","status":"in_progress"}' }
		end
		return { Success = true, StatusCode = 200, Body = [[{"id":"resp_1","status":"completed","output":[
			{"type":"search_results","results":[{"id":1,"title":"Tides","url":"https://noaa.gov/tides","snippet":"s"}]},
			{"type":"message","content":[{"type":"output_text","text":"Tides come from the moon [web:1].","annotations":[{"type":"url_citation","title":"NOAA","url":"https://noaa.gov/tides"}]}]}]}]] }
	end
	local p = R.Providers.Perplexity({ ApiKey = "pplx-test-key-123", PollEvery = 0.05 })
	local s = R.new({ Provider = p })
	s:Run("why tides", { Depth = "Deep" })
	assert(waitUntil(function() return s.State.Status == "done" end, 10), s.State.Status .. tostring(s.State.Error))
	local post = calls[1]
	assert(post.Url == "https://api.perplexity.ai/v1/agent" and post.Method == "POST")
	assert(post.Headers.Authorization == "Bearer pplx-test-key-123")
	local body = Polaris.Util.JSON.decode(post.Body)
	assert(body.effort == "high" and body.input == "why tides" and body.background == true)
	assert(calls[2].Url == "https://api.perplexity.ai/v1/agent/resp_1" and calls[2].Method == "GET")
	assert(#s.State.Sources == 1, "sources deduped by url: " .. #s.State.Sources)
	assert(s.State.Report:find("moon"))
	Polaris.Util.Http.Handler = nil
end)

check("perplexity provider: missing key, bad key, failed run", function()
	local R = Polaris.Research
	local s = R.new({ Provider = R.Providers.Perplexity({}) })
	s:Run("q")
	assert(waitUntil(function() return s.State.Status == "error" end))
	assert(s.State.Error:find("API key"))
	Polaris.Util.Http.Handler = function() return { Success = false, StatusCode = 401, Body = "{}" } end
	local s2 = R.new({ Provider = R.Providers.Perplexity({ ApiKey = "abcdefghijk" }) })
	s2:Run("q")
	assert(waitUntil(function() return s2.State.Status == "error" end))
	assert(s2.State.Error:find("rejected"))
	Polaris.Util.Http.Handler = function(req)
		if req.Method == "POST" then return { Success = true, StatusCode = 200, Body = '{"id":"x","status":"failed","error":{"message":"nope"}}' } end
	end
	local s3 = R.new({ Provider = R.Providers.Perplexity({ ApiKey = "abcdefghijk" }) })
	s3:Run("q")
	assert(waitUntil(function() return s3.State.Status == "error" end))
	assert(s3.State.Error:find("nope"))
	Polaris.Util.Http.Handler = nil
end)

check("http provider", function()
	local R = Polaris.Research
	Polaris.Util.Http.Handler = function(req)
		assert(req.Url == "https://my.server/research")
		return { Success = true, StatusCode = 200, Body = '{"report":"# R\\nfact [1]","sources":[{"title":"A","url":"https://a.b"}]}' }
	end
	local s = R.new({ Provider = R.Providers.HTTP({ Url = "https://my.server/research" }) })
	s:Run("q")
	assert(waitUntil(function() return s.State.Status == "done" end))
	assert(s.State.Report:find("fact") and #s.State.Sources == 1)
	Polaris.Util.Http.Handler = nil
	H.expectError(function() R.Providers.HTTP({}) end)
end)

check("research widget end to end", function()
	local w = Polaris:CreateWindow({ Name = "R1" })
	local t = w:CreateTab({ Name = "Research" })
	local el = t:CreateResearch({ Provider = "Demo", Depth = "Quick" })
	el._ask.Text = "what is a volcano"
	el._go.Activated:Fire()
	assert(waitUntil(function() return el.Session.State.Status == "done" end, 10))
	assert(el._report.Text:find("Demo report"), el._report.Text)
	assert(el._go.Text == "Research")
	assert(el._actions.Visible == true)
	assert(#el._srcBox:GetChildren() >= 2)
	el:Copy()
	el:SetDepth("Deep")
	assert(el._depth == "Deep")
	-- key row appears for key providers
	local el2 = t:CreateResearch({ Provider = "Perplexity" })
	assert(el2._keyRow.Visible == true)
	el2._ask.Text = "x"
	assert(el2:Start() == false)
	el2._keyBox.Text = "pplx-abcdefghijkl"
	el2._keyBox.FocusLost:Fire(false)
	assert(el2.Session.Provider:HasKey())
	assert(el2._keyBox.Text:gsub("\u{2022}", "") == "", "key must be masked")
	el:Destroy(); el2:Destroy()
	w:Destroy()
end)

H.finish()
