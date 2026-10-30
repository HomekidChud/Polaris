-- kit: small themed building blocks shared by every new widget
-- (library, research panel, launcher, dialogs ...).

local Create, themed, safeTween = I.Create, I.themed, I.safeTween

local Kit = {}
Polaris.Kit = Kit

function Kit.theme()
	return Polaris.Themes[Polaris.CurrentThemeName or "Default"] or Polaris.Themes.Default
end

-- Apply a color that is either a theme key ("Accent") or a literal Color3.
local function paint(inst, prop, color)
	if type(color) == "string" then
		themed(inst, prop, color)
	elseif color ~= nil then
		inst[prop] = color
	end
end
Kit.paint = paint

-- Frame with optional rounded corners / outline.
-- o: Color (theme key|Color3), Radius, Stroke (bool|theme key), Size, Position, Name, Transparency, Parent, ZIndex, Clip
function Kit.frame(parent, o)
	o = o or {}
	local f = Create("Frame", {
		Name = o.Name or "Frame",
		Size = o.Size or UDim2.new(1, 0, 1, 0),
		Position = o.Position or UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = o.Transparency or 0,
		BorderSizePixel = 0,
		ClipsDescendants = o.Clip == true,
		Parent = parent,
	})
	if o.ZIndex then
		f.ZIndex = o.ZIndex
	end
	if o.Anchor then
		f.AnchorPoint = o.Anchor
	end
	paint(f, "BackgroundColor3", o.Color or "Secondary")
	if o.Radius ~= 0 then
		Create("UICorner", { CornerRadius = UDim.new(0, o.Radius or 8), Parent = f })
	end
	if o.Stroke then
		local st = Create("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.8, Parent = f })
		paint(st, "Color", type(o.Stroke) == "string" and o.Stroke or "Stroke")
	end
	return f
end

-- Text label. o: Size (text size), Color, Bold, Align ("Left"|"Center"|"Right"), VAlign, Wrap, Rich, Height, Width, Position, Auto
function Kit.label(parent, text, o)
	o = o or {}
	local l = Create("TextLabel", {
		Name = o.Name or "Label",
		Size = UDim2.new(o.Width or 1, o.WidthOffset or 0, 0, o.Height or 20),
		Position = o.Position or UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		Text = tostring(text),
		TextSize = o.Size or 14,
		TextXAlignment = Enum.TextXAlignment[o.Align or "Left"],
		TextYAlignment = Enum.TextYAlignment[o.VAlign or "Center"],
		TextWrapped = o.Wrap == true,
		RichText = o.Rich == true,
		TextTruncate = o.Truncate and Enum.TextTruncate.AtEnd or Enum.TextTruncate.None,
		Parent = parent,
	})
	if o.Bold then
		l.Font = Enum.Font.GothamBold
	end
	if o.Auto then
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.Size = UDim2.new(o.Width or 1, o.WidthOffset or 0, 0, o.Height or 20)
	end
	paint(l, "TextColor3", o.Color or "Text")
	return l
end

-- Clickable rounded button. o: Color, TextColor, Size, Position, TextSize, OnClick, Radius, Bold (default true), Name
function Kit.button(parent, text, o)
	o = o or {}
	local b = Create("TextButton", {
		Name = o.Name or "Button",
		Size = o.Size or UDim2.new(1, 0, 0, 30),
		Position = o.Position or UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = tostring(text),
		TextSize = o.TextSize or 14,
		Font = o.Bold == false and Polaris.Font or Enum.Font.GothamBold,
		Parent = parent,
	})
	if o.Anchor then
		b.AnchorPoint = o.Anchor
	end
	paint(b, "BackgroundColor3", o.Color or "Accent")
	if o.TextColor then
		paint(b, "TextColor3", o.TextColor)
	else
		b.TextColor3 = Color3.new(1, 1, 1)
	end
	Create("UICorner", { CornerRadius = UDim.new(0, o.Radius or 6), Parent = b })
	b.MouseEnter:Connect(function()
		safeTween(b, 0.12, { BackgroundTransparency = 0.18 })
	end)
	b.MouseLeave:Connect(function()
		safeTween(b, 0.12, { BackgroundTransparency = 0 })
	end)
	local conn
	if o.OnClick then
		conn = b.Activated:Connect(function()
			I.invokeCallback(o.OnClick, b)
		end)
	end
	return b, conn
end

-- Single-line text input with a placeholder. o: Size, Position, Text, Placeholder, TextSize, Name
function Kit.input(parent, o)
	o = o or {}
	local box = Create("TextBox", {
		Name = o.Name or "Input",
		Size = o.Size or UDim2.new(1, 0, 0, 30),
		Position = o.Position or UDim2.new(0, 0, 0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BorderSizePixel = 0,
		Text = tostring(o.Text or ""),
		PlaceholderText = tostring(o.Placeholder or ""),
		TextSize = o.TextSize or 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		MultiLine = o.MultiLine == true,
		TextWrapped = o.MultiLine == true,
		TextYAlignment = o.MultiLine and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
		Parent = parent,
	})
	paint(box, "BackgroundColor3", o.Color or "Secondary")
	paint(box, "TextColor3", "Text")
	paint(box, "PlaceholderColor3", "SubText")
	Create("UICorner", { CornerRadius = UDim.new(0, o.Radius or 6), Parent = box })
	Create("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, o.MultiLine and 8 or 0), Parent = box })
	local st = Create("UIStroke", { Color = Color3.new(1, 1, 1), Transparency = 0.8, Parent = box })
	paint(st, "Color", "Stroke")
	return box
end

-- Scrolling list that stacks children vertically and grows its canvas automatically.
-- o: Size, Position, Padding, Transparent (default true), Name
function Kit.scroll(parent, o)
	o = o or {}
	local s = Create("ScrollingFrame", {
		Name = o.Name or "Scroll",
		Size = o.Size or UDim2.new(1, 0, 1, 0),
		Position = o.Position or UDim2.new(0, 0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Parent = parent,
	})
	local layout = Create("UIListLayout", {
		Padding = UDim.new(0, o.Padding or 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = s,
	})
	return s, layout
end

-- Stable pastel-ish accent color from any string (used for script icons).
function Kit.colorFor(str)
	local h = 0
	for i = 1, #str do
		h = (h * 31 + string.byte(str, i)) % 360
	end
	return Color3.fromHSV(h / 360, 0.55, 0.85)
end

-- Remove every child except layout helpers.
function Kit.clear(parent)
	for _, child in parent:GetChildren() do
		local c = child.ClassName
		if c ~= "UIListLayout" and c ~= "UIGridLayout" and c ~= "UIPadding" and c ~= "UICorner" and c ~= "UIStroke" then
			child:Destroy()
		end
	end
end

-- Safe wrapper so one buggy callback can never take the whole UI down.
function Kit.safe(fn, ...)
	if type(fn) ~= "function" then
		return true
	end
	local ok, err = pcall(fn, ...)
	if not ok then
		warn("[Polaris] error:", err)
		return false, tostring(err)
	end
	return true
end

-- Viewport helpers so the same UI works on desktop, tablet and phone.
function Kit.viewport()
	local ok, size = pcall(function()
		return workspace.CurrentCamera.ViewportSize
	end)
	if ok and size and size.X and size.X > 0 then
		return size
	end
	return Vector2.new(1280, 720)
end

function Kit.isTouch()
	local uis = I.services.UserInputService
	local ok, v = pcall(function()
		return uis.TouchEnabled and not uis.KeyboardEnabled
	end)
	return ok and v == true
end

-- Clamp a wanted window size to the screen (leaves a margin).
function Kit.fitSize(w, h)
	local vp = Kit.viewport()
	return Vector2.new(math.min(w, math.floor(vp.X * 0.94)), math.min(h, math.floor(vp.Y * 0.88)))
end
