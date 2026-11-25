--!strict
-- Dresses the restrooms' fittings (tag: Fitting, Kind = Toilet / Urinal / Sink /
-- PaperHolder / StallBin / TowelBin) with the
-- sculpted, filthy meshes kept in ServerStorage.PropMeshes (RestroomToilet,
-- RestroomUrinal, RestroomSink - made in Studio with Roblox's mesh generator). The plain
-- block-built fitting under it is hidden; it still blocks movement where it should.
-- Without the meshes (a place built from the source alone) the plain fittings stay.

local CollectionService = game:GetService("CollectionService")
local ServerStorage = game:GetService("ServerStorage")

local RestroomService = {}

local TEMPLATE = {
	Toilet = "RestroomToilet",
	Urinal = "RestroomUrinal",
	Sink = "RestroomSink",
	PaperHolder = "RestroomPaperHolder",
	StallBin = "RestroomStallBin",
	TowelBin = "RestroomTowelBin",
	HandDryer = "RestroomHandDryer",
	TowelDispenser = "RestroomTowelDispenser",
}

-- Plain pieces that belong with each fitting and go when the mesh comes in.
local COMPANIONS = { Toilet = { "ToiletTank" }, Urinal = { "UrinalLip", "FlushPipe" }, Sink = { "Tap" } }

local function hideNear(part: BasePart, names: { string })
	local parent = part.Parent
	if not parent then
		return
	end
	for _, child in parent:GetChildren() do
		if
			child:IsA("BasePart")
			and table.find(names, child.Name)
			and (child.Position - part.Position).Magnitude < 2.2
		then
			child.Transparency = 1
			child.CanCollide = false
		end
	end
end

local function dress(part: BasePart, folder: Instance)
	local kind = part:GetAttribute("Kind")
	local name = if type(kind) == "string" then TEMPLATE[kind] else nil
	local template = if name then folder:FindFirstChild(name) else nil
	if not template or not template:IsA("BasePart") then
		return
	end
	local base = Vector3.new(
		part:GetAttribute("BaseX") :: number,
		part:GetAttribute("BaseY") :: number,
		part:GetAttribute("BaseZ") :: number
	)
	local facing = part:GetAttribute("Facing") :: number
	local mesh = template:Clone()
	mesh.Name = name :: string
	mesh.Anchored = true
	mesh.CanCollide = false
	mesh.CanQuery = false
	mesh.CanTouch = false
	-- Facing: 0 = towards +X (back to the west wall), otherwise along Z (+1 / -1: the
	-- sinks face away from the plumbing wall).
	local look = if facing == 0 then Vector3.new(1, 0, 0) else Vector3.new(0, 0, facing)
	local size = mesh.Size
	local centre
	if kind == "Sink" then
		-- Top of the basin level with the counter, centred on it.
		centre = base + Vector3.new(0, size.Y / 2 - 0.35, 0)
	else
		-- Back against the wall, standing on the floor (or the wall bracket height).
		centre = base + look * (size.Z / 2) + Vector3.new(0, size.Y / 2, 0)
	end
	-- (The generated meshes have their front on their -Z side, the LookVector.)
	mesh.CFrame = CFrame.lookAt(centre, centre + look)
	mesh.Parent = part.Parent
	part.Transparency = 1
	hideNear(part, COMPANIONS[kind] or {})
end

function RestroomService.Start()
	local folder = ServerStorage:FindFirstChild("PropMeshes")
	if not folder then
		return
	end
	for _, part in CollectionService:GetTagged("Fitting") do
		if part:IsA("BasePart") then
			dress(part, folder)
		end
	end
end

return RestroomService
