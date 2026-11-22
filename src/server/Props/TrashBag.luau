--!strict
-- A full black bin bag, tied at the top. Used by the trash task (the bags you carry) and
-- by the dumpsters (the ones already thrown in).
--
-- No two are the same: the body is built from many overlapping rounded lumps placed at
-- random round a slumped profile - wide and heavy at the bottom where the rubbish has
-- settled, a couple of hard corners pushing out the plastic, narrowing in uneven folds up
-- to a twisted neck, a knot and the two tied ends. The plastic is glossy black, the
-- creases a shade lighter so they catch the light.

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local TrashBag = {}

local PLASTIC = Color3.fromRGB(32, 33, 38)
local CREASE = Color3.fromRGB(56, 58, 65)
local HOLLOW = Color3.fromRGB(16, 16, 20)

-- Where the hand holds the bag: the knot, this far above the body's centre.
TrashBag.GripHeight = 1.5

local function jitter(amount: number): number
	return (math.random() * 2 - 1) * amount
end

-- The plastic a little lighter or darker here and there.
local function shade(base: Color3): Color3
	local d = jitter(5) / 255
	return Color3.new(
		math.clamp(base.R + d, 0, 1),
		math.clamp(base.G + d, 0, 1),
		math.clamp(base.B + d, 0, 1)
	)
end

-- A rounded shape (a sphere mesh stretched to the part's size).
local function blob(name: string, size: Vector3, color: Color3?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color or shade(PLASTIC)
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = if color == HOLLOW then 0.04 else 0.16
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- A round bar (a cylinder whose axis is the part's X axis).
local function bar(name: string, length: number, thickness: number, color: Color3?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(length, thickness, thickness)
	part.Color = color or PLASTIC
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = 0.14
	return part
end

-- Lumps spaced round a ring at height `y`, each a random size and a little out of place.
local function ring(
	attach: (BasePart, CFrame) -> (),
	count: number,
	y: number,
	radius: number,
	size: Vector3,
	spread: number
)
	local start = math.random() * math.pi * 2
	for index = 1, count do
		local angle = start + index / count * math.pi * 2 + jitter(0.35)
		local r = radius + jitter(spread)
		local lump = blob(
			"Lump",
			Vector3.new(
				size.X * (0.8 + math.random() * 0.4),
				size.Y * (0.8 + math.random() * 0.35),
				size.Z * (0.8 + math.random() * 0.4)
			)
		)
		attach(
			lump,
			CFrame.new(math.cos(angle) * r, y + jitter(0.08), math.sin(angle) * r)
				* CFrame.Angles(jitter(0.3), math.random() * math.pi, jitter(0.3))
		)
	end
end

-- The real bags: sculpted meshes kept in ServerStorage.PropMeshes (TrashBagA, TrashBagB -
-- made with Roblox's mesh generator in Studio, black glossy plastic with the folds running
-- up to the knot, as in the reference photos). They live in the place file, not in the
-- source, so a place built from source alone falls back to the bag built from parts below.
local function meshTemplates(): { MeshPart }
	local folder = ServerStorage:FindFirstChild("PropMeshes")
	local list = {}
	if folder then
		for _, child in folder:GetChildren() do
			if child:IsA("MeshPart") and string.sub(child.Name, 1, 8) == "TrashBag" then
				table.insert(list, child)
			end
		end
	end
	return list
end

-- A bag from one of the meshes, a little different in size and turned at random, its
-- bottom where a built bag's would be.
local function fromMesh(template: MeshPart, position: Vector3): BasePart
	local bag = template:Clone()
	local scale = 0.92 + math.random() * 0.16
	bag.Size = template.Size * Vector3.new(scale * (0.95 + math.random() * 0.1), scale, scale)
	local bottom = position.Y - 0.86
	bag.CFrame = CFrame.new(position.X, bottom + bag.Size.Y / 2, position.Z)
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)
	bag.Name = "TrashBag"
	-- Held by the knot, just below the very top.
	bag:SetAttribute("GripHeight", bag.Size.Y / 2 - 0.18)
	bag.Anchored = false
	bag.CanCollide = false
	bag.Parent = Workspace
	return bag
end

-- Builds a bag standing at `position` (the centre of its body; its bottom is about 0.9
-- below). The body is the returned part; everything else is welded to it.
function TrashBag.Create(position: Vector3): BasePart
	local templates = meshTemplates()
	if #templates > 0 then
		return fromMesh(templates[math.random(1, #templates)], position)
	end
	local bag = blob("TrashBag", Vector3.new(1.55, 1.6, 1.4))
	bag.CFrame = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	bag:SetAttribute("GripHeight", TrashBag.GripHeight)

	local function attach(part: BasePart, offset: CFrame)
		part.CFrame = bag.CFrame * offset
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = true
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = bag
		weld.Part1 = part
		weld.Parent = part
		part.Parent = bag
	end

	-- Settled on the floor: a flat dark underside and an uneven, bulging bottom.
	attach(blob("Base", Vector3.new(1.65, 0.32, 1.5), HOLLOW), CFrame.new(jitter(0.05), -0.78, jitter(0.05)))
	-- (The lumps sit mostly inside the body and only push its surface out a little here
	-- and there: broad, uneven bulges rather than a bunch of balls.)
	ring(attach, 5, -0.42, 0.32, Vector3.new(1.15, 0.9, 1.05), 0.08)
	-- The middle: the sides sag and bulge unevenly.
	ring(attach, 4, 0.08, 0.28, Vector3.new(1.0, 0.95, 0.9), 0.08)
	-- Hard corners of whatever is inside (a box, a bottle) pushing at the plastic.
	for _ = 1, 2 do
		local angle = math.random() * math.pi * 2
		local corner = blob("Corner", Vector3.new(0.5 + math.random() * 0.2, 0.55, 0.42))
		attach(
			corner,
			CFrame.new(math.cos(angle) * 0.58, -0.25 + jitter(0.2), math.sin(angle) * 0.58)
				* CFrame.Angles(jitter(0.5), angle, jitter(0.5))
		)
	end
	-- Narrowing towards the top: a ring of smaller lumps, then the gathered plastic.
	ring(attach, 3, 0.6, 0.16, Vector3.new(0.85, 0.65, 0.78), 0.06)
	local lean = Vector3.new(jitter(0.1), 0, jitter(0.1))
	attach(blob("Gather", Vector3.new(0.62, 0.5, 0.58)), CFrame.new(lean * 0.6 + Vector3.new(0, 0.98, 0)))
	-- Folds where the plastic was pulled up and tied: uneven ridges lying on the surface,
	-- leaning in towards the neck, two short pieces each so they bend.
	local folds = 7 + math.random(0, 3)
	for index = 1, folds do
		local angle = index / folds * math.pi * 2 + jitter(0.25)
		local out = Vector3.new(math.cos(angle), 0, math.sin(angle))
		local tangent = Vector3.new(-out.Z, 0, out.X)
		local length = 0.5 + math.random() * 0.25
		local lower = (Vector3.new(0, 0.9, 0) - out * 0.35).Unit
		local upper = (Vector3.new(0, 0.9, 0) - out * 0.75).Unit
		local thick = 0.06 + math.random() * 0.04
		attach(
			blob("Fold", Vector3.new(thick, length, thick * 1.3), CREASE),
			CFrame.fromMatrix(out * 0.58 + Vector3.new(0, 0.32, 0), tangent, lower)
		)
		attach(
			blob("Fold", Vector3.new(thick * 0.9, length * 0.8, thick * 1.2), CREASE),
			CFrame.fromMatrix(out * 0.42 + lean * 0.5 + Vector3.new(0, 0.78, 0), tangent, upper)
		)
	end
	-- The twisted neck, a little off-centre.
	attach(
		bar("Neck", 0.32, 0.22),
		CFrame.new(lean + Vector3.new(0, 1.24, 0)) * CFrame.Angles(jitter(0.2), 0.4, math.pi / 2)
	)
	attach(
		bar("Twist", 0.12, 0.28, CREASE),
		CFrame.new(lean + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 1.2, math.pi / 2 + jitter(0.2))
	)
	-- The knot, and the two short tied ends sticking out of it.
	attach(
		blob("Knot", Vector3.new(0.32, 0.25, 0.3)),
		CFrame.new(lean + Vector3.new(0, 1.44, 0)) * CFrame.Angles(0, math.random() * 3, jitter(0.3))
	)
	for _, side in { 1, -1 } do
		attach(
			blob("Ear", Vector3.new(0.13, 0.22 + math.random() * 0.06, 0.09)),
			CFrame.new(lean + Vector3.new(side * 0.13, 1.56, jitter(0.05)))
				* CFrame.Angles(jitter(0.3), 0, side * -(0.6 + math.random() * 0.4))
		)
	end

	bag.Parent = Workspace
	return bag
end

return TrashBag
