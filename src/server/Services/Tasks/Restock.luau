--!strict
-- Restock shelves: some shelf bays are empty; carry a stock box from the storage room
-- to each one.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local Tags = require(Shared.Config.Tags)
local Services = script.Parent.Parent
local CarryService = require(Services.CarryService)
local InteractionService = require(Services.InteractionService)

local Restock = {}

-- Shows or hides the products of a bay.
local function setStocked(bay: Instance, stocked: boolean)
	bay:SetAttribute("Stocked", stocked)
	for _, child in bay:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Anchor" then
			child.Transparency = if stocked then 0 else 1
		end
	end
end

local function createBox(position: Vector3): BasePart
	local box = Instance.new("Part")
	box.Name = "StockBox"
	box.Size = Vector3.new(2.2, 1.8, 2.2)
	box.Color = Color3.fromRGB(170, 130, 86)
	box.Material = Enum.Material.Cardboard
	box.CFrame = CFrame.new(position)
	box.Parent = Workspace
	return box
end

-- Returns how many bays were actually emptied (the task's goal).
function Restock.Begin(task: any, count: number, context: any): number
	local available = {}
	for _, bay in CollectionService:GetTagged(Tags.ShelfBay) do
		if bay:GetAttribute("Stocked") == true and bay:FindFirstChild("Anchor") then
			table.insert(available, bay)
		end
	end
	local deliveries = CollectionService:GetTagged(Tags.DeliveryPoint)
	if #deliveries == 0 then
		return 0
	end

	local state = { Bays = {}, Boxes = {}, Prompts = {} }
	task.State = state

	local aisles = {}
	for index, bay in context.Rng:Sample(available, count) do
		setStocked(bay, false)
		table.insert(state.Bays, bay)
		aisles[bay:GetAttribute("Aisle")] = true

		state.Prompts[bay] = InteractionService.AddPrompt(bay.Anchor, {
			action = "Restock",
			object = tostring(bay:GetAttribute("Category")),
			hold = 1.5,
		}, function(player: Player, prompt: ProximityPrompt)
			if bay:GetAttribute("Stocked") == true then
				return
			end
			if not CarryService.Consume(player, "StockBox") then
				context.Notify(
					player,
					"You need a stock box. They are delivered to the storage room.",
					"Warning"
				)
				return
			end
			setStocked(bay, true)
			state.Prompts[bay] = nil
			prompt:Destroy()
			context.Progress(1, player)
		end)

		-- One box per empty bay, stacked in fours at the delivery points.
		local delivery = deliveries[(index - 1) % #deliveries + 1] :: BasePart
		local layer = (index - 1) // #deliveries
		local floor = delivery.Position.Y - delivery.Size.Y / 2
		local box = createBox(
			Vector3.new(
				delivery.Position.X + (layer % 2) * 2.4,
				floor + 0.9 + (layer // 2) * 1.8,
				delivery.Position.Z
			)
		)
		CarryService.Register(box, "StockBox")
		table.insert(state.Boxes, box)
	end

	local list = {}
	for aisle in aisles do
		table.insert(list, aisle)
	end
	table.sort(list)
	for index, aisle in list do
		list[index] = tostring(aisle)
	end
	task.Detail = string.format("Aisle %s. Boxes are in the storage room.", table.concat(list, ", "))
	return #state.Bays
end

-- Puts the world back as it was: shelves full, no boxes left around.
function Restock.Cleanup(task: any)
	local state = task.State
	if not state then
		return
	end
	for _, bay in state.Bays do
		setStocked(bay, true)
	end
	for _, prompt in state.Prompts do
		prompt:Destroy()
	end
	for _, box in state.Boxes do
		if box.Parent then
			CarryService.Remove(box)
		end
	end
	task.State = nil
end

return Restock
