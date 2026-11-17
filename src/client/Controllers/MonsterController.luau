--!strict
-- Draws The Customer and plays everything the player feels about it.
--
-- The server moves an invisible part ("TheCustomer", tag Monster) ten times a second.
-- Each client builds its own visible body and glides it after that part every frame,
-- so the monster moves smoothly instead of in steps, and poses it procedurally:
-- a stiff walk, arms that hang too long, a head that tilts while it stares.
--
-- Also: a darkening at the edges of the screen when it is near, a red tint while it is
-- chasing you, and the catch sequence when it gets you.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local HudController = require(script.Parent.HudController)

-- Within this distance the screen edges start to darken.
local DANGER_RANGE = 45
local CATCH_LINES = {
	"THANK YOU FOR SHOPPING WITH US",
	"PLEASE REMAIN WHERE YOU ARE",
	"YOUR SHIFT IS NOT OVER",
}

type Piece = { Part: BasePart, Offset: CFrame }

local MonsterController = {}

local root: BasePart? = nil
local body: Model? = nil
local pieces: { [string]: Piece } = {}
local shown: CFrame? = nil
local walkPhase = 0
local danger = 0
local vignette: { Frame } = {}
local grade: ColorCorrectionEffect? = nil
local scare: Frame? = nil
local scareText: TextLabel? = nil
local scareActive = false

-- Body ------------------------------------------------------------------------------------

local SKIN = Color3.fromRGB(196, 186, 176)
local COAT = Color3.fromRGB(122, 116, 104)
local TROUSERS = Color3.fromRGB(46, 48, 54)
local SHOES = Color3.fromRGB(24, 22, 22)
local DARK = Color3.fromRGB(16, 14, 14)

-- Offsets are from the root centre (3.7 above the floor); the body faces -Z.
local function buildBody(): Model
	local model = Instance.new("Model")
	model.Name = "TheCustomerBody"

	local function piece(name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?)
		local part = Instance.new("Part")
		part.Name = name
		part.Size = size
		part.Color = color
		part.Material = material or Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.CastShadow = true
		part.Parent = model
		pieces[name] = { Part = part, Offset = offset }
	end

	piece("LeftLeg", Vector3.new(0.55, 3.6, 0.55), CFrame.new(-0.36, -1.9, 0), TROUSERS, Enum.Material.Fabric)
	piece("RightLeg", Vector3.new(0.55, 3.6, 0.55), CFrame.new(0.36, -1.9, 0), TROUSERS, Enum.Material.Fabric)
	piece("LeftShoe", Vector3.new(0.6, 0.3, 0.9), CFrame.new(-0.36, -3.55, -0.15), SHOES)
	piece("RightShoe", Vector3.new(0.6, 0.3, 0.9), CFrame.new(0.36, -3.55, -0.15), SHOES)
	piece("Coat", Vector3.new(1.75, 2.9, 0.95), CFrame.new(0, 0.55, 0), COAT, Enum.Material.Fabric)
	-- Arms reach almost to the knees.
	piece("LeftArm", Vector3.new(0.42, 3.5, 0.42), CFrame.new(-1.08, 0.2, 0), COAT, Enum.Material.Fabric)
	piece("RightArm", Vector3.new(0.42, 3.5, 0.42), CFrame.new(1.08, 0.2, 0), COAT, Enum.Material.Fabric)
	piece("LeftHand", Vector3.new(0.36, 0.7, 0.3), CFrame.new(-1.08, -1.85, 0), SKIN)
	piece("RightHand", Vector3.new(0.36, 0.7, 0.3), CFrame.new(1.08, -1.85, 0), SKIN)
	piece("Neck", Vector3.new(0.34, 0.75, 0.34), CFrame.new(0, 2.3, 0), SKIN)
	piece("Head", Vector3.new(0.95, 1.3, 0.95), CFrame.new(0, 3.05, 0), SKIN)
	-- A face that is nearly right: small dark eyes set a little too far apart, no smile.
	piece("LeftEye", Vector3.new(0.16, 0.08, 0.05), CFrame.new(-0.26, 3.18, -0.49), DARK)
	piece("RightEye", Vector3.new(0.16, 0.08, 0.05), CFrame.new(0.26, 3.18, -0.49), DARK)
	piece("Mouth", Vector3.new(0.34, 0.04, 0.05), CFrame.new(0, 2.72, -0.49), DARK)

	return model
end

-- Poses every piece for one frame around the displayed root CFrame.
local function pose(base: CFrame, speed: number, state: string, dt: number)
	walkPhase += dt * speed * 0.9
	local stride = math.clamp(speed / 10, 0, 1)
	local swing = math.sin(walkPhase) * 0.5 * stride
	local lean = if state == "Chase" then -0.18 else 0
	local now = os.clock()
	-- While staring, the head slowly tips to one side and back.
	local tilt = if state == "Observe" then math.sin(now * 0.6) * 0.45 else 0.05
	local bob = math.abs(math.sin(walkPhase)) * 0.12 * stride

	local torso = base * CFrame.new(0, bob, 0) * CFrame.Angles(lean, 0, 0)
	for name, piece in pieces do
		local offset = piece.Offset
		local cframe: CFrame
		if name == "LeftLeg" or name == "LeftShoe" then
			cframe = base
				* CFrame.new(0, -0.1, 0)
				* CFrame.Angles(swing, 0, 0)
				* CFrame.new(0, 0.1, 0)
				* offset
		elseif name == "RightLeg" or name == "RightShoe" then
			cframe = base
				* CFrame.new(0, -0.1, 0)
				* CFrame.Angles(-swing, 0, 0)
				* CFrame.new(0, 0.1, 0)
				* offset
		elseif name == "LeftArm" or name == "LeftHand" then
			-- Arms barely swing: they hang.
			cframe = torso
				* CFrame.new(0, 1.9, 0)
				* CFrame.Angles(-swing * 0.3, 0, 0)
				* CFrame.new(0, -1.9, 0)
				* offset
		elseif name == "RightArm" or name == "RightHand" then
			cframe = torso
				* CFrame.new(0, 1.9, 0)
				* CFrame.Angles(swing * 0.3, 0, 0)
				* CFrame.new(0, -1.9, 0)
				* offset
		elseif name == "Head" or name == "LeftEye" or name == "RightEye" or name == "Mouth" then
			cframe = torso
				* CFrame.new(0, 2.6, 0)
				* CFrame.Angles(0, 0, tilt)
				* CFrame.new(0, -2.6, 0)
				* offset
		else
			cframe = torso * offset
		end
		piece.Part.CFrame = cframe
	end
end

local function setVisible(visible: boolean)
	if body then
		body.Parent = if visible then Workspace else nil
	end
end

-- Screen effects -----------------------------------------------------------------------------

local function buildEffects(screen: ScreenGui)
	-- Four gradient strips that darken the edges of the screen.
	local edges = {
		{ UDim2.new(1, 0, 0.35, 0), UDim2.new(0, 0, 0, 0), 90 },
		{ UDim2.new(1, 0, 0.35, 0), UDim2.new(0, 0, 0.65, 0), 270 },
		{ UDim2.new(0.3, 0, 1, 0), UDim2.new(0, 0, 0, 0), 0 },
		{ UDim2.new(0.3, 0, 1, 0), UDim2.new(0.7, 0, 0, 0), 180 },
	}
	for _, edge in edges do
		local frame = Theme.create("Frame", {
			Name = "DangerEdge",
			Size = edge[1],
			Position = edge[2],
			BackgroundColor3 = Color3.new(0, 0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			ZIndex = 0,
			Parent = screen,
		}, {
			Theme.create("UIGradient", {
				Rotation = edge[3],
				Transparency = NumberSequence.new(0, 1),
			}),
		}) :: Frame
		table.insert(vignette, frame)
	end

	scareText = Theme.label({
		Name = "Line",
		Size = UDim2.new(1, -40, 0, 60),
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		FontFace = Theme.Fonts.Title,
		TextSize = 30,
		TextColor3 = Theme.Colors.Accent,
		TextTransparency = 1,
		Text = "",
	})
	scare = Theme.create("Frame", {
		Name = "Scare",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 50,
		Visible = false,
		Parent = screen,
	}, { scareText :: TextLabel }) :: Frame
end

local function updateEffects(dt: number, chasingMe: boolean)
	for _, frame in vignette do
		frame.BackgroundTransparency = 1 - danger * 0.75
	end
	local camera = Workspace.CurrentCamera
	if camera and not grade then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "DangerGrade"
		effect.Parent = camera
		grade = effect
	end
	local effect = grade
	if effect then
		local target = if chasingMe then 1 else 0
		local current = (effect:GetAttribute("Level") :: number?) or 0
		local level = current + (target - current) * math.min(1, dt * 3)
		effect:SetAttribute("Level", level)
		effect.TintColor = Color3.new(1, 1 - level * 0.25, 1 - level * 0.25)
		effect.Saturation = -0.3 * level
		effect.Contrast = 0.1 * level
	end
end

-- The catch ------------------------------------------------------------------------------------

local function playCatch(variant: number)
	local camera = Workspace.CurrentCamera
	local overlay, line = scare, scareText
	if not camera or not overlay or not line then
		return
	end
	scareActive = true
	local start = camera.CFrame
	local facing = start.LookVector
	local flat = Vector3.new(facing.X, 0, facing.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)

	-- It is suddenly right there, a little too close, looking down at you. The camera
	-- sits about 4.5 studs above the floor; the monster's root is 3.7 above it.
	local spot = start.Position + flat * 2.6
	local rootPosition = Vector3.new(spot.X, start.Position.Y - 4.5 + 3.7, spot.Z)
	local face = CFrame.lookAt(rootPosition, Vector3.new(start.Position.X, rootPosition.Y, start.Position.Z))
	shown = face
	setVisible(true)

	camera.CameraType = Enum.CameraType.Scriptable
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	line.TextTransparency = 1
	line.Text = CATCH_LINES[variant] or CATCH_LINES[1]

	task.spawn(function()
		local headPosition = face * CFrame.new(0, 3.05, 0)
		local started = os.clock()
		while os.clock() - started < 1.1 do
			local t = (os.clock() - started) / 1.1
			local shake = if variant == 2
				then Vector3.new(math.sin(t * 90) * 0.06, math.cos(t * 70) * 0.06, 0)
				else Vector3.zero
			local push = if variant == 1 then t * 0.6 else 0
			camera.CFrame = CFrame.lookAt(start.Position + flat * push + shake, headPosition.Position)
			if variant == 3 then
				-- The lights go first; its face is the last thing you see.
				overlay.BackgroundTransparency = 1 - math.min(1, t * 1.3) * 0.85
			end
			task.wait()
		end
		overlay.BackgroundColor3 = Color3.fromRGB(70, 0, 0)
		overlay.BackgroundTransparency = 0.2
		task.wait(0.08)
		overlay.BackgroundColor3 = Color3.new(0, 0, 0)
		overlay.BackgroundTransparency = 0
		setVisible(false)
		for step = 0, 10 do
			line.TextTransparency = 1 - step / 10
			task.wait(0.04)
		end
	end)
end

-- Clears the catch sequence once the player is working again or watching the others.
local function endCatch()
	if not scareActive then
		return
	end
	scareActive = false
	local overlay, line = scare, scareText
	if overlay and line then
		task.spawn(function()
			for step = 0, 10 do
				overlay.BackgroundTransparency = step / 10
				line.TextTransparency = step / 10
				task.wait(0.05)
			end
			overlay.Visible = false
			overlay.BackgroundTransparency = 1
		end)
	end
end

-- Frame loop -------------------------------------------------------------------------------------

local function onFrame(dt: number)
	local part = root
	local player = Players.LocalPlayer
	local present = part ~= nil and part.Parent ~= nil and part:GetAttribute("Present") == true
	local chasingMe = false

	if part and present and not scareActive then
		local target = part.CFrame
		local previous = shown or target
		local alpha = 1 - math.exp(-dt * 10)
		local nextFrame = previous:Lerp(target, alpha)
		-- A big jump (it reappeared) is not glided across the store.
		if (target.Position - previous.Position).Magnitude > 20 then
			nextFrame = target
		end
		local speed = if dt > 0 then (nextFrame.Position - previous.Position).Magnitude / dt else 0
		shown = nextFrame
		setVisible(true)
		pose(nextFrame, speed, tostring(part:GetAttribute("State")), dt)
		chasingMe = part:GetAttribute("State") == "Chase" and part:GetAttribute("Target") == player.UserId
	elseif not scareActive then
		setVisible(false)
	end

	local level = 0
	local character = player.Character
	local myRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if part and present and myRoot and myRoot:IsA("BasePart") then
		local distance = (myRoot.Position - part.Position).Magnitude
		level = math.clamp(1 - distance / DANGER_RANGE, 0, 1)
		if chasingMe then
			level = math.max(level, 0.6)
		end
	end
	danger += (level - danger) * math.min(1, dt * 2)
	updateEffects(dt, chasingMe)
end

local function attach(instance: Instance)
	if instance:IsA("BasePart") then
		root = instance
	end
end

function MonsterController.Init()
	body = buildBody()
	buildEffects(HudController.GetScreen())

	Net.On("Caught", function(userId: any, _name: any, variant: any)
		if userId == Players.LocalPlayer.UserId then
			playCatch(tonumber(variant) or 1)
		end
	end)
end

function MonsterController.Start()
	CollectionService:GetInstanceAddedSignal("Monster"):Connect(attach)
	for _, instance in CollectionService:GetTagged("Monster") do
		attach(instance)
	end

	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("Status"):Connect(function()
		local status = player:GetAttribute("Status")
		if status == "Working" or status == "Spectating" then
			-- Give the catch sequence time to be seen before it lifts.
			task.delay(if status == "Working" then 0.2 else 0.6, endCatch)
		end
	end)

	RunService.RenderStepped:Connect(onFrame)
end

-- For tests: one frame of the loop.
MonsterController.Frame = onFrame
MonsterController.CatchDuration = MonsterConfig.CatchSequenceSeconds

return MonsterController
