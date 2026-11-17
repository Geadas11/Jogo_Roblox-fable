--!strict
-- Connects the monster's Brain to the game: who it can hunt, what it hears, what it
-- opens, where it appears, and the invisible part ("TheCustomer") whose position every
-- client follows to draw it.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Tags = require(Shared.Config.Tags)
local Log = require(Shared.Util.Log)
local Rng = require(Shared.Util.Rng)
local Brain = require(script.Parent.Parent.Monster.Brain)
local MapGrid = require(script.Parent.Parent.Monster.MapGrid)
local DoorService = require(script.Parent.DoorService)
local GameManager = require(script.Parent.GameManager)
local HidingService = require(script.Parent.HidingService)
local NoiseService = require(script.Parent.NoiseService)
local PlayerManager = require(script.Parent.PlayerManager)
local ShiftManager = require(script.Parent.ShiftManager)
local SurvivalService = require(script.Parent.SurvivalService)

local log = Log.new("Monster")

-- Height of the root part's centre above the floor (the monster is about 7.4 tall).
local ROOT_HEIGHT = 3.7
local CATCH_VARIANTS = 3

local MonsterManager = {}

local brain: Brain.Brain? = nil
local root: BasePart? = nil
local rng = Rng.new(os.time() + 17)
local doors: { BasePart } = {}
local patrolPoints: { { x: number, z: number } } = {}

local function playerById(id: number): Player?
	for _, player in Players:GetPlayers() do
		if player.UserId == id then
			return player
		end
	end
	return nil
end

local function huntable(): { Player }
	local list = {}
	for _, player in PlayerManager.GetReadyPlayers() do
		if SurvivalService.IsHuntable(player) then
			table.insert(list, player)
		end
	end
	return list
end

local function targets(): { Brain.Target }
	local list = {}
	for _, player in huntable() do
		local part = PlayerManager.GetRoot(player) :: BasePart
		table.insert(list, {
			Id = player.UserId,
			X = part.Position.X,
			Z = part.Position.Z,
			Running = NoiseService.IsRunning(player),
			Hidden = player:GetAttribute("Status") == "Hiding",
			Spot = HidingService.SpotIdOf(player),
		})
	end
	return list
end

-- A patrol point far from everyone and out of their sight.
local function chooseSpawn(): { x: number, z: number }?
	local grid = MapGrid.Get()
	if not grid or #patrolPoints == 0 then
		return nil
	end
	local players = targets()
	local candidates = {}
	for _, point in patrolPoints do
		local ok = true
		for _, target in players do
			local dx, dz = point.x - target.X, point.z - target.Z
			if
				math.sqrt(dx * dx + dz * dz) < MonsterConfig.Behaviour.SpawnMinDistance
				or grid:CanSee(point.x, point.z, target.X, target.Z)
			then
				ok = false
				break
			end
		end
		if ok then
			table.insert(candidates, point)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return rng:Pick(candidates)
end

local function ensureRoot(): BasePart
	if root and root.Parent then
		return root
	end
	local part = Instance.new("Part")
	part.Name = "TheCustomer"
	part.Size = Vector3.new(2, ROOT_HEIGHT * 2, 1.2)
	part.Transparency = 1
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part:SetAttribute("State", "Vanished")
	part:SetAttribute("Target", 0)
	part:SetAttribute("Present", false)
	part:AddTag("Monster")
	part.Parent = Workspace
	root = part
	return part
end

local function sync()
	local current = brain
	if not current then
		return
	end
	local part = ensureRoot()
	part:SetAttribute("Present", current.Present)
	part:SetAttribute("State", current.State)
	part:SetAttribute("Target", current.TargetId or 0)
	if current.Present then
		local position = Vector3.new(current.X, ROOT_HEIGHT, current.Z)
		part.CFrame = CFrame.lookAt(position, position + Vector3.new(current.FaceX, 0, current.FaceZ))
	end
end

-- Opens closed doors in its way.
local function openDoors()
	local current = brain
	if not current or not current.Present then
		return
	end
	for _, door in doors do
		if door:GetAttribute("Open") ~= true then
			local position = door.Position
			local dx, dz = position.X - current.X, position.Z - current.Z
			if math.sqrt(dx * dx + dz * dz) <= MonsterConfig.DoorOpenDistance then
				DoorService.SetOpen(door, true, nil)
			end
		end
	end
end

function MonsterManager.GetBrain(): Brain.Brain?
	return brain
end

-- Advances the monster by `dt` seconds. Called by the loop in Start; public for tests.
function MonsterManager.Step(dt: number)
	local current = brain
	if not current then
		return
	end
	current:Step(dt)
	openDoors()
	sync()
end

-- Brings the monster into the store, at a given point or somewhere out of sight.
function MonsterManager.Spawn(x: number?, z: number?): boolean
	local current = brain
	if not current then
		return false
	end
	local point = if x and z then { x = x, z = z } else chooseSpawn()
	if not point then
		-- Everywhere is in someone's view: use the patrol point furthest from everyone.
		local best, bestDistance = nil, -1
		for _, candidate in patrolPoints do
			local nearest = math.huge
			for _, target in targets() do
				nearest =
					math.min(nearest, math.sqrt((candidate.x - target.X) ^ 2 + (candidate.z - target.Z) ^ 2))
			end
			if nearest > bestDistance then
				best, bestDistance = candidate, nearest
			end
		end
		point = best
	end
	if not point then
		return false
	end
	current:Appear(point.x, point.z)
	sync()
	log:Info("The Customer is in the store (%.0f, %.0f)", current.X, current.Z)
	return true
end

function MonsterManager.Despawn()
	local current = brain
	if current and (current.Present or current.State ~= "Vanished") then
		current:Disappear()
		sync()
	end
end

function MonsterManager.Init()
	local grid = MapGrid.Get()
	if not grid then
		log:Warn(
			"No navigation grid in ServerStorage: the monster is disabled. Build the place with tools/build.luau."
		)
		return
	end

	brain = Brain.new(grid, {
		Targets = targets,
		PatrolPoints = patrolPoints,
		HidingSpots = {},
		OccupantOf = function(id: number): number?
			local player = HidingService.OccupantOf(id)
			return if player then player.UserId else nil
		end,
		OnCatch = function(id: number)
			local player = playerById(id)
			if player then
				SurvivalService.Catch(player, rng:Int(1, CATCH_VARIANTS))
			end
		end,
		OnStateChanged = nil,
		ChooseSpawn = chooseSpawn,
		Random = function(): number
			return rng:Next()
		end,
	}, MonsterConfig :: any)

	NoiseService.Heard:Connect(function(position: Vector3, radius: number)
		local current = brain
		if current and current.Present then
			local dx, dz = position.X - current.X, position.Z - current.Z
			if math.sqrt(dx * dx + dz * dz) <= radius then
				current:Hear(position.X, position.Z)
			end
		end
	end)
end

function MonsterManager.Start()
	local current = brain
	if not current then
		return
	end

	for _, node in CollectionService:GetTagged(Tags.PatrolNode) do
		if node:IsA("BasePart") then
			table.insert(patrolPoints, { x = node.Position.X, z = node.Position.Z })
		end
	end
	for _, door in CollectionService:GetTagged(Tags.Door) do
		if door:IsA("BasePart") and door:GetAttribute("Locked") ~= true then
			table.insert(doors, door)
		end
	end
	-- The brain reads hiding spots by id; HidingService has numbered them by now.
	for _, spot in HidingService.GetSpots() do
		table.insert(
			current.World.HidingSpots,
			{ Id = spot.Id, X = spot.Part.Position.X, Z = spot.Part.Position.Z }
		)
	end
	ensureRoot()

	ShiftManager.HourChanged:Connect(function(hour: number)
		if hour == 0 then
			MonsterManager.Despawn()
			return
		end
		current.SpeedMultiplier = 1
			+ MonsterConfig.SpeedGrowthPerHour * math.max(0, hour - MonsterConfig.ActiveFromHour)
		if hour >= MonsterConfig.ActiveFromHour and not current.Present and current.State == "Vanished" then
			MonsterManager.Spawn()
		end
	end)
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase ~= "Shift" then
			MonsterManager.Despawn()
		end
	end)

	-- Real time from the synchronised clock, so a stalled server does not make it jump.
	local last = Workspace:GetServerTimeNow()
	while true do
		task.wait(0.1)
		local now = Workspace:GetServerTimeNow()
		local dt = math.clamp(now - last, 0, 0.5)
		last = now
		if dt > 0 and GameManager.GetPhase() == "Shift" then
			MonsterManager.Step(dt)
		end
	end
end

return MonsterManager
