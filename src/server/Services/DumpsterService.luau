--!strict
-- The dumpsters behind the store (tag: Dumpster). The map only places a plain block for
-- each - its footprint, its collision and where the "Throw away" prompt goes. This turns
-- each one into a proper commercial bin: a green steel box higher at the back than at the
-- front, a rusty inside, two black ribbed plastic lids (one shut, one thrown open), fork
-- pockets on the sides, a reinforcing rib, a chained padlock, skids underneath - with a
-- pile of bin bags inside and flies hanging over it.
--
-- Every bag thrown away during the night lands on that pile and stays there until the
-- next shift starts.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Config.Tags)
local GameManager = require(script.Parent.GameManager)
local TrashBag = require(script.Parent.Parent.Props.TrashBag)

local DumpsterService = {}

-- Size (studs): across, front to back, height at the back and at the front.
local WIDTH = 8.5
local DEPTH = 6
local HEIGHT_BACK = 4.6
local HEIGHT_FRONT = 3.7
local WALL = 0.16
-- The box stands on skids this high.
local SKIDS = 0.25
-- Bags already in each bin when the night starts, and how many fit on the pile.
local BAGS_AT_START = 3
local MAX_BAGS = 10

local GREEN = Color3.fromRGB(44, 116, 64)
local GREEN_DARK = Color3.fromRGB(31, 88, 49)
local RUST = Color3.fromRGB(104, 44, 30)
local LID = Color3.fromRGB(30, 31, 33)
local STEEL = Color3.fromRGB(120, 122, 126)
local DARK = Color3.fromRGB(22, 22, 24)

type Bin = {
	Part: BasePart,
	Frame: CFrame, -- at the ground, in the middle, -Z towards the front
	Bags: { BasePart },
	Started: number, -- bags put there when the night began
}

local bins: { [BasePart]: Bin } = {}

-- Which way the bin faces: the side of its block that points at the store.
local function frontOf(part: BasePart): Vector3
	local toStore = Vector3.new(-part.Position.X, 0, -part.Position.Z)
	local best, bestDot = part.CFrame.LookVector, -math.huge
	for _, axis in { part.CFrame.LookVector, part.CFrame.RightVector } do
		for _, sign in { 1, -1 } do
			local candidate = Vector3.new(axis.X, 0, axis.Z).Unit * sign
			local dot = candidate:Dot(toStore)
			if dot > bestDot then
				best, bestDot = candidate, dot
			end
		end
	end
	return best
end

local function dress(part: BasePart): Bin
	local ground = part.Position.Y - part.Size.Y / 2
	local base = Vector3.new(part.Position.X, ground, part.Position.Z)
	local frame = CFrame.lookAt(base, base + frontOf(part))

	-- The block becomes the bin's invisible collision box (and still holds the prompt).
	part.Size = Vector3.new(WIDTH, HEIGHT_BACK + SKIDS, DEPTH)
	part.CFrame = frame * CFrame.new(0, (HEIGHT_BACK + SKIDS) / 2, 0)
	part.Transparency = 1
	for _, child in part:GetChildren() do
		if child:IsA("BasePart") then
			child:Destroy()
		end
	end

	local model = Instance.new("Model")
	model.Name = "Bin"
	model.Parent = part
	local function add(
		name: string,
		size: Vector3,
		at: CFrame,
		color: Color3,
		material: Enum.Material?,
		class: string?
	): BasePart
		local piece = Instance.new(class or "Part") :: BasePart
		piece.Name = name
		piece.Size = size
		piece.CFrame = frame * at
		piece.Color = color
		-- (Painted steel reads best as plain plastic: Roblox's metal is dark and glossy and
		-- barely shows under one lamp at night.)
		piece.Material = material or Enum.Material.Plastic
		piece.Anchored = true
		piece.CanCollide = false
		piece.CanQuery = false
		piece.CanTouch = false
		piece.TopSurface = Enum.SurfaceType.Smooth
		piece.BottomSurface = Enum.SurfaceType.Smooth
		piece.Parent = model
		return piece
	end

	local w, d, hb, hf, t, y0 = WIDTH, DEPTH, HEIGHT_BACK, HEIGHT_FRONT, WALL, SKIDS
	local rise = hb - hf
	local slope = math.atan2(rise, d)
	local topLength = math.sqrt(d * d + rise * rise)

	-- Skids and floor.
	for _, s in { 1, -1 } do
		add("Skid", Vector3.new(0.35, y0, d - 0.2), CFrame.new(s * (w / 2 - 0.7), y0 / 2, 0), DARK)
	end
	add("Floor", Vector3.new(w, 0.2, d), CFrame.new(0, y0 + 0.1, 0), GREEN_DARK)

	-- Walls: low at the front, high at the back, the sides sloping between (a box topped
	-- by a wedge, whose tall side is at the back).
	add("Front", Vector3.new(w, hf, t), CFrame.new(0, y0 + hf / 2, -d / 2 + t / 2), GREEN)
	add("Back", Vector3.new(w, hb, t), CFrame.new(0, y0 + hb / 2, d / 2 - t / 2), GREEN)
	for _, s in { 1, -1 } do
		local x = s * (w / 2 - t / 2)
		add("Side", Vector3.new(t, hf, d), CFrame.new(x, y0 + hf / 2, 0), GREEN)
		add("SideTop", Vector3.new(t, rise, d), CFrame.new(x, y0 + hf + rise / 2, 0), GREEN, nil, "WedgePart")
	end

	-- The inside: rusty brown steel.
	local inner = 0.011
	add(
		"Liner",
		Vector3.new(w - 2 * t, hf - 0.1, 0.02),
		CFrame.new(0, y0 + hf / 2, -d / 2 + t + inner),
		RUST,
		Enum.Material.CorrodedMetal
	)
	add(
		"Liner",
		Vector3.new(w - 2 * t, hb - 0.1, 0.02),
		CFrame.new(0, y0 + hb / 2, d / 2 - t - inner),
		RUST,
		Enum.Material.CorrodedMetal
	)
	add(
		"Liner",
		Vector3.new(w - 2 * t, 0.02, d - 2 * t),
		CFrame.new(0, y0 + 0.2 + inner, 0),
		RUST,
		Enum.Material.CorrodedMetal
	)
	for _, s in { 1, -1 } do
		add(
			"Liner",
			Vector3.new(0.02, hf - 0.1, d - 2 * t),
			CFrame.new(s * (w / 2 - t - inner), y0 + hf / 2, 0),
			RUST,
			Enum.Material.CorrodedMetal
		)
	end

	-- The rim round the top.
	add("Rim", Vector3.new(w + 0.12, 0.2, 0.3), CFrame.new(0, y0 + hf, -d / 2 + 0.05), GREEN_DARK)
	add("Rim", Vector3.new(w + 0.12, 0.2, 0.3), CFrame.new(0, y0 + hb, d / 2 - 0.05), GREEN_DARK)
	for _, s in { 1, -1 } do
		add(
			"Rim",
			Vector3.new(0.3, 0.2, topLength),
			CFrame.new(s * w / 2, y0 + (hf + hb) / 2, 0) * CFrame.Angles(-slope, 0, 0),
			GREEN_DARK
		)
	end

	-- A lid: black ribbed plastic, its free edge at its -Z end.
	local lidWidth = w / 2 - 0.1
	local lidLength = topLength + 0.15
	local function lid(at: CFrame)
		local plate = add("Lid", Vector3.new(lidWidth, 0.14, lidLength), at, LID, Enum.Material.Plastic)
		local plateFrame = frame:ToObjectSpace(plate.CFrame)
		for index = -2, 2 do
			add(
				"Rib",
				Vector3.new(0.16, 0.1, lidLength - 0.5),
				plateFrame * CFrame.new(index * lidWidth / 5.5, 0.1, 0.1),
				LID,
				Enum.Material.Plastic
			)
		end
		add(
			"LidEdge",
			Vector3.new(lidWidth, 0.22, 0.12),
			plateFrame * CFrame.new(0, -0.02, -lidLength / 2 + 0.06),
			LID,
			Enum.Material.Plastic
		)
	end
	-- Left one shut, lying on the slope.
	lid(CFrame.new(-w / 4, y0 + (hf + hb) / 2 + 0.17, 0) * CFrame.Angles(-slope, 0, 0))
	-- Right one thrown open: flipped over its hinge at the back, leaning back.
	local hinge = Vector3.new(w / 4, y0 + hb + 0.08, d / 2 + 0.02)
	local up = Vector3.new(0, 0.8, 0.6)
	local outward = Vector3.new(0, -0.6, 0.8)
	lid(CFrame.fromMatrix(hinge + up * lidLength / 2, Vector3.new(1, 0, 0), outward))

	-- Fork pockets on the sides, a rib across the front, the front corner posts.
	for _, s in { 1, -1 } do
		add(
			"ForkPocket",
			Vector3.new(0.32, 0.8, 1.9),
			CFrame.new(s * (w / 2 + 0.16), y0 + hf * 0.45, 0),
			GREEN_DARK
		)
		add("ForkHole", Vector3.new(0.34, 0.5, 1.6), CFrame.new(s * (w / 2 + 0.17), y0 + hf * 0.45, 0), DARK)
		add(
			"Post",
			Vector3.new(0.22, hf, 0.2),
			CFrame.new(s * (w / 2 - 0.1), y0 + hf / 2, -d / 2 - 0.06),
			GREEN_DARK
		)
	end
	add("FrontRib", Vector3.new(w - 0.2, 0.25, 0.18), CFrame.new(0, y0 + hf * 0.3, -d / 2 - 0.07), GREEN_DARK)

	-- A chained padlock hanging from the front edge.
	add(
		"Chain",
		Vector3.new(0.06, 0.5, 0.06),
		CFrame.new(0.4, y0 + hf - 0.3, -d / 2 - 0.12),
		STEEL,
		Enum.Material.Metal
	)
	add(
		"Padlock",
		Vector3.new(0.2, 0.24, 0.1),
		CFrame.new(0.4, y0 + hf - 0.66, -d / 2 - 0.13),
		STEEL,
		Enum.Material.Metal
	)

	-- Worn paint and grime: faint, uneven streaks running down the front.
	for _ = 1, 5 do
		local streak = add(
			"Grime",
			Vector3.new(0.15 + math.random() * 0.5, 0.6 + math.random() * 1.6, 0.02),
			CFrame.new((math.random() - 0.5) * (w - 1.2), y0 + 0.3 + math.random() * (hf - 2), -d / 2 - 0.01),
			Color3.fromRGB(34, 62, 38),
			Enum.Material.Concrete
		)
		streak.Transparency = 0.55
	end

	-- Old rubbish filling the bin most of the way up: squashed bags and flattened boxes.
	-- The new bags go on top of it, where they show over the rim.
	for _ = 1, 7 do
		local lump = add(
			"OldBag",
			Vector3.new(2 + math.random() * 1.2, 1.4 + math.random() * 0.6, 1.8 + math.random() * 0.8),
			CFrame.new(
				(math.random() - 0.5) * (w - 2.6),
				y0 + 1.0 + math.random() * 0.5,
				(math.random() - 0.5) * (d - 2.4)
			) * CFrame.Angles(0, math.random() * math.pi, 0),
			Color3.fromRGB(26 + math.random(0, 8), 27 + math.random(0, 8), 31 + math.random(0, 8)),
			Enum.Material.SmoothPlastic
		)
		lump.Reflectance = 0.25
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = lump
	end
	for _ = 1, 3 do
		add(
			"Cardboard",
			Vector3.new(1.4 + math.random() * 0.6, 0.12, 1 + math.random() * 0.6),
			CFrame.new(
				(math.random() - 0.5) * (w - 2.5),
				y0 + 1.75 + math.random() * 0.2,
				(math.random() - 0.5) * (d - 2.5)
			)
				* CFrame.Angles(
					(math.random() - 0.5) * 0.8,
					math.random() * math.pi,
					(math.random() - 0.5) * 0.8
				),
			Color3.fromRGB(150, 112, 70),
			Enum.Material.Cardboard
		)
	end

	-- Flies over the open side: tiny dark specks drifting about.
	local swarm =
		add("Flies", Vector3.new(w / 2 - 0.6, 1.2, d - 1.2), CFrame.new(w / 4, y0 + hf + 0.9, 0), DARK)
	swarm.Transparency = 1
	if ColorSequence then
		for index, settings in { { Rate = 14, Speed = 1.6, Up = 0.25 }, { Rate = 8, Speed = 2.6, Up = -0.2 } } do
			local flies = Instance.new("ParticleEmitter")
			flies.Name = "Flies" .. index
			flies.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			-- (Lit by the lamp like everything else, so they show against the bin.)
			flies.Color = ColorSequence.new(Color3.fromRGB(70, 68, 60))
			flies.LightEmission = 0
			flies.LightInfluence = 1
			flies.Size = NumberSequence.new(0.09)
			flies.Rate = settings.Rate
			flies.Lifetime = NumberRange.new(1.2, 2.6)
			flies.Speed = NumberRange.new(settings.Speed * 0.4, settings.Speed)
			flies.SpreadAngle = Vector2.new(180, 180)
			flies.Drag = 1.8
			flies.Acceleration = Vector3.new(0, settings.Up, 0)
			flies.RotSpeed = NumberRange.new(-200, 200)
			flies.Shape = Enum.ParticleEmitterShape.Box
			flies.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			flies.Parent = swarm
		end
	end

	local bin: Bin = { Part = part, Frame = frame, Bags = {}, Started = 0 }
	return bin
end

-- Where the next bag goes on the pile: across the open half, filling a layer, then the
-- next one up.
local function pileSpot(bin: Bin, index: number): CFrame
	local perLayer = 4
	local layer = math.floor((index - 1) / perLayer)
	local slot = (index - 1) % perLayer
	local x = WIDTH / 4 + (if slot % 2 == 0 then -1 else 1) * 1.0 + (math.random() - 0.5) * 0.3
	local z = (if slot < 2 then -1 else 1) * 1.25 + (math.random() - 0.5) * 0.3
	-- (On top of the old rubbish, about 1.9 studs deep.)
	local y = SKIDS + 1.9 + 0.86 + layer * 1.05
	return bin.Frame
		* CFrame.new(x, y, z)
		* CFrame.Angles((math.random() - 0.5) * 0.5, math.random() * math.pi * 2, (math.random() - 0.5) * 0.5)
end

-- Puts a bag on the pile in this bin (the bag a player just threw away).
function DumpsterService.Store(part: BasePart)
	local bin = bins[part]
	if not bin or #bin.Bags >= MAX_BAGS then
		return
	end
	local bag = TrashBag.Create(Vector3.zero)
	bag.Anchored = true
	bag.CanCollide = false
	-- (pileSpot places a bag whose centre is 0.86 above its bottom; taller ones are raised.)
	bag.CFrame = pileSpot(bin, #bin.Bags + 1) * CFrame.new(0, bag.Size.Y / 2 - 0.86, 0)
	bag.Name = "BinnedBag"
	bag.Parent = part
	table.insert(bin.Bags, bag)
end

-- Bags thrown in during the night, in this bin.
function DumpsterService.GetCount(part: BasePart): number
	local bin = bins[part]
	return if bin then #bin.Bags - bin.Started else 0
end

-- Back to how it was when the night began.
local function reset(bin: Bin)
	for index = #bin.Bags, bin.Started + 1, -1 do
		bin.Bags[index]:Destroy()
		bin.Bags[index] = nil
	end
end

function DumpsterService.Start()
	for _, part in CollectionService:GetTagged(Tags.Dumpster) do
		if part:IsA("BasePart") and not bins[part] then
			local bin = dress(part)
			bins[part] = bin
			for _ = 1, BAGS_AT_START do
				DumpsterService.Store(part)
			end
			bin.Started = #bin.Bags
		end
	end
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase == "Lobby" then
			for _, bin in bins do
				reset(bin)
			end
		end
	end)
end

return DumpsterService
