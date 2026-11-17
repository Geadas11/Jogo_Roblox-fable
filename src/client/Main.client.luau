--!strict
-- Client entry point. The only LocalScript: every controller is a ModuleScript started
-- from here, in an explicit order.

-- Wait for the initial replication so everything under ReplicatedStorage exists.
if not game:IsLoaded() then
	game.Loaded:Wait()
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Loader = require(Shared.Util.Loader)
local Log = require(Shared.Util.Log)
local SessionState = require(Shared.SessionState)
local Net = require(script.Parent.Net)

-- Boot order. A new controller must be added here or it will not run.
local CONTROLLER_ORDER = {
	"CameraController",
	"HudController",
	"ObjectivesController",
	"SurvivalController",
	"MonsterController",
	"LightingController",
}

local log = Log.new("Main")

SessionState.Start()
Net.Start()

Loader.Run(script.Parent.Controllers, CONTROLLER_ORDER, log)

-- Tell the server this client is loaded and listening.
Net.FireServer("ClientReady")

log:Info("Client ready (build %s, %d controllers)", SessionState.Get("BuildVersion"), #CONTROLLER_ORDER)
