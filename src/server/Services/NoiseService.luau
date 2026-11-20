--!strict
-- Turns what players do into noises the monster can hear: running, slamming doors,
-- dropping what they carry. Walking is silent.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Signal = require(Shared.Util.Signal)
local CarryService = require(script.Parent.CarryService)
local DoorService = require(script.Parent.DoorService)
local PlayerManager = require(script.Parent.PlayerManager)

local NoiseService = {}

-- Fired for every noise: (position, how far it carries, what made it).
NoiseService.Heard = Signal.new() :: Signal.Signal<Vector3, number, string>

-- Horizontal speed above which a player counts as running.
local RUNNING_SPEED = (MonsterConfig.Player.WalkSpeed + MonsterConfig.Player.RunSpeed) / 2

function NoiseService.Emit(position: Vector3, radius: number, source: string)
	NoiseService.Heard:Fire(position, radius, source)
end

-- Whether a player is moving at running speed right now.
function NoiseService.IsRunning(player: Player): boolean
	local root = PlayerManager.GetRoot(player)
	if not root or root.Anchored then
		return false
	end
	local velocity = root.AssemblyLinearVelocity
	return Vector3.new(velocity.X, 0, velocity.Z).Magnitude > RUNNING_SPEED
end

-- Checks every player once; called twice a second by the loop in Start.
function NoiseService.SampleFootsteps()
	for _, player in PlayerManager.GetReadyPlayers() do
		if NoiseService.IsRunning(player) then
			local root = PlayerManager.GetRoot(player) :: BasePart
			NoiseService.Emit(root.Position, MonsterConfig.Noise.Running, "Running")
		end
	end
end

function NoiseService.Start()
	DoorService.DoorMoved:Connect(function(door: BasePart, _open: boolean, player: Player?)
		if player then
			NoiseService.Emit(door.Position, MonsterConfig.Noise.Door, "Door")
		end
	end)
	CarryService.Dropped:Connect(function(_player: Player, item: BasePart, _kind: string, noisy: boolean)
		-- Setting something down to hide, or losing it when caught, is not a noise.
		if noisy then
			NoiseService.Emit(item.Position, MonsterConfig.Noise.DropItem, "Drop")
		end
	end)

	while true do
		task.wait(0.5)
		NoiseService.SampleFootsteps()
	end
end

return NoiseService
