--!strict
-- The local player's state on the night: running with stamina, hiding, and watching
-- the team after being caught.
--
--   Run      hold Left Shift (or the RUN button on touch screens)
--   Hiding   SPACE or the LEAVE button steps out
--   Caught   watch a teammate; LEFT / RIGHT (or the buttons) switch between them

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local HudController = require(script.Parent.HudController)

local SurvivalController = {}

local stamina = MonsterConfig.Player.StaminaSeconds
local lastRunAt = -math.huge
local runHeld = false
local runButton: TextButton? = nil

local staminaBar: Frame
local staminaFill: Frame
local hidingPanel: Frame
local spectatePanel: Frame
local spectateLabel: TextLabel
local spectateIndex = 1

local function status(): string
	return tostring(Players.LocalPlayer:GetAttribute("Status") or "")
end

local function humanoid(): Humanoid?
	local character = Players.LocalPlayer.Character
	local found = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return found
end

-- Building ------------------------------------------------------------------------------------

local function button(name: string, text: string, properties: { [string]: any }): TextButton
	local defaults: { [string]: any } = {
		Name = name,
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.2,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Text,
		TextSize = 15,
		Text = text,
		AutoButtonColor = true,
	}
	for key, value in properties do
		defaults[key] = value
	end
	local created = Theme.create("TextButton", defaults, {
		Theme.create("UICorner", { CornerRadius = UDim.new(0, 6) }),
	}) :: TextButton
	return created
end

local function build(screen: ScreenGui)
	staminaFill = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Theme.Colors.Text,
		BorderSizePixel = 0,
	}) :: Frame
	staminaBar = Theme.create("Frame", {
		Name = "Stamina",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -18),
		Size = UDim2.new(0, 180, 0, 4),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.3,
		BorderSizePixel = 0,
		Visible = false,
		Parent = screen,
	}, { staminaFill }) :: Frame

	if UserInputService.TouchEnabled then
		local run = button("Run", "RUN", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -24, 1, -170),
			Size = UDim2.new(0, 76, 0, 76),
			Parent = screen,
		})
		run.MouseButton1Down:Connect(function()
			runHeld = true
		end)
		run.MouseButton1Up:Connect(function()
			runHeld = false
		end)
		runButton = run
	end

	-- Hiding: horizontal slats over the view, as if looking through a locker vent.
	hidingPanel = Theme.create("Frame", {
		Name = "Hiding",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = screen,
	}) :: Frame
	for index = 0, 9 do
		Theme.create("Frame", {
			Name = "Slat",
			Position = UDim2.new(0, 0, index / 10, 0),
			Size = UDim2.new(1, 0, 0.07, 0),
			BackgroundColor3 = Color3.fromRGB(14, 15, 16),
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = hidingPanel,
		})
	end
	local leave = button("Leave", "LEAVE  [SPACE]", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(0, 200, 0, 40),
		ZIndex = 6,
		Parent = hidingPanel,
	})
	leave.Activated:Connect(function()
		Net.FireServer("LeaveHiding")
	end)

	spectateLabel = Theme.label({
		Name = "Label",
		Size = UDim2.new(1, -180, 1, 0),
		Position = UDim2.new(0, 90, 0, 0),
		TextSize = 16,
		Text = "",
	})
	spectatePanel = Theme.panel({
		Name = "Spectating",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -40),
		Size = UDim2.new(0, 480, 0, 54),
		Visible = false,
		Parent = screen,
	}, { spectateLabel })
	local previous = button("Previous", "<", {
		Position = UDim2.new(0, 8, 0, 7),
		Size = UDim2.new(0, 70, 0, 40),
		Parent = spectatePanel,
	})
	local nextButton = button("Next", ">", {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -8, 0, 7),
		Size = UDim2.new(0, 70, 0, 40),
		Parent = spectatePanel,
	})
	previous.Activated:Connect(function()
		spectateIndex -= 1
	end)
	nextButton.Activated:Connect(function()
		spectateIndex += 1
	end)
end

-- Running ------------------------------------------------------------------------------------

-- Advances stamina and sets the walk speed for this frame.
function SurvivalController.UpdateRunning(dt: number, wantsToRun: boolean)
	local config = MonsterConfig.Player
	local found = humanoid()
	local moving = found ~= nil and found.MoveDirection.Magnitude > 0.1
	local running = wantsToRun and moving and stamina > 0 and status() == "Working"
	if running then
		stamina = math.max(0, stamina - dt)
		lastRunAt = os.clock()
	elseif os.clock() - lastRunAt > config.StaminaRegenDelay then
		stamina = math.min(
			config.StaminaSeconds,
			stamina + dt * config.StaminaSeconds / config.StaminaRefillSeconds
		)
	end
	if found then
		found.WalkSpeed = if running then config.RunSpeed else config.WalkSpeed
	end
	staminaBar.Visible = stamina < config.StaminaSeconds - 0.01
	staminaFill.Size = UDim2.new(stamina / config.StaminaSeconds, 0, 1, 0)
	staminaFill.BackgroundColor3 = if stamina < 1 then Theme.Colors.Accent else Theme.Colors.Text
	return running
end

function SurvivalController.GetStamina(): number
	return stamina
end

-- Spectating ------------------------------------------------------------------------------------

local function teammates(): { Player }
	local list = {}
	for _, other in Players:GetPlayers() do
		if
			other ~= Players.LocalPlayer
			and other.Character
			and other:GetAttribute("Status") ~= "Spectating"
		then
			table.insert(list, other)
		end
	end
	table.sort(list, function(a: Player, b: Player)
		return a.UserId < b.UserId
	end)
	return list
end

local function updateSpectating()
	local camera = Workspace.CurrentCamera
	local list = teammates()
	if #list == 0 or not camera then
		spectateLabel.Text = "CAUGHT. BACK AT THE NEXT HOUR"
		return
	end
	spectateIndex = (spectateIndex - 1) % #list + 1
	local watched = list[spectateIndex]
	spectateLabel.Text = "CAUGHT. BACK AT THE NEXT HOUR\nWatching " .. watched.Name
	local character = watched.Character
	local head = if character then character:FindFirstChild("Head") else nil
	if head and head:IsA("BasePart") then
		camera.CameraType = Enum.CameraType.Scriptable
		local behind = head.CFrame * CFrame.new(0, 1.5, 7)
		camera.CFrame = CFrame.lookAt(behind.Position, head.Position)
	end
end

-- Status ------------------------------------------------------------------------------------

function SurvivalController.Refresh()
	local current = status()
	hidingPanel.Visible = current == "Hiding"
	spectatePanel.Visible = current == "Spectating"
	if runButton then
		runButton.Visible = current == "Working"
	end
end

function SurvivalController.Init()
	build(HudController.GetScreen())
end

function SurvivalController.Start()
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Status"):Connect(SurvivalController.Refresh)
	SurvivalController.Refresh()

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed then
			return
		end
		local current = status()
		if input.KeyCode == Enum.KeyCode.Space and current == "Hiding" then
			Net.FireServer("LeaveHiding")
		elseif
			current == "Spectating"
			and (input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.Right)
		then
			spectateIndex += if input.KeyCode == Enum.KeyCode.Left then -1 else 1
		end
	end)

	RunService.RenderStepped:Connect(function(dt: number)
		local wantsToRun = runHeld
			or UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
			or UserInputService:IsKeyDown(Enum.KeyCode.ButtonL3)
		SurvivalController.UpdateRunning(dt, wantsToRun)
		if status() == "Spectating" then
			updateSpectating()
		end
	end)
end

return SurvivalController
