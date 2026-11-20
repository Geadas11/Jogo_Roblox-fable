--!strict
-- Go and look at a few things: the chosen objects show an amber warning light until a
-- player has been to each one. Which objects, and what the prompt says, come from the
-- task type's Params in Config.TaskDefinitions:
--   Tag     CollectionService tag of the candidates
--   Action  prompt verb ("Inspect", "Cash up")
--   Object  prompt noun ("Cooler", "Register")
--   Hold    seconds the key is held
--   Detail  hint shown under the task title

local CollectionService = game:GetService("CollectionService")

local Services = script.Parent.Parent
local InteractionService = require(Services.InteractionService)

local Inspect = {}

-- The task library, saved here: inside Begin, `task` is the task being set up.
local later = task.delay

-- Units currently waiting for an inspection, across all tasks.
local flagged: { [Instance]: boolean } = {}

-- The part a prompt can hang on: the object itself, or its Anchor.
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

function Inspect.Begin(task: any, count: number, context: any): number
	local params = context.Params
	local available = {}
	for _, unit in CollectionService:GetTagged(params.Tag) do
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
			action = params.Action,
			object = params.Object,
			hold = params.Hold,
		}, function(player: Player)
			if not state.Units[unit] then
				return
			end
			state.Units[unit] = nil
			flagged[unit] = nil
			prompt:Destroy()
			-- Checked: the warning light turns green for a moment, then goes out.
			light.Name = "CheckedLight"
			light.Color = Color3.fromRGB(90, 230, 120)
			later(1.2, function()
				light:Destroy()
			end)
			context.Progress(1, player)
		end)
		state.Units[unit] = { Light = light, Prompt = prompt }
	end

	task.Detail = params.Detail
	return goal
end

function Inspect.Cleanup(task: any)
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

return Inspect
