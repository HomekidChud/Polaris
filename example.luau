--[[
	Polaris demo - Studio (LocalScript)
	------------------------------------
	1. Put Polaris.luau in ReplicatedStorage as a ModuleScript named "Polaris"
	2. Put this script in StarterPlayerScripts as a LocalScript
	3. Hit Play - the window appears immediately (no Init call needed)

	Executor variant: replace the two lines below the marker with
		local Polaris = loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"))()
	and replace setclipboard usage with your executor's clipboard API.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Polaris = require(ReplicatedStorage:WaitForChild("Polaris"))

local Window = Polaris:CreateWindow({
	Name = "My Hub",
	Theme = "Midnight", -- Default | Midnight | Light (or your own, see AddTheme)
	ToggleKey = Enum.KeyCode.RightControl, -- hide/show the UI
})

local Main = Window:CreateTab({ Name = "Main" })

Main:CreateSection({ Name = "Actions" })

Main:CreateButton({
	Name = "Say Hello",
	Callback = function()
		Polaris:Notify({ Title = "Hello!", Content = "You clicked the button", Duration = 3 })
	end,
})

local flyEnabled = false
local flyToggle = Main:CreateToggle({
	Name = "Fly",
	Default = false,
	Flag = "fly", -- flags make settings saveable
	Callback = function(value)
		flyEnabled = value
	end,
})

Main:CreateSlider({
	Name = "Speed",
	Min = 0,
	Max = 100,
	Default = 16,
	Increment = 1,
	ValueName = "studs/s",
	Flag = "speed",
	Callback = function(value)
		print("speed:", value)
	end,
})

Main:CreateDropdown({
	Name = "Target Player",
	Options = { "Player1", "Player2", "Player3" },
	Flag = "target",
	Callback = function(selected)
		print("selected:", selected)
	end,
})

Main:CreateDropdown({
	Name = "Multi Example",
	Options = { "a", "b", "c" },
	Multiple = true, -- multi-select dropdown
	Flag = "multi",
})

Main:CreateColorPicker({
	Name = "Highlight Color",
	Default = Color3.fromRGB(120, 130, 255),
	Flag = "color",
	Callback = function(color)
		print("picked:", color)
	end,
})

Main:CreateKeybind({
	Name = "Toggle Fly Key",
	Default = Enum.KeyCode.F,
	Flag = "flykey",
	Callback = function()
		flyEnabled = not flyEnabled
		flyToggle:Set(flyEnabled)
	end,
})

Main:CreateTextbox({
	Name = "Custom Message",
	Default = "hello world",
	Flag = "message",
	TextDisappear = false,
	Callback = function(text)
		print("entered:", text)
	end,
})

Main:CreateParagraph({ Text = "This is a paragraph. Use it for notes or instructions." })

Main:CreateDivider({})

local Settings = Window:CreateTab({ Name = "Settings" })

Settings:CreateSection({ Name = "Theme" })

Settings:CreateDropdown({
	Name = "Theme",
	Options = Polaris:GetThemeNames(),
	Default = "Midnight",
	Callback = function(theme)
		Polaris:SetTheme(theme)
	end,
})

Settings:CreateKeybind({
	Name = "UI Toggle Key",
	Default = Enum.KeyCode.RightControl,
	Callback = function() end, -- handled by the window itself
})

Settings:CreateButton({
	Name = "Export Config (JSON)",
	Callback = function()
		local json = Window:ExportConfig()
		print("Config JSON:", json) -- executor: use setclipboard(json)
	end,
})

Settings:CreateButton({
	Name = "Destroy UI",
	Callback = function()
		Window:Destroy()
	end,
})

-- Elements can also be controlled from code:
-- flyToggle:Set(true)          -- set + fire callback
-- flyToggle:Set(true, true)     -- set silently
-- flyToggle:Get()               -> current value
-- flyToggle:SetVisible(false)   -- hide the row
-- flyToggle:SetDisabled(true)   -- grey out + ignore clicks
-- flyToggle:Destroy()           -- remove + clean up
