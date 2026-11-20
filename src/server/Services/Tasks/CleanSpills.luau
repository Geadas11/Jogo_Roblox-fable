--!strict
-- Clean up spills: puddles appear on the floor; each one is mopped up with a mop from
-- the maintenance room.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Config.Tags)
local Services = script.Parent.Parent
local CarryService = require(Services.CarryService)
local InteractionService = require(Services.InteractionService)

local CleanSpills = {}

-- Spill points currently holding a puddle, across all tasks.
local occupied: { [Instance]: boolean } = {}

local function createSpill(position: Vector3, diameter: number): BasePart
	local spill = Instance.new("Part")
	spill.Name = "Spill"
	spill.Shape = Enum.PartType.Cylinder
	spill.Size = Vector3.new(0.1, diameter, diameter)
	-- A cylinder's axis is its X axis: turn it upright so it lies flat on the floor.
	spill.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.pi / 2)
	spill.Color = Color3.fromRGB(70, 96, 110)
	spill.Material = Enum.Material.Glass
	spill.Reflectance = 0.15
	spill.Anchored = true
	spill.CanCollide = false
	spill.CastShadow = false
	spill.Parent = Workspace
	return spill
end

function CleanSpills.Begin(task: any, count: number, context: any): number
	local free = {}
	for _, point in CollectionService:GetTagged(Tags.SpillPoint) do
		if point:IsA("BasePart") and not occupied[point] then
			table.insert(free, point)
		end
	end

	local state = { Spills = {} }
	task.State = state

	local zones = {}
	for _, point in context.Rng:Sample(free, count) do
		occupied[point] = true
		-- The marker floats half a stud above the floor.
		local floor = point.Position.Y - 0.5
		local spill =
			createSpill(Vector3.new(point.Position.X, floor + 0.05, point.Position.Z), context.Rng:Int(5, 7))
		state.Spills[spill] = point
		zones[tostring(point:GetAttribute("Zone"))] = true

		InteractionService.AddPrompt(spill, {
			action = "Clean",
			object = "Spill",
			hold = 2.5,
		}, function(player: Player)
			if not state.Spills[spill] then
				return
			end
			if CarryService.GetKind(player) ~= "Mop" then
				context.Notify(player, "You need a mop. There is one in the maintenance room.", "Warning")
				return
			end
			state.Spills[spill] = nil
			occupied[point] = nil
			-- Mopped up: the puddle shrinks away instead of vanishing.
			spill.Name = "MoppedSpill"
			local prompt = spill:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				prompt:Destroy()
			end
			local tween = TweenService:Create(
				spill,
				TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = Vector3.new(spill.Size.X, 0.2, 0.2) }
			)
			tween.Completed:Once(function()
				spill:Destroy()
			end)
			tween:Play()
			context.Progress(1, player)
		end)
	end

	local created = 0
	for _ in state.Spills do
		created += 1
	end
	task.Detail = "Get a mop from the maintenance room."
	return created
end

function CleanSpills.Cleanup(task: any)
	local state = task.State
	if not state then
		return
	end
	for spill, point in state.Spills do
		occupied[point] = nil
		spill:Destroy()
	end
	task.State = nil
end

return CleanSpills
