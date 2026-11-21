--!strict
-- Two HUD panels: the list of current tasks (top left), and the "hands" panel in the
-- bottom-right corner - what the player is holding and the keys that matter right now,
-- the way most first-person horror games show it:
--
--        MOP                          (or "Empty hands", dimmed)
--        [G] Drop   [F] Light   [Shift] Run
--
-- On touch screens the key hints are replaced by a DROP button.

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
local hintRow: Frame
local dropHint: Frame?
local dropButton: TextButton?

-- A key cap ("G") followed by what it does ("Drop").
local function keyHint(key: string, text: string, order: number): Frame
	local cap = Theme.label({
		Name = "Key",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 22, 0, 22),
		BackgroundTransparency = 0.1,
		BackgroundColor3 = Theme.Colors.Text,
		TextColor3 = Theme.Colors.Background,
		FontFace = Theme.Fonts.Title,
		TextSize = 13,
		TextWrapped = false,
		Text = key,
		LayoutOrder = 1,
	})
	Theme.create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = cap })
	Theme.create("UIPadding", {
		PaddingLeft = UDim.new(0, 6),
		PaddingRight = UDim.new(0, 6),
		Parent = cap,
	})
	local label = Theme.label({
		Name = "Text",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 22),
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 13,
		TextWrapped = false,
		Text = text,
		LayoutOrder = 2,
	})
	return Theme.create("Frame", {
		Name = "Hint",
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.new(0, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder = order,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
		cap,
		label,
	}) :: Frame
end

local function build(screen: ScreenGui)
	list = Theme.create("Frame", {
		Name = "Objectives",
		-- Below Roblox's own buttons in the top-left corner (the HUD ignores the inset).
		Position = UDim2.new(0, 14, 0, 70),
		Size = UDim2.new(0, 300, 0, 300),
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		Theme.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 6),
		}),
	}) :: Frame

	-- What is in your hands: big, right-aligned, no box around it.
	carryLabel = Theme.label({
		Name = "Label",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.Fonts.Title,
		TextSize = 24,
		TextStrokeTransparency = 0.6,
		Text = "",
	})

	hintRow = Theme.create("Frame", {
		Name = "Hints",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 36),
		Size = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
	}, {
		Theme.create("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding = UDim.new(0, 14),
		}),
	}) :: Frame

	if UserInputService.TouchEnabled then
		-- Touch: one clear button instead of keys nobody has.
		local button = Theme.create("TextButton", {
			Name = "Drop",
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, 0, 0, 36),
			Size = UDim2.new(0, 92, 0, 34),
			BackgroundColor3 = Theme.Colors.Panel,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			FontFace = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.Text,
			TextSize = 14,
			Text = "DROP",
		}, {
			Theme.create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		}) :: TextButton
		button.Activated:Connect(function()
			Net.FireServer("DropItem")
		end)
		dropButton = button
	else
		local drop = keyHint("G", "Drop", 1)
		drop.Parent = hintRow
		dropHint = drop
		keyHint("F", "Flashlight", 2).Parent = hintRow
		keyHint("Shift", "Run", 3).Parent = hintRow
	end

	carryPanel = Theme.create("Frame", {
		Name = "Carrying",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -28, 1, -24),
		Size = UDim2.new(0, 360, 0, 70),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = screen,
	}, { carryLabel, hintRow }) :: Frame
	if dropButton then
		(dropButton :: TextButton).Parent = carryPanel
	end
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
			-- Long hints wrap onto more lines; the panel grows with them.
			Size = UDim2.new(1, -16, 0, 16),
			AutomaticSize = Enum.AutomaticSize.Y,
			Position = UDim2.new(0, 8, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Left,
			TextSize = 12,
			TextColor3 = Theme.Colors.TextDim,
			Text = if done then "Done" else tostring(task.Detail or ""),
		})
		Theme.panel({
			Name = "Task",
			Size = UDim2.new(1, 0, 0, 48),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = index,
			BackgroundTransparency = if done then 0.6 else 0.25,
			Parent = list,
		}, { title, detail, Theme.create("UIPadding", { PaddingBottom = UDim.new(0, 7) }) })
	end
end

-- The hands panel: shown while working (dimmed with nothing in hand), hidden while
-- hiding, caught or watching the others.
local function refreshHands()
	local player = Players.LocalPlayer
	local kind = player:GetAttribute("Carrying")
	local holding = type(kind) == "string" and kind ~= ""
	local status = player:GetAttribute("Status")
	local working = status == nil or status == "Working"

	-- On touch screens the panel only matters while holding something (the DROP button).
	carryPanel.Visible = working and (holding or dropButton == nil)
	carryLabel.Text = if holding
		then string.upper((GameConfig.Carry.Names :: any)[kind :: string] or (kind :: string))
		else "Empty hands"
	carryLabel.TextColor3 = if holding then Theme.Colors.Text else Theme.Colors.TextDim
	carryLabel.TextSize = if holding then 24 else 16
	if dropHint then
		(dropHint :: Frame).Visible = holding
	end
	if dropButton then
		(dropButton :: TextButton).Visible = holding
	end
end

function ObjectivesController.Init()
	build(HudController.GetScreen())
	Net.On("TasksChanged", ObjectivesController.Show)
end

function ObjectivesController.Start()
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Carrying"):Connect(refreshHands)
	player:GetAttributeChangedSignal("Status"):Connect(refreshHands)
	refreshHands()

	UserInputService.InputBegan:Connect(function(input: InputObject)
		local kind = player:GetAttribute("Carrying")
		local typing = UserInputService:GetFocusedTextBox() ~= nil
		if not typing and input.KeyCode == DROP_KEY and type(kind) == "string" and kind ~= "" then
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
