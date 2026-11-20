--!strict
-- The night's strange events (Config.EventConfig): flickering lights, a cart that rolls
-- on its own, something falling off a shelf, knocking, footsteps behind you, a door that
-- slams, the intercom, a figure at the end of an aisle, a short blackout.
--
-- The server decides what happens, where and when, so every player experiences the
-- same night. Anything that changes the world (a cart, a door, a fallen item) is done
-- here; clients are told through the HorrorEvent remote and play the sound or effect.
--
-- Pacing: nothing at midnight; from 1 AM an event is due every IntervalByHour seconds
-- on average (sooner with more players). Some due events are skipped on purpose
-- (silence), and nothing is added while the monster is chasing someone.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local EventConfig = require(Shared.Config.EventConfig)
local Tags = require(Shared.Config.Tags)
local Log = require(Shared.Util.Log)
local Rng = require(Shared.Util.Rng)
local Signal = require(Shared.Util.Signal)
local Net = require(script.Parent.Parent.Net)
local MapGrid = require(script.Parent.Parent.Monster.MapGrid)
local DoorService = require(script.Parent.DoorService)
local GameManager = require(script.Parent.GameManager)
local MonsterManager = require(script.Parent.MonsterManager)
local PlayerManager = require(script.Parent.PlayerManager)
local ShiftManager = require(script.Parent.ShiftManager)

local log = Log.new("Events")

type Handler = (target: Player, root: BasePart) -> boolean

local EventManager = {}

-- Fired after an event happened: (name).
EventManager.Happened = Signal.new() :: Signal.Signal<string>

local rng = Rng.new(os.time() + 53)
local handlers: { [string]: Handler } = {}
local lastRun: { [string]: number } = {}
local nextAt = math.huge
-- Things this service put in the world during the shift; removed at the end.
local spawned: { Instance } = {}
local carts: { Model } = {}

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flat(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Players who are up and about, with their root part.
local function working(): { { Player: Player, Root: BasePart } }
	local list = {}
	for _, player in PlayerManager.GetReadyPlayers() do
		local root = PlayerManager.GetRoot(player)
		if root and player:GetAttribute("Status") == "Working" then
			table.insert(list, { Player = player, Root = root })
		end
	end
	return list
end

-- Whether any working player could see a point right now (in front of them, no walls).
local function anyoneSees(position: Vector3, range: number): boolean
	local grid = MapGrid.Get()
	for _, entry in working() do
		local root = entry.Root
		local offset = Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
		local distance = offset.Magnitude
		if distance < 6 then
			return true
		end
		if distance <= range then
			local look = root.CFrame.LookVector
			local facing = Vector3.new(look.X, 0, look.Z)
			local inFront = facing.Magnitude > 0.01 and offset.Unit:Dot(facing.Unit) > 0.25
			local clear = grid == nil or grid:CanSee(root.Position.X, root.Position.Z, position.X, position.Z)
			if inFront and clear then
				return true
			end
		end
	end
	return false
end

local function sound(name: string, position: Vector3)
	Net.FireAllClients(
		"HorrorEvent",
		"Sound",
		{ Name = name, X = position.X, Y = position.Y, Z = position.Z }
	)
end

-- Events --------------------------------------------------------------------------------------

handlers.Flicker = function(_target, root)
	Net.FireAllClients("HorrorEvent", "Flicker", { X = root.Position.X, Z = root.Position.Z, Radius = 32 })
	return true
end

handlers.Blackout = function(_target, root)
	Net.FireAllClients(
		"HorrorEvent",
		"Blackout",
		{ X = root.Position.X, Z = root.Position.Z, Radius = 40, Seconds = 3.5 }
	)
	return true
end

handlers.Knock = function(_target, root)
	local options = {}
	for _, door in CollectionService:GetTagged(Tags.Door) do
		if door:IsA("BasePart") then
			local distance = flat(door.Position, root.Position)
			if distance >= 18 and distance <= 70 then
				table.insert(options, door)
			end
		end
	end
	if #options == 0 then
		return false
	end
	local door = rng:Pick(options) :: BasePart
	sound("Knock", door.Position)
	return true
end

handlers.Footsteps = function(_target, root)
	-- Behind them, a little way off, somewhere a person could stand.
	local look = root.CFrame.LookVector
	local back = -Vector3.new(look.X, 0, look.Z)
	if back.Magnitude < 0.01 then
		return false
	end
	back = back.Unit
	local grid = MapGrid.Get()
	local distance = rng:Int(14, 22)
	local x, z = root.Position.X + back.X * distance, root.Position.Z + back.Z * distance
	if grid then
		local point = grid:Nearest(x, z, 8)
		if not point then
			return false
		end
		x, z = point.x, point.z
	end
	sound("Steps", Vector3.new(x, root.Position.Y - 2.5, z))
	return true
end

handlers.DoorSlam = function(_target, root)
	local open, closed = {}, {}
	for _, door in CollectionService:GetTagged(Tags.Door) do
		if door:IsA("BasePart") and door:GetAttribute("Locked") ~= true then
			local distance = flat(door.Position, root.Position)
			if distance >= 16 and distance <= 80 then
				table.insert(if DoorService.IsOpen(door) then open else closed, door)
			end
		end
	end
	if #open > 0 then
		local door = rng:Pick(open) :: BasePart
		if DoorService.SetOpen(door, false, nil) then
			sound("DoorBang", door.Position)
			return true
		end
	end
	-- Nothing to slam: one that was shut is quietly found open later.
	for _, door in closed do
		if not anyoneSees(door.Position, 90) and DoorService.SetOpen(door, true, nil) then
			return true
		end
	end
	return false
end

handlers.Announcement = function(_target, _root)
	local hour = ShiftManager.GetHour()
	local lines = EventConfig.Announcements[math.clamp(hour + 1, 3, 6)]
	if not lines or #lines == 0 then
		return false
	end
	Net.FireAllClients("HorrorEvent", "Announcement", { Text = rng:Pick(lines) })
	return true
end

handlers.Silhouette = function(target, root)
	-- A patrol point ahead of them, in plain view, at the end of the aisle.
	local grid = MapGrid.Get()
	local look = root.CFrame.LookVector
	local facing = Vector3.new(look.X, 0, look.Z)
	if facing.Magnitude < 0.01 then
		return false
	end
	facing = facing.Unit
	local options = {}
	for _, node in CollectionService:GetTagged(Tags.PatrolNode) do
		if node:IsA("BasePart") then
			local offset =
				Vector3.new(node.Position.X - root.Position.X, 0, node.Position.Z - root.Position.Z)
			local distance = offset.Magnitude
			if
				distance >= 28
				and distance <= 65
				and offset.Unit:Dot(facing) > 0.8
				and (
					grid == nil
					or grid:CanSee(root.Position.X, root.Position.Z, node.Position.X, node.Position.Z)
				)
			then
				table.insert(options, node)
			end
		end
	end
	if #options == 0 then
		return false
	end
	local node = rng:Pick(options) :: BasePart
	Net.FireAllClients("HorrorEvent", "Silhouette", {
		X = node.Position.X,
		Z = node.Position.Z,
		LookX = root.Position.X,
		LookZ = root.Position.Z,
		Seconds = 5,
		For = target.UserId,
	})
	return true
end

handlers.ItemFall = function(_target, root)
	local options = {}
	for _, bay in CollectionService:GetTagged(Tags.ShelfBay) do
		local anchor = bay:FindFirstChild("Anchor")
		if bay:GetAttribute("Stocked") == true and anchor and anchor:IsA("BasePart") then
			local distance = flat(anchor.Position, root.Position)
			if distance >= 12 and distance <= 55 and not anyoneSees(anchor.Position, 30) then
				table.insert(options, bay)
			end
		end
	end
	if #options == 0 then
		return false
	end
	local bay = rng:Pick(options) :: Instance
	local anchor = bay:FindFirstChild("Anchor") :: BasePart
	local products = {}
	for _, child in bay:GetChildren() do
		if child:IsA("BasePart") and child.Name == "Product" and child.Transparency < 1 then
			table.insert(products, child)
		end
	end
	if #products == 0 then
		return false
	end
	local product = rng:Pick(products) :: BasePart
	-- A copy tips off the front of the shelf and lands in the aisle.
	local outward =
		Vector3.new(anchor.Position.X - product.Position.X, 0, anchor.Position.Z - product.Position.Z)
	outward = if outward.Magnitude > 0.01 then outward.Unit else Vector3.new(1, 0, 0)
	local fallen = Instance.new("Part")
	fallen.Name = "FallenItem"
	fallen.Size = product.Size
	fallen.Color = product.Color
	fallen.Material = product.Material
	fallen.CanCollide = true
	fallen.Anchored = false
	fallen.CFrame = CFrame.new(product.Position + outward * 1.2)
	fallen.Parent = Workspace
	fallen.AssemblyLinearVelocity = outward * 6
	table.insert(spawned, fallen)
	sound("ItemFall", anchor.Position)
	return true
end

handlers.CartRoll = function(_target, root)
	local options = {}
	for _, cart in carts do
		if cart.Parent then
			local position = cart:GetPivot().Position
			local distance = flat(position, root.Position)
			if distance <= 75 and not anyoneSees(position, 80) then
				table.insert(options, cart)
			end
		end
	end
	if #options == 0 then
		return false
	end
	local cart = rng:Pick(options) :: Model
	local start = cart:GetPivot()
	local grid = MapGrid.Get()
	-- Roll forward or back, wherever there is room.
	local distance = rng:Int(4, 7)
	local direction = start.LookVector * (if rng:Next() < 0.5 then 1 else -1)
	local finish = start.Position + direction * distance
	if grid and not grid:CanWalkLine(start.Position.X, start.Position.Z, finish.X, finish.Z) then
		direction = -direction
		finish = start.Position + direction * distance
		if not grid:CanWalkLine(start.Position.X, start.Position.Z, finish.X, finish.Z) then
			return false
		end
	end
	sound("CartRoll", start.Position)
	task.spawn(function()
		local steps = 24
		for step = 1, steps do
			if not cart.Parent then
				return
			end
			-- Eases out, like something given a slow push.
			local t = 1 - (1 - step / steps) ^ 2
			cart:PivotTo(start + direction * distance * t)
			task.wait(1.8 / steps)
		end
	end)
	return true
end

-- Abandoned carts --------------------------------------------------------------------------

-- Leaves a couple of carts in the shop aisles at the start of the night (they are part
-- of the scenery until one of them moves).
local function placeCarts()
	local template: Model? = nil
	for _, model in Workspace:GetDescendants() do
		if model:IsA("Model") and model.Name == "ShoppingCart" then
			template = model
			break
		end
	end
	if not template then
		return
	end
	local points = {}
	for _, point in CollectionService:GetTagged(Tags.CartPoint) do
		if point:IsA("BasePart") and point:GetAttribute("Zone") == "ShopFloor" then
			table.insert(points, point)
		end
	end
	for _, point in rng:Sample(points, 2) do
		local cart = (template :: Model):Clone()
		cart.Name = "AbandonedCart"
		-- Wheels on the floor: the marker floats half a stud above it, and the pivot sits
		-- this far above the bottom of the cart.
		local pivot = (template :: Model):GetPivot()
		local boxCFrame, boxSize = (template :: Model):GetBoundingBox()
		local pivotAboveBottom = pivot.Position.Y - (boxCFrame.Position.Y - boxSize.Y / 2)
		local floor = point.Position.Y - 0.5
		local rotation = pivot - pivot.Position
		local x, z = point.Position.X, point.Position.Z
		-- Pointed somewhere it has room to roll (forward or back), so it can move later.
		local grid = MapGrid.Get()
		local placed = CFrame.new(x, floor + pivotAboveBottom, z)
			* CFrame.Angles(0, rng:Next() * math.pi * 2, 0)
			* rotation
		if grid then
			for _ = 1, 16 do
				local look = placed.LookVector
				if
					grid:CanWalkLine(x, z, x + look.X * 7, z + look.Z * 7)
					or grid:CanWalkLine(x, z, x - look.X * 7, z - look.Z * 7)
				then
					break
				end
				placed = CFrame.new(x, floor + pivotAboveBottom, z)
					* CFrame.Angles(0, rng:Next() * math.pi * 2, 0)
					* rotation
			end
		end
		cart:PivotTo(placed)
		cart.Parent = Workspace
		table.insert(carts, cart)
		table.insert(spawned, cart)
	end
end

local function clearWorld()
	for _, instance in spawned do
		instance:Destroy()
	end
	spawned = {}
	carts = {}
end

-- Scheduling --------------------------------------------------------------------------------

local function interval(hour: number): number
	local base = EventConfig.IntervalByHour[math.clamp(hour + 1, 1, #EventConfig.IntervalByHour)] or 0
	if base <= 0 then
		return math.huge
	end
	local extra = math.max(0, #PlayerManager.GetReadyPlayers() - 1)
	base /= 1 + EventConfig.PerPlayerSpeedup * extra
	-- Random spacing around the average, so the rhythm is never predictable.
	return base * (0.6 + rng:Next() * 0.8)
end

-- Runs one event now, on a random working player (or `target`). Returns whether it
-- happened. Public so tests and debugging can trigger events directly.
function EventManager.Trigger(name: string, target: Player?): boolean
	local handler = handlers[name]
	if not handler or GameManager.GetPhase() ~= "Shift" then
		return false
	end
	local candidates = working()
	if #candidates == 0 then
		return false
	end
	local chosen = candidates[rng:Int(1, #candidates)]
	if target then
		chosen = nil :: any
		for _, entry in candidates do
			if entry.Player == target then
				chosen = entry
			end
		end
		if not chosen then
			return false
		end
	end
	local ok, result = xpcall(handler, debug.traceback, chosen.Player, chosen.Root)
	if not ok then
		log:Warn("%s failed: %s", name, tostring(result))
		return false
	end
	if result then
		lastRun[name] = now()
		log:Debug("%s (near %s)", name, chosen.Player.Name)
		EventManager.Happened:Fire(name)
	end
	return result == true
end

-- Picks and runs whichever event is due. Called once a second during the shift.
function EventManager.Update()
	if GameManager.GetPhase() ~= "Shift" or now() < nextAt then
		return
	end
	local hour = ShiftManager.GetHour()
	nextAt = now() + interval(hour)

	-- Let a chase play out on its own.
	local brain = MonsterManager.GetBrain()
	if brain and brain.Present and brain.State == "Chase" then
		nextAt = now() + 10
		return
	end
	if rng:Next() < EventConfig.SilenceChance then
		return
	end

	local candidates = {}
	for name, spec in EventConfig.Events do
		local last = lastRun[name]
		if hour >= spec.MinHour and (last == nil or now() - last >= spec.Cooldown) and handlers[name] then
			table.insert(candidates, name)
		end
	end
	table.sort(candidates)
	-- Try a few: some events need a particular situation (an open door, a cart...).
	for _ = 1, 3 do
		if #candidates == 0 then
			return
		end
		local name = rng:PickWeighted(candidates, function(candidate: string)
			return EventConfig.Events[candidate].Weight
		end) :: string
		if EventManager.Trigger(name) then
			return
		end
		table.remove(candidates, table.find(candidates, name))
	end
end

function EventManager.Start()
	ShiftManager.HourChanged:Connect(function(hour: number)
		if hour == 0 then
			lastRun = {}
			clearWorld()
			local ok, message = pcall(placeCarts)
			if not ok then
				log:Debug("No abandoned carts: %s", tostring(message))
			end
		end
		nextAt = now() + interval(hour)
	end)
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase ~= "Shift" then
			nextAt = math.huge
		end
		if phase == "Lobby" then
			clearWorld()
		end
	end)

	while true do
		task.wait(1)
		EventManager.Update()
	end
end

return EventManager
