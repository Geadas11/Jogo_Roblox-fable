--!strict
-- Server entry point. The only Script on the server: everything else is a ModuleScript
-- started from here, so the boot order is explicit and the same on every run.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Loader = require(Shared.Util.Loader)
local Log = require(Shared.Util.Log)
local SessionState = require(Shared.SessionState)
local Net = require(script.Parent.Net)

-- Boot order. A new service must be added here or it will not run
-- (the Loader warns about modules that exist but are not listed).
local SERVICE_ORDER = {
	"CollisionService",
	"EnvironmentService",
	"PlayerManager",
	"InteractionService",
	"DoorService",
	"ShiftManager",
	"GameManager",
}

local log = Log.new("Main")
local startedAt = os.clock()

-- Replicated objects first, so they exist before any client finishes loading.
SessionState.Start()
SessionState.Set("BuildVersion", GameConfig.BuildVersion)
Net.Start()

Loader.Run(script.Parent.Services, SERVICE_ORDER, log)

log:Info(
	"Server ready (build %s, %d services, %d ms)",
	GameConfig.BuildVersion,
	#SERVICE_ORDER,
	math.round((os.clock() - startedAt) * 1000)
)
