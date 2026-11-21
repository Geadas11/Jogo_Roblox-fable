--!strict
-- The local player's state on the night: running with stamina, hiding, and watching
-- the team after being caught.
--
--   Run      hold Left Shift (or the RUN button on touch screens)
--   Hiding   SPACE or the LEAVE button steps out
--   Caught   watch a teammate; LEFT / RIGHT (or the buttons) switch between them

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(Shared.Config.AudioConfig)
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)
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

	-- Hiding: what frames the view depends on where you are (HidingKind attribute).
	hidingPanel = Theme.create("Frame", {
		Name = "Hiding",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		ZIndex = 5,
		Parent = screen,
	}) :: Frame
	local function view(name: string): Frame
		return Theme.create("Frame", {
			Name = name,
			Size = UDim2.new(1, 0, 1, 0),
			BackgroundTransparency = 1,
			Visible = false,
			ZIndex = 5,
			Parent = hidingPanel,
		}) :: Frame
	end
	local function block(parent: Instance, position: UDim2, size: UDim2, color: Color3, transparency: number?)
		Theme.create("Frame", {
			Position = position,
			Size = size,
			BackgroundColor3 = color,
			BackgroundTransparency = transparency or 0,
			BorderSizePixel = 0,
			ZIndex = 5,
			Parent = parent,
		})
	end
	local metal = Color3.fromRGB(14, 15, 16)

	-- Locker: looking out through the slatted vent in the door.
	local locker = view("Locker")
	for index = 0, 9 do
		block(locker, UDim2.new(0, 0, index / 10, 0), UDim2.new(1, 0, 0.07, 0), metal)
	end

	-- Under the desk: nothing drawn over the view. You are really down there, curled up
	-- on the floor (CharacterAnimator), looking out from under the desk top.
	view("UnderDesk")

	-- Restroom stall: the door is shut; you watch through the gap at its edge.
	local stall = view("Stall")
	local door = Color3.fromRGB(46, 58, 64)
	block(stall, UDim2.new(0, 0, 0, 0), UDim2.new(0.47, 0, 1, 0), door)
	block(stall, UDim2.new(0.53, 0, 0, 0), UDim2.new(0.47, 0, 1, 0), door)
	block(stall, UDim2.new(0.47, 0, 0, 0), UDim2.new(0.06, 0, 1, 0), Color3.new(0, 0, 0), 0.35)
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

-- Your own breathing: only right at the end of your stamina. Running on the last 18% of
-- it you start to pant (full in the last 10%); when it runs out you gasp and keep
-- panting while you are spent. The moment the stamina starts coming back the panting
-- fades out within half a second.
local panting: Sound? = nil
local breathLevel = 0
local gasped = false
local BREATH_FROM = 0.18
local BREATH_FULL = 0.1

local function breathe(dt: number, running: boolean)
	local config = MonsterConfig.Player
	local share = stamina / config.StaminaSeconds
	local target = 0
	if stamina <= 0.001 then
		-- Spent: heavy breathing until the stamina starts to come back.
		target = 1
	elseif running and share < BREATH_FROM then
		target = math.clamp((BREATH_FROM - share) / (BREATH_FROM - BREATH_FULL), 0, 1)
	end
	breathLevel += (target - breathLevel) * math.min(1, dt * (if target > breathLevel then 3 else 6))

	if stamina <= 0 and not gasped then
		gasped = true
		AudioController.Play("Gasp")
	elseif share > 0.4 then
		gasped = false
	end

	if not panting and breathLevel > 0.02 then
		panting = AudioController.Loop("Panting")
	end
	local sound = panting
	if sound then
		sound.Volume = AudioConfig.Sounds.Panting.Volume * breathLevel
		if breathLevel > 0.02 and not sound.IsPlaying then
			sound:Play()
		elseif breathLevel <= 0.02 and sound.IsPlaying then
			sound:Stop()
		end
	end
end

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
		-- At the monitor watching the cameras you stand still (and so does your back).
		local watchingCameras = Players.LocalPlayer:GetAttribute("WatchingCameras") == true
		found.WalkSpeed = if watchingCameras then 0 elseif running then config.RunSpeed else config.WalkSpeed
	end
	staminaBar.Visible = stamina < config.StaminaSeconds - 0.01
	staminaFill.Size = UDim2.new(stamina / config.StaminaSeconds, 0, 1, 0)
	staminaFill.BackgroundColor3 = if stamina < 1 then Theme.Colors.Accent else Theme.Colors.Text
	breathe(dt, running)
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

-- Under a desk the body must face out of the open side, the way the server placed it:
-- the first-person camera may already have turned it on this client.
local function faceOutOfSpot()
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return
	end
	local nearest: BasePart? = nil
	local best = 6
	for _, spot in CollectionService:GetTagged("HidingSpot") do
		if spot:IsA("BasePart") and spot:GetAttribute("Kind") == "UnderDesk" then
			local distance =
				Vector3.new(spot.Position.X - root.Position.X, 0, spot.Position.Z - root.Position.Z).Magnitude
			if distance < best then
				best = distance
				nearest = spot
			end
		end
	end
	if nearest then
		local look = nearest.CFrame.LookVector
		root.CFrame = CFrame.lookAt(root.Position, root.Position + Vector3.new(look.X, 0, look.Z))
	end
end

-- The way into the room you are hiding in: its door (same Zone), so the first thing
-- you see from under the desk is the doorway, where it would come in. You can still
-- look around afterwards.
local function lookAtDoor()
	local camera = Workspace.CurrentCamera
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not camera or not root or not root:IsA("BasePart") then
		return
	end
	local zone = nil
	local closest = 6
	for _, spot in CollectionService:GetTagged("HidingSpot") do
		if spot:IsA("BasePart") then
			local distance = (spot.Position - root.Position).Magnitude
			if distance < closest then
				closest = distance
				zone = spot:GetAttribute("Zone")
			end
		end
	end
	local target: Vector3? = nil
	local nearestDoor = math.huge
	for _, door in CollectionService:GetTagged("Door") do
		if door:IsA("BasePart") and door:GetAttribute("Zone") == zone then
			local closedPose = door:GetAttribute("ClosedCFrame")
			local position = if typeof(closedPose) == "CFrame" then closedPose.Position else door.Position
			local distance = (position - root.Position).Magnitude
			if distance < nearestDoor then
				nearestDoor = distance
				target = position
			end
		end
	end
	if target and camera.CameraType == Enum.CameraType.Custom then
		local eye = camera.CFrame.Position
		-- Level with the eyes, a little up: the middle of the doorway.
		camera.CFrame = CFrame.lookAt(eye, Vector3.new(target.X, eye.Y + 0.6, target.Z))
	end
end

function SurvivalController.Refresh()
	local current = status()
	hidingPanel.Visible = current == "Hiding"
	local kind = tostring(Players.LocalPlayer:GetAttribute("HidingKind") or "Locker")
	if current == "Hiding" and kind == "UnderDesk" then
		-- Again a moment later, once the body has stopped turning with the camera.
		task.defer(faceOutOfSpot)
		task.delay(0.25, faceOutOfSpot)
		-- Once the camera has settled down at the eyes, turn it to the door.
		task.delay(0.35, lookAtDoor)
	end
	for _, child in hidingPanel:GetChildren() do
		if child:IsA("Frame") then
			child.Visible = child.Name == kind
				or (child.Name == "Locker" and kind ~= "UnderDesk" and kind ~= "Stall")
		end
	end
	spectatePanel.Visible = current == "Spectating"
	if runButton then
		runButton.Visible = current == "Working"
	end
end

function SurvivalController.Init()
	build(HudController.GetScreen())
end

-- No jumping (the server also sets JumpPower to 0; this also hides the jump button).
local function disableJump(character: Model)
	local found = character:WaitForChild("Humanoid", 10)
	if found and found:IsA("Humanoid") then
		pcall(function()
			found:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		end)
	end
end

function SurvivalController.Start()
	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Status"):Connect(SurvivalController.Refresh)
	player:GetAttributeChangedSignal("HidingKind"):Connect(SurvivalController.Refresh)
	SurvivalController.Refresh()
	player.CharacterAdded:Connect(disableJump)
	if player.Character then
		task.spawn(disableJump, player.Character)
	end

	-- Only typing (chat, a text box) blocks these keys: Roblox and Studio may flag plain
	-- key presses as processed without anything being typed.
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if UserInputService:GetFocusedTextBox() ~= nil then
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
