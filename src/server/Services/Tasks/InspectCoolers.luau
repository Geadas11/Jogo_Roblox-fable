--!strict
-- Check the coolers: a few refrigeration units show an amber warning light and need
-- to be looked at.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Config.Tags)
local Services = script.Parent.Parent
local InteractionService = require(Services.InteractionService)

local InspectCoolers = {}

-- Units currently waiting for an inspection, across all tasks.
local flagged: { [Instance]: boolean } = {}

-- The part a prompt can hang on: the unit itself, or its Anchor.
local function anchorOf(unit: Instance): BasePart?
	if unit:IsA("BasePart") then
		return unit
	end
	local anchor = unit:FindFirstChild("Anchor")
	if anchor and anchor:IsA("BasePart") then
		return anchor
	end
	return nil
end

local function createWarningLight(anchor: BasePart): BasePart
	local light = Instance.new("Part")
	light.Name = "WarningLight"
	light.Size = Vector3.new(0.8, 0.5, 0.8)
	light.Color = Color3.fromRGB(255, 170, 40)
	light.Material = Enum.Material.Neon
	light.Anchored = true
	light.CanCollide = false
	light.CastShadow = false
	-- Above head height, where it can be seen along an aisle.
	light.CFrame = CFrame.new(anchor.Position + Vector3.new(0, anchor.Size.Y / 2 + 2.6, 0))
	light.Parent = anchor
	return light
end

function InspectCoolers.Begin(task: any, count: number, context: any): number
	local available = {}
	for _, unit in CollectionService:GetTagged(Tags.FridgeUnit) do
		if not flagged[unit] and anchorOf(unit) then
			table.insert(available, unit)
		end
	end

	local state = { Units = {} }
	task.State = state

	local goal = 0
	for _, unit in context.Rng:Sample(available, count) do
		local anchor = anchorOf(unit) :: BasePart
		flagged[unit] = true
		goal += 1
		local light = createWarningLight(anchor)
		local prompt
		prompt = InteractionService.AddPrompt(anchor, {
			action = "Inspect",
			object = "Cooler",
			hold = 1.5,
		}, function(player: Player)
			if not state.Units[unit] then
				return
			end
			state.Units[unit] = nil
			flagged[unit] = nil
			light:Destroy()
			prompt:Destroy()
			context.Progress(1, player)
		end)
		state.Units[unit] = { Light = light, Prompt = prompt }
	end

	task.Detail = "Look for the amber warning lights."
	return goal
end

function InspectCoolers.Cleanup(task: any)
	local state = task.State
	if not state then
		return
	end
	for unit, entry in state.Units do
		flagged[unit] = nil
		entry.Light:Destroy()
		entry.Prompt:Destroy()
	end
	task.State = nil
end

return InspectCoolers
