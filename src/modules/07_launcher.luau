-- launcher: Polaris.Start() - a big, colourful "tap a picture" screen that opens any template.
-- Made for small hands: huge tap targets, almost no reading, confetti on every tap.

local Create, safeTween = I.Create, I.safeTween
local Kit = Polaris.Kit

local RAINBOW = {
	Color3.fromRGB(255, 90, 95), Color3.fromRGB(255, 160, 60), Color3.fromRGB(250, 205, 60),
	Color3.fromRGB(90, 200, 120), Color3.fromRGB(70, 160, 255), Color3.fromRGB(160, 110, 240),
}

-- Burst of falling squares.  parent: any GuiObject/ScreenGui.
function Polaris.Confetti(parent, count)
	count = count or 36
	local vp = Kit.viewport()
	local rnd = Random and Random.new() or nil
	local function r(a, b)
		if rnd then
			return rnd:NextNumber(a, b)
		end
		return a + math.random() * (b - a)
	end
	for _ = 1, count do
		local size = r(7, 14)
		local piece = Create("Frame", {
			Size = UDim2.new(0, size, 0, size * r(0.5, 1.2)),
			Position = UDim2.new(0.5, r(-60, 60), 0.35, r(-20, 20)),
			BackgroundColor3 = RAINBOW[math.random(1, #RAINBOW)],
			BorderSizePixel = 0,
			Rotation = r(0, 360),
			ZIndex = 500,
			Parent = parent,
		})
		local t = r(0.9, 1.7)
		safeTween(piece, t, {
			Position = UDim2.new(0.5, r(-vp.X * 0.45, vp.X * 0.45), 0.35, r(vp.Y * 0.25, vp.Y * 0.7)),
			Rotation = r(-540, 540),
			BackgroundTransparency = 1,
		})
		task.delay(t + 0.1, function()
			pcall(function()
				piece:Destroy()
			end)
		end)
	end
end

----------------------------------------------------------------
-- Icons drawn from plain frames (no images, no emoji fonts needed)
----------------------------------------------------------------

local function bar(parent, x, y, w, h, color, round)
	local f = Create("Frame", {
		Size = UDim2.new(w, 0, h, 0), Position = UDim2.new(x, 0, y, 0),
		BackgroundColor3 = color or Color3.new(1, 1, 1), BorderSizePixel = 0, Parent = parent,
	})
	Create("UICorner", { CornerRadius = round and UDim.new(1, 0) or UDim.new(0.2, 0), Parent = f })
	return f
end

local ICONS = {
	list = function(p)
		bar(p, 0.1, 0.12, 0.8, 0.18)
		bar(p, 0.1, 0.41, 0.8, 0.18)
		bar(p, 0.1, 0.70, 0.5, 0.18)
	end,
	search = function(p)
		local ring = Create("Frame", { Size = UDim2.new(0.58, 0, 0.58, 0), Position = UDim2.new(0.08, 0, 0.08, 0), BackgroundTransparency = 1, BorderSizePixel = 0, Parent = p })
		Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
		Create("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 6, Parent = ring })
		local handle = bar(p, 0.58, 0.72, 0.4, 0.14)
		handle.Rotation = 45
		handle.AnchorPoint = Vector2.new(0, 0)
	end,
	grid = function(p)
		bar(p, 0.08, 0.08, 0.38, 0.38)
		bar(p, 0.54, 0.08, 0.38, 0.38)
		bar(p, 0.08, 0.54, 0.38, 0.38)
		bar(p, 0.54, 0.54, 0.38, 0.38)
	end,
	plus = function(p)
		bar(p, 0.4, 0.08, 0.2, 0.84)
		bar(p, 0.08, 0.4, 0.84, 0.2)
	end,
	rainbow = function(p)
		for i = 1, 5 do
			bar(p, 0.04 + (i - 1) * 0.19, 0.5 - i * 0.07, 0.15, 0.3 + i * 0.07, RAINBOW[(i % #RAINBOW) + 1])
		end
	end,
	dots = function(p)
		bar(p, 0.05, 0.35, 0.27, 0.27, nil, true)
		bar(p, 0.365, 0.35, 0.27, 0.27, nil, true)
		bar(p, 0.68, 0.35, 0.27, 0.27, nil, true)
	end,
}

----------------------------------------------------------------
-- Toy: one giant button.  Press it.  Nothing can go wrong.
----------------------------------------------------------------

function Polaris.Toy()
	local gui = Create("ScreenGui", { Name = "PolarisToy", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = I.getGuiParent() })
	local bg = Create("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.fromRGB(30, 30, 50), BackgroundTransparency = 0.15, BorderSizePixel = 0, Parent = gui })
	local count = 0
	local counter = Kit.label(bg, "0", { Size = 64, Bold = true, Align = "Center", Position = UDim2.new(0, 0, 0.08, 0), Height = 80, Color = Color3.new(1, 1, 1) })
	local hint = Kit.label(bg, "Press the big button!", { Size = 26, Align = "Center", Position = UDim2.new(0, 0, 0.82, 0), Height = 40, Color = Color3.fromRGB(220, 225, 255) })
	local vp = Kit.viewport()
	local d = math.floor(math.min(vp.X, vp.Y) * 0.45)
	local big = Kit.button(bg, "", { Color = RAINBOW[1], Size = UDim2.new(0, d, 0, d), Position = UDim2.new(0.5, -d / 2, 0.5, -d / 2), Radius = d / 2, TextSize = 40 })
	big.Active = true
	local close = Kit.button(bg, "X", { Color = "Danger", Size = UDim2.new(0, 56, 0, 56), Position = UDim2.new(1, -70, 0, 14), TextSize = 28, Radius = 28 })
	close.Activated:Connect(function()
		gui:Destroy()
	end)
	big.Activated:Connect(function()
		count += 1
		counter.Text = tostring(count)
		big.BackgroundColor3 = RAINBOW[(count % #RAINBOW) + 1]
		big.Size = UDim2.new(0, d * 0.88, 0, d * 0.88)
		big.Position = UDim2.new(0.5, -d * 0.44, 0.5, -d * 0.44)
		safeTween(big, 0.18, { Size = UDim2.new(0, d, 0, d), Position = UDim2.new(0.5, -d / 2, 0.5, -d / 2) })
		hint.Text = ({ "Yay!", "Wow!", "Again!", "Super!", "Great!", "Hooray!" })[(count % 6) + 1]
		Polaris.Confetti(bg, count % 5 == 0 and 60 or 14)
	end)
	return gui
end

----------------------------------------------------------------
-- Make your own hub: the block editor, pre-loaded with a working script hub.
-- Blocks build the hub; Script blocks hold your own code; Export gives a script you can share.
----------------------------------------------------------------

function Polaris.MakeHub(template)
	local B = Polaris.Builder
	B:LoadTemplate(template or "My Script Hub")
	if B:IsOpen() then
		B:_refreshAll()
	else
		B:Open()
	end
	return B
end

----------------------------------------------------------------
-- Launcher
----------------------------------------------------------------

local function defaultTiles()
	local T = Polaris.Templates
	return {
		{ Name = "Script Hub", Icon = "list", Color = Color3.fromRGB(66, 133, 244), Action = function() return T.ScriptLibrary({ Name = "Script Hub" }) end },
		{ Name = "Research", Icon = "search", Color = Color3.fromRGB(150, 95, 235), Action = function() return T.DeepResearch() end },
		{ Name = "Game Hub", Icon = "grid", Color = Color3.fromRGB(52, 168, 100), Action = function() return T.RobloxHub() end },
		{ Name = "Everything", Icon = "rainbow", Color = Color3.fromRGB(240, 140, 40), Action = function() return T.Everything() end },
		{ Name = "Play", Icon = "dots", Color = Color3.fromRGB(235, 190, 40), Action = function() return Polaris.Toy() end },
	}
end

-- opts: Title, Tiles (list of { Name, Icon, Color, Action }), Theme, Keep (leave launcher open after a tap)
function Polaris.Start(opts)
	opts = opts or {}
	if opts.Theme and Polaris.Themes[opts.Theme] then
		Polaris:SetTheme(opts.Theme)
	end
	local gui = Create("ScreenGui", { Name = "PolarisStart", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = I.getGuiParent() })
	local dim = Create("TextButton", { Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, BorderSizePixel = 0, Text = "", AutoButtonColor = false, Parent = gui })
	local vp = Kit.viewport()
	local W = math.min(math.floor(vp.X * 0.94), 780)
	local H = math.min(math.floor(vp.Y * 0.92), 600)
	local card = Kit.frame(dim, { Color = "Background", Radius = 18, Stroke = "Accent", Size = UDim2.new(0, W, 0, H), Position = UDim2.new(0.5, -W / 2, 0.5, -H / 2) })

	local rainbowTitle = {}
	local word = opts.Title or "Polaris"
	for i = 1, #word do
		local c = RAINBOW[((i - 1) % #RAINBOW) + 1]
		table.insert(rainbowTitle, string.format('<font color="#%02x%02x%02x">%s</font>', c.R * 255, c.G * 255, c.B * 255, word:sub(i, i)))
	end
	Kit.label(card, table.concat(rainbowTitle), { Size = 38, Bold = true, Rich = true, Position = UDim2.new(0, 20, 0, 10), Width = 1, WidthOffset = -90, Height = 50 })
	Kit.label(card, opts.Subtitle or "Tap a picture!", { Size = 22, Color = "SubText", Position = UDim2.new(0, 22, 0, 58), Width = 1, WidthOffset = -90, Height = 30 })
	local close = Kit.button(card, "X", { Color = "Danger", Size = UDim2.new(0, 48, 0, 48), Position = UDim2.new(1, -62, 0, 14), TextSize = 24, Radius = 24 })
	close.Activated:Connect(function()
		gui:Destroy()
	end)

	local tiles = opts.Tiles or defaultTiles()
	local cols = W < 560 and 2 or 3
	local gap = 12
	local cell = math.floor((W - 40 - (cols - 1) * gap) / cols)
	local cellH = math.min(cell, 168)
	local scroll = Create("ScrollingFrame", {
		Size = UDim2.new(1, -24, 1, opts.MakeHub == false and -104 or -184), Position = UDim2.new(0, 12, 0, 96), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 5, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Parent = card,
	})
	Create("UIGridLayout", { CellSize = UDim2.new(0, cell, 0, cellH), CellPadding = UDim2.new(0, gap, 0, gap), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = scroll })
	Create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8), Parent = scroll })

	local handle = { Gui = gui }
	function handle:Close()
		if gui.Parent then
			gui:Destroy()
		end
	end

	if opts.MakeHub ~= false then
		local banner = Create("TextButton", { Name = "MakeHub", Text = "", AutoButtonColor = false, BackgroundColor3 = Color3.fromRGB(230, 80, 140), BorderSizePixel = 0, Size = UDim2.new(1, -24, 0, 66), Position = UDim2.new(0, 12, 1, -78), Parent = card })
		Create("UICorner", { CornerRadius = UDim.new(0, 18), Parent = banner })
		local plus = Create("Frame", { Size = UDim2.new(0, 40, 0, 40), Position = UDim2.new(0, 16, 0.5, -20), BackgroundTransparency = 1, Parent = banner })
		ICONS.plus(plus)
		Kit.label(banner, "Create your own script hub", { Size = 24, Bold = true, Position = UDim2.new(0, 70, 0, 8), Width = 1, WidthOffset = -84, Height = 30, Color = Color3.new(1, 1, 1) })
		Kit.label(banner, "Snap blocks together and add your own scripts", { Size = 14, Position = UDim2.new(0, 70, 0, 38), Width = 1, WidthOffset = -84, Height = 20, Color = Color3.fromRGB(255, 225, 240) })
		banner.Activated:Connect(function()
			Polaris.Confetti(gui, 30)
			task.delay(0.35, function()
				if not opts.Keep then
					handle:Close()
				end
				local ok, err = pcall(Polaris.MakeHub)
				if not ok then
					warn("[Polaris] could not open the hub maker:", err)
					Polaris:Notify({ Title = "Oops", Content = "The hub maker did not open. " .. tostring(err), Type = "error", Duration = 6 })
				end
			end)
		end)
	end

	for i, tile in ipairs(tiles) do
		local btn = Create("TextButton", { Name = "Tile", Text = "", AutoButtonColor = false, BackgroundColor3 = tile.Color or RAINBOW[(i % #RAINBOW) + 1], BorderSizePixel = 0, LayoutOrder = i, Parent = scroll })
		Create("UICorner", { CornerRadius = UDim.new(0, 20), Parent = btn })
		local iconSize = math.floor(cellH * 0.5)
		local icon = Create("Frame", { Size = UDim2.new(0, iconSize, 0, iconSize), Position = UDim2.new(0.5, -iconSize / 2, 0, math.floor(cellH * 0.1)), BackgroundTransparency = 1, Parent = btn })
		local draw = ICONS[tile.Icon]
		if draw then
			draw(icon)
		end
		Kit.label(btn, tile.Name, { Size = math.max(18, math.floor(cellH * 0.15)), Bold = true, Align = "Center", Position = UDim2.new(0, 0, 1, -math.floor(cellH * 0.28)), Height = math.floor(cellH * 0.22), Color = Color3.new(1, 1, 1) })
		btn.Activated:Connect(function()
			safeTween(btn, 0.12, { Size = UDim2.new(0, cell * 0.92, 0, cellH * 0.92) })
			Polaris.Confetti(gui, 30)
			task.delay(0.35, function()
				if not opts.Keep then
					handle:Close()
				end
				local ok, err = pcall(tile.Action)
				if not ok then
					warn("[Polaris] tile failed:", err)
					Polaris:Notify({ Title = "Oops", Content = "That one did not open. " .. tostring(err), Type = "error", Duration = 6 })
				end
			end)
		end)
	end
	return handle
end
