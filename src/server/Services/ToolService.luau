--!strict
-- Puts the tools players need for their work where the map says they are kept
-- (tag: ToolPickup). Currently: mops by the bucket in the maintenance room.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Tags = require(Shared.Config.Tags)
local Log = require(Shared.Util.Log)
local CarryService = require(script.Parent.CarryService)

local log = Log.new("Tools")

local ToolService = {}

local function createMop(position: Vector3): BasePart
	local mop = Instance.new("Part")
	mop.Name = "Mop"
	mop.Size = Vector3.new(0.4, 5, 0.4)
	mop.Color = Color3.fromRGB(134, 100, 68)
	mop.Material = Enum.Material.Wood
	mop.CFrame = CFrame.new(position)
	mop.Parent = Workspace
	return mop
end

function ToolService.Start()
	local mops = 0
	for _, station in CollectionService:GetTagged(Tags.ToolPickup) do
		if station:IsA("BasePart") and station:GetAttribute("Tool") == "Mop" then
			-- Stand the mops on the floor just in front of the bucket.
			local floor = station.Position.Y - station.Size.Y / 2
			for index = 1, GameConfig.Carry.MopCount do
				local offset = Vector3.new((index - 1) * 1.1 - 0.5, 0, station.Size.Z / 2 + 0.8)
				local mop =
					createMop(Vector3.new(station.Position.X, floor + 2.5, station.Position.Z) + offset)
				CarryService.Register(mop, "Mop")
				mops += 1
			end
		end
	end
	if mops == 0 then
		log:Warn("The map has no mop station: spills cannot be cleaned")
	end
end

return ToolService
