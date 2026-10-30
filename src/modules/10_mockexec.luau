-- mock executor: a look-alike "executor style" window built only from Polaris elements.
-- It is a MOCK.  It does not attach to anything, bypass anything or inject anything.
--   * "Attach" only flips a pretend status light.
--   * "Execute" in the default mock mode only checks the text and prints what it WOULD do.
--   * Live mode (opt-in) runs the text with loadstring, exactly like a Script block does, so it works only
--     where the environment already provides loadstring (an executor you already run, or Studio with it enabled).
-- Untested in a real Roblox client (see GUIDE.md).

local MAX_TABS = 8

local function stamp()
	return os.date and os.date("%H:%M:%S") or "--:--:--"
end

-- opts: Name, Size (Vector2), Live (default false), Run (function(code) used by Live mode instead of loadstring),
--       Scripts (list for the Script Hub tab; defaults to Polaris.HubScripts()), Folder, Theme, Code (first script text)
function Polaris.MockExecutor(opts)
	opts = opts or {}
	local name = opts.Name or "Mock Executor"
	if not Polaris.Themes.MockMoon then
		Polaris:AddTheme("MockMoon", {
			Background = Color3.fromRGB(14, 12, 24), Secondary = Color3.fromRGB(22, 19, 38), Primary = Color3.fromRGB(34, 29, 58),
			Accent = Color3.fromRGB(150, 110, 255), Stroke = Color3.fromRGB(52, 44, 88), Text = Color3.fromRGB(232, 228, 250),
			SubText = Color3.fromRGB(150, 142, 190),
		})
	end
	local window = Polaris:CreateWindow({ Name = name, Theme = opts.Theme or "MockMoon", Size = opts.Size or Vector2.new(680, 520) })
	window:SetTitle(name)

	local self = { Window = window, _live = opts.Live == true, _attached = false, _tabs = {}, _current = 1 }

	-- editor tab ------------------------------------------------------------
	local tab = window:CreateTab({ Name = "Editor" })
	local status = tab:CreateLabel({ Text = '<font color="#ff6b78">\u{25CF}</font> Not attached (mock)', Rich = true, Size = 15 })
	local first = opts.Code or '-- Type a script here, then press Execute.\nprint("hello from the mock")'
	self._tabs[1] = { Name = "Script 1", Code = first }

	local picker = tab:CreateDropdown({ Name = "Script tab", Options = { "Script 1" }, Default = "Script 1", Callback = function(choice)
		for i, t in ipairs(self._tabs) do
			if t.Name == choice and i ~= self._current then
				self._tabs[self._current].Code = self.Editor:Get()
				self._current = i
				self.Editor:Set(t.Code, true)
			end
		end
	end })
	local editor = tab:CreateCodeEditor({ Default = first, Height = 190, Placeholder = "-- your script", Callback = function(text)
		self._tabs[self._current].Code = text
	end })
	local console = tab:CreateConsole({ Name = "Output", Height = 110 })
	self.Editor, self.Console, self.Status, self.Picker = editor, console, status, picker

	function self:Log(text, kind)
		console:Log(("[%s] %s"):format(stamp(), tostring(text)), kind)
	end

	local function refreshTabs()
		local names = {}
		for _, t in ipairs(self._tabs) do
			names[#names + 1] = t.Name
		end
		picker:Refresh(names, true)
		picker:Set(self._tabs[self._current].Name, true)
	end

	local function setStatus(attached, text)
		status:SetText(('<font color="%s">\u{25CF}</font> %s'):format(attached and "#6be39a" or "#ff6b78", text))
	end

	function self:IsAttached() return self._attached end
	function self:IsLive() return self._live end
	function self:SetLive(on)
		self._live = on == true
		self:Log(self._live and "Live mode on: Execute will run the text with loadstring." or "Mock mode on: Execute only checks the text.", self._live and "warn" or "info")
	end
	function self:SetCode(text)
		self._tabs[self._current].Code = tostring(text)
		editor:Set(text, true)
	end
	function self:GetCode()
		self._tabs[self._current].Code = editor:Get()
		return self._tabs[self._current].Code
	end

	function self:Attach()
		if self._attached then
			return self:Detach()
		end
		if self._attaching then
			return
		end
		self._attaching = true
		setStatus(false, "Attaching ... (pretend)")
		self:Log("Attach pressed. This is a mock: nothing is being injected.", "dim")
		task.delay(0.8, function()
			if window._destroyed then return end
			self._attaching, self._attached = false, true
			setStatus(true, "Attached (mock)")
			self:Log("Status light is green. Execute is now allowed.", "ok")
		end)
	end

	function self:Detach()
		self._attached = false
		setStatus(false, "Not attached (mock)")
		self:Log("Detached.", "dim")
	end

	function self:Execute()
		if not self._attached then
			self:Log("Press Attach first (the mock wants the green light).", "error")
			return false
		end
		local code = self:GetCode()
		if code:match("^%s*$") then
			self:Log("Nothing to run.", "warn")
			return false
		end
		local _, breaks = code:gsub("\n", "\n")
		local lines = breaks + 1
		if not self._live then
			if type(loadstring) == "function" then
				local fn, err = loadstring(code)
				if not fn then
					self:Log("Mock check found a mistake: " .. tostring(err), "error")
					return false
				end
				self:Log(("Mock: %d lines, %d characters, no mistakes found. Not run (mock mode)."):format(lines, #code), "ok")
			else
				self:Log(("Mock: %d lines, %d characters. Not run (mock mode)."):format(lines, #code), "ok")
			end
			return true
		end
		-- live mode
		if type(opts.Run) == "function" then
			local ok, err = pcall(opts.Run, code)
			self:Log(ok and "Ran with your Run handler." or ("Error: " .. tostring(err)), ok and "ok" or "error")
			return ok
		end
		if type(loadstring) ~= "function" then
			self:Log("Live mode needs loadstring, which this place does not have.", "error")
			return false
		end
		local fn, err = loadstring(code)
		if not fn then
			self:Log("Mistake in the script: " .. tostring(err), "error")
			return false
		end
		local ok, runErr = pcall(fn)
		self:Log(ok and "Ran." or ("Error while running: " .. tostring(runErr)), ok and "ok" or "error")
		return ok
	end

	function self:NewTab(title, code)
		if #self._tabs >= MAX_TABS then
			self:Log(("Up to %d script tabs."):format(MAX_TABS), "warn")
			return nil
		end
		self._tabs[self._current].Code = editor:Get()
		local n = #self._tabs + 1
		self._tabs[n] = { Name = title or ("Script " .. n), Code = code or "" }
		self._current = n
		refreshTabs()
		editor:Set(self._tabs[n].Code, true)
		return n
	end

	function self:CloseTab()
		if #self._tabs <= 1 then
			self:SetCode("")
			return
		end
		table.remove(self._tabs, self._current)
		self._current = math.max(1, self._current - 1)
		refreshTabs()
		editor:Set(self._tabs[self._current].Code, true)
	end

	tab:CreateButtonRow({ Buttons = {
		{ Name = "Attach", Callback = function() self:Attach() end },
		{ Name = "Execute", Callback = function() self:Execute() end, Color = "Success" },
		{ Name = "Clear", Callback = function() editor:Clear(); self._tabs[self._current].Code = "" end },
		{ Name = "Clear output", Callback = function() console:Clear() end },
	} })
	tab:CreateButtonRow({ Buttons = {
		{ Name = "New tab", Callback = function() self:NewTab() end },
		{ Name = "Close tab", Callback = function() self:CloseTab() end },
	} })
	self:Log("Mock executor ready. Nothing here injects into anything.", "dim")

	-- script hub tab --------------------------------------------------------
	local hubTab = window:CreateTab({ Name = "Script Hub" })
	hubTab:CreateLabel({ Text = "Ready-made harmless scripts. Tap one to run it, or copy ideas into the editor.", Size = 13, Color = "SubText" })
	self.Library = hubTab:CreateScriptLibrary({ Scripts = opts.Scripts or Polaris.HubScripts(), Folder = opts.Folder or "mockexecutor" })

	-- settings tab ----------------------------------------------------------
	local setTab = window:CreateTab({ Name = "Settings" })
	setTab:CreateToggle({ Name = "Live mode (run the text with loadstring)", Default = self._live, Callback = function(on) self:SetLive(on) end })
	setTab:CreateLabel({ Text = "Off by default. In mock mode the Execute button only checks the text and says what it would do. Live mode needs loadstring from an executor you already run; this window never attaches to anything.", Size = 13, Color = "SubText" })
	setTab:CreateButton({ Name = "Create your own script hub (blocks)", Callback = function() Polaris.MakeHub() end })

	return self
end
