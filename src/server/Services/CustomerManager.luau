--!strict
-- Late-night customers (Config.CustomerConfig).
--
-- In the first hours a few ordinary people come in, wander between the shelves, stop
-- to look at the products, go to the checkout and leave. They make the store feel
-- lived-in, and they make the player look twice at every figure in an aisle.
--
-- From 1 AM one of them may not shop at all: it stops, turns to the nearest employee and
-- stares; when nobody is looking at it any more, it is gone. At 2 AM the last
-- customers leave, so the store is empty when the monster arrives.
--
-- Customers are ordinary Humanoid rigs owned by the server, walking along the same
-- navigation grid as the monster. They are tagged AnimatedCharacter, so every client
-- animates them with the same procedural walk as the players.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local CustomerConfig = require(Shared.Config.CustomerConfig)
local Tags = require(Shared.Config.Tags)
local Log = require(Shared.Util.Log)
local Rng = require(Shared.Util.Rng)
local MapGrid = require(script.Parent.Parent.Monster.MapGrid)
local GameManager = require(script.Parent.GameManager)
local PlayerManager = require(script.Parent.PlayerManager)
local ShiftManager = require(script.Parent.ShiftManager)

local log = Log.new("Customers")

local CustomerManager = {}

type Node = { X: number, Z: number, Kind: string }

local rng = Rng.new(os.time() + 71)
local nodes: { Node } = {}
local customers: { [Model]: boolean } = {}
-- Bumped whenever the night ends: every customer's thread checks it and stops.
local generation = 0
local nextArrival = math.huge
local folder: Folder? = nil

local function color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function count(): number
	local total = 0
	for model in customers do
		if model.Parent then
			total += 1
		end
	end
	return total
end

local function limit(): number
	local players = #PlayerManager.GetReadyPlayers()
	return math.min(
		CustomerConfig.MaxTotal,
		CustomerConfig.MaxBase + CustomerConfig.MaxPerTwoPlayers * (players // 2)
	)
end

local function nodesOf(kind: string): { Node }
	local list = {}
	for _, node in nodes do
		if node.Kind == kind then
			table.insert(list, node)
		end
	end
	return list
end

-- Building -----------------------------------------------------------------------------------

local function build(): Model?
	local description = Instance.new("HumanoidDescription")
	local skin = color(rng:Pick(CustomerConfig.Skin))
	local shirt = color(rng:Pick(CustomerConfig.Shirts))
	local trousers = color(rng:Pick(CustomerConfig.Trousers))
	description.HeadColor = skin
	description.LeftArmColor = shirt
	description.RightArmColor = shirt
	description.TorsoColor = shirt
	description.LeftLegColor = trousers
	description.RightLegColor = trousers
	-- A little variety in build.
	description.HeightScale = 0.95 + rng:Next() * 0.12
	description.WidthScale = 0.9 + rng:Next() * 0.2
	local ok, model = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not model then
		return nil
	end
	-- Hands and face in skin colour (the arms above are the shirt's sleeves).
	for _, part in model:GetChildren() do
		if part:IsA("BasePart") and string.find(part.Name, "Hand") then
			part.Color = skin
		end
	end
	model.Name = "Customer"
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.WalkSpeed = CustomerConfig.WalkSpeed
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	humanoid.BreakJointsOnDeath = false
	-- No default animation script: clients animate it themselves.
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	return model
end

-- Walking ------------------------------------------------------------------------------------

-- Walks the model to (x, z) along the navigation grid. Returns false if it gave up or the
-- night ended on the way.
local function walkTo(model: Model, x: number, z: number, token: number): boolean
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart")
	local grid = MapGrid.Get()
	if not humanoid or not root or not root:IsA("BasePart") or not grid then
		return false
	end
	local path = grid:FindPath(root.Position.X, root.Position.Z, x, z)
	if not path then
		return false
	end
	for _, point in path do
		if generation ~= token or not model.Parent then
			return false
		end
		local target = Vector3.new(point.x, root.Position.Y, point.z)
		humanoid:MoveTo(target)
		local started = os.clock()
		while
			(Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(point.x, 0, point.z)).Magnitude
			> 1.5
		do
			if generation ~= token or not model.Parent or os.clock() - started > 8 then
				return generation == token and model.Parent ~= nil
			end
			task.wait(0.1)
		end
	end
	return true
end

local function face(model: Model, x: number, z: number)
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local position = root.Position
		local target = Vector3.new(x, position.Y, z)
		if (target - position).Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(position, target)
		end
	end
end

-- Whether any working player is looking roughly towards this point (and could see it).
local function watched(position: Vector3): boolean
	local grid = MapGrid.Get()
	for _, player in PlayerManager.GetReadyPlayers() do
		local root = PlayerManager.GetRoot(player)
		if root then
			local offset = Vector3.new(position.X - root.Position.X, 0, position.Z - root.Position.Z)
			if offset.Magnitude < 1 then
				return true
			end
			local look = root.CFrame.LookVector
			local facing = Vector3.new(look.X, 0, look.Z)
			if
				facing.Magnitude > 0.01
				and offset.Unit:Dot(facing.Unit) > 0.5
				and (grid == nil or grid:CanSee(root.Position.X, root.Position.Z, position.X, position.Z))
			then
				return true
			end
		end
	end
	return false
end

local function nearestPlayer(position: Vector3): BasePart?
	local best, bestDistance = nil, math.huge
	for _, player in PlayerManager.GetReadyPlayers() do
		local root = PlayerManager.GetRoot(player)
		if root then
			local distance = (root.Position - position).Magnitude
			if distance < bestDistance then
				best, bestDistance = root, distance
			end
		end
	end
	return best
end

-- Behaviour ----------------------------------------------------------------------------------

local function remove(model: Model)
	customers[model] = nil
	if model.Parent then
		model:Destroy()
	end
end

-- An ordinary visit: a few shelves, the checkout, out.
local function shop(model: Model, token: number)
	local browse = nodesOf("Browse")
	for _ = 1, rng:Int(CustomerConfig.StopsMin, CustomerConfig.StopsMax) do
		if #browse == 0 or ShiftManager.GetHour() >= CustomerConfig.LeaveHour then
			break
		end
		local stop = rng:Pick(browse)
		if not walkTo(model, stop.X, stop.Z, token) then
			return
		end
		-- Turn to the nearer shelf (aisles run north-south, shelves to either side).
		face(model, stop.X + (if rng:Next() < 0.5 then -3 else 3), stop.Z)
		task.wait(rng:Int(CustomerConfig.BrowseMin, CustomerConfig.BrowseMax))
		if generation ~= token then
			return
		end
	end
	local queues = nodesOf("Queue")
	if #queues > 0 and ShiftManager.GetHour() < CustomerConfig.LeaveHour then
		local queue = rng:Pick(queues)
		if walkTo(model, queue.X, queue.Z, token) then
			task.wait(rng:Int(3, 6))
		end
	end
	local entries = nodesOf("Entry")
	if #entries > 0 then
		walkTo(model, entries[1].X, entries[1].Z, token)
	end
	remove(model)
end

-- The wrong one: goes somewhere, stops, and stares at the nearest employee. Gone the
-- moment nobody is watching it.
local function stare(model: Model, token: number)
	local browse = nodesOf("Browse")
	if #browse > 0 then
		local spot = rng:Pick(browse)
		if not walkTo(model, spot.X, spot.Z, token) then
			return
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		remove(model)
		return
	end
	model:SetAttribute("Staring", true)
	local seen = false
	local started = os.clock()
	while generation == token and model.Parent and os.clock() - started < CustomerConfig.StareSeconds do
		local target = nearestPlayer(root.Position)
		if target then
			face(model, target.Position.X, target.Position.Z)
		end
		local isWatched = watched(root.Position)
		if isWatched then
			seen = true
		elseif seen then
			-- It was looked at, and now nobody is looking: it is not there any more.
			break
		end
		task.wait(0.2)
	end
	remove(model)
end

local function arrive()
	local entries = nodesOf("Entry")
	if #entries == 0 or not folder then
		return
	end
	local model = build()
	if not model then
		return
	end
	local entry = entries[1]
	model:PivotTo(CFrame.new(entry.X + rng:Int(-2, 2), 3, entry.Z) * CFrame.Angles(0, math.pi, 0))
	model:AddTag("AnimatedCharacter")
	model:AddTag("Customer")
	model.Parent = folder
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	customers[model] = true

	local token = generation
	local hour = ShiftManager.GetHour()
	local strange = hour >= CustomerConfig.StarerFromHour and rng:Next() < CustomerConfig.StarerChance
	task.spawn(if strange then stare else shop, model, token)
end

-- Everyone out (end of the customer hours, end of the night).
function CustomerManager.Clear()
	generation += 1
	for model in customers do
		remove(model)
	end
	customers = {}
end

-- Called once a second: lets the next customer in when it is time.
function CustomerManager.Update()
	if GameManager.GetPhase() ~= "Shift" then
		return
	end
	local hour = ShiftManager.GetHour()
	if hour < CustomerConfig.FirstHour or hour >= CustomerConfig.LeaveHour then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if now < nextArrival then
		return
	end
	nextArrival = now + rng:Int(CustomerConfig.ArrivalMin, CustomerConfig.ArrivalMax)
	if count() < limit() then
		arrive()
	end
end

function CustomerManager.Count(): number
	return count()
end

function CustomerManager.Start()
	for _, node in CollectionService:GetTagged(Tags.CustomerNode) do
		if node:IsA("BasePart") then
			table.insert(nodes, {
				X = node.Position.X,
				Z = node.Position.Z,
				Kind = tostring(node:GetAttribute("Kind") or "Browse"),
			})
		end
	end
	local created = Instance.new("Folder")
	created.Name = "Customers"
	created.Parent = Workspace
	folder = created

	ShiftManager.HourChanged:Connect(function(hour: number)
		if hour == 0 then
			-- The first customer a little after clocking in.
			nextArrival = Workspace:GetServerTimeNow() + 12
		elseif hour == CustomerConfig.LeaveHour then
			-- Those still shopping head for the exit; anything else simply is not there.
			generation += 1
			local token = generation
			for model in customers do
				if model:GetAttribute("Staring") then
					remove(model)
				else
					task.spawn(function()
						local entries = nodesOf("Entry")
						if #entries > 0 then
							walkTo(model, entries[1].X, entries[1].Z, token)
						end
						remove(model)
					end)
				end
			end
		end
	end)
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase ~= "Shift" then
			nextArrival = math.huge
			CustomerManager.Clear()
		end
	end)
	log:Info("%d customer points", #nodes)

	while true do
		task.wait(1)
		CustomerManager.Update()
	end
end

return CustomerManager
