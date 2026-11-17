--!strict
-- Session-wide state that every client must always agree on, stored as Attributes on
-- a single Folder (ReplicatedStorage.State).
--
-- Why Attributes: they replicate on their own and a player who joins late receives the
-- current values with the folder, so there is no "catch-up" code to write or get wrong.
-- Only the server writes; clients read and observe.
--
-- Use this for small scalar facts about the session (phase, hour, ...). Lists and
-- per-player data travel through Net instead.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.Config.GameConfig)

local FOLDER_NAME = "State"

type KeySpec = {
	default: any,
	-- When present, the value must be one of these.
	allowed: { any }?,
}

-- Every key must be declared here with its default. Add keys as systems need them.
local KEYS: { [string]: KeySpec } = {
	-- Copied from GameConfig by the server at boot.
	BuildVersion = { default = "" },
	-- Where the session is in its loop. Driven by GameManager.
	Phase = { default = "Lobby", allowed = { "Lobby", "Shift", "Results" } },
	-- Current hour of the shift: 0 = 12 AM ... 6 = 6 AM (shift over). Driven by ShiftManager.
	Hour = { default = 0 },
	-- Workspace:GetServerTimeNow() at the moment the shift began, and the real seconds
	-- one in-game hour lasts. Together they let every client draw the same clock.
	ShiftStartTime = { default = 0 },
	HourDuration = { default = 240 },
	-- Electricity, driven by PowerManager. One key per circuit in Config.PowerConfig.
	PowerShop = { default = true },
	PowerBackOfHouse = { default = true },
	PowerCold = { default = true },
	PowerStaff = { default = true },
	PowerExterior = { default = true },
	Generator = { default = true },
}

local SessionState = {}

local folder: Instance? = nil

local function getFolder(): Instance
	if not folder then
		error("SessionState used before SessionState.Start()", 3)
	end
	return folder
end

local function getSpec(key: string): KeySpec
	local spec = KEYS[key]
	if not spec then
		error(string.format("SessionState: unknown key %q", key), 3)
	end
	return spec
end

-- Server: creates the folder with every default. Client: waits for it to replicate.
-- Called once by each entry point.
function SessionState.Start()
	assert(not folder, "SessionState.Start called twice")

	if RunService:IsServer() then
		local created = Instance.new("Folder")
		created.Name = FOLDER_NAME
		for key, spec in KEYS do
			created:SetAttribute(key, spec.default)
		end
		created.Parent = ReplicatedStorage
		folder = created
	else
		local timeout = GameConfig.Boot.ReplicationTimeout
		local found = ReplicatedStorage:WaitForChild(FOLDER_NAME, timeout)
		if not found then
			error(
				string.format(
					"SessionState: ReplicatedStorage.%s did not appear within %d s. Did the server script fail to start?",
					FOLDER_NAME,
					timeout
				),
				0
			)
		end
		folder = found
	end
end

function SessionState.Get(key: string): any
	local spec = getSpec(key)
	local value = getFolder():GetAttribute(key)
	if value == nil then
		return spec.default
	end
	return value
end

-- Server only.
function SessionState.Set(key: string, value: any)
	assert(RunService:IsServer(), "SessionState.Set can only be called on the server")
	local spec = getSpec(key)

	if typeof(value) ~= typeof(spec.default) then
		error(
			string.format("SessionState: %q expects a %s, got %s", key, typeof(spec.default), typeof(value)),
			2
		)
	end
	if spec.allowed and not table.find(spec.allowed, value) then
		error(string.format("SessionState: %q cannot be set to %q", key, tostring(value)), 2)
	end

	getFolder():SetAttribute(key, value)
end

-- Calls `callback` with the current value right away, then again on every change.
function SessionState.Observe(key: string, callback: (value: any) -> ()): RBXScriptConnection
	getSpec(key)
	local target = getFolder()
	local connection = target:GetAttributeChangedSignal(key):Connect(function()
		callback(SessionState.Get(key))
	end)
	task.spawn(callback, SessionState.Get(key))
	return connection
end

return SessionState
