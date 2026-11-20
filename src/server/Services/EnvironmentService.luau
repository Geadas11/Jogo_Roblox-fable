--!strict
-- Puts the world into its baseline state at boot:
--   * applies the base lighting profile from Config.LightingConfig
--   * reports place settings that cannot be set from code and do not match the design
--
-- Lighting is fully config-driven at runtime. Whatever is saved in the place file is
-- overridden while the game runs (nothing is written back to the file), so the look
-- does not depend on what a Studio template happened to contain.

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local LightingConfig = require(Shared.Config.LightingConfig)
local Log = require(Shared.Util.Log)

local log = Log.new("Environment")

local EnvironmentService = {}

-- Sets each property on its own, so one that cannot be written (renamed by a Roblox
-- update, or not scriptable) is reported instead of aborting the rest.
local function applyProperties(instance: Instance, properties: { [string]: any })
	for name, value in properties do
		-- Some properties (LightingStyle, PrioritizeLightingQuality) can only be written
		-- by Studio, not by a game script. When the place already has the right value
		-- there is nothing to write; reportPlaceSettings warns when it does not.
		local readOk, current = pcall(function()
			return (instance :: any)[name]
		end)
		if readOk and current == value then
			continue
		end
		local ok, message = pcall(function()
			(instance :: any)[name] = value
		end)
		if not ok then
			log:Warn("Could not set %s.%s: %s", instance:GetFullName(), name, tostring(message))
		end
	end
end

local function applyLightingProfile(profile: LightingConfig.Profile)
	applyProperties(Lighting, profile.Lighting)

	-- Instances this profile owns. Reuse one of the right class when it already exists
	-- (Studio templates ship with their own Atmosphere / Bloom) rather than stacking a
	-- second one on top.
	local managed: { [Instance]: boolean } = {}
	for _, spec in profile.Children do
		local child: Instance = Lighting:FindFirstChildOfClass(spec.ClassName) or Instance.new(spec.ClassName)
		child.Name = spec.Name
		applyProperties(child, spec.Properties)
		child.Parent = Lighting
		managed[child] = true
	end

	-- Any other post-processing effect left in Lighting would alter the look in ways
	-- the config does not describe. Switch it off for this session and say so.
	for _, child in Lighting:GetChildren() do
		if child:IsA("PostEffect") and not managed[child] and child.Enabled then
			child.Enabled = false
			log:Info("Disabled %s (%s): not part of the lighting profile", child.Name, child.ClassName)
		end
	end
end

local function reportPlaceSettings()
	-- Lighting style cannot be guaranteed from code on every platform; verify it stuck.
	local wantedStyle = LightingConfig.Base.Lighting.LightingStyle
	if wantedStyle ~= nil and Lighting.LightingStyle ~= wantedStyle then
		log:Warn(
			"Lighting.LightingStyle is %s, expected %s. Set it in Studio: Explorer > Lighting > Properties.",
			Lighting.LightingStyle.Name,
			wantedStyle.Name
		)
	end

	if Players.MaxPlayers ~= GameConfig.MaxPlayers then
		local message = "Server size is %d players, the game is designed for %d. "
			.. "Change it in Studio: Game Settings > Places (requires a published place)."
		if RunService:IsStudio() then
			log:Info(message, Players.MaxPlayers, GameConfig.MaxPlayers)
		else
			log:Warn(message, Players.MaxPlayers, GameConfig.MaxPlayers)
		end
	end
end

function EnvironmentService.Init()
	applyLightingProfile(LightingConfig.Base)
end

function EnvironmentService.Start()
	reportPlaceSettings()
end

return EnvironmentService
