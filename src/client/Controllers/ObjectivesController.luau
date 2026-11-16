--!strict
-- Two small HUD panels: the list of current tasks, and what the player is carrying
-- (with the way to drop it: G on a keyboard, the button on touch).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local HudController = require(script.Parent.HudController)

local MAX_ROWS = 6
local DROP_KEY = Enum.KeyCode.G

local ObjectivesController = {}

local list: Frame
local carryPanel: Frame
local carryLabel: TextLabel

local function build(screen: ScreenGui)
	list = Theme.create("Frame", {
		Name = "Objectives",
		Position = UDim2.new(0, 14, 0, 14),
		Size = UDim2.new(0, 300, 0, 300),
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		Theme.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	}) :: Frame

	carryLabel = Theme.label({
		Name = "Label",
		Size = UDim2.new(1, -96, 1, 0),
		Position = UDim2.new(0, 12, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		Text = "",
	})
	local dropButton = Theme.create("TextButton", {
		Name = "Drop",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -8, 0.5, 0),
		Size = UDim2.new(0, 80, 0, 30),
		BackgroundColor3 = Theme.Colors.Accent,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Text,
		TextSize = 14,
		Text = "DROP [G]",
	}, {
		Theme.create("UICorner", { CornerRadius = UDim.new(0, 6) }),
	}) :: TextButton
	dropButton.Activated:Connect(function()
		Net.FireServer("DropItem")
	end)

	carryPanel = Theme.panel({
		Name = "Carrying",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(0, 320, 0, 42),
		Visible = false,
		Parent = screen,
	}, { carryLabel, dropButton })
end

-- Redraws the objectives list from a snapshot sent by the server.
function ObjectivesController.Show(snapshot: any)
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if type(snapshot) ~= "table" then
		return
	end

	-- Unfinished tasks first, then the most recently finished ones.
	local ordered = {}
	for _, task in snapshot do
		if type(task) == "table" and not task.Completed then
			table.insert(ordered, task)
		end
	end
	for index = #snapshot, 1, -1 do
		local task = snapshot[index]
		if type(task) == "table" and task.Completed then
			table.insert(ordered, task)
		end
	end

	for index, task in ordered do
		if index > MAX_ROWS then
			break
		end
		local done = task.Completed == true
		local title = Theme.label({
			Name = "Title",
			Size = UDim2.new(1, -16, 0, 20),
			Position = UDim2.new(0, 8, 0, 5),
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Theme.Fonts.Title,
			TextSize = 15,
			TextColor3 = if done then Theme.Colors.Good else Theme.Colors.Text,
			Text = string.format(
				"%s   %d/%d",
				tostring(task.Title),
				tonumber(task.Progress) or 0,
				tonumber(task.Goal) or 0
			),
		})
		local detail = Theme.label({
			Name = "Detail",
			Size = UDim2.new(1, -16, 0, 16),
			Position = UDim2.new(0, 8, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 12,
			TextColor3 = Theme.Colors.TextDim,
			Text = if done then "Done" else tostring(task.Detail or ""),
		})
		Theme.panel({
			Name = "Task",
			Size = UDim2.new(1, 0, 0, 48),
			LayoutOrder = index,
			BackgroundTransparency = if done then 0.6 else 0.25,
			Parent = list,
		}, { title, detail })
	end
end

local function showCarrying(kind: any)
	if type(kind) ~= "string" or kind == "" then
		carryPanel.Visible = false
		return
	end
	carryLabel.Text = "Carrying: " .. ((GameConfig.Carry.Names :: any)[kind] or kind)
	carryPanel.Visible = true
end

function ObjectivesController.Init()
	build(HudController.GetScreen())
	Net.On("TasksChanged", ObjectivesController.Show)
end

function ObjectivesController.Start()
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Carrying"):Connect(function()
		showCarrying(player:GetAttribute("Carrying"))
	end)
	showCarrying(player:GetAttribute("Carrying"))

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == DROP_KEY and carryPanel.Visible then
			Net.FireServer("DropItem")
		end
	end)

	-- The list as it stands now, for a client that joined mid-shift.
	local ok, snapshot = Net.InvokeServer("GetTasks")
	if ok then
		ObjectivesController.Show(snapshot)
	end
end

return ObjectivesController
