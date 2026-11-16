-- Shared.Util.Loader: boot order and failure handling.
-- Uses hand-made containers so each case can decide what a module does.

local world = Engine.new()
local Loader = world.side("server").load("ReplicatedStorage.Shared.Util.Loader")

-- Builds a Folder with one (empty) ModuleScript per entry of `modules`.
local function container(modules)
	local folder = world.newInstance("Folder", "Services")
	for name, definition in modules do
		local module = world.newInstance(definition.className or "ModuleScript", name)
		module.Parent = folder
	end
	return folder
end

local function logger()
	local warnings = {}
	return {
		Info = function() end,
		Warn = function(_self, message, ...)
			table.insert(warnings, string.format(message, ...))
		end,
	},
		warnings
end

-- The Loader calls the global `require`. Load a private copy of it whose `require`
-- returns our canned modules (or raises when asked to).
local function loaderWith(modules)
	local fs = require("@lune/fs")
	local luau = require("@lune/luau")
	local chunk = luau.load(fs.readFile("src/shared/Util/Loader.luau"), {
		debugName = "Loader",
		environment = {
			task = task,
			typeof = typeof,
			require = function(instance)
				local definition = modules[instance.Name]
				if definition.requireError then
					error(definition.requireError, 0)
				end
				return definition.value
			end,
		},
	})
	return chunk()
end

test("requires, Inits and Starts in the listed order", function()
	local events = {}
	local function module(name)
		return {
			value = {
				Init = function()
					table.insert(events, name .. ".Init")
				end,
				Start = function()
					table.insert(events, name .. ".Start")
				end,
			},
		}
	end
	local modules = { B = module("B"), A = module("A"), C = module("C") }
	local log = logger()
	local loaded = loaderWith(modules).Run(container(modules), { "C", "A", "B" }, log)
	expect.equal(table.concat(events, " "), "C.Init A.Init B.Init C.Start A.Start B.Start")
	expect.equal(loaded.A, modules.A.value)
end)

test("Init and Start are optional", function()
	local modules = { Plain = { value = {} } }
	loaderWith(modules).Run(container(modules), { "Plain" }, logger())
end)

test("a missing module aborts the boot", function()
	local modules = { A = { value = {} } }
	expect.throws(function()
		loaderWith(modules).Run(container(modules), { "A", "Ghost" }, logger())
	end, 'no ModuleScript named "Ghost"')
end)

test("something that is not a ModuleScript is not accepted", function()
	local modules = { A = { value = {}, className = "Folder" } }
	expect.throws(function()
		loaderWith(modules).Run(container(modules), { "A" }, logger())
	end, 'no ModuleScript named "A"')
end)

test("a module that fails to load aborts the boot", function()
	local modules = { A = { requireError = "syntax error" } }
	expect.throws(function()
		loaderWith(modules).Run(container(modules), { "A" }, logger())
	end, 'could not require "A": syntax error')
end)

test("a module that does not return a table aborts the boot", function()
	local modules = { A = { value = 5 } }
	expect.throws(function()
		loaderWith(modules).Run(container(modules), { "A" }, logger())
	end, "must return a table")
end)

test("a failing Init aborts the boot before anything Starts", function()
	local started = false
	local modules = {
		A = {
			value = {
				Init = function()
					error("init broke", 0)
				end,
			},
		},
		B = {
			value = {
				Start = function()
					started = true
				end,
			},
		},
	}
	expect.throws(function()
		loaderWith(modules).Run(container(modules), { "A", "B" }, logger())
	end, "A.Init failed: init broke")
	expect.falsy(started)
end)

test("a failing Start is reported and the others still run", function()
	local started = false
	local modules = {
		A = {
			value = {
				Start = function()
					error("start broke", 0)
				end,
			},
		},
		B = {
			value = {
				Start = function()
					started = true
				end,
			},
		},
	}
	local log, warnings = logger()
	loaderWith(modules).Run(container(modules), { "A", "B" }, log)
	expect.truthy(started)
	expect.anyLine(warnings, "A.Start failed: start broke")
end)

test("a Start that yields does not delay the others", function()
	local events = {}
	local modules = {
		Slow = {
			value = {
				Start = function()
					task.wait(0.05)
					table.insert(events, "slow")
				end,
			},
		},
		Fast = {
			value = {
				Start = function()
					table.insert(events, "fast")
				end,
			},
		},
	}
	loaderWith(modules).Run(container(modules), { "Slow", "Fast" }, logger())
	expect.equal(table.concat(events, ","), "fast")
	task.wait(0.1)
	expect.equal(table.concat(events, ","), "fast,slow")
end)

test("warns about a module that exists but is not in the boot order", function()
	local modules = { A = { value = {} }, Forgotten = { value = {} } }
	local log, warnings = logger()
	loaderWith(modules).Run(container(modules), { "A" }, log)
	expect.anyLine(warnings, "Forgotten exists in Services but is not in the boot order")
end)

test("a name listed twice is a mistake", function()
	local modules = { A = { value = {} } }
	expect.throws(function()
		loaderWith(modules).Run(container(modules), { "A", "A" }, logger())
	end, "listed twice")
end)
