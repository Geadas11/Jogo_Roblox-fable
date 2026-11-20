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
local PowerManager = require(script.Parent.PowerManager)
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
-- Players in a hiding spot: since when (monster time) and whether it already came to look.
local hiders: { [Player]: { Spot: number, Since: number, Suspected: boolean } } = {}
local monsterTime = 0

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
			Flashlight = player:GetAttribute("FlashlightOn") == true,
			Lit = player:GetAttribute("FlashlightOn") == true
				or PowerManager.IsLit(part.Position.X, part.Position.Z),
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

-- The body every client draws: a real R15 rig made from Roblox's own body parts (no
-- downloaded models), too tall and too thin, grey-skinned - an old employee of the
-- store in its uniform: a faded yellow short-sleeved shirt, a blue apron with a name
-- badge someone scratched out, dark trousers. The apron and the hands are stained with
-- blood. Built once at boot and kept in ReplicatedStorage as a template; clients clone
-- it, draw its face and move its joints. Without it (e.g. outside Roblox) clients fall
-- back to a simple body made of blocks.
local SKIN = Color3.fromRGB(176, 172, 164)
local SHIRT = Color3.fromRGB(196, 164, 62)
local APRON = Color3.fromRGB(38, 64, 118)
local TROUSERS = Color3.fromRGB(30, 30, 34)
local BLOODY_HANDS = Color3.fromRGB(128, 62, 56)
local BLOOD = Color3.fromRGB(92, 8, 10)

-- A part welded to `to`, placed at `offset` from it; decorative only.
local function wear(
	rig: Model,
	to: BasePart,
	name: string,
	size: Vector3,
	offset: CFrame,
	color: Color3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = Enum.Material.Fabric
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Massless = true
	part.CastShadow = true
	part.CFrame = to.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = to
	weld.Part1 = part
	weld.Parent = part
	part.Parent = rig
	return part
end

-- Blood soaked into cloth: dark splashes of different sizes, a few running downwards.
local function stain(part: BasePart, seed: number, amount: number)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Stains"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 60
	gui.LightInfluence = 1
	gui.Parent = part
	local random = Random.new(seed)
	for _ = 1, amount do
		local splash = Instance.new("Frame")
		local size = random:NextNumber(0.06, 0.2)
		local x, y = random:NextNumber(0.1, 0.9), random:NextNumber(0.05, 0.8)
		splash.AnchorPoint = Vector2.new(0.5, 0.5)
		splash.Position = UDim2.new(x, 0, y, 0)
		splash.Size = UDim2.new(size, 0, size * random:NextNumber(0.6, 1.4), 0)
		splash.Rotation = random:NextNumber(0, 180)
		splash.BackgroundColor3 = BLOOD
		splash.BackgroundTransparency = random:NextNumber(0.05, 0.45)
		splash.BorderSizePixel = 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = splash
		splash.Parent = gui
		-- Some of it ran, straight down (a separate frame, so the splash's rotation
		-- does not tip the run sideways).
		if random:NextNumber() < 0.45 then
			local drip = Instance.new("Frame")
			drip.AnchorPoint = Vector2.new(0.5, 0)
			drip.Position = UDim2.new(x + random:NextNumber(-0.02, 0.02), 0, y, 0)
			drip.Size = UDim2.new(size * 0.16, 0, random:NextNumber(0.08, 0.22), 0)
			drip.BackgroundColor3 = BLOOD
			drip.BackgroundTransparency = splash.BackgroundTransparency + 0.1
			drip.BorderSizePixel = 0
			drip.Parent = gui
		end
	end
end

local function buildRigTemplate()
	local description = Instance.new("HumanoidDescription")
	description.HeightScale = 1.42
	description.WidthScale = 0.78
	description.DepthScale = 0.82
	description.HeadScale = 0.9
	description.BodyTypeScale = 0.35
	description.ProportionScale = 1
	description.HeadColor = SKIN
	description.TorsoColor = SHIRT
	description.LeftArmColor = SHIRT
	description.RightArmColor = SHIRT
	description.LeftLegColor = TROUSERS
	description.RightLegColor = TROUSERS
	local ok, rig = pcall(function()
		return Players:CreateHumanoidModelFromDescription(description, Enum.HumanoidRigType.R15)
	end)
	if not ok or not rig then
		log:Info("No monster rig template (%s); clients use the simple body", tostring(rig))
		return
	end
	rig.Name = "TheCustomerRig"
	local animate = rig:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	local humanoid = rig:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	end
	for _, part in rig:GetDescendants() do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
			part.Massless = true
			if string.find(part.Name, "Hand") then
				-- Hands dark with dried blood.
				part.Color = BLOODY_HANDS
			elseif string.find(part.Name, "LowerArm") then
				-- Short sleeves: bare forearms.
				part.Color = SKIN
			elseif string.find(part.Name, "Foot") then
				part.Color = Color3.fromRGB(16, 15, 15)
			end
		elseif part:IsA("Decal") and part.Name == "face" then
			-- Its face is drawn by the client: no smile.
			part:Destroy()
		end
	end
	-- The uniform: shirt collar, the blue apron (bib, neck strap, long front), the badge.
	local lowerTorso = rig:FindFirstChild("LowerTorso")
	local upperTorso = rig:FindFirstChild("UpperTorso")
	if lowerTorso and lowerTorso:IsA("BasePart") and upperTorso and upperTorso:IsA("BasePart") then
		local up, low = upperTorso.Size, lowerTorso.Size
		wear(
			rig,
			upperTorso,
			"Collar",
			Vector3.new(up.X * 0.62, 0.22, up.Z * 1.06),
			CFrame.new(0, up.Y / 2 + 0.06, 0),
			SHIRT
		)
		local bib = wear(
			rig,
			upperTorso,
			"ApronBib",
			Vector3.new(up.X * 0.72, up.Y * 0.78, 0.06),
			CFrame.new(0, -up.Y * 0.1, -(up.Z / 2 + 0.03)),
			APRON
		)
		wear(
			rig,
			upperTorso,
			"ApronStrap",
			Vector3.new(up.X * 0.5, 0.12, up.Z + 0.08),
			CFrame.new(0, up.Y / 2 - 0.02, 0),
			APRON
		)
		local front = wear(
			rig,
			lowerTorso,
			"ApronFront",
			Vector3.new(low.X * 1.08, 2.5, 0.06),
			CFrame.new(0, -1.05, -(low.Z / 2 + 0.05)) * CFrame.Angles(-0.06, 0, 0),
			APRON
		)
		stain(bib, 7, 5)
		stain(front, 13, 6)

		-- "HELLO, MY NAME IS" - and the name scratched out.
		local badge = wear(
			rig,
			upperTorso,
			"NameBadge",
			Vector3.new(0.42, 0.22, 0.03),
			CFrame.new(up.X * 0.2, up.Y * 0.18, -(up.Z / 2 + 0.07)),
			Color3.fromRGB(226, 220, 204)
		)
		badge.Material = Enum.Material.SmoothPlastic
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 200
		gui.LightInfluence = 1
		gui.Parent = badge
		local hello = Instance.new("TextLabel")
		hello.BackgroundTransparency = 1
		hello.Size = UDim2.new(1, 0, 0.4, 0)
		hello.Text = "HELLO, MY NAME IS"
		hello.TextScaled = true
		hello.TextColor3 = Color3.fromRGB(150, 30, 30)
		hello.FontFace = Font.fromEnum(Enum.Font.GothamBold)
		hello.Parent = gui
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.new(0, 0, 0.4, 0)
		name.Size = UDim2.new(1, 0, 0.6, 0)
		name.Text = "WALTER"
		name.TextScaled = true
		name.TextColor3 = Color3.fromRGB(30, 30, 30)
		name.FontFace = Font.fromEnum(Enum.Font.PermanentMarker)
		name.Parent = gui
		for index = 1, 3 do
			local scratch = Instance.new("Frame")
			scratch.AnchorPoint = Vector2.new(0.5, 0.5)
			scratch.Position = UDim2.new(0.5, 0, 0.55 + index * 0.08, 0)
			scratch.Size = UDim2.new(0.9, 0, 0.07, 0)
			scratch.Rotation = (index - 2) * 6
			scratch.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
			scratch.BorderSizePixel = 0
			scratch.Parent = gui
		end
	end
	rig.Parent = ReplicatedStorage
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
	monsterTime += dt
	current:Step(dt)
	openDoors()
	MonsterManager.CheckHiders()
	sync()
end

-- Draws the monster to anyone who has been hiding too long (only while it is here).
function MonsterManager.CheckHiders()
	local current = brain
	if not current or not current.Present then
		-- Time spent hiding while it is away does not count.
		for _, entry in hiders do
			entry.Since = monsterTime
		end
		return
	end
	for _, entry in hiders do
		if
			not entry.Suspected
			and monsterTime - entry.Since >= MonsterConfig.Behaviour.LongHideSeconds
			and current:Suspect(entry.Spot)
		then
			entry.Suspected = true
			return -- one at a time
		end
	end
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

	HidingService.Changed:Connect(function(player: Player, spotId: number?)
		if spotId then
			hiders[player] = { Spot = spotId, Since = monsterTime, Suspected = false }
		else
			hiders[player] = nil
		end
	end)

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
	task.spawn(buildRigTemplate)

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
