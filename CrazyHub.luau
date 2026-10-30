--[[
	Crazy Hub - a big, silly script hub built entirely with Polaris 3
	-----------------------------------------------------------------
	Paste into your executor, or run it as a LocalScript in Studio:

		loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/CrazyHub.luau"))()

	Everything in here only changes YOUR OWN screen, camera and lighting, or plays small games.
	It never touches other players or the game's data. Press "Calm down" (Settings tab) to undo it all.
	RightControl shows or hides the window.

	Flashing warning: the Party tab fades colours instead of flashing, and Gentle mode (on by default)
	keeps every effect slow. Turn Gentle mode off only if you are sure you are comfortable with it.
]]

local Polaris = loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"))()

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local camera = workspace.CurrentCamera

----------------------------------------------------------------
-- Small toolbox: loops, overlays, undo list, session log
----------------------------------------------------------------
local gentle = true -- slow and soft effects
local loops = {} -- name -> token, a loop stops when its token is removed or replaced
local undo = {} -- name -> function that puts one thing back
local toggles = {} -- every on/off switch, so "Calm down" can flip them all off
local guis = {} -- name -> ScreenGui we made
local logTable -- filled in when the Stats tab is built
local fpsNow = 60
local onClosed -- set below: puts the world back when the window is closed
local Window -- set below; loops stop by themselves when the window is destroyed

local function rand(a, b)
	return a + math.random() * (b - a)
end

local function guiParent()
	local ok, parent = pcall(function()
		if gethui then
			return gethui()
		end
		return game:GetService("CoreGui")
	end)
	if ok and parent then
		return parent
	end
	return game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
end

local function startLoop(name, interval, step)
	local token = {}
	loops[name] = token
	task.spawn(function()
		local tick = 0
		while loops[name] == token do
			if Window and Window._destroyed then
				loops[name] = nil
				if onClosed then
					local cleanup = onClosed
					onClosed = nil
					cleanup()
				end
				return
			end
			local ok, err = pcall(step, tick)
			if not ok then
				warn("[CrazyHub] " .. name .. " stopped: " .. tostring(err))
				if loops[name] == token then
					loops[name] = nil
				end
				return
			end
			tick += 1
			task.wait(interval)
		end
	end)
end

local function stopLoop(name)
	loops[name] = nil
end

local function note(title, text, kind)
	Polaris:Notify({ Title = title, Content = text, Type = kind or "info", Duration = 3 })
end

local function log(what)
	if logTable then
		logTable:AddRow({ os.date("%H:%M:%S"), what })
	end
end

local function overlay(name)
	if guis[name] then
		return guis[name]
	end
	local g = Instance.new("ScreenGui")
	g.Name = "CrazyHub" .. name
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 40
	g.Parent = guiParent()
	guis[name] = g
	return g
end

local function removeOverlay(name)
	if guis[name] then
		pcall(function()
			guis[name]:Destroy()
		end)
		guis[name] = nil
	end
end

local function frame(parent, props)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in props do
		f[k] = v
	end
	f.Parent = parent
	return f
end

-- remember how the world looked so everything can be put back
local original = {}
for _, key in { "Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "FogEnd", "FogStart", "FogColor", "ColorShift_Top" } do
	pcall(function()
		original[key] = Lighting[key]
	end)
end
local originalFov = (camera and camera.FieldOfView) or 70

local function restoreLighting()
	for key, value in original do
		pcall(function()
			Lighting[key] = value
		end)
	end
end

local effects = {}
local function effect(name, class, props)
	local fx = effects[name]
	if not fx then
		fx = Instance.new(class)
		fx.Name = "CrazyHub" .. name
		fx.Parent = Lighting
		effects[name] = fx
	end
	for k, v in props do
		pcall(function()
			fx[k] = v
		end)
	end
	return fx
end

local function removeEffects()
	for name, fx in effects do
		pcall(function()
			fx:Destroy()
		end)
		effects[name] = nil
	end
end

local function fade(target, goal, seconds)
	pcall(function()
		TweenService:Create(target, TweenInfo.new(seconds, Enum.EasingStyle.Sine), goal):Play()
	end)
end

----------------------------------------------------------------
-- Window
----------------------------------------------------------------
Window = Polaris:CreateWindow({
	Name = "Crazy Hub",
	Theme = "Midnight",
	ToggleKey = Enum.KeyCode.RightControl,
	SaveConfig = true,
	ConfigFolder = "CrazyHub",
})

local save = Polaris.State({ clicks = 0, power = 1, auto = 0, best = 0 }, { Persist = "game", Folder = "CrazyHub" })

-- a switch that remembers how to turn itself off
local function switch(tab, name, description, on, off)
	local t
	t = tab:CreateToggle({
		Name = name,
		Default = false,
		Callback = function(value)
			if value then
				on()
				log(name .. " on")
			else
				off()
				log(name .. " off")
			end
		end,
	})
	toggles[name] = { toggle = t, off = off }
	return t
end

----------------------------------------------------------------
-- Tab 1: Party
----------------------------------------------------------------
local Party = Window:CreateTab({ Name = "Party" })
Party:CreateParagraph({
	Text = "Everything on this tab is just for you: your screen and your sky. Colours fade slowly, never flash. Gentle mode is on. Settings has Calm down.",
})

Party:CreateSection({ Name = "Sky and lights" })

local discoSpeed = 2
switch(Party, "Disco lights", "Fades the world through colours", function()
	local hue = 0
	startLoop("disco", 1, function()
		hue = (hue + 0.13) % 1
		local seconds = (gentle and 1.4 or 0.6) / (0.5 + discoSpeed * 0.3)
		seconds = math.max(seconds, 0.5)
		local colour = Color3.fromHSV(hue, 0.65, 0.9)
		fade(Lighting, { Ambient = colour, OutdoorAmbient = colour, ColorShift_Top = Color3.fromHSV((hue + 0.5) % 1, 0.5, 0.8) }, seconds)
		task.wait(math.max(seconds - 1, 0))
	end)
end, function()
	stopLoop("disco")
	pcall(function()
		Lighting.Ambient = original.Ambient
		Lighting.OutdoorAmbient = original.OutdoorAmbient
		Lighting.ColorShift_Top = original.ColorShift_Top
	end)
end)

Party:CreateSlider({
	Name = "Disco speed", Min = 1, Max = 5, Default = 2, Increment = 1,
	Callback = function(v)
		discoSpeed = v
	end,
})

switch(Party, "Time lapse", "Sun races across the sky", function()
	startLoop("timelapse", 0.2, function()
		Lighting.ClockTime = (Lighting.ClockTime + (gentle and 0.15 or 0.4)) % 24
	end)
end, function()
	stopLoop("timelapse")
	pcall(function()
		Lighting.ClockTime = original.ClockTime
	end)
end)

Party:CreateSection({ Name = "Window and view" })

local themeNames = {}
for i, hue in { 0.0, 0.08, 0.16, 0.33, 0.5, 0.62, 0.75, 0.88 } do
	local name = "Crazy " .. i
	Polaris:AddTheme(name, { Accent = Color3.fromHSV(hue, 0.6, 1), Success = Color3.fromHSV(hue, 0.5, 0.9) })
	table.insert(themeNames, name)
end

switch(Party, "Rainbow window", "The accent colour keeps changing", function()
	local i = 0
	startLoop("rainbow", gentle and 2 or 1, function()
		i = i % #themeNames + 1
		Polaris:SetTheme(themeNames[i])
	end)
end, function()
	stopLoop("rainbow")
	Polaris:SetTheme("Midnight")
end)

switch(Party, "Wobbly view", "Your field of view breathes in and out", function()
	local base = camera.FieldOfView or originalFov
	startLoop("wobble", 0.05, function(tick)
		local amount = gentle and 3 or 8
		camera.FieldOfView = base + math.sin(tick * 0.15) * amount
	end)
	undo.wobble = function()
		camera.FieldOfView = base
	end
end, function()
	stopLoop("wobble")
	camera.FieldOfView = originalFov
end)

Party:CreateSection({ Name = "Confetti" })

local function confetti(count)
	local g = overlay("Confetti")
	if #g:GetChildren() > 160 then
		return
	end
	for _ = 1, count do
		local piece = frame(g, {
			Size = UDim2.new(0, math.random(6, 12), 0, math.random(8, 16)),
			Position = UDim2.new(math.random(), 0, 0, -20),
			BackgroundColor3 = Color3.fromHSV(math.random(), 0.8, 1),
			Rotation = math.random(0, 360),
		})
		local seconds = rand(2, 4)
		pcall(function()
			TweenService:Create(piece, TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = UDim2.new(piece.Position.X.Scale, math.random(-90, 90), 1, 20),
				Rotation = piece.Rotation + math.random(-360, 360),
			}):Play()
		end)
		task.delay(seconds + 0.2, function()
			pcall(function()
				piece:Destroy()
			end)
		end)
	end
end

Party:CreateButtonRow({ Buttons = {
	{ Name = "Confetti burst", Callback = function() confetti(60) log("Confetti burst") end },
	{ Name = "Huge burst", Callback = function() confetti(gentle and 90 or 140) end },
} })

switch(Party, "Confetti rain", "A steady shower", function()
	startLoop("rain", 0.4, function()
		confetti(gentle and 4 or 9)
	end)
end, function()
	stopLoop("rain")
end)

Party:CreateSection({ Name = "Go wild" })

Party:CreateButtonRow({ Buttons = {
	{
		Name = "Surprise me",
		Callback = function()
			local names = { "Disco lights", "Time lapse", "Rainbow window", "Wobbly view", "Confetti rain" }
			local pick = names[math.random(#names)]
			toggles[pick].toggle:Set(true)
			note("Surprise", pick .. " is on.", "success")
		end,
	},
	{
		Name = "Party mode",
		Callback = function()
			for _, name in { "Disco lights", "Rainbow window", "Confetti rain" } do
				toggles[name].toggle:Set(true)
			end
			note("Party mode", "Disco, rainbow window and confetti rain are on.", "success")
		end,
	},
} })

----------------------------------------------------------------
-- Tab 2: Look (camera, lighting, filters)
----------------------------------------------------------------
local Look = Window:CreateTab({ Name = "Look" })
Look:CreateSection({ Name = "Camera and light" })

Look:CreateSlider({ Name = "Field of view", Min = 30, Max = 120, Default = originalFov, Increment = 1, ValueName = "deg",
	Callback = function(v) camera.FieldOfView = v end })
Look:CreateSlider({ Name = "Time of day", Min = 0, Max = 24, Default = 14, Increment = 0.5, ValueName = "h",
	Callback = function(v) Lighting.ClockTime = v end })
Look:CreateSlider({ Name = "Brightness", Min = 0, Max = 5, Default = original.Brightness or 2, Increment = 0.1,
	Callback = function(v) Lighting.Brightness = v end })
Look:CreateSlider({ Name = "Fog distance", Min = 50, Max = 5000, Default = 1000, Increment = 50,
	Callback = function(v) Lighting.FogEnd = v end })

Look:CreateSection({ Name = "Filters" })

local MOODS = {
	Normal = { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.fromRGB(255, 255, 255) },
	Sepia = { Saturation = -0.5, Contrast = 0.1, Brightness = 0, TintColor = Color3.fromRGB(255, 225, 175) },
	Noir = { Saturation = -1, Contrast = 0.3, Brightness = -0.05, TintColor = Color3.fromRGB(255, 255, 255) },
	Neon = { Saturation = 1, Contrast = 0.25, Brightness = 0, TintColor = Color3.fromRGB(255, 200, 255) },
	Frozen = { Saturation = -0.2, Contrast = 0.1, Brightness = 0.05, TintColor = Color3.fromRGB(190, 225, 255) },
	Sunset = { Saturation = 0.3, Contrast = 0.15, Brightness = 0, TintColor = Color3.fromRGB(255, 200, 160) },
	Toxic = { Saturation = 0.6, Contrast = 0.2, Brightness = 0, TintColor = Color3.fromRGB(190, 255, 170) },
}
Look:CreateDropdown({
	Name = "Colour mood", Options = { "Normal", "Sepia", "Noir", "Neon", "Frozen", "Sunset", "Toxic" }, Default = "Normal",
	Callback = function(choice)
		local mood = MOODS[choice]
		if not mood then return end
		effect("Mood", "ColorCorrectionEffect", mood)
		log("Mood " .. choice)
	end,
})
Look:CreateSlider({ Name = "Glow (bloom)", Min = 0, Max = 2, Default = 0, Increment = 0.1,
	Callback = function(v) effect("Bloom", "BloomEffect", { Intensity = v, Size = 24, Threshold = 0.9 }) end })
Look:CreateSlider({ Name = "Blur", Min = 0, Max = 24, Default = 0, Increment = 1,
	Callback = function(v) effect("Blur", "BlurEffect", { Size = v }) end })
Look:CreateSlider({ Name = "Sun rays", Min = 0, Max = 1, Default = 0, Increment = 0.05,
	Callback = function(v) effect("Rays", "SunRaysEffect", { Intensity = v, Spread = 0.8 }) end })

Look:CreateButton({ Name = "Reset the look", Callback = function()
	restoreLighting()
	removeEffects()
	camera.FieldOfView = originalFov
	note("Look", "Put back to normal.")
end })

----------------------------------------------------------------
-- Tab 3: Screen (overlays)
----------------------------------------------------------------
local Screen = Window:CreateTab({ Name = "Screen" })
Screen:CreateSection({ Name = "Overlays" })

local function glyph()
	local chars = "01ABCDEFGHIJKLMNOPQRSTUVWXYZ+=<>"
	local i = math.random(#chars)
	return chars:sub(i, i)
end

switch(Screen, "Matrix rain", "Green letters fall down your screen", function()
	local g = overlay("Matrix")
	local columns, rows = 26, 14
	local labels, phase = {}, {}
	for i = 1, columns do
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(0, 16, 0, rows * 16)
		l.TextColor3 = Color3.fromRGB(80, 255, 130)
		l.TextTransparency = 0.35
		l.TextSize = 14
		l.Font = Enum.Font.Code
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.Parent = g
		labels[i], phase[i] = l, math.random()
	end
	local ticks = 0
	startLoop("matrix", 0.1, function()
		ticks += 1
		for i, l in labels do
			phase[i] = (phase[i] + (0.02 + (i % 5) * 0.006)) % 1.4
			l.Position = UDim2.new(i / (columns + 1), 0, phase[i] - 0.3, 0)
			if (ticks + i) % 3 == 0 then
				local text = {}
				for r = 1, rows do text[r] = glyph() end
				l.Text = table.concat(text, "\n")
			end
		end
	end)
end, function()
	stopLoop("matrix")
	removeOverlay("Matrix")
end)

switch(Screen, "Retro TV lines", "Old television scan lines", function()
	local g = overlay("CRT")
	for i = 0, 89 do
		frame(g, { Size = UDim2.new(1, 0, 0, 2), Position = UDim2.new(0, 0, i / 90, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.78 })
	end
	frame(g, { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 255, 160), BackgroundTransparency = 0.94 })
end, function()
	removeOverlay("CRT")
end)

switch(Screen, "Dark corners", "A soft vignette", function()
	local g = overlay("Vignette")
	local sides = {
		{ UDim2.new(1, 0, 0.22, 0), UDim2.new(0, 0, 0, 0), 90 },
		{ UDim2.new(1, 0, 0.22, 0), UDim2.new(0, 0, 0.78, 0), 270 },
		{ UDim2.new(0.14, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 },
		{ UDim2.new(0.14, 0, 1, 0), UDim2.new(0.86, 0, 0, 0), 180 },
	}
	for _, s in sides do
		local f = frame(g, { Size = s[1], Position = s[2], BackgroundColor3 = Color3.new(0, 0, 0) })
		pcall(function()
			local grad = Instance.new("UIGradient")
			grad.Rotation = s[3]
			grad.Transparency = NumberSequence.new(0.3, 1)
			grad.Parent = f
		end)
	end
end, function()
	removeOverlay("Vignette")
end)

switch(Screen, "Clock", "Time in the top middle", function()
	local g = overlay("Clock")
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(0, 140, 0, 28)
	l.Position = UDim2.new(0.5, -70, 0, 6)
	l.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
	l.BackgroundTransparency = 0.3
	l.TextColor3 = Color3.fromRGB(235, 235, 240)
	l.TextSize = 18
	l.Parent = g
	startLoop("clock", 1, function()
		l.Text = os.date("%H:%M:%S")
	end)
end, function()
	stopLoop("clock")
	removeOverlay("Clock")
end)

Screen:CreateSection({ Name = "Crosshair" })
Screen:CreateDropdown({
	Name = "Crosshair style", Options = { "Off", "Dot", "Plus", "Ring" }, Default = "Off",
	Callback = function(choice)
		removeOverlay("Crosshair")
		if choice == "Off" then return end
		local g = overlay("Crosshair")
		local white = Color3.fromRGB(255, 255, 255)
		local mid = UDim2.new(0.5, 0, 0.5, 0)
		if choice == "Dot" then
			local d = frame(g, { Size = UDim2.new(0, 6, 0, 6), AnchorPoint = Vector2.new(0.5, 0.5), Position = mid, BackgroundColor3 = white })
			pcall(function() Instance.new("UICorner", d).CornerRadius = UDim.new(1, 0) end)
		elseif choice == "Plus" then
			frame(g, { Size = UDim2.new(0, 14, 0, 2), AnchorPoint = Vector2.new(0.5, 0.5), Position = mid, BackgroundColor3 = white })
			frame(g, { Size = UDim2.new(0, 2, 0, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = mid, BackgroundColor3 = white })
		else
			local r = frame(g, { Size = UDim2.new(0, 22, 0, 22), AnchorPoint = Vector2.new(0.5, 0.5), Position = mid, BackgroundTransparency = 1 })
			pcall(function()
				Instance.new("UICorner", r).CornerRadius = UDim.new(1, 0)
				local s = Instance.new("UIStroke")
				s.Color, s.Thickness = white, 2
				s.Parent = r
			end)
		end
	end,
})

----------------------------------------------------------------
-- Tab 4: Games
----------------------------------------------------------------
local Games = Window:CreateTab({ Name = "Games" })
Games:CreateSection({ Name = "Cookie-style clicker (saved)" })

local clickLabel = Games:CreateLabel({ Text = "", Size = 22, Bold = true })
clickLabel:Bind(save, function(s)
	return ("Clicks: %d   Power: %d   Helpers: %d"):format(s.clicks, s.power, s.auto)
end)

local function gain(n)
	save:Update(function(s)
		local c = table.clone(s)
		c.clicks += n
		return c
	end)
end

Games:CreateButton({ Name = "CLICK", Callback = function()
	gain(save:Get().power)
end })
Games:CreateButtonRow({ Buttons = {
	{ Name = "Buy power (25 x power)", Callback = function()
		local s = save:Get()
		local cost = 25 * s.power
		if s.clicks < cost then return note("Clicker", "You need " .. cost .. " clicks.", "warning") end
		local c = table.clone(s)
		c.clicks -= cost
		c.power += 1
		save:Set(c)
	end },
	{ Name = "Buy helper (100)", Callback = function()
		local s = save:Get()
		if s.clicks < 100 then return note("Clicker", "You need 100 clicks.", "warning") end
		local c = table.clone(s)
		c.clicks -= 100
		c.auto += 1
		save:Set(c)
	end },
} })
startLoop("helpers", 1, function()
	local helpers = save:Get().auto
	if helpers > 0 then
		gain(helpers)
	end
end)

Games:CreateSection({ Name = "Dice and coins" })
local rolled = Games:CreateLabel({ Text = "Roll something", Size = 20, Bold = true })
local dieChoice = "Coin"
Games:CreateDropdown({ Name = "What to roll", Options = { "Coin", "d6", "d20", "d100" }, Default = "Coin",
	Callback = function(v) dieChoice = v end })
local history = Games:CreateTable({ Columns = { "Time", "Roll", "Result" }, Rows = {}, Height = 120, MaxRows = 15, Empty = "No rolls yet" })
Games:CreateButton({ Name = "Roll", Callback = function()
	local result
	if dieChoice == "Coin" then
		result = math.random(2) == 1 and "Heads" or "Tails"
	else
		result = tostring(math.random(tonumber(dieChoice:sub(2))))
	end
	rolled:SetText(dieChoice .. ": " .. result)
	history:AddRow({ os.date("%H:%M:%S"), dieChoice, result })
end })

Games:CreateSection({ Name = "Reaction test" })
local reactLabel = Games:CreateLabel({ Text = "Press Start. When it says NOW, press Go as fast as you can.", Wrap = true })
local reactToken, goAt = nil, nil
Games:CreateButtonRow({ Buttons = {
	{ Name = "Start", Callback = function()
		local token = {}
		reactToken, goAt = token, nil
		reactLabel:SetText("Wait for it...")
		task.delay(rand(1.5, 4), function()
			if reactToken == token then
				goAt = os.clock()
				reactLabel:SetText("NOW!")
			end
		end)
	end },
	{ Name = "Go", Callback = function()
		if goAt then
			local ms = math.floor((os.clock() - goAt) * 1000)
			goAt, reactToken = nil, nil
			local s = save:Get()
			local best = (s.best == 0 or ms < s.best) and ms or s.best
			local c = table.clone(s)
			c.best = best
			save:Set(c)
			reactLabel:SetText(("%d ms   (best %d ms)"):format(ms, best))
		elseif reactToken then
			reactToken = nil
			reactLabel:SetText("Too early. Press Start to try again.")
		end
	end },
} })

Games:CreateSection({ Name = "Fortune" })
local fortune = Games:CreateLabel({ Text = "Ask the hub a question, then press the button.", Wrap = true })
local FORTUNES = {
	"Yes, but only on a Tuesday.", "Ask again after a snack.", "The confetti says yes.", "Absolutely not. Sorry.",
	"A wise penguin nods.", "You already know the answer.", "Outlook cloudy, with a chance of pizza.", "Do a little dance first.",
}
Games:CreateButton({ Name = "Ask the hub", Callback = function()
	fortune:SetText(FORTUNES[math.random(#FORTUNES)])
end })

----------------------------------------------------------------
-- Tab 5: Script shelf (real script library) and Make your own
----------------------------------------------------------------
local Shelf = Window:CreateTab({ Name = "Script shelf" })
Shelf:CreateParagraph({ Text = "Search, favourite and run ready-made scripts. Use + Add to add your own link or code. Only add scripts you trust." })
local scripts = Polaris.HubScripts()
table.insert(scripts, {
	Name = "Crazy confetti", Description = "One confetti burst", Tags = { "party" },
	Run = function() confetti(80) end,
})
Shelf:Add("ScriptLibrary", { Name = "Crazy shelf", Scripts = scripts, Height = 340, Folder = "CrazyHub" })

local Make = Window:CreateTab({ Name = "Make your own" })
Make:CreateParagraph({ Text = "Build your own hub the same way this one was made. Blocks and scripts work together." })
Make:CreateButtonRow({ Buttons = {
	{ Name = "Block editor", Callback = function() Polaris.MakeHub() end },
	{ Name = "Make Anything", Callback = function() Polaris.Imaginer() end },
	{ Name = "Mock executor window", Callback = function() Polaris.MockExecutor() end },
} })
Make:CreateParagraph({ Text = "The mock executor is only a look-alike window. It does not inject into anything." })

----------------------------------------------------------------
-- Tab 6: Stats
----------------------------------------------------------------
local Stats = Window:CreateTab({ Name = "Stats" })
Stats:CreateStats({ Items = { "FPS", "Ping", "Players", "Memory" }, Columns = 2 })
local fpsChart = Stats:CreateChart({ Type = "line", Title = "FPS over the last minute", MaxPoints = 60, Height = 150 })
Stats:CreateSection({ Name = "What you did" })
logTable = Stats:CreateTable({ Columns = { "Time", "What" }, Rows = {}, Height = 160, MaxRows = 40, Empty = "Nothing yet" })

pcall(function()
	RunService.Heartbeat:Connect(function(dt)
		if dt and dt > 0 then
			fpsNow = math.floor(1 / dt + 0.5)
		end
	end)
end)
startLoop("fpschart", 1, function()
	fpsChart:AddPoint(fpsNow)
end)

----------------------------------------------------------------
-- Settings and the big undo button
----------------------------------------------------------------
local Settings = Window:AddSettingsTab()
Settings:CreateSection({ Name = "Comfort and cleanup" })
Settings:CreateToggle({ Name = "Gentle mode", Default = true, Callback = function(v) gentle = v end })

local function calmDown(closing)
	for _, entry in toggles do
		pcall(function()
			if closing then
				entry.off() -- the window is gone, so just undo the effect
			elseif entry.toggle:Get() then
				entry.toggle:Set(false)
			end
		end)
	end
	for name in loops do
		if closing or (name ~= "helpers" and name ~= "fpschart") then
			loops[name] = nil
		end
	end
	for name in guis do
		removeOverlay(name)
	end
	for _, fn in undo do
		pcall(fn)
	end
	restoreLighting()
	removeEffects()
	camera.FieldOfView = originalFov
	pcall(function()
		Polaris:SetTheme("Midnight")
	end)
	if closing ~= true then
		note("Calm down", "Everything is back to normal.", "success")
	end
end
onClosed = function()
	calmDown(true)
end

Settings:CreateButton({ Name = "Calm down (undo everything)", Callback = function() calmDown(false) end })

Polaris:Notify({ Title = "Crazy Hub", Content = "Pick a tab. Press RightControl to hide the window.", Type = "success", Duration = 4 })

return { Window = Window, CalmDown = calmDown, State = save, Toggles = toggles, Loops = loops, Overlays = guis }
