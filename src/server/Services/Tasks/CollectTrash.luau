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

local function createBag(position: Vector3): BasePart
	local bag = Instance.new("Part")
	bag.Name = "TrashBag"
	bag.Shape = Enum.PartType.Ball
	bag.Size = Vector3.new(1.8, 1.8, 1.8)
	bag.Color = Color3.fromRGB(24, 24, 26)
	bag.Material = Enum.Material.SmoothPlastic
	bag.CFrame = CFrame.new(position)
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
		local bag = createBag(Vector3.new(point.Position.X, ground + 0.9, point.Position.Z))
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
