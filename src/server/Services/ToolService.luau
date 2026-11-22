--!strict
-- Puts the tools players need for their work where the map says they are kept
-- (tag: ToolPickup). Currently: mops by the bucket in the maintenance room.
--
-- Tools left lying around the store go back to their station at the start of every
-- shift, so a mop dropped in the parking lot last night never makes spills impossible.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Tags = require(Shared.Config.Tags)
local Log = require(Shared.Util.Log)
local CarryService = require(script.Parent.CarryService)
local GameManager = require(script.Parent.GameManager)

local log = Log.new("Tools")

local ToolService = {}

-- Every tool created here and where it is kept.
local homes: { [BasePart]: CFrame } = {}

-- The cleaning tool is an old straw broom (the "Mop" kind, as the tasks call it): a long
-- pale wooden handle with flecks of worn orange paint, and a flat fan of straw - bound
-- tight at the top with rows of dark stitching, spreading out to a ragged, darker edge.
-- The item itself is an invisible stick the length of the whole broom (it stands upright
-- on its bristles, and the prompt sits halfway up); everything you see is welded to it.
local BROOM_LENGTH = 5.4
local HANDLE = Color3.fromRGB(196, 186, 166)
local PAINT = Color3.fromRGB(196, 104, 52)
local STRAW = Color3.fromRGB(184, 140, 82)
local STRAW_DARK = Color3.fromRGB(122, 86, 46)
local STITCH = Color3.fromRGB(58, 40, 28)

local function createMop(position: Vector3): BasePart
	local broom = Instance.new("Part")
	broom.Name = "Mop"
	broom.Size = Vector3.new(0.3, BROOM_LENGTH, 0.3)
	broom.Transparency = 1
	broom.CFrame = CFrame.new(position)
	broom:SetAttribute("Tool", "Broom")

	local bottom = -BROOM_LENGTH / 2
	local function attach(part: BasePart, offset: CFrame)
		part.CFrame = broom.CFrame * offset
		part.Anchored = false
		part.Massless = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = broom
		weld.Part1 = part
		weld.Parent = part
		part.Parent = broom
	end
	local function piece(name: string, size: Vector3, color: Color3, material: Enum.Material): Part
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material
		return part
	end
	local function rod(name: string, length: number, thickness: number, color: Color3): Part
		local part = piece(name, Vector3.new(length, thickness, thickness), color, Enum.Material.Wood)
		part.Shape = Enum.PartType.Cylinder
		return part
	end
	-- (A cylinder's axis is its X axis: turned to stand along the broom.)
	local upright = CFrame.Angles(0, 0, math.pi / 2)

	-- The handle, from inside the straw to the top, with a rounded end.
	local handleBottom = bottom + 1.1
	local handleLength = BROOM_LENGTH / 2 - handleBottom
	attach(
		rod("Handle", handleLength, 0.17, HANDLE),
		CFrame.new(0, handleBottom + handleLength / 2, 0) * upright
	)
	local cap = piece("HandleEnd", Vector3.new(0.17, 0.17, 0.17), HANDLE, Enum.Material.Wood)
	cap.Shape = Enum.PartType.Ball
	attach(cap, CFrame.new(0, BROOM_LENGTH / 2, 0))
	-- Worn flecks of orange paint along it.
	for index, y in { 1.9, 1.1, 0.5, -0.3 } do
		attach(
			rod("Paint", 0.07 + (index % 2) * 0.05, 0.176, PAINT),
			CFrame.new(0, y, 0) * upright * CFrame.Angles(index * 1.3, 0, 0)
		)
	end

	-- The straw: gathered round the end of the handle into a rounded collar, then pressed
	-- into a flat fan that widens down to the floor.
	local collar = piece("Collar", Vector3.new(0.5, 0.5, 0.34), STRAW, Enum.Material.Fabric)
	local collarMesh = Instance.new("SpecialMesh")
	collarMesh.MeshType = Enum.MeshType.Sphere
	collarMesh.Parent = collar
	attach(collar, CFrame.new(0, bottom + 1.12, 0))
	attach(
		piece("Body", Vector3.new(0.66, 0.6, 0.26), STRAW, Enum.Material.Fabric),
		CFrame.new(0, bottom + 0.82, 0)
	)
	-- Rows of stitching across the bound part.
	for index = 0, 2 do
		attach(
			piece("Stitch", Vector3.new(0.68 + index * 0.06, 0.05, 0.28), STITCH, Enum.Material.Fabric),
			CFrame.new(0, bottom + 1.0 - index * 0.15, 0)
		)
	end
	-- The loose straw fanning out below the stitching: strips that lean further out the
	-- further they are from the middle, darker and ragged at the tips.
	local strips = 9
	for index = 1, strips do
		local across = (index - (strips + 1) / 2) / ((strips - 1) / 2) -- -1 .. 1
		local length = 0.62 + (1 - math.abs(across)) * 0.06 + (index % 3) * 0.03
		-- (Turned about its middle, so its bottom end swings out to the side it is on.)
		local lean = across * 0.32
		local x = across * 0.42
		local strip = piece("Straw", Vector3.new(0.16, length, 0.2), STRAW, Enum.Material.Fabric)
		attach(strip, CFrame.new(x, bottom + length / 2 + 0.02, 0) * CFrame.Angles(0, 0, lean))
		local tip = piece("StrawTip", Vector3.new(0.17, 0.16, 0.21), STRAW_DARK, Enum.Material.Fabric)
		attach(
			tip,
			CFrame.new(x + math.sin(lean) * (length / 2 - 0.08), bottom + 0.1, 0) * CFrame.Angles(0, 0, lean)
		)
	end

	broom.Parent = Workspace
	return broom
end

-- Puts every tool nobody is holding back at its station.
function ToolService.ReturnAll()
	for tool, home in homes do
		if tool.Parent and tool:GetAttribute("CarriedBy") == nil then
			tool.CFrame = home
			tool.Anchored = true
		end
	end
end

function ToolService.Start()
	local mops = 0
	for _, station in CollectionService:GetTagged(Tags.ToolPickup) do
		if station:IsA("BasePart") and station:GetAttribute("Tool") == "Mop" then
			-- Stand the brooms on their bristles just in front of the bucket.
			local floor = station.Position.Y - station.Size.Y / 2
			for index = 1, GameConfig.Carry.MopCount do
				local offset = Vector3.new((index - 1) * 1.2 - 0.6, 0, station.Size.Z / 2 + 0.8)
				local mop = createMop(
					Vector3.new(station.Position.X, floor + BROOM_LENGTH / 2, station.Position.Z) + offset
				)
				CarryService.Register(mop, "Mop")
				homes[mop] = mop.CFrame
				mops += 1
			end
		end
	end
	if mops == 0 then
		log:Warn("The map has no mop station: spills cannot be cleaned")
	end

	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase == "Lobby" then
			ToolService.ReturnAll()
		end
	end)
end

return ToolService
