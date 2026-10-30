-- hub scripts: ready-made, harmless client-side scripts so the library is a real script hub the moment
-- it opens.  Everything here only changes YOUR OWN camera, lighting and screen, or shows information.
-- None of it touches other players or the game's data.  Untested in a real Roblox client (see GUIDE.md).

local Util = Polaris.Util

local function svc(name)
	return Util.svc(name)
end

local function note(title, text, kind)
	Polaris:Notify({ Title = title, Content = text, Type = kind or "info", Duration = 3.5 })
end

local saved = {} -- remembered values so a second run can undo the change

function Polaris.HubScripts()
	return {
		{
			Name = "Fullbright", Description = "Brightens a dark game. Run again to put it back.", Tags = { "look", "lighting" },
			Run = function()
				local L = svc("Lighting")
				if saved.Fullbright then
					for k, v in saved.Fullbright do
						L[k] = v
					end
					saved.Fullbright = nil
					return note("Fullbright", "Back to normal.")
				end
				saved.Fullbright = { Brightness = L.Brightness, ClockTime = L.ClockTime, FogEnd = L.FogEnd, GlobalShadows = L.GlobalShadows, Ambient = L.Ambient }
				L.Brightness, L.ClockTime, L.FogEnd, L.GlobalShadows = 2, 14, 100000, false
				L.Ambient = Color3.fromRGB(170, 170, 170)
				note("Fullbright", "Lights on. Run it again to undo.", "success")
			end,
		},
		{
			Name = "Wide view", Description = "Field of view 100 for a wider picture. Run again for normal.", Tags = { "look", "camera" },
			Run = function()
				local cam = workspace.CurrentCamera
				if saved.Fov then
					cam.FieldOfView = saved.Fov
					saved.Fov = nil
					return note("Wide view", "Back to normal.")
				end
				saved.Fov = cam.FieldOfView
				cam.FieldOfView = 100
				note("Wide view", "Field of view is 100.", "success")
			end,
		},
		{
			Name = "Day or night", Description = "Flips your sky between midday and midnight, just for you.", Tags = { "look", "lighting" },
			Run = function()
				local L = svc("Lighting")
				local night = (L.ClockTime < 6 or L.ClockTime > 18)
				L.ClockTime = night and 14 or 0
				note("Day or night", night and "It is midday." or "It is midnight.")
			end,
		},
		{
			Name = "FPS counter", Description = "A small frames-per-second number in the corner. Run again to hide it.", Tags = { "info", "tools" },
			Run = function()
				if saved.FpsGui then
					pcall(function()
						saved.FpsConn:Disconnect()
					end)
					saved.FpsGui:Destroy()
					saved.FpsGui, saved.FpsConn = nil, nil
					return note("FPS counter", "Hidden.")
				end
				local gui = Instance.new("ScreenGui")
				gui.Name = "PolarisFps"
				gui.ResetOnSpawn = false
				gui.Parent = I.getGuiParent()
				local label = Instance.new("TextLabel")
				label.Size = UDim2.new(0, 90, 0, 26)
				label.Position = UDim2.new(1, -100, 0, 8)
				label.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
				label.BackgroundTransparency = 0.25
				label.TextColor3 = Color3.fromRGB(120, 255, 160)
				label.TextSize = 16
				label.Text = "FPS ..."
				label.Parent = gui
				local frames, last = 0, os.clock()
				saved.FpsGui = gui
				saved.FpsConn = svc("RunService").Heartbeat:Connect(function()
					frames += 1
					local now = os.clock()
					if now - last >= 0.5 then
						label.Text = "FPS " .. math.floor(frames / (now - last) + 0.5)
						frames, last = 0, now
					end
				end)
			end,
		},
		{
			Name = "Server info", Description = "Shows the place id, player count and server id.", Tags = { "info" },
			Run = function()
				local ok, players = pcall(function()
					return #svc("Players"):GetPlayers()
				end)
				local id = tostring(game.JobId or "")
				local job = id ~= "" and id:sub(1, 8) or "studio"
				note("Server info", "Place " .. tostring(game.PlaceId) .. "  |  Players " .. tostring(ok and players or "?") .. "  |  Server " .. job)
			end,
		},
		{
			Name = "Copy game link", Description = "Copies this game's Roblox page link so you can share it.", Tags = { "info", "tools" },
			Run = function()
				local link = "https://www.roblox.com/games/" .. tostring(game.PlaceId)
				if I.copyText(link) then
					note("Copied", link, "success")
				else
					note("Could not copy", "This place has no clipboard. The link is " .. link, "warning")
				end
			end,
		},
		{
			Name = "Hide chat", Description = "Hides or shows the chat window. Run again to flip it.", Tags = { "screen" },
			Run = function()
				local sg = svc("StarterGui")
				saved.ChatHidden = not saved.ChatHidden
				sg:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, not saved.ChatHidden)
				note("Chat", saved.ChatHidden and "Hidden." or "Showing.")
			end,
		},
		{
			Name = "Rejoin this server", Description = "Leaves and joins the same server again.", Tags = { "tools" },
			Run = function()
				local ok, err = pcall(function()
					svc("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, I.LocalPlayer)
				end)
				if not ok then
					error("Could not rejoin: " .. tostring(err), 0)
				end
			end,
		},
	}
end
