--[[
	Test runner. From the repository root:

		lune run tests/run

	1. Compiles every .luau file under src/ (catches syntax errors).
	2. Runs every tests/specs/*.spec.luau against the fake engine in tests/engine.luau.

	Exit code 0 means every check passed. See tests/engine.luau for what this does and
	does not prove.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local task = require("@lune/task")

local Engine = require("./engine")

local failures = {}
local passed = 0

local function fail(name, message)
	table.insert(failures, { name = name, message = message })
	print(string.format("%sFAIL%s %s\n     %s", stdio.color("red"), stdio.color("reset"), name, message))
end

-- 1. Compile ---------------------------------------------------------------------------

local function collect(directory, into)
	for _, entry in fs.readDir(directory) do
		local path = directory .. "/" .. entry
		if fs.isDir(path) then
			collect(path, into)
		elseif string.match(entry, "%.luau$") then
			table.insert(into, path)
		end
	end
	return into
end

local sources = collect("src", {})
table.sort(sources)
for _, path in sources do
	local ok, message = pcall(luau.compile, fs.readFile(path))
	if ok then
		passed += 1
	else
		fail("compile " .. path, tostring(message))
	end
end
print(string.format("Compiled %d source files", #sources))

-- 2. Specs -----------------------------------------------------------------------------

local expect = {}

local function describe(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end
	return tostring(value)
end

function expect.equal(actual, expected, label)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				if label then label .. ": " else "",
				describe(expected),
				describe(actual)
			),
			2
		)
	end
end

function expect.truthy(value, label)
	if not value then
		error(
			string.format(
				"%sexpected a truthy value, got %s",
				if label then label .. ": " else "",
				describe(value)
			),
			2
		)
	end
end

function expect.falsy(value, label)
	if value then
		error(
			string.format(
				"%sexpected a falsy value, got %s",
				if label then label .. ": " else "",
				describe(value)
			),
			2
		)
	end
end

-- Asserts that `callback` raises an error whose message contains `fragment`.
function expect.throws(callback, fragment)
	local ok, message = pcall(callback)
	if ok then
		error("expected an error, but the call succeeded", 2)
	end
	if fragment and not string.find(tostring(message), fragment, 1, true) then
		error(string.format("expected an error containing %q, got %q", fragment, tostring(message)), 2)
	end
end

-- Asserts that some line in `lines` contains `fragment`.
function expect.anyLine(lines, fragment)
	for _, line in lines do
		if string.find(line, fragment, 1, true) then
			return
		end
	end
	error(
		string.format("no line contains %q. Lines:\n       %s", fragment, table.concat(lines, "\n       ")),
		2
	)
end

local specDirectory = "tests/specs"
local specs = {}
for _, entry in fs.readDir(specDirectory) do
	if string.match(entry, "%.spec%.luau$") then
		table.insert(specs, entry)
	end
end
table.sort(specs)

for _, entry in specs do
	local tests = {}
	local environment = {
		Engine = Engine,
		expect = expect,
		task = task,
		test = function(name, callback)
			table.insert(tests, { name = name, callback = callback })
		end,
	}

	local path = specDirectory .. "/" .. entry
	local loaded, loadError = pcall(function()
		luau.load(fs.readFile(path), { debugName = path, environment = environment })()
	end)
	if not loaded then
		fail(entry, "could not load spec: " .. tostring(loadError))
		continue
	end

	for _, case in tests do
		local name = string.gsub(entry, "%.spec%.luau$", "") .. " > " .. case.name
		local ok, message = xpcall(case.callback, function(err)
			return tostring(err)
		end)
		if ok then
			passed += 1
		else
			fail(name, message)
		end
	end
end

print("")
if #failures > 0 then
	print(
		string.format("%s%d failed%s, %d passed", stdio.color("red"), #failures, stdio.color("reset"), passed)
	)
	process.exit(1)
end
print(string.format("%sAll %d checks passed%s", stdio.color("green"), passed, stdio.color("reset")))
-- Exit explicitly: one spec deliberately lets a handler fail in a background thread,
-- which Lune would otherwise report as a non-zero exit code.
process.exit(0)
