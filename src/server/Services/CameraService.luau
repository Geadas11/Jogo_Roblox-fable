--!strict
-- The security cameras. The office computer and the monitors (tags OfficeComputer,
-- SecurityMonitor) have a "Watch cameras" prompt; using one puts the player in front of
-- the feeds from every CCTVCamera on the map (the client draws them: CctvController).
--
-- While watching, the player stands at the desk and cannot move - the monster can walk
-- right up behind them. They stop watching when they look away (the client says so),
-- when they are caught or leave, and when the shift ends.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Config.Tags)
local Log = require(Shared.Util.Log)
local Net = require(script.Parent.Parent.Net)
local GameManager = require(script.Parent.GameManager)
local InteractionService = require(script.Parent.InteractionService)

local log = Log.new("Cameras")

local CameraService = {}

-- Whether `player` is watching the cameras right now.
function CameraService.IsWatching(player: Player): boolean
	return player:GetAttribute("WatchingCameras") == true
end

function CameraService.Open(player: Player): boolean
	if CameraService.IsWatching(player) or player:GetAttribute("Status") ~= "Working" then
		return false
	end
	player:SetAttribute("WatchingCameras", true)
	Net.FireClient(player, "OpenCameras")
	return true
end

function CameraService.Close(player: Player)
	if not CameraService.IsWatching(player) then
		return
	end
	player:SetAttribute("WatchingCameras", false)
	Net.FireClient(player, "CloseCameras")
end

local function register(instance: Instance)
	local holder: BasePart? = nil
	if instance:IsA("BasePart") then
		holder = instance
	end
	if not holder then
		return
	end
	InteractionService.AddPrompt(holder, {
		action = "Watch cameras",
		object = "Security",
		distance = 7,
	}, function(player: Player)
		CameraService.Open(player)
	end)
end

function CameraService.Start()
	local count = 0
	for _, tag in { Tags.OfficeComputer, Tags.SecurityMonitor } do
		for _, instance in CollectionService:GetTagged(tag) do
			-- The wall of monitors in the office is watched from the computer below it;
			-- only the one in the employee room gets its own prompt.
			if tag == Tags.OfficeComputer or instance:GetAttribute("Zone") ~= "Office" then
				register(instance)
				count += 1
			end
		end
	end

	Net.On("LeaveCameras", function(player: Player)
		CameraService.Close(player)
	end)
	local function watch(player: Player)
		player:GetAttributeChangedSignal("Status"):Connect(function()
			if player:GetAttribute("Status") ~= "Working" then
				CameraService.Close(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase ~= "Shift" then
			for _, player in Players:GetPlayers() do
				CameraService.Close(player)
			end
		end
	end)
	log:Info("%d places to watch the cameras from", count)
end

return CameraService
