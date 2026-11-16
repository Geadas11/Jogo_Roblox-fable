--!strict
-- Client side of the network layer. Controllers never touch remotes directly.
--
--   Net.FireServer("ClientReady")                 -- client -> server event
--   local ok, a, b = Net.InvokeServer("Query", x) -- client -> server function (yields)
--   Net.On("SomeEvent", function(...) ... end)    -- server -> client event
--
-- Arguments are checked against the same validators the server uses before sending.
-- That is a development aid only (it turns our own mistakes into immediate errors);
-- the server never relies on it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Check = require(Shared.Net.Check)
local Definitions = require(Shared.Net.Definitions)
local GameConfig = require(Shared.Config.GameConfig)

local Net = {}

local started = false
local eventRemotes: { [string]: RemoteEvent } = {}
local functionRemotes: { [string]: RemoteFunction } = {}

local function getDefinition(name: string, kind: string, from: string)
	local definition = Definitions[name]
	if not definition then
		error(string.format("Net: %q is not declared in Shared.Net.Definitions", name), 3)
	end
	if definition.kind ~= kind or definition.from ~= from then
		error(
			string.format(
				"Net: %q is a %s sent by the %s, it cannot be used as a %s sent by the %s",
				name,
				definition.kind,
				definition.from,
				kind,
				from
			),
			3
		)
	end
	return definition
end

local function waitForChild(parent: Instance, name: string): Instance
	local timeout = GameConfig.Boot.ReplicationTimeout
	local child = parent:WaitForChild(name, timeout)
	if not child then
		error(
			string.format(
				"Net: %s.%s did not appear within %d s. Did the server script fail to start?",
				parent:GetFullName(),
				name,
				timeout
			),
			0
		)
	end
	return child
end

-- Waits for the remotes created by the server. Called once by the client entry point.
function Net.Start()
	assert(not started, "Net.Start called twice")
	started = true

	local root = waitForChild(ReplicatedStorage, "Remotes")
	local eventsFolder = waitForChild(root, "Events")
	local functionsFolder = waitForChild(root, "Functions")

	for name, definition in Definitions do
		if definition.kind == "Event" then
			eventRemotes[name] = waitForChild(eventsFolder, name) :: RemoteEvent
		else
			functionRemotes[name] = waitForChild(functionsFolder, name) :: RemoteFunction
		end
	end
end

function Net.FireServer(name: string, ...: any)
	local definition = getDefinition(name, "Event", "Client")
	local remote = eventRemotes[name]
	assert(remote, "Net.FireServer called before Net.Start")

	local ok, reason = Check.args(definition.args, ...)
	if not ok then
		error(string.format("Net: invalid arguments for %q: %s", name, reason or "invalid"), 2)
	end
	remote:FireServer(...)
end

-- Yields until the server answers. Returns `true, ...results` on success, or
-- `false, code` when the call was rejected, failed, or the connection dropped.
function Net.InvokeServer(name: string, ...: any): (boolean, ...any)
	local definition = getDefinition(name, "Function", "Client")
	local remote = functionRemotes[name]
	assert(remote, "Net.InvokeServer called before Net.Start")

	local ok, reason = Check.args(definition.args, ...)
	if not ok then
		error(string.format("Net: invalid arguments for %q: %s", name, reason or "invalid"), 2)
	end

	local results = table.pack(pcall(remote.InvokeServer, remote, ...))
	if not results[1] then
		return false, "invoke failed"
	end
	if results[2] ~= true then
		return false, results[3]
	end
	return table.unpack(results, 2, results.n)
end

-- Listens to a server -> client event.
function Net.On(name: string, handler: (...any) -> ()): RBXScriptConnection
	getDefinition(name, "Event", "Server")
	local remote = eventRemotes[name]
	assert(remote, "Net.On called before Net.Start")
	return remote.OnClientEvent:Connect(handler)
end

return Net
