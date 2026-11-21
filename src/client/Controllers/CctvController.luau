--!strict
-- The security camera feeds (CameraService on the server decides when).
--
-- The view jumps to one CCTVCamera at a time: washed-out green-grey picture, scan lines,
-- the camera's name, a blinking REC and the time. A burst of static between cameras.
-- No power to the office (the Staff circuit), no picture: NO SIGNAL.
--
--   A / Left, D / Right   previous / next camera (or the buttons)
--   E, Space, Backspace   look away from the monitor (or the button)
--
-- Some suspicious customers look normal to the eye but not to the cameras: a customer
-- with the "CameraOnly" anomaly has no head on the feed.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SessionState = require(Shared.SessionState)
local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local HudController = require(script.Parent.HudController)

local CctvController = {}

local FIELD_OF_VIEW = 78
local STATIC_SECONDS = 0.22

local screen: ScreenGui
local nameLabel: TextLabel
local recLabel: TextLabel
local clockLabel: TextLabel
local staticFrame: Frame
local noSignal: TextLabel
local grade: ColorCorrectionEffect? = nil

local watching = false
local cameras: { BasePart } = {}
local index = 1
local savedFieldOfView = 70
local staticUntil = 0
-- The settings button, hidden while watching (shown again on leaving).
local hiddenGear: GuiObject? = nil

-- The feeds, in camera-number order.
local function collectCameras()
	cameras = {}
	for _, part in CollectionService:GetTagged("CCTVCamera") do
		if part:IsA("BasePart") then
			table.insert(cameras, part)
		end
	end
	table.sort(cameras, function(a: BasePart, b: BasePart)
		return (tonumber(a:GetAttribute("CameraId")) or 0) < (tonumber(b:GetAttribute("CameraId")) or 0)
	end)
end

local function powered(): boolean
	return SessionState.Get("PowerStaff") ~= false
end

-- Hides (or shows again) the heads of the customers the cameras see through.
local function revealOnCamera(show: boolean)
	local folder = Workspace:FindFirstChild("Customers")
	if not folder then
		return
	end
	for _, model in folder:GetChildren() do
		if model:IsA("Model") and model:GetAttribute("Anomaly") == "CameraOnly" then
			local head = model:FindFirstChild("Head")
			for _, part in model:GetDescendants() do
				if part:IsA("BasePart") then
					local onHead = part == head
					local accessory = part:FindFirstAncestorOfClass("Accessory")
					if accessory then
						local weld = part:FindFirstChild("AccessoryWeld")
						onHead = weld ~= nil
							and weld:IsA("Weld")
							and (weld.Part0 == head or weld.Part1 == head)
					end
					if onHead then
						part.LocalTransparencyModifier = if show then 1 else 0
					end
				elseif part:IsA("Decal") and part.Parent == head then
					part.LocalTransparencyModifier = if show then 1 else 0
				end
			end
		end
	end
end

-- The night's time, from when the shift started and how long an hour lasts.
local function clockText(): string
	local hour = tonumber(SessionState.Get("Hour")) or 0
	local started = tonumber(SessionState.Get("ShiftStartTime")) or 0
	local length = math.max(1, tonumber(SessionState.Get("HourDuration")) or 240)
	local elapsed = math.max(0, Workspace:GetServerTimeNow() - started)
	local minute = math.floor((elapsed % length) / length * 60)
	local shown = if hour == 0 then 12 else hour
	return string.format("%d:%02d AM", shown, minute)
end

local function show(newIndex: number)
	if #cameras == 0 then
		return
	end
	index = (newIndex - 1) % #cameras + 1
	local camera = cameras[index]
	nameLabel.Text = tostring(camera:GetAttribute("DisplayName") or camera.Name)
	staticUntil = os.clock() + STATIC_SECONDS
end

local function close(tellServer: boolean)
	if not watching then
		return
	end
	watching = false
	screen.Enabled = false
	HudController.GetScreen().Enabled = true
	if hiddenGear then
		hiddenGear.Visible = true
		hiddenGear = nil
	end
	for _, feed in cameras do
		feed.LocalTransparencyModifier = 0
	end
	revealOnCamera(false)
	if grade then
		grade:Destroy()
		grade = nil
	end
	local camera = Workspace.CurrentCamera
	if camera then
		camera.FieldOfView = savedFieldOfView
		camera.CameraType = Enum.CameraType.Custom
	end
	ProximityPromptService.Enabled = true
	Players.LocalPlayer:SetAttribute("UsingScreen", false)
	if tellServer then
		Net.FireServer("LeaveCameras")
	end
end

local function open()
	if watching then
		return
	end
	collectCameras()
	if #cameras == 0 then
		Net.FireServer("LeaveCameras")
		return
	end
	watching = true
	local camera = Workspace.CurrentCamera
	if camera then
		savedFieldOfView = camera.FieldOfView
		camera.CameraType = Enum.CameraType.Scriptable
		camera.FieldOfView = FIELD_OF_VIEW
	end
	-- Prompts nearby would steal E; the cursor is needed for the buttons.
	ProximityPromptService.Enabled = false
	Players.LocalPlayer:SetAttribute("UsingScreen", true)
	local effect = Instance.new("ColorCorrectionEffect")
	effect.Name = "CctvGrade"
	effect.Saturation = -0.75
	effect.Contrast = 0.18
	effect.Brightness = 0.04
	effect.TintColor = Color3.fromRGB(205, 232, 210)
	effect.Parent = Lighting
	grade = effect
	-- Only the feed on screen: the task list and the rest of the HUD step aside, and so
	-- does the settings button.
	HudController.GetScreen().Enabled = false
	local menu = Players.LocalPlayer:FindFirstChild("PlayerGui")
		and Players.LocalPlayer.PlayerGui:FindFirstChild("Menu")
	local gear = menu and menu:FindFirstChild("Gear")
	if gear and gear:IsA("GuiObject") and gear.Visible then
		gear.Visible = false
		hiddenGear = gear
	end
	screen.Enabled = true
	show(index)
end

local function button(text: string, properties: { [string]: any }, onClick: () -> ()): TextButton
	local defaults: { [string]: any } = {
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(220, 235, 220),
		TextSize = 18,
		Text = text,
	}
	for key, value in properties do
		defaults[key] = value
	end
	local made = Theme.create("TextButton", defaults, {
		Theme.create("UICorner", { CornerRadius = UDim.new(0, 4) }),
	}) :: TextButton
	made.Activated:Connect(onClick)
	return made
end

local function build(): ScreenGui
	local gui = Theme.create("ScreenGui", {
		Name = "Cameras",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 20,
		Enabled = false,
	}) :: ScreenGui

	-- Scan lines across the whole picture, and a dark rim.
	local lines = Theme.create("Frame", {
		Name = "ScanLines",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	for row = 0, 59 do
		Theme.create("Frame", {
			Position = UDim2.new(0, 0, row / 60, 0),
			Size = UDim2.new(1, 0, 0, 1),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			Parent = lines,
		})
	end
	for _, side in { { 0, 0, 1, 0.1 }, { 0, 0.9, 1, 0.1 }, { 0, 0, 0.06, 1 }, { 0.94, 0, 0.06, 1 } } do
		Theme.create("Frame", {
			Position = UDim2.new(side[1], 0, side[2], 0),
			Size = UDim2.new(side[3], 0, side[4], 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 0.55,
			BorderSizePixel = 0,
			Parent = gui,
		})
	end

	local mono = Font.fromEnum(Enum.Font.Code)
	nameLabel = Theme.label({
		Name = "CameraName",
		Position = UDim2.new(0, 40, 0, 26),
		Size = UDim2.new(0.6, 0, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = mono,
		TextSize = 24,
		TextColor3 = Color3.fromRGB(225, 240, 225),
		TextStrokeTransparency = 0.4,
		Text = "",
		Parent = gui,
	})
	recLabel = Theme.label({
		Name = "Rec",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -40, 0, 26),
		Size = UDim2.new(0, 120, 0, 30),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = mono,
		TextSize = 24,
		TextColor3 = Color3.fromRGB(230, 50, 40),
		TextStrokeTransparency = 0.4,
		Text = "● REC",
		Parent = gui,
	})
	clockLabel = Theme.label({
		Name = "Clock",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -40, 0, 58),
		Size = UDim2.new(0, 200, 0, 26),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = mono,
		TextSize = 20,
		TextColor3 = Color3.fromRGB(225, 240, 225),
		TextStrokeTransparency = 0.4,
		Text = "",
		Parent = gui,
	})
	noSignal = Theme.label({
		Name = "NoSignal",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(8, 10, 9),
		BackgroundTransparency = 0,
		FontFace = mono,
		TextSize = 34,
		TextColor3 = Color3.fromRGB(200, 210, 200),
		Text = "NO SIGNAL",
		Visible = false,
		ZIndex = 2,
		Parent = gui,
	})
	-- Static between cameras: a grey snow of little blocks redrawn every frame.
	staticFrame = Theme.create("Frame", {
		Name = "Static",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(70, 74, 72),
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = 3,
		ClipsDescendants = true,
		Parent = gui,
	}) :: Frame
	for _ = 1, 140 do
		Theme.create("Frame", {
			Size = UDim2.new(0.05, 0, 0.03, 0),
			BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0,
			ZIndex = 3,
			Parent = staticFrame,
		})
	end

	local bar = Theme.create("Frame", {
		Name = "Controls",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -30),
		Size = UDim2.new(0, 520, 0, 44),
		BackgroundTransparency = 1,
		ZIndex = 4,
		Parent = gui,
	})
	button("<  A", {
		Size = UDim2.new(0, 110, 1, 0),
		ZIndex = 4,
		Parent = bar,
	}, function()
		show(index - 1)
	end)
	button("LEAVE  [E]", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(0, 220, 1, 0),
		ZIndex = 4,
		Parent = bar,
	}, function()
		close(true)
	end)
	button("D  >", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 0),
		Size = UDim2.new(0, 110, 1, 0),
		ZIndex = 4,
		Parent = bar,
	}, function()
		show(index + 1)
	end)
	return gui
end

local function frame()
	if not watching then
		return
	end
	local camera = Workspace.CurrentCamera
	local feed = cameras[index]
	if camera and feed then
		camera.CameraType = Enum.CameraType.Scriptable
		-- From just in front of the lens (the camera's own housing is not in the picture).
		camera.CFrame = feed.CFrame * CFrame.new(0, 0, -(feed.Size.Z / 2 + 0.3))
		for _, other in cameras do
			other.LocalTransparencyModifier = if other == feed then 1 else 0
		end
	end
	local live = powered()
	noSignal.Visible = not live
	recLabel.Visible = live and (os.clock() % 1.2) < 0.75
	clockLabel.Text = clockText()
	local snowing = os.clock() < staticUntil
	staticFrame.Visible = snowing
	if snowing then
		for _, speck in staticFrame:GetChildren() do
			if speck:IsA("Frame") then
				speck.Position = UDim2.new(math.random(), 0, math.random(), 0)
				speck.BackgroundTransparency = 0.2 + math.random() * 0.7
			end
		end
	end
	revealOnCamera(live)
end

function CctvController.Init()
	screen = build()
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function CctvController.Start()
	Net.On("OpenCameras", open)
	Net.On("CloseCameras", function()
		close(false)
	end)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if not watching or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.A or key == Enum.KeyCode.Left then
			show(index - 1)
		elseif key == Enum.KeyCode.D or key == Enum.KeyCode.Right then
			show(index + 1)
		elseif key == Enum.KeyCode.E or key == Enum.KeyCode.Space or key == Enum.KeyCode.Backspace then
			close(true)
		end
	end)
	RunService:BindToRenderStep("NSSCctv", Enum.RenderPriority.Camera.Value + 3, frame)
end

-- For tests.
function CctvController.IsWatching(): boolean
	return watching
end

return CctvController
