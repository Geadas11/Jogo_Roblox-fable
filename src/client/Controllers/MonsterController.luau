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
local SessionState = require(Shared.SessionState)
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Net = require(script.Parent.Parent.Net)
local Settings = require(script.Parent.Parent.Settings)
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
-- 0 = walking, 1 = running flat out (eased, so the gait blends).
local runBlend = 0
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

-- The R15 body (when the server provides the template) ------------------------------------------

local rig: Model? = nil
local rigRoot: BasePart? = nil
local rigHead: BasePart? = nil
local rigJoints: { [string]: any } = {}
-- Turns applied under the pose at some joints: the sculpted body comes with its arms
-- held out (an "A" pose), so its shoulders are turned to bring them down to the sides.
local restFix: { [string]: CFrame } = {}
-- Height of the rig's root above the floor (the server's root is ROOT_HEIGHT above it).
local rigRootHeight = 3.7
local SERVER_ROOT_HEIGHT = 3.7

-- A face that is nearly right: small, dark, wide-set eyes of slightly different sizes,
-- a thin mouth that does not quite go straight, shadows under the eyes.
local function drawFace(head: BasePart)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 100
	gui.LightInfluence = 1
	gui.Parent = head
	local function mark(
		x: number,
		y: number,
		w: number,
		h: number,
		color: Color3,
		transparency: number,
		rotation: number?
	)
		local frame = Instance.new("Frame")
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.new(x, 0, y, 0)
		frame.Size = UDim2.new(w, 0, h, 0)
		frame.BackgroundColor3 = color
		frame.BackgroundTransparency = transparency
		frame.BorderSizePixel = 0
		frame.Rotation = rotation or 0
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = frame
		frame.Parent = gui
	end
	local shadow = Color3.fromRGB(70, 62, 66)
	local blood = Color3.fromRGB(96, 8, 10)
	-- Sunken, red-rimmed eyes, slightly different sizes.
	mark(0.27, 0.42, 0.22, 0.18, shadow, 0.5)
	mark(0.75, 0.43, 0.2, 0.17, shadow, 0.5)
	mark(0.27, 0.42, 0.14, 0.1, Color3.fromRGB(120, 30, 30), 0.35)
	mark(0.75, 0.43, 0.12, 0.09, Color3.fromRGB(120, 30, 30), 0.35)
	mark(0.27, 0.42, 0.09, 0.07, DARK, 0)
	mark(0.75, 0.43, 0.075, 0.065, DARK, 0)

	-- A mouth that opens too wide, a little crooked, full of uneven yellowed teeth.
	local mouth = Instance.new("Frame")
	mouth.Name = "Mouth"
	mouth.AnchorPoint = Vector2.new(0.5, 0.5)
	mouth.Position = UDim2.new(0.52, 0, 0.68, 0)
	mouth.Size = UDim2.new(0.5, 0, 0.16, 0)
	mouth.Rotation = -5
	mouth.BackgroundColor3 = Color3.fromRGB(26, 6, 8)
	mouth.BorderSizePixel = 0
	mouth.ClipsDescendants = true
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.45, 0)
	corner.Parent = mouth
	mouth.Parent = gui
	local teeth = Color3.fromRGB(214, 200, 160)
	for index = 0, 7 do
		for _, top in { true, false } do
			local tooth = Instance.new("Frame")
			local height = 0.28 + ((index * 37 + (if top then 11 else 23)) % 17) / 60
			tooth.AnchorPoint = Vector2.new(0, if top then 0 else 1)
			tooth.Position = UDim2.new(0.04 + index * 0.115, 0, if top then 0 else 1, 0)
			tooth.Size = UDim2.new(0.095, 0, height, 0)
			tooth.Rotation = ((index * 13) % 9) - 4
			tooth.BackgroundColor3 = teeth:Lerp(Color3.fromRGB(150, 130, 90), ((index * 7) % 5) / 8)
			tooth.BorderSizePixel = 0
			tooth.Parent = mouth
		end
	end

	-- Blood around the mouth, running from its corners down the chin.
	mark(0.52, 0.77, 0.34, 0.04, blood, 0.3)
	for _, drip in { { 0.3, 0.74, 0.035, 0.14 }, { 0.71, 0.73, 0.03, 0.2 }, { 0.5, 0.78, 0.04, 0.12 } } do
		local run = Instance.new("Frame")
		run.AnchorPoint = Vector2.new(0.5, 0)
		run.Position = UDim2.new(drip[1], 0, drip[2], 0)
		run.Size = UDim2.new(drip[3], 0, drip[4], 0)
		run.BackgroundColor3 = blood
		run.BackgroundTransparency = 0.1
		run.BorderSizePixel = 0
		run.Parent = gui
	end
end

local function setUpRig(template: Model)
	local model = template:Clone()
	model.Name = "TheCustomerBody"
	local root = model:FindFirstChild("HumanoidRootPart")
	local head = model:FindFirstChild("Head")
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not head or not head:IsA("BasePart") or not humanoid then
		return
	end
	root.Anchored = true
	root.Transparency = 1
	-- It is moved by hand: no physics, no state machine, and no Animator (which would
	-- reset the joints to the rest pose every frame).
	humanoid.EvaluateStateMachine = false
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if animator then
		animator:Destroy()
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
			rigJoints[descendant.Name] = descendant
		elseif descendant:IsA("BasePart") then
			descendant.CastShadow = true
		end
	end
	-- (The sculpted body has a face of its own; the simple one gets one drawn on.)
	if model:GetAttribute("Sculpted") ~= true then
		drawFace(head)
	else
		-- Measure how far out each arm is held in the rest pose, in the torso's frame, and
		-- turn the shoulder so it hangs straight down instead.
		for _, side in { "Right", "Left" } do
			local upper = model:FindFirstChild(side .. "UpperArm")
			local hand = model:FindFirstChild(side .. "Hand")
			local torso = model:FindFirstChild("UpperTorso")
			local shoulder = rigJoints[side .. "Shoulder"]
			if
				upper
				and upper:IsA("BasePart")
				and hand
				and hand:IsA("BasePart")
				and torso
				and torso:IsA("BasePart")
				and shoulder
			then
				-- (The joint's own frame: C0 on a Motor6D, its first attachment on an
				-- AnimationConstraint.)
				local frame = if shoulder:IsA("Motor6D")
					then torso.CFrame * shoulder.C0
					elseif shoulder.Attachment0 then shoulder.Attachment0.WorldCFrame
					else torso.CFrame
				local along = frame:VectorToObjectSpace(hand.Position - upper.Position)
				if along.Magnitude > 0.1 then
					-- A touch out from the body, so the hands clear the apron.
					local down = Vector3.new(if side == "Right" then 0.12 else -0.12, -1, 0).Unit
					restFix[side .. "Shoulder"] = CFrame.fromRotationBetweenVectors(along.Unit, down)
				end
			end
		end
	end
	rigRootHeight = humanoid.HipHeight + root.Size.Y / 2
	rig, rigRoot, rigHead = model, root, head
	-- Replace the simple body.
	if body then
		local wasVisible = body.Parent ~= nil
		body.Parent = nil
		body = model
		model.Parent = if wasVisible then Workspace else nil
	end
end

local function joint(name: string, cframe: CFrame)
	local motor = rigJoints[name]
	if motor then
		local fix = restFix[name]
		motor.Transform = if fix then fix * cframe else cframe
	end
end

-- Poses the rig: a stiff walk with arms that hang and barely move; while staring the
-- head slowly tips to one side. Running (chasing someone at full speed) blends into a
-- lurching sprint: long strides, knees snapping up, the body thrown forward, the long
-- arms pumping wildly and the head jerking about - fast, but never quite human.
local function poseRig(base: CFrame, speed: number, state: string, dt: number)
	local root = rigRoot :: BasePart
	local runTarget = math.clamp((speed - 9) / 5, 0, 1)
	runBlend += (runTarget - runBlend) * (1 - math.exp(-6 * dt))
	local run = runBlend
	-- Longer strides when running: the legs cycle a little slower for the speed.
	walkPhase += dt * speed * (0.9 - 0.3 * run)
	local stride = math.clamp(speed / 9, 0, 1)
	local p = walkPhase
	local s = math.sin(p)
	local chase = if state == "Chase" then 1 else 0
	local now = os.clock()
	local tilt = if state == "Observe" then math.sin(now * 0.6) * 0.5 else 0.09
	local bob = math.abs(math.cos(p)) * (0.1 + 0.35 * run) * stride
	-- Jerks of the head while it runs: two uneven wobbles, never in step with the legs.
	local twitch = run * (math.sin(now * 13.7) * 0.12 + math.sin(now * 7.3 + 1.1) * 0.08)

	root.CFrame = base * CFrame.new(0, rigRootHeight - SERVER_ROOT_HEIGHT, 0)
	-- The body thrown forward, twisting with each stride.
	local lean = 0.28 * chase * (1 - run) + 0.55 * run
	joint("Root", CFrame.new(0, bob - 0.15 * run, 0) * CFrame.Angles(-lean, s * 0.12 * run, 0))
	joint("Waist", CFrame.Angles(-0.1 * chase * (1 - run) - 0.15 * run, -s * 0.25 * run, 0))
	-- The head does not bob with the body: it stays level (pushed up against the lean),
	-- tilted, a little forward.
	joint(
		"Neck",
		CFrame.Angles(0.12 + 0.2 * chase * (1 - run) + 0.35 * run + twitch, twitch * 0.6, tilt + twitch * 0.5)
	)
	local legAmp = (0.45 + 0.25 * chase) * stride * (1 - run) + 1.0 * run
	joint("RightHip", CFrame.Angles(-s * legAmp - 0.25 * run, 0, 0))
	joint("LeftHip", CFrame.Angles(s * legAmp - 0.25 * run, 0, 0))
	-- Walking, knees that bend too little (the walk looks wrong); running, they snap up
	-- high behind as each leg swings back.
	local kneeAmp = 0.25 * stride * (1 - run) + 1.5 * run
	joint("RightKnee", CFrame.Angles(-kneeAmp * math.max(0, -math.sin(p + 0.9)), 0, 0))
	joint("LeftKnee", CFrame.Angles(-kneeAmp * math.max(0, math.sin(p + 0.9)), 0, 0))
	-- Arms: hanging, reaching forward when it is after you; running, swinging hard
	-- against the legs with the elbows bent, flung a little out to the sides.
	local reach = 0.9 * chase * (1 - run)
	local armSwing = s * (0.06 * stride * (1 - run) + 1.1 * run)
	local flail = 0.18 * run
	joint("RightShoulder", CFrame.Angles(reach + armSwing + 0.2 * run, 0, 0.03 + flail))
	joint("LeftShoulder", CFrame.Angles(reach - armSwing + 0.2 * run, 0, -0.03 - flail))
	joint("RightElbow", CFrame.Angles(0.15 * chase * (1 - run) + (0.7 + 0.4 * math.max(0, s)) * run, 0, 0))
	joint("LeftElbow", CFrame.Angles(0.15 * chase * (1 - run) + (0.7 + 0.4 * math.max(0, -s)) * run, 0, 0))
end

-- Where its head is, for the catch sequence.
local function headPosition(): Vector3
	if rigHead then
		return (rigHead :: BasePart).Position
	end
	local piece = pieces.Head
	return if piece then piece.Part.Position else Vector3.zero
end

-- Poses every piece for one frame around the displayed root CFrame.
local function pose(base: CFrame, speed: number, state: string, dt: number)
	if rig then
		poseRig(base, speed, state, dt)
		return
	end
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
	-- Put the body right there, leaning in.
	pose(face, 0, "Chase", 0)

	camera.CameraType = Enum.CameraType.Scriptable
	overlay.Visible = true
	overlay.BackgroundTransparency = 1
	line.TextTransparency = 1
	line.Text = CATCH_LINES[variant] or CATCH_LINES[1]

	task.spawn(function()
		local lookAt = headPosition()
		local started = os.clock()
		while os.clock() - started < 1.1 do
			local t = (os.clock() - started) / 1.1
			local shake = if variant == 2 and Settings.Get("CameraShake") >= 0.5
				then Vector3.new(math.sin(t * 90) * 0.06, math.cos(t * 70) * 0.06, 0)
				else Vector3.zero
			local push = if variant == 1 then t * 0.6 else 0
			camera.CFrame = CFrame.lookAt(start.Position + flat * push + shake, lookAt)
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
	-- A catch that ends the shift (alone, or the last of the team): the player stays
	-- "Caught" until the lobby, so lift the black screen for the results instead.
	SessionState.Observe("Phase", function(phase: string)
		if phase ~= "Shift" then
			task.delay(1.2, endCatch)
		end
	end)

	RunService.RenderStepped:Connect(onFrame)

	-- The proper body, once the server has built it (it may take a moment after joining).
	task.spawn(function()
		local template = ReplicatedStorage:WaitForChild("TheCustomerRig", 30)
		if template and template:IsA("Model") then
			setUpRig(template)
		end
	end)
end

-- For tests: one frame of the loop.
MonsterController.Frame = onFrame
MonsterController.CatchDuration = MonsterConfig.CatchSequenceSeconds

return MonsterController
