--!strict
-- Server side of the network layer. The ONLY place that creates remotes or listens
-- to them directly.
--
-- Every call coming from a client goes through the Gate (known remote, rate limit,
-- argument validation) before a handler runs. Handlers therefore receive well-formed
-- arguments, but must still decide whether the request is legitimate for that player
-- right now (distance, state, cooldown...).
--
-- Usage from a service:
--   Net.On("ClientReady", function(player) ... end)      -- client -> server event
--   Net.Handle("SomeQuery", function(player, ...) ... end) -- client -> server function
--   Net.FireClient(player, "SomeEvent", ...)               -- server -> one client
--   Net.FireAllClients("SomeEvent", ...)                   -- server -> everyone

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local Definitions = require(Shared.Net.Definitions)
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local Gate = require(script.Gate)

local log = Log.new("Net")

type EventHandler = (player: Player, ...any) -> ()
type FunctionHandler = (player: Player, ...any) -> ...any

local Net = {}

local started = false
local gate: Gate.Gate? = nil
local eventRemotes: { [string]: RemoteEvent } = {}
local eventHandlers: { [string]: EventHandler } = {}
local functionHandlers: { [string]: FunctionHandler } = {}
local lastViolationLogAt: { [Player]: number } = {}

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

-- Logs a rejected call, at most once per ViolationLogInterval for each player.
local function reportViolation(player: Player, name: string, reason: string?)
	local now = os.clock()
	local last = lastViolationLogAt[player]
	if last and now - last < GameConfig.Net.ViolationLogInterval then
		return
	end
	lastViolationLogAt[player] = now

	local total = if gate then gate:Violations(player) else 0
	log:Warn(
		"Rejected %s from %s (%d): %s. Rejected calls from this player so far: %d",
		name,
		player.Name,
		player.UserId,
		reason or "invalid",
		total
	)
end

-- Returns true when the call may reach its handler.
local function admit(player: Player, name: string, ...: any): boolean
	if not gate then
		return false
	end
	local ok, reason = gate:Admit(player, name, ...)
	if not ok then
		reportViolation(player, name, reason)
	end
	return ok
end

-- Creates every remote declared in Definitions. Called once by the server entry point,
-- before any service is initialised.
function Net.Start()
	assert(RunService:IsServer(), "Server Net module required on the client")
	assert(not started, "Net.Start called twice")
	started = true
	gate = Gate.new(Definitions)

	local root = Instance.new("Folder")
	root.Name = "Remotes"
	local eventsFolder = Instance.new("Folder")
	eventsFolder.Name = "Events"
	eventsFolder.Parent = root
	local functionsFolder = Instance.new("Folder")
	functionsFolder.Name = "Functions"
	functionsFolder.Parent = root

	for name, definition in Definitions do
		if definition.kind == "Event" then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = eventsFolder
			eventRemotes[name] = remote

			-- Listen even on server -> client events: a client firing one is rejected
			-- and counted here instead of piling up in the engine's unhandled queue.
			remote.OnServerEvent:Connect(function(player: Player, ...: any)
				if not admit(player, name, ...) then
					return
				end
				local handler = eventHandlers[name]
				if handler then
					handler(player, ...)
				end
			end)
		else
			local remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = functionsFolder

			-- Every function answers `(ok, ...)`. On failure the second value is a
			-- short code; internal error text is never sent to the client.
			remote.OnServerInvoke = function(player: Player, ...: any): ...any
				if not admit(player, name, ...) then
					return false, "rejected"
				end
				local handler = functionHandlers[name]
				if not handler then
					return false, "unavailable"
				end
				local results = table.pack(pcall(handler, player, ...))
				if not results[1] then
					log:Warn("Handler for %s failed: %s", name, tostring(results[2]))
					return false, "error"
				end
				return table.unpack(results, 1, results.n)
			end
		end
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		lastViolationLogAt[player] = nil
		if gate then
			gate:Forget(player)
		end
	end)

	-- Parent last so clients receive the complete set at once.
	root.Parent = ReplicatedStorage
end

-- Binds the handler for a client -> server event. One handler per event.
function Net.On(name: string, handler: EventHandler)
	getDefinition(name, "Event", "Client")
	if eventHandlers[name] then
		error(string.format("Net: %q already has a handler", name), 2)
	end
	eventHandlers[name] = handler
end

-- Binds the handler for a client -> server function. One handler per function.
-- Whatever the handler returns is sent back to the client after a leading `true`.
function Net.Handle(name: string, handler: FunctionHandler)
	getDefinition(name, "Function", "Client")
	if functionHandlers[name] then
		error(string.format("Net: %q already has a handler", name), 2)
	end
	functionHandlers[name] = handler
end

function Net.FireClient(player: Player, name: string, ...: any)
	getDefinition(name, "Event", "Server")
	local remote = eventRemotes[name]
	assert(remote, "Net.FireClient called before Net.Start")
	remote:FireClient(player, ...)
end

function Net.FireAllClients(name: string, ...: any)
	getDefinition(name, "Event", "Server")
	local remote = eventRemotes[name]
	assert(remote, "Net.FireAllClients called before Net.Start")
	remote:FireAllClients(...)
end

return Net
