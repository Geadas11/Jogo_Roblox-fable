--!strict
-- Hiding spots (tag: HidingSpot): lockers, under the office desk, a restroom stall.
-- A hidden player is held still inside the spot and cannot be seen. The monster can
-- still open a spot it saw them enter, or one it decides to check while searching.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Config.Tags)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Net = require(script.Parent.Parent.Net)
local MapGrid = require(script.Parent.Parent.Monster.MapGrid)
local CarryService = require(script.Parent.CarryService)
local GameManager = require(script.Parent.GameManager)
local InteractionService = require(script.Parent.InteractionService)
local PlayerManager = require(script.Parent.PlayerManager)

local log = Log.new("Hiding")

-- Seconds before a player who just came out can hide again.
local REHIDE_COOLDOWN = 1.5

export type Spot = {
	Id: number,
	Part: BasePart,
	Kind: string,
	Prompt: ProximityPrompt,
	Occupant: Player?,
}

local HidingService = {}

-- Fired when a player goes in or comes out: (player, spot id or nil).
HidingService.Changed = Signal.new() :: Signal.Signal<Player, number?>

local spots: { Spot } = {}
local spotOf: { [Player]: Spot } = {}
local leftAt: { [Player]: number } = {}

local function setStatusIf(player: Player, from: string, to: string)
	if player:GetAttribute("Status") == from then
		player:SetAttribute("Status", to)
	end
end

-- Where the root part goes while hidden: inside the spot, standing or crouched.
local function insideCFrame(spot: Spot): CFrame
	local position = spot.Part.Position
	local height = if spot.Kind == "UnderDesk" then 1.6 else 3
	return CFrame.new(position.X, height, position.Z)
end

-- Somewhere walkable just outside the spot.
local function exitCFrame(spot: Spot): CFrame
	local position = spot.Part.Position
	local grid = MapGrid.Get()
	local point = if grid then grid:Nearest(position.X, position.Z, 8) else nil
	if point then
		return CFrame.new(point.x, 3, point.z)
	end
	return CFrame.new(position.X, 3, position.Z + 3)
end

-- Clears the player from their spot without moving them (caught, gone, respawned).
function HidingService.Release(player: Player)
	local spot = spotOf[player]
	if not spot then
		return
	end
	spotOf[player] = nil
	spot.Occupant = nil
	spot.Part:SetAttribute("Occupied", false)
	spot.Prompt.Enabled = true
	leftAt[player] = os.clock()
	player:SetAttribute("HidingKind", nil)
	setStatusIf(player, "Hiding", "Working")
	HidingService.Changed:Fire(player, nil)
end

function HidingService.Hide(player: Player, spot: Spot): boolean
	if spot.Occupant or spotOf[player] or player:GetAttribute("Status") ~= "Working" then
		return false
	end
	local last = leftAt[player]
	if last and os.clock() - last < REHIDE_COOLDOWN then
		return false
	end
	local root = PlayerManager.GetRoot(player)
	if not root then
		return false
	end

	-- Set down quietly: a noise here would lead the monster straight to the spot.
	CarryService.Drop(player, false, true)
	spot.Occupant = player
	spotOf[player] = spot
	spot.Part:SetAttribute("Occupied", true)
	spot.Prompt.Enabled = false
	root.Anchored = true
	root.CFrame = insideCFrame(spot)
	-- What the client draws over the view: locker vents, the desk above, a stall door.
	player:SetAttribute("HidingKind", spot.Kind)
	player:SetAttribute("Status", "Hiding")
	HidingService.Changed:Fire(player, spot.Id)
	return true
end

-- Steps out of the spot.
function HidingService.Leave(player: Player): boolean
	local spot = spotOf[player]
	if not spot then
		return false
	end
	HidingService.Release(player)
	local root = PlayerManager.GetRoot(player)
	if root then
		root.CFrame = exitCFrame(spot)
		root.Anchored = false
	end
	return true
end

function HidingService.GetSpots(): { Spot }
	return spots
end

function HidingService.SpotIdOf(player: Player): number?
	local spot = spotOf[player]
	return if spot then spot.Id else nil
end

function HidingService.OccupantOf(id: number): Player?
	local spot = spots[id]
	return if spot then spot.Occupant else nil
end

function HidingService.Init()
	Net.On("LeaveHiding", function(player: Player)
		HidingService.Leave(player)
	end)
end

function HidingService.Start()
	-- Ids follow positions, so the same map always numbers its spots the same way.
	local parts = {}
	for _, instance in CollectionService:GetTagged(Tags.HidingSpot) do
		if instance:IsA("BasePart") then
			table.insert(parts, instance)
		end
	end
	table.sort(parts, function(a: BasePart, b: BasePart)
		if a.Position.X ~= b.Position.X then
			return a.Position.X < b.Position.X
		end
		return a.Position.Z < b.Position.Z
	end)

	for index, part in parts do
		local spot: Spot
		local prompt = InteractionService.AddPrompt(part, {
			action = "Hide",
			object = if part:GetAttribute("Kind") == "UnderDesk" then "Under the desk" else "",
			hold = 0.4,
			distance = 7,
		}, function(player: Player)
			HidingService.Hide(player, spot)
		end)
		spot = {
			Id = index,
			Part = part,
			Kind = tostring(part:GetAttribute("Kind") or "Locker"),
			Prompt = prompt,
			Occupant = nil,
		}
		part:SetAttribute("Occupied", false)
		table.insert(spots, spot)
	end
	log:Info("%d hiding spots", #spots)

	PlayerManager.PlayerLeft:Connect(function(player: Player)
		HidingService.Release(player)
		leftAt[player] = nil
	end)
	-- Back in the lobby nobody needs to hide.
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase == "Lobby" then
			for _, player in Players:GetPlayers() do
				HidingService.Leave(player)
			end
		end
	end)
end

return HidingService
