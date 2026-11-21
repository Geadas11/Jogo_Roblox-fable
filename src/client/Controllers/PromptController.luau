--!strict
-- Draws every interaction prompt ("[E] Pick up  Mop") in the game's own style instead of
-- Roblox's default bubble: a small key cap, the action, the object underneath, and a thin
-- bar that fills while the key is held.
--
-- The server creates every prompt with Style = Custom (InteractionService); Roblox then
-- leaves the drawing to us through ProximityPromptService.PromptShown. Keyboard, gamepad
-- and touch all work: on touch screens the prompt itself is the button.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Parent.UI.Theme)

local PromptController = {}

-- Short names for gamepad buttons.
local GAMEPAD_NAMES: { [string]: string } = {
	ButtonX = "X",
	ButtonY = "Y",
	ButtonA = "A",
	ButtonB = "B",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
}

local function keyName(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Gamepad then
		local name = prompt.GamepadKeyCode.Name
		return GAMEPAD_NAMES[name] or name
	elseif inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	end
	return prompt.KeyboardKeyCode.Name
end

local function createPrompt(
	prompt: ProximityPrompt,
	inputType: Enum.ProximityPromptInputType,
	gui: Instance
): () -> ()
	local touch = inputType == Enum.ProximityPromptInputType.Touch

	-- The key sits a few pixels in from the prompt's left edge: the outline drawn round it
	-- reaches past the key, and a BillboardGui cuts off anything outside its own box (that
	-- hid the left side of the outline).
	local INSET = 6
	local cap = Theme.label({
		Name = "Key",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, INSET, 0.5, 0),
		Size = UDim2.new(0, if touch then 44 else 30, 0, 30),
		BackgroundTransparency = 0.05,
		BackgroundColor3 = Theme.Colors.Text,
		TextColor3 = Theme.Colors.Background,
		FontFace = Theme.Fonts.Title,
		TextSize = if touch then 12 else 16,
		TextWrapped = false,
		Text = keyName(prompt, inputType),
	})
	Theme.create("UICorner", { CornerRadius = UDim.new(0, 5), Parent = cap })

	-- While the key is held, an outline draws itself around the key as two lines: both
	-- start together at the middle of the bottom edge, run out to the bottom corners, up
	-- the two sides and along the top, and meet in the middle of the top edge.
	-- Everything is placed in exact pixels from the ring's top-left corner (no anchors or
	-- scales), so each piece is exactly where the path says.
	local THICK = 3
	local capWidth = if touch then 44 else 30
	local capHeight = 30
	local ringWidth = capWidth + (THICK + 1) * 2
	local ringHeight = capHeight + (THICK + 1) * 2
	local ring = Theme.create("Frame", {
		Name = "Ring",
		Position = UDim2.new(0, -(THICK + 1), 0, -(THICK + 1)),
		Size = UDim2.new(0, ringWidth, 0, ringHeight),
		BackgroundTransparency = 1,
		-- Only for prompts you hold (hide, restock...); a door is just a press.
		Visible = prompt.HoldDuration > 0,
		ZIndex = 3,
	}) :: Frame
	ring.Parent = cap
	local function edge(name: string): Frame
		return Theme.create("Frame", {
			Name = name,
			Size = UDim2.new(0, 0, 0, 0),
			BackgroundColor3 = Theme.Colors.Warning,
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 3,
			Parent = ring,
		}) :: Frame
	end
	local paths = {}
	for _, side in { 1, -1 } do
		table.insert(paths, { Side = side, Bottom = edge("Bottom"), Up = edge("Up"), Top = edge("Top") })
	end
	local half = ringWidth / 2
	local length = half + ringHeight + half
	-- Shows `frame` as the rectangle x, y, w, h (pixels), or hides it when empty.
	local function place(frame: Frame, x: number, y: number, w: number, h: number)
		frame.Visible = w > 0.5 and h > 0.5
		frame.Position = UDim2.new(0, math.floor(x + 0.5), 0, math.floor(y + 0.5))
		frame.Size = UDim2.new(0, math.ceil(w), 0, math.ceil(h))
	end
	local function drawRing(t: number)
		local done = math.clamp(t, 0, 1) * length
		local bottom = math.clamp(done, 0, half)
		local up = math.clamp(done - half, 0, ringHeight)
		local top = math.clamp(done - half - ringHeight, 0, half)
		for _, path in paths do
			if path.Side == 1 then
				-- Right: from the bottom middle to the right, up the right side, then left.
				place(path.Bottom, half, ringHeight - THICK, bottom, THICK)
				place(path.Up, ringWidth - THICK, ringHeight - up, THICK, up)
				place(path.Top, ringWidth - top, 0, top, THICK)
			else
				-- Left: the mirror image.
				place(path.Bottom, half - bottom, ringHeight - THICK, bottom, THICK)
				place(path.Up, 0, ringHeight - up, THICK, up)
				place(path.Top, 0, 0, top, THICK)
			end
		end
	end
	drawRing(0)
	local progress = Instance.new("NumberValue")
	progress.Changed:Connect(drawRing)

	local action = Theme.label({
		Name = "Action",
		Position = UDim2.new(0, INSET + (if touch then 54 else 40), 0, 2),
		Size = UDim2.new(1, -40, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Fonts.Title,
		TextSize = 17,
		TextWrapped = false,
		TextStrokeTransparency = 0.5,
		Text = prompt.ActionText,
	})
	local object = Theme.label({
		Name = "Object",
		Position = UDim2.new(0, INSET + (if touch then 54 else 40), 0, 22),
		Size = UDim2.new(1, -40, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 13,
		TextWrapped = false,
		TextColor3 = Theme.Colors.TextDim,
		TextStrokeTransparency = 0.6,
		Text = prompt.ObjectText,
	})

	local root: GuiObject
	if touch then
		local button = Theme.create("TextButton", {
			Name = "Prompt",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Text = "",
			AutoButtonColor = false,
		}) :: TextButton
		button.InputBegan:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				prompt:InputHoldBegin()
			end
		end)
		button.InputEnded:Connect(function(input: InputObject)
			if
				input.UserInputType == Enum.UserInputType.Touch
				or input.UserInputType == Enum.UserInputType.MouseButton1
			then
				prompt:InputHoldEnd()
			end
		end)
		root = button
	else
		root = Theme.create("Frame", {
			Name = "Prompt",
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
		}) :: Frame
	end
	cap.Parent = root
	action.Parent = root
	object.Parent = root

	local billboard = Theme.create("BillboardGui", {
		Name = "Prompt",
		AlwaysOnTop = true,
		Size = UDim2.new(0, 240, 0, 40),
		SizeOffset = Vector2.new(0.4, 0),
		Adornee = prompt.Parent,
		Active = touch,
		ResetOnSpawn = false,
		ClipsDescendants = false,
	}, { root })
	billboard.Parent = gui

	local holdTween: Tween? = nil
	local connections = {
		prompt.PromptButtonHoldBegan:Connect(function()
			progress.Value = 0
			local tween = TweenService:Create(
				progress,
				TweenInfo.new(prompt.HoldDuration, Enum.EasingStyle.Linear),
				{ Value = 1 }
			)
			tween:Play()
			holdTween = tween
		end),
		prompt.PromptButtonHoldEnded:Connect(function()
			if holdTween then
				holdTween:Cancel()
				holdTween = nil
			end
			progress.Value = 0
		end),
		-- The server renames some prompts while they are shown (Open/Close, Clock in/out).
		prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
			action.Text = prompt.ActionText
		end),
		prompt:GetPropertyChangedSignal("ObjectText"):Connect(function()
			object.Text = prompt.ObjectText
		end),
	}

	return function()
		for _, connection in connections do
			connection:Disconnect()
		end
		if holdTween then
			holdTween:Cancel()
		end
		progress:Destroy()
		billboard:Destroy()
	end
end

function PromptController.Start()
	local gui = Players.LocalPlayer:WaitForChild("PlayerGui")
	ProximityPromptService.PromptShown:Connect(
		function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
			if prompt.Style ~= Enum.ProximityPromptStyle.Custom then
				return
			end
			local cleanup = createPrompt(prompt, inputType, gui)
			prompt.PromptHidden:Once(cleanup)
		end
	)
end

return PromptController
