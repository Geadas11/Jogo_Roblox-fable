--!strict
-- Late-night customers (Config.CustomerConfig).
--
-- In the first hours a few ordinary people come in, wander between the shelves, stop
-- to look at the products, go to the checkout and leave. They make the store feel
-- lived-in, and they make the player look twice at every figure in an aisle.
--
-- Some of them are not what they seem (CustomerConfig.Anomalies): one walks backwards,
-- one floats, one is too tall, one has no face, one's head hangs at an impossible angle,
-- one stops and stares, and one looks fine - except on the security cameras, where it
-- has no head. Any customer can be asked to leave (hold the prompt): a suspicious one
-- stares at you, then hurries out and is gone; an ordinary one leaves offended, and that
-- counts as a mistake. A suspicious one left alone too long vanishes - and the monster
-- hears where. At 2 AM the store closes and the ordinary customers leave; whoever still
-- walks in after that is one of them.
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
local Net = require(script.Parent.Parent.Net)
local GameManager = require(script.Parent.GameManager)
local InteractionService = require(script.Parent.InteractionService)
local NoiseService = require(script.Parent.NoiseService)
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

-- The night's tally, for the results screen.
local stats = { Suspicious = 0, Expelled = 0, Mistakes = 0, Escaped = 0 }

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

local function pickAnomaly(): string
	local total = 0
	for _, entry in CustomerConfig.Anomalies do
		total += entry.Weight
	end
	local roll = rng:Next() * total
	for _, entry in CustomerConfig.Anomalies do
		roll -= entry.Weight
		if roll <= 0 then
			return entry.Name
		end
	end
	return CustomerConfig.Anomalies[1].Name
end

local function build(anomaly: string?): Model?
	local description = Instance.new("HumanoidDescription")
	local skin = color(rng:Pick(CustomerConfig.Skin))
	local shirt = color(rng:Pick(CustomerConfig.Shirts))
	local trousers = color(rng:Pick(CustomerConfig.Trousers))
	-- Skin everywhere; the shirt and trousers (catalog clothing) go over it. The plain
	-- colours below only show if the clothing cannot be loaded.
	description.HeadColor = skin
	description.LeftArmColor = skin
	description.RightArmColor = skin
	description.TorsoColor = shirt
	description.LeftLegColor = trousers
	description.RightLegColor = trousers
	description.HairAccessory = tostring(rng:Pick(CustomerConfig.Hair))
	description.Shirt = rng:Pick(CustomerConfig.ShirtIds)
	description.Pants = rng:Pick(CustomerConfig.PantsIds)
	-- A little variety in build.
	description.HeightScale = if anomaly == "TooTall" then 1.32 else 0.95 + rng:Next() * 0.12
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

	-- What is wrong with it (clients draw HeadTilt and CameraOnly themselves).
	if anomaly then
		model:SetAttribute("Suspicious", true)
		model:SetAttribute("Anomaly", anomaly)
		if anomaly == "Floating" then
			humanoid.HipHeight += 0.9
		elseif anomaly == "NoFace" then
			local head = model:FindFirstChild("Head")
			for _, child in if head then head:GetChildren() else {} do
				if child:IsA("Decal") then
					child:Destroy()
				end
			end
		end
	end
	return model
end

-- Walking ------------------------------------------------------------------------------------

-- What a customer is doing changes when it is asked to leave: every walk belongs to a
-- plan, and a walk stops as soon as the customer's plan is not its own any more.
local function planOf(model: Model): number
	return tonumber(model:GetAttribute("Plan")) or 0
end

-- Walks the model to (x, z) along the navigation grid. Returns false if it gave up, the
-- night ended, or its plan changed on the way.
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
	local plan = planOf(model)
	local backwards = model:GetAttribute("Anomaly") == "Backwards"
	humanoid.AutoRotate = not backwards
	-- Turning it by setting its CFrame would stop the walk dead; a physics constraint
	-- holds it facing backwards while the Humanoid keeps walking.
	local facing: AlignOrientation? = nil
	if backwards then
		local existing = root:FindFirstChild("Backwards")
		if existing and existing:IsA("AlignOrientation") then
			facing = existing
		else
			local attachment = root:FindFirstChild("RootAttachment") :: Attachment?
			if not attachment then
				local made = Instance.new("Attachment")
				made.Name = "RootAttachment"
				made.Parent = root
				attachment = made
			end
			local align = Instance.new("AlignOrientation")
			align.Name = "Backwards"
			align.Mode = Enum.OrientationAlignmentMode.OneAttachment
			align.Attachment0 = attachment
			align.Responsiveness = 25
			align.MaxTorque = math.huge
			align.CFrame = root.CFrame.Rotation
			align.Parent = root
			facing = align
		end
	end
	local function current(): boolean
		return generation == token and model.Parent ~= nil and planOf(model) == plan
	end
	for _, point in path do
		if not current() then
			return false
		end
		local target = Vector3.new(point.x, root.Position.Y, point.z)
		humanoid:MoveTo(target)
		local started = os.clock()
		while
			(Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(point.x, 0, point.z)).Magnitude
			> 1.5
		do
			if not current() or os.clock() - started > 8 then
				return current()
			end
			if facing then
				-- Facing where it came from while it walks on.
				local away = Vector3.new(root.Position.X - point.x, 0, root.Position.Z - point.z)
				if away.Magnitude > 0.1 then
					facing.CFrame = CFrame.lookAt(Vector3.zero, away.Unit)
				end
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
			local align = root:FindFirstChild("Backwards")
			if align and align:IsA("AlignOrientation") then
				align.CFrame = CFrame.lookAt(Vector3.zero, target - position)
			else
				root.CFrame = CFrame.lookAt(position, target)
			end
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

-- The "Ask to leave" prompt of each customer in the store.
local prompts: { [Model]: ProximityPrompt } = {}

local function remove(model: Model)
	customers[model] = nil
	prompts[model] = nil
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
	local plan = planOf(model)
	while
		generation == token
		and model.Parent
		and planOf(model) == plan
		and os.clock() - started < CustomerConfig.StareSeconds
	do
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
	if planOf(model) == plan then
		model:SetAttribute("Staring", false)
		remove(model)
	end
end

-- One of them that is not staring: drifts from shelf to shelf, never buying, never
-- leaving - until someone asks it to, or it has been here too long.
local function lurk(model: Model, token: number)
	local browse = nodesOf("Browse")
	local plan = planOf(model)
	while generation == token and model.Parent and planOf(model) == plan and #browse > 0 do
		local stop = rng:Pick(browse)
		if not walkTo(model, stop.X, stop.Z, token) then
			return
		end
		face(model, stop.X + (if rng:Next() < 0.5 then -3 else 3), stop.Z)
		task.wait(rng:Int(CustomerConfig.BrowseMin, CustomerConfig.BrowseMax))
	end
end

-- Walks a customer out through the entrance, then it is gone.
local function walkOut(model: Model, token: number)
	local entries = nodesOf("Entry")
	if #entries > 0 and model.Parent then
		walkTo(model, entries[1].X, entries[1].Z, token)
	end
	remove(model)
end

-- `player` asked this customer to leave.
local function expel(model: Model, player: Player)
	if not model.Parent or model:GetAttribute("Leaving") then
		return
	end
	model:SetAttribute("Leaving", true)
	-- Whatever it was doing stops.
	model:SetAttribute("Plan", planOf(model) + 1)
	local prompt = prompts[model]
	if prompt then
		prompt.Enabled = false
	end
	local token = generation
	local suspicious = model:GetAttribute("Suspicious") == true
	if suspicious then
		stats.Expelled += 1
		Net.FireClient(player, "Notify", "It is leaving. Something was very wrong with that one.", "Info")
	else
		stats.Mistakes += 1
		Net.FireClient(player, "Notify", "That was an ordinary customer. They left, offended.", "Warning")
	end
	log:Info("%s asked a %s customer to leave", player.Name, if suspicious then "suspicious" else "normal")
	task.spawn(function()
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart")
		if suspicious and humanoid and root and root:IsA("BasePart") then
			-- It stops, turns to you and stares for a long moment... then hurries out.
			humanoid:MoveTo(root.Position)
			local target = PlayerManager.GetRoot(player)
			if target then
				face(model, target.Position.X, target.Position.Z)
			end
			model:SetAttribute("Staring", true)
			task.wait(1.6)
			model:SetAttribute("Staring", false)
			humanoid.WalkSpeed = CustomerConfig.ExpelledWalkSpeed
		end
		walkOut(model, token)
	end)
end

local function arrive(hour: number, forced: string?)
	local entries = nodesOf("Entry")
	if #entries == 0 or not folder then
		return
	end
	local chance =
		CustomerConfig.SuspiciousChanceByHour[math.clamp(hour + 1, 1, #CustomerConfig.SuspiciousChanceByHour)]
	local anomaly = forced or (if rng:Next() < chance then pickAnomaly() else nil)
	if anomaly == "None" then
		anomaly = nil
	end
	local model = build(anomaly)
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
	model:SetAttribute("Plan", 0)

	if root and root:IsA("BasePart") then
		prompts[model] = InteractionService.AddPrompt(root, {
			action = "Ask to leave",
			object = "Customer",
			hold = CustomerConfig.ExpelHold,
			distance = CustomerConfig.ExpelDistance,
		}, function(player: Player)
			expel(model, player)
		end)
	end

	local token = generation
	if anomaly then
		stats.Suspicious += 1
		-- Left alone too long, it is simply gone - and something heard it go.
		task.delay(CustomerConfig.LingerSeconds, function()
			if generation == token and model.Parent and not model:GetAttribute("Leaving") then
				local body = model:FindFirstChild("HumanoidRootPart")
				if body and body:IsA("BasePart") then
					NoiseService.Emit(body.Position, CustomerConfig.LingerNoiseRadius, "Anomaly")
				end
				stats.Escaped += 1
				remove(model)
			end
		end)
	end
	task.spawn(if anomaly == "Staring" then stare elseif anomaly then lurk else shop, model, token)
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
	-- After closing (LeaveHour) only they still come in, more rarely, until LateUntilHour.
	local late = hour >= CustomerConfig.LeaveHour
	if hour < CustomerConfig.FirstHour or (late and hour >= CustomerConfig.LateUntilHour) then
		return
	end
	local now = Workspace:GetServerTimeNow()
	if now < nextArrival then
		return
	end
	nextArrival = now
		+ if late
			then rng:Int(CustomerConfig.LateArrivalMin, CustomerConfig.LateArrivalMax)
			else rng:Int(CustomerConfig.ArrivalMin, CustomerConfig.ArrivalMax)
	if count() < limit() then
		arrive(hour)
	end
end

-- The night's tally of suspicious customers (for the results and for tests).
function CustomerManager.GetStats()
	return table.clone(stats)
end

-- For tests and tools: asks `model` to leave on behalf of `player`.
CustomerManager.Expel = expel

-- For tests and tools: lets a customer in now, optionally with a given anomaly ("None"
-- for an ordinary one).
function CustomerManager.Arrive(anomaly: string?)
	arrive(ShiftManager.GetHour(), anomaly)
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
			-- Closing time: the ordinary customers head for the exit. The others do not.
			local token = generation
			for model in customers do
				if not model:GetAttribute("Suspicious") and not model:GetAttribute("Leaving") then
					model:SetAttribute("Leaving", true)
					model:SetAttribute("Plan", planOf(model) + 1)
					task.spawn(walkOut, model, token)
				end
			end
			nextArrival = Workspace:GetServerTimeNow() + CustomerConfig.LateArrivalMin / 2
		end
	end)
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase == "Shift" then
			stats = { Suspicious = 0, Expelled = 0, Mistakes = 0, Escaped = 0 }
		else
			nextArrival = math.huge
			CustomerManager.Clear()
		end
	end)
	GameManager.AddResultsContributor(function(results: any)
		results.SuspiciousTotal = stats.Suspicious
		results.SuspiciousExpelled = stats.Expelled
		results.WrongExpels = stats.Mistakes
	end)
	log:Info("%d customer points", #nodes)

	while true do
		task.wait(1)
		CustomerManager.Update()
	end
end

return CustomerManager
