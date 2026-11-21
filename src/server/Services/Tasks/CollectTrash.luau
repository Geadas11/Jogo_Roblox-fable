--!strict
-- Take out the trash: bags of rubbish appear around the store and have to be carried
-- to the dumpsters in the loading area behind the building - outside, at night.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Config.Tags)
local Services = script.Parent.Parent
local CarryService = require(Services.CarryService)
local InteractionService = require(Services.InteractionService)

local CollectTrash = {}

-- The dumpsters carry one "Throw away" prompt each, so only one trash run exists at a time.
local active = false

-- Dark grey shiny plastic (pure black reads as a hole under the store lights), tied with
-- a yellow drawstring - the handle you see in your hand.
local BAG_PLASTIC = Color3.fromRGB(46, 48, 54)
local DRAWSTRING = Color3.fromRGB(232, 196, 58)

-- A rounded shape (a sphere mesh stretched to the part's size).
local function blob(name: string, size: Vector3, color: Color3?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color or BAG_PLASTIC
	part.Material = Enum.Material.SmoothPlastic
	part.Reflectance = if color then 0 else 0.24
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Where the hand holds the bag: the top of the drawstring loop, this far above the
-- body's centre. CarryService hangs the bag from here, free to swing.
local GRIP_HEIGHT = 1.3

-- A thin straight piece of drawstring from `a` to `b` (bag space).
local function string_(a: Vector3, b: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "Drawstring"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new((b - a).Magnitude, 0.06, 0.06)
	part.Color = DRAWSTRING
	part.Material = Enum.Material.SmoothPlastic
	return part
end

-- A bin bag: a full body that sits wide on the floor with a bulge to one side, the
-- plastic gathered up into a short twisted neck, cinched with a yellow drawstring whose
-- loop is the handle, and the two loose ends of the plastic flopping down either side.
-- The body is the item (CarryService moves it); the rest is welded to it.
local function createBag(position: Vector3): BasePart
	local bag = blob("TrashBag", Vector3.new(1.45, 1.45, 1.35))
	bag.CFrame = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
	bag:SetAttribute("GripHeight", GRIP_HEIGHT)

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
	-- Wider and flatter at the bottom, where the rubbish settles; a bulge to one side.
	-- (Overlapping, so they melt into one lumpy shape instead of stacked rings.)
	attach(blob("Bottom", Vector3.new(1.55, 1.0, 1.45)), CFrame.new(0.04, -0.24, -0.03))
	attach(blob("Lump", Vector3.new(1.0, 1.0, 0.92)), CFrame.new(0.4, -0.05, 0.3))
	attach(blob("Lump", Vector3.new(0.82, 0.86, 0.8)), CFrame.new(-0.36, 0.08, -0.3))
	-- The plastic gathered in towards the neck.
	attach(blob("Gather", Vector3.new(0.95, 0.7, 0.88)), CFrame.new(0, 0.46, 0))
	local neck = Instance.new("Part")
	neck.Name = "Neck"
	neck.Shape = Enum.PartType.Cylinder
	neck.Size = Vector3.new(0.3, 0.26, 0.26)
	neck.Color = BAG_PLASTIC
	neck.Material = Enum.Material.SmoothPlastic
	neck.Reflectance = 0.2
	attach(neck, CFrame.new(0, 0.88, 0) * CFrame.Angles(0, 0, math.pi / 2))
	attach(blob("Knot", Vector3.new(0.3, 0.22, 0.28)), CFrame.new(0, 1.04, 0))
	-- The loose ends of the plastic, flopped over to each side.
	for _, side in { 1, -1 } do
		attach(
			blob("Flap", Vector3.new(0.42, 0.08, 0.26)),
			CFrame.new(side * 0.2, 1.02, 0.02) * CFrame.Angles(0, 0, side * -0.75)
		)
	end
	-- The drawstring: cinched round the neck, its loop standing up as the handle.
	local cinch = Instance.new("Part")
	cinch.Name = "Drawstring"
	cinch.Shape = Enum.PartType.Cylinder
	cinch.Size = Vector3.new(0.05, 0.3, 0.3)
	cinch.Color = DRAWSTRING
	cinch.Material = Enum.Material.SmoothPlastic
	attach(cinch, CFrame.new(0, 0.92, 0) * CFrame.Angles(0, 0, math.pi / 2))
	local top = Vector3.new(0, GRIP_HEIGHT, 0)
	for _, side in { 1, -1 } do
		local foot = Vector3.new(side * 0.13, 1.06, 0)
		local piece = string_(foot, top)
		attach(piece, CFrame.lookAt((foot + top) / 2, top) * CFrame.Angles(0, math.pi / 2, 0))
	end

	-- The prompt (CarryService) sits on the body; the whole bag stands on the floor.
	bag.Parent = Workspace
	return bag
end

function CollectTrash.Begin(task: any, count: number, context: any): number
	if active then
		return 0
	end
	local dumpsters = {}
	for _, dumpster in CollectionService:GetTagged(Tags.Dumpster) do
		if dumpster:IsA("BasePart") then
			table.insert(dumpsters, dumpster)
		end
	end
	local points = {}
	for _, point in CollectionService:GetTagged(Tags.TrashPoint) do
		if point:IsA("BasePart") then
			table.insert(points, point)
		end
	end
	if #dumpsters == 0 or #points == 0 then
		return 0
	end

	local state = { Bags = {}, Prompts = {} }
	task.State = state
	active = true

	for _, point in context.Rng:Sample(points, count) do
		-- The marker floats half a stud above the ground.
		local ground = point.Position.Y - 0.5
		local bag = createBag(Vector3.new(point.Position.X, ground + 0.75, point.Position.Z))
		CarryService.Register(bag, "Trash")
		table.insert(state.Bags, bag)
	end

	for _, dumpster in dumpsters do
		table.insert(
			state.Prompts,
			InteractionService.AddPrompt(dumpster, {
				action = "Throw away",
				object = "Trash",
				hold = 1,
				distance = 10,
			}, function(player: Player)
				if not CarryService.Consume(player, "Trash") then
					context.Notify(player, "You are not carrying a trash bag.", "Warning")
					return
				end
				context.Progress(1, player)
			end)
		)
	end

	task.Detail = "Carry the bags to the dumpsters behind the store."
	return #state.Bags
end

function CollectTrash.Cleanup(task: any)
	local state = task.State
	if not state then
		return
	end
	for _, prompt in state.Prompts do
		prompt:Destroy()
	end
	for _, bag in state.Bags do
		if bag.Parent then
			CarryService.Remove(bag)
		end
	end
	active = false
	task.State = nil
end

return CollectTrash
