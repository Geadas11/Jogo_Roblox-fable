--!strict
-- Shows new players the way: a trail on the floor (drawn by the client's GuideController)
-- along the walkable route to their next step. Before the shift, after 30 seconds without
-- anyone clocking in, to the time clock. During it, in the cleaning and trash jobs:
--
--   spills to clean, empty-handed   -> the nearest free broom (maintenance room)
--   carrying a broom                -> the nearest spill
--   bags to take out, empty-handed  -> the nearest bag
--   carrying a bag                  -> the nearest dumpster, out the back
--
-- The route comes from the same walking grid the monster uses (MapGrid), which knows the
-- way through every doorway. Recomputed every second for each player who is working.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Config.Tags)
local Net = require(script.Parent.Parent.Net)
local MapGrid = require(script.Parent.Parent.Monster.MapGrid)
local CarryService = require(script.Parent.CarryService)
local GameManager = require(script.Parent.GameManager)
local PlayerManager = require(script.Parent.PlayerManager)

local GuideService = {}

-- Seconds between updates.
local INTERVAL = 1
-- Closer than this to the target, the trail goes away (you are there).
local ARRIVED = 4

-- Before the shift: a player who has been in the store this long without anyone clocking
-- in is shown the way to the time clock (and told once what to do).
local CLOCK_HINT_AFTER = 30

-- What each player was last sent, so an unchanged "nothing" is not sent every second.
local sentEmpty: { [Player]: boolean } = {}
-- When each player's character appeared, and whether they were told about the clock.
local arrivedAt: { [Player]: number } = {}
local toldClock: { [Player]: boolean } = {}

local function timeClock(position: Vector3): Vector3?
	local clocks = {}
	for _, clock in CollectionService:GetTagged(Tags.TimeClock) do
		if clock:IsA("BasePart") then
			table.insert(clocks, clock)
		end
	end
	local best, bestDistance = nil, math.huge
	for _, clock in clocks do
		local distance = (clock.Position - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = clock, distance
		end
	end
	return if best then best.Position else nil
end

local function nearest(position: Vector3, candidates: { BasePart }): BasePart?
	local best, bestDistance = nil, math.huge
	for _, part in candidates do
		local distance = (part.Position - position).Magnitude
		if distance < bestDistance then
			best, bestDistance = part, distance
		end
	end
	return best
end

-- Loose items of one kind in the world (not in anybody's hands).
local function loose(name: string): { BasePart }
	local list = {}
	for _, child in Workspace:GetChildren() do
		if child.Name == name and child:IsA("BasePart") and child:GetAttribute("CarriedBy") == nil then
			table.insert(list, child)
		end
	end
	return list
end

-- Where this player should head next, or nil.
function GuideService.TargetFor(player: Player): Vector3?
	local root = PlayerManager.GetRoot(player)
	if not root then
		return nil
	end
	-- Waiting for the shift to start: after a while, the way to the time clock.
	if GameManager.GetPhase() == "Lobby" then
		local since = arrivedAt[player]
		if since and os.clock() - since >= CLOCK_HINT_AFTER then
			return timeClock(root.Position)
		end
		return nil
	end
	local carrying = CarryService.GetKind(player)
	local spills = loose("Spill")
	if carrying == "Mop" then
		local spill = nearest(root.Position, spills)
		return if spill then spill.Position else nil
	elseif carrying == "Trash" then
		local bins = {}
		for _, bin in CollectionService:GetTagged(Tags.Dumpster) do
			if bin:IsA("BasePart") then
				table.insert(bins, bin)
			end
		end
		local bin = nearest(root.Position, bins)
		return if bin then bin.Position else nil
	elseif carrying == nil then
		if #spills > 0 then
			local broom = nearest(root.Position, loose("Mop"))
			if broom then
				return broom.Position
			end
		end
		local bag = nearest(root.Position, loose("TrashBag"))
		return if bag then bag.Position else nil
	end
	return nil
end

-- The route for one player as a flat list { x1, z1, x2, z2, ... } (empty for none).
function GuideService.RouteFor(player: Player): { number }
	local root = PlayerManager.GetRoot(player)
	local target = GuideService.TargetFor(player)
	local grid = MapGrid.Get()
	if not root or not target or not grid then
		return {}
	end
	local from = root.Position
	if Vector3.new(target.X - from.X, 0, target.Z - from.Z).Magnitude < ARRIVED then
		return {}
	end
	local path = grid:FindPath(from.X, from.Z, target.X, target.Z)
	if not path then
		return {}
	end
	local flat = { from.X, from.Z }
	for _, point in path do
		table.insert(flat, point.x)
		table.insert(flat, point.z)
	end
	return flat
end

local function update()
	local phase = GameManager.GetPhase()
	for _, player in Players:GetPlayers() do
		local route = if phase == "Lobby"
				or (phase == "Shift" and player:GetAttribute("Status") == "Working")
			then GuideService.RouteFor(player)
			else {}
		if phase == "Lobby" and #route > 0 and not toldClock[player] then
			toldClock[player] = true
			Net.FireClient(
				player,
				"Notify",
				"To start your shift, clock in at the time clock. Follow the lights on the floor.",
				"Info"
			)
		end
		if #route > 0 or not sentEmpty[player] then
			Net.FireClient(player, "Guide", route)
			sentEmpty[player] = #route == 0
		end
	end
end

function GuideService.Start()
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			arrivedAt[player] = os.clock()
		end)
		if player.Character then
			arrivedAt[player] = os.clock()
		end
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		sentEmpty[player] = nil
		arrivedAt[player] = nil
		toldClock[player] = nil
	end)
	-- A new night: whoever needs the clock again is told again.
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase == "Lobby" then
			for player in arrivedAt do
				arrivedAt[player] = os.clock()
				toldClock[player] = nil
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(INTERVAL)
			local ok, message = pcall(update)
			if not ok then
				warn("[GuideService] " .. tostring(message))
			end
		end
	end)
end

return GuideService
