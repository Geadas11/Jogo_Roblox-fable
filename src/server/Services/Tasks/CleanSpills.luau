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
local WetFloorSign = require(Services.Parent.Props.WetFloorSign)

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

	local state = { Spills = {}, Signs = {} }
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
		-- A "wet floor" sign stood in the puddle, a little off its middle (always on the
		-- open floor the puddle covers, never into a shelf or a wall).
		local angle = context.Rng:Next() * math.pi * 2
		local reach = spill.Size.Y / 2 * 0.55
		local sign = WetFloorSign.Create(
			Vector3.new(
				point.Position.X + math.cos(angle) * reach,
				floor,
				point.Position.Z + math.sin(angle) * reach
			),
			context.Rng:Next() * math.pi * 2
		)
		state.Signs[spill] = sign

		local prompt = InteractionService.AddPrompt(spill, {
			action = "Clean",
			object = "Spill",
			hold = 2.5,
		}, function(player: Player)
			player:SetAttribute("Sweeping", nil)
			if not state.Spills[spill] then
				return
			end
			if CarryService.GetKind(player) ~= "Mop" then
				context.Notify(player, "You need a broom. There is one in the maintenance room.", "Warning")
				return
			end
			state.Spills[spill] = nil
			occupied[point] = nil
			if state.Signs[spill] then
				state.Signs[spill]:Destroy()
				state.Signs[spill] = nil
			end
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
		-- While the key is held with a broom in hand, everyone sees them sweeping
		-- (CharacterAnimator reads the attribute).
		prompt.PromptButtonHoldBegan:Connect(function(player: Player)
			if CarryService.GetKind(player) == "Mop" then
				player:SetAttribute("Sweeping", true)
			end
		end)
		prompt.PromptButtonHoldEnded:Connect(function(player: Player)
			player:SetAttribute("Sweeping", nil)
		end)
	end

	local created = 0
	for _ in state.Spills do
		created += 1
	end
	task.Detail = "Get a broom from the maintenance room."
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
	for _, sign in state.Signs do
		sign:Destroy()
	end
	task.State = nil
end

return CleanSpills
