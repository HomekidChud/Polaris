--[[
	Polaris Builder launcher
	------------------------
	Run this script on its own to open the Polaris Builder:
	an animated splash, then a visual editor where you assemble
	your own hub out of blocks and export a ready-to-paste script.

	Executor:
		loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Builder.luau"))()

	Studio: require the Polaris ModuleScript, then call
		Polaris.Builder:Open()
]]

local Polaris = loadstring(game:HttpGet("https://raw.githubusercontent.com/HomekidChud/Polaris/main/Polaris.luau"))()
Polaris.Builder:Open()
