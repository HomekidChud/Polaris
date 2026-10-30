-- Shared loader for the v2 test files: loads src/Polaris.luau into the mocked Roblox environment.
local luau = require("@lune/luau")
local fs = require("@lune/fs")
local process = require("@lune/process")
local mock = require("./mock")

local H = {}

function H.load(path, envTweaks)
	local source = fs.readFile(path or process.args[1] or "src/Polaris.luau")
	local env = mock.buildEnv()
	setmetatable(env, { __index = _G })
	env.task = require("@lune/task")
	env.os = os
	env.utf8 = utf8
	if envTweaks then
		envTweaks(env)
	end
	local chunk = luau.load(source, { debugName = "Polaris.luau", environment = env })
	return chunk(), env, source
end

local passed, failed, failures = 0, 0, {}
function H.check(name, fn)
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print(("PASS  %s"):format(name))
	else
		failed += 1
		table.insert(failures, { name = name, err = tostring(err) })
		print(("FAIL  %s\n        %s"):format(name, tostring(err)))
	end
end
function H.expectError(fn)
	local ok, err = pcall(fn)
	assert(not ok, "expected an error, but none was raised")
	return err
end
function H.finish()
	print(("\n%d passed, %d failed"):format(passed, failed))
	if failed > 0 then
		for _, f in failures do
			print("  FAIL: " .. f.name .. " -> " .. f.err)
		end
		process.exit(1)
	end
	process.exit(0) -- background widgets (live stats) keep timers alive
end
return H
