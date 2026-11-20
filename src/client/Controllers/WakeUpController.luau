--!strict
-- The start of a night: you wake up at the table in the employee room.
--
--   eyes closed, everything blurred, head down on the table
--   two heavy blinks, the eyelids opening a little more each time
--   the head comes up, you push the chair back and stand
--
-- About four seconds, then the camera is yours. Each player gets a different chair.
-- Purely local: nobody else sees it, and the character is only placed by the chair.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Theme = require(script.Parent.Parent.UI.Theme)

local WakeUpController = {}

-- The four chairs round the staff table: where they are and which way they face.
local SEATS = {
	{ X = -88.5, Z = -13, Facing = Vector3.new(0, 0, -1) },
	{ X = -83.5, Z = -13, Facing = Vector3.new(0, 0, -1) },
	{ X = -88.5, Z = -22, Facing = Vector3.new(0, 0, 1) },
	{ X = -83.5, Z = -22, Facing = Vector3.new(0, 0, 1) },
}
local SEATED_EYE = 3.6
local STANDING_EYE = 4.5

local gui: ScreenGui? = nil
local upper: Frame
local lower: Frame
local playing = false

local function build()
	local screen = Theme.create("ScreenGui", {
		Name = "WakeUp",
		IgnoreGuiInset = true,
		ResetOnSpawn = false,
		DisplayOrder = 60,
		Enabled = false,
	}) :: ScreenGui
	-- Eyelids: black halves that meet in the middle, soft at the edge.
	local function lid(name: string, top: boolean): Frame
		return Theme.create("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0, if top then 1 else 0),
			Position = UDim2.new(0, 0, 0.5, 0),
			Size = UDim2.new(1, 0, 0.75, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			Parent = screen,
		}, {
			Theme.create("UIGradient", {
				Rotation = if top then 90 else 270,
				Transparency = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 0),
					NumberSequenceKeypoint.new(0.85, 0),
					NumberSequenceKeypoint.new(1, 0.6),
				}),
			}),
		}) :: Frame
	end
	upper = lid("Upper", true)
	lower = lid("Lower", false)
	screen.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	gui = screen
end

-- 0 = eyes shut, 1 = wide open.
local function setEyes(openness: number, seconds: number)
	local gap = openness * 0.5
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
	TweenService:Create(upper, info, { Position = UDim2.new(0, 0, 0.5 - gap, 0) }):Play()
	TweenService:Create(lower, info, { Position = UDim2.new(0, 0, 0.5 + gap, 0) }):Play()
	task.wait(seconds)
end

local function seatFor(player: Player)
	local list = Players:GetPlayers()
	table.sort(list, function(a: Player, b: Player)
		return a.UserId < b.UserId
	end)
	local index = table.find(list, player) or 1
	return SEATS[(index - 1) % #SEATS + 1]
end

function WakeUpController.IsPlaying(): boolean
	return playing
end

-- Plays the wake-up. Yields until the player has control again.
function WakeUpController.Play()
	if playing then
		return
	end
	playing = true
	if not gui then
		build()
	end
	local screen = gui :: ScreenGui
	local player = Players.LocalPlayer
	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 10)
	local camera = Workspace.CurrentCamera
	if not root or not root:IsA("BasePart") or not camera then
		playing = false
		return
	end

	local seat = seatFor(player)
	local seatPosition = Vector3.new(seat.X, 0, seat.Z)
	-- The character waits beside the chair; the view is from the chair itself.
	root.CFrame =
		CFrame.lookAt(seatPosition + Vector3.new(0, 3, 0), seatPosition + Vector3.new(0, 3, 0) + seat.Facing)
	root.Anchored = true

	local blur = Instance.new("BlurEffect")
	blur.Size = 24
	blur.Parent = camera

	-- Head down on the table, tilted.
	local eye = seatPosition + Vector3.new(0, SEATED_EYE, 0) - seat.Facing * 0.3
	local function headCFrame(pitch: number, roll: number, height: number, forward: number): CFrame
		local position = Vector3.new(eye.X, height, eye.Z) + seat.Facing * forward
		return CFrame.lookAt(position, position + seat.Facing) * CFrame.Angles(pitch, 0, roll)
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = headCFrame(-0.75, 0.18, SEATED_EYE - 0.35, 0.35)

	upper.Position = UDim2.new(0, 0, 0.5, 0)
	lower.Position = UDim2.new(0, 0, 0.5, 0)
	screen.Enabled = true

	local function cameraTo(target: CFrame, seconds: number)
		TweenService:Create(
			camera,
			TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ CFrame = target }
		):Play()
	end
	local function blurTo(size: number, seconds: number)
		TweenService:Create(blur, TweenInfo.new(seconds), { Size = size }):Play()
	end

	task.wait(0.4)
	-- First blink: barely open, everything a smear.
	setEyes(0.25, 0.45)
	blurTo(16, 0.5)
	setEyes(0, 0.2)
	task.wait(0.15)
	-- Second: more open, the head starts to come up.
	cameraTo(headCFrame(-0.35, 0.08, SEATED_EYE - 0.15, 0.15), 0.9)
	setEyes(0.6, 0.45)
	blurTo(6, 0.6)
	task.wait(0.25)
	setEyes(0.35, 0.12)
	-- Awake.
	setEyes(1, 0.35)
	blurTo(0, 0.7)
	cameraTo(headCFrame(-0.05, 0, SEATED_EYE, 0), 0.5)
	task.wait(0.55)
	-- Push back and stand up.
	cameraTo(headCFrame(0, 0, STANDING_EYE, -0.6), 0.8)
	task.wait(0.85)

	screen.Enabled = false
	blur:Destroy()
	-- Hand over: stand where the view ended up.
	root.CFrame = CFrame.lookAt(
		seatPosition - seat.Facing * 0.6 + Vector3.new(0, 3, 0),
		seatPosition - seat.Facing * 0.6 + Vector3.new(0, 3, 0) + seat.Facing
	)
	root.Anchored = false
	camera.CameraType = Enum.CameraType.Custom
	camera.CFrame = CFrame.lookAt(camera.CFrame.Position, camera.CFrame.Position + seat.Facing)
	-- One frame for the first-person camera to settle before control returns.
	RunService.RenderStepped:Wait()
	playing = false
end

return WakeUpController
