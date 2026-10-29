--[[
	My Hub - built with Polaris
	---------------------------
	Paste this into your executor, or run it as a LocalScript in Studio
	(with Polaris in ReplicatedStorage, swap the loadstring line for require()).

	RightControl shows/hides the UI.
]]

-- Load the library
local Polaris = loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"))()

-- Services
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

----------------------------------------------------------------
-- Window
----------------------------------------------------------------

local Window = Polaris:CreateWindow({
	Name = "My Hub",
	Theme = "Midnight",
	ToggleKey = Enum.KeyCode.RightControl,
	SaveConfig = true,
	ConfigFolder = "MyHub",
})

----------------------------------------------------------------
-- Character tab
----------------------------------------------------------------

local Character = Window:CreateTab({ Name = "Character" })

Character:CreateSection({ Name = "Movement" })

local WalkSpeed = Character:CreateSlider({
	Name = "Walk Speed",
	Min = 16,
	Max = 200,
	Default = 16,
	Increment = 1,
	Flag = "walkspeed",
	Callback = function(value)
		local character = LocalPlayer.Character
		if character and character:FindFirstChildOfClass("Humanoid") then
			character:FindFirstChildOfClass("Humanoid").WalkSpeed = value
		end
	end,
})

local JumpPower = Character:CreateSlider({
	Name = "Jump Power",
	Min = 50,
	Max = 300,
	Default = 50,
	Increment = 5,
	Flag = "jumppower",
	Callback = function(value)
		local character = LocalPlayer.Character
		if character and character:FindFirstChildOfClass("Humanoid") then
			character:FindFirstChildOfClass("Humanoid").JumpPower = value
		end
	end,
})

local Noclip = false
local NoclipConn = nil

Character:CreateToggle({
	Name = "Noclip",
	Default = false,
	Flag = "noclip",
	Callback = function(enabled)
		Noclip = enabled
		if enabled then
			NoclipConn = game:GetService("RunService").Stepped:Connect(function()
				local character = LocalPlayer.Character
				if character then
					for _, part in character:GetDescendants() do
						if part:IsA("BasePart") then
							part.CanCollide = false
						end
					end
				end
			end)
		else
			if NoclipConn then
				NoclipConn:Disconnect()
				NoclipConn = nil
			end
		end
	end,
})

Character:CreateButton({
	Name = "Reset Character",
	Callback = function()
		LocalPlayer.Character:BreakJoints()
		Polaris:Notify({ Title = "Reset", Content = "Character reset", Duration = 3, Type = "success" })
	end,
})

----------------------------------------------------------------
-- Players tab
----------------------------------------------------------------

local PlayersTab = Window:CreateTab({ Name = "Players" })

local TargetPlayer = PlayersTab:CreateDropdown({
	Name = "Target Player",
	Options = {},
	Flag = "target",
	Callback = function(selected)
		print("Targeting:", selected)
	end,
})

-- keep the player list fresh as people join/leave
local function refreshPlayerList()
	local names = {}
	for _, player in Players:GetPlayers() do
		table.insert(names, player.Name)
	end
	TargetPlayer:Refresh(names, true)
end
refreshPlayerList()
Players.PlayerAdded:Connect(refreshPlayerList)
Players.PlayerRemoving:Connect(refreshPlayerList)

PlayersTab:CreateButton({
	Name = "Teleport To Target",
	Callback = function()
		local targetName = TargetPlayer:Get()
		if type(targetName) ~= "string" then
			Polaris:Notify({ Title = "Error", Content = "Pick a target first", Duration = 3, Type = "error" })
			return
		end
		local target = Players:FindFirstChild(targetName)
		local myChar = LocalPlayer.Character
		if target and target.Character and myChar and myChar.PrimaryPart then
			myChar:PivotTo(target.Character.HumanoidRootPart.CFrame + Vector3.new(0, 3, 0))
			Polaris:Notify({ Title = "Teleport", Content = "Warped to " .. targetName, Duration = 3, Type = "success" })
		else
			Polaris:Notify({ Title = "Error", Content = "Could not teleport", Duration = 3, Type = "error" })
		end
	end,
})

PlayersTab:CreateToggle({
	Name = "Highlight Target",
	Default = false,
	Flag = "highlight",
	Callback = function(enabled)
		for _, player in Players:GetPlayers() do
			local highlight = player.Character and player.Character:FindFirstChild("PolarisHighlight")
			if highlight then highlight:Destroy() end
		end
		if not enabled then return end
		local targetName = TargetPlayer:Get()
		local target = type(targetName) == "string" and Players:FindFirstChild(targetName)
		if target and target.Character then
			local highlight = Instance.new("Highlight")
			highlight.Name = "PolarisHighlight"
			highlight.FillColor = Color3.fromRGB(120, 130, 255)
			highlight.OutlineColor = Color3.new(1, 1, 1)
			highlight.Adornee = target.Character
			highlight.Parent = target.Character
		end
	end,
})

----------------------------------------------------------------
-- Settings tab
----------------------------------------------------------------

local Settings = Window:CreateTab({ Name = "Settings" })

Settings:CreateSection({ Name = "Appearance" })

Settings:CreateDropdown({
	Name = "Theme",
	Options = Polaris:GetThemeNames(),
	Default = "Midnight",
	Flag = "theme",
	Callback = function(theme)
		Polaris:SetTheme(theme)
	end,
})

Settings:CreateSection({ Name = "Config" })

Settings:CreateButton({
	Name = "Save Config",
	Callback = function()
		Window:SaveConfig("default")
		Polaris:Notify({ Title = "Saved", Content = "Your settings were saved", Duration = 4, Type = "success" })
	end,
})

Settings:CreateButton({
	Name = "Destroy UI",
	Callback = function()
		Window:Destroy()
	end,
})

Polaris:Notify({ Title = "Welcome", Content = "Loaded My Hub - press RightControl to toggle", Duration = 5 })
