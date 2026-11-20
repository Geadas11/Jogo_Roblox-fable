--!strict
-- The game's own walk, run and idle, drawn procedurally on every client for every
-- character: players (with their own avatars, R15 or R6) and customer NPCs.
--
-- Roblox's default Animate script is replaced by an empty one (src/character), so
-- nothing else moves the joints. Each frame, for each character near the camera, this
-- reads how fast it is really moving and poses its Motor6D joints:
--
--   idle   slow breathing, and now and then a glance to one side
--   walk   a tired night-shift walk: modest stride, arms barely swinging
--   run    long stride, knees high, elbows bent, body leaning forward
--   carry  both arms forward around whatever is held (players' "Carrying" attribute)
--
-- Because it is driven by real movement, every client sees the same thing without any
-- network traffic. For the local player it also shows their own body in first person
-- (look down: legs, arms, the box you carry) and adds a gentle head bob while walking.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Settings = require(script.Parent.Parent.Settings)
local AudioConfig = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared").Config.AudioConfig)
local AudioController = require(script.Parent.AudioController)

local CharacterAnimator = {}

-- Beyond this distance from the camera nobody can see the detail: skip the work.
local MAX_DISTANCE = 140
-- Joint names on the two rig types.
local R15 = {
	Root = "Root",
	Waist = "Waist",
	Neck = "Neck",
	LeftShoulder = "LeftShoulder",
	RightShoulder = "RightShoulder",
	LeftElbow = "LeftElbow",
	RightElbow = "RightElbow",
	LeftHip = "LeftHip",
	RightHip = "RightHip",
	LeftKnee = "LeftKnee",
	RightKnee = "RightKnee",
}
local R6 = {
	Root = "RootJoint",
	Neck = "Neck",
	LeftShoulder = "Left Shoulder",
	RightShoulder = "Right Shoulder",
	LeftHip = "Left Hip",
	RightHip = "Right Hip",
}

type Rig = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	R15: boolean,
	Joints: { [string]: any },
	Phase: number,
	-- Eased values, so poses blend instead of snapping.
	Move: number, -- 0 = standing, 1 = full stride
	Run: number, -- 0 = walking, 1 = running
	Carry: number,
	GlanceYaw: number,
	GlanceTarget: number,
	NextGlance: number,
	Player: Player?,
	-- This character's footsteps (a loop at the feet, driven by its speed).
	Steps: Sound?,
}

local rigs: { [Model]: Rig } = {}

-- Rigs -------------------------------------------------------------------------------------------

local function track(model: Model, player: Player?)
	if rigs[model] then
		return
	end
	local humanoid = model:WaitForChild("Humanoid", 10)
	local root = model:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not humanoid:IsA("Humanoid") or not root or not root:IsA("BasePart") then
		return
	end
	-- Joints are created with the body; give them a moment on a slow connection.
	task.wait(0.2)
	local isR15 = model:FindFirstChild("UpperTorso") ~= nil
	local names = if isR15 then R15 else R6
	local joints: { [string]: any } = {}
	for _, descendant in model:GetDescendants() do
		-- Classic rigs use Motor6D; avatars with Roblox's newer joints use
		-- AnimationConstraint. Both have the same names and a Transform.
		if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
			for key, name in names do
				if descendant.Name == name then
					joints[key] = descendant
				end
			end
		end
	end
	if not joints.LeftHip or not joints.RightHip then
		model:SetAttribute("Animated", false)
		return
	end
	-- Local marker (this client only), handy when debugging in Studio.
	model:SetAttribute("Animated", true)
	rigs[model] = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		R15 = isR15,
		Joints = joints,
		Phase = math.random() * math.pi * 2,
		Move = 0,
		Run = 0,
		Carry = 0,
		GlanceYaw = 0,
		GlanceTarget = 0,
		NextGlance = os.clock() + math.random(3, 7),
		Player = player,
		Steps = AudioController.LoopAt("Footsteps", root, 55),
	}
end

local function set(rig: Rig, key: string, cframe: CFrame)
	local joint = rig.Joints[key]
	if joint then
		joint.Transform = cframe
	end
end

-- Posing -----------------------------------------------------------------------------------------

local function ease(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function pose(rig: Rig, dt: number, now: number)
	local velocity = rig.Root.AssemblyLinearVelocity
	local speed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
	if rig.Root.Anchored then
		speed = 0
	end

	-- Footsteps: faster and louder with speed, silent when standing. Roblox's default
	-- running sound (made by its character sound script) is muted so steps are not doubled.
	local steps = rig.Steps
	if steps then
		local walking = speed > 1 and rig.Humanoid.FloorMaterial ~= Enum.Material.Air
		steps.PlaybackSpeed = math.clamp(speed / 11, 0.6, 1.5)
		steps.Volume = if walking
			then AudioConfig.Sounds.Footsteps.Volume * (0.55 + 0.6 * math.clamp((speed - 8) / 8, 0, 1))
			else 0
		if walking and not steps.IsPlaying then
			steps:Play()
		elseif not walking and steps.IsPlaying then
			steps:Stop()
		end
	end
	local defaultSteps = rig.Root:FindFirstChild("Running")
	if defaultSteps and defaultSteps:IsA("Sound") and defaultSteps.Volume ~= 0 then
		defaultSteps.Volume = 0
	end

	rig.Move = ease(rig.Move, math.clamp(speed / 5, 0, 1), 8, dt)
	rig.Run = ease(rig.Run, math.clamp((speed - 10) / 4, 0, 1), 6, dt)
	local carrying = rig.Player ~= nil
			and (rig.Player :: Player):GetAttribute("Carrying") ~= nil
			and (rig.Player :: Player):GetAttribute("Carrying") ~= ""
		or rig.Model:GetAttribute("Carrying") == true
	rig.Carry = ease(rig.Carry, if carrying then 1 else 0, 10, dt)

	-- One full stride cycle (two steps) per this many studs: longer when running.
	local cycleLength = 4.6 + 2.6 * rig.Run
	rig.Phase = (rig.Phase + speed * dt / cycleLength * math.pi * 2) % (math.pi * 2)

	-- Now and then, standing or walking, it glances to one side.
	if now >= rig.NextGlance then
		rig.NextGlance = now + 2.5 + math.random() * 5
		rig.GlanceTarget = if math.random() < 0.45 then (math.random() - 0.5) * 1.2 else 0
	end
	rig.GlanceYaw = ease(rig.GlanceYaw, rig.GlanceTarget * (1 - rig.Run), 3, dt)

	local p = rig.Phase
	local move, run, carry = rig.Move, rig.Run, rig.Carry
	local s = math.sin(p)
	local breath = math.sin(now * 1.7 + p) * (1 - move)

	-- Amplitudes blend from a tired walk to a full sprint.
	local hipAmp = (0.42 + 0.5 * run) * move
	local kneeAmp = (0.55 + 0.75 * run) * move
	local armAmp = (0.22 + 0.75 * run) * move * (1 - carry)
	local elbowBase = 0.12 + 1.15 * run
	local lean = 0.2 * run * move
	local bob = math.abs(math.cos(p)) * (0.06 + 0.16 * run) * move

	-- Knees bend while each leg swings back and lifts.
	local kneeRight = kneeAmp * math.max(0, -math.sin(p + 0.9))
	local kneeLeft = kneeAmp * math.max(0, math.sin(p + 0.9))

	-- Carrying: both arms forward around the item, elbows a little bent.
	local carryShoulder = 1.25 * carry
	local carryElbow = 0.35 * carry

	if rig.R15 then
		set(rig, "Root", CFrame.new(0, bob - 0.04 * move, 0) * CFrame.Angles(-lean, 0, 0))
		set(rig, "Waist", CFrame.Angles(-0.05 * run * move + breath * 0.02, -s * 0.08 * move, 0))
		set(rig, "Neck", CFrame.Angles(lean * 0.6 + breath * 0.015, rig.GlanceYaw, 0))
		set(rig, "RightHip", CFrame.Angles(-s * hipAmp, 0, 0))
		set(rig, "LeftHip", CFrame.Angles(s * hipAmp, 0, 0))
		set(rig, "RightKnee", CFrame.Angles(-kneeRight, 0, 0))
		set(rig, "LeftKnee", CFrame.Angles(-kneeLeft, 0, 0))
		set(rig, "RightShoulder", CFrame.Angles(s * armAmp + carryShoulder, 0, 0.04 * (1 - carry)))
		set(rig, "LeftShoulder", CFrame.Angles(-s * armAmp + carryShoulder, 0, -0.04 * (1 - carry)))
		set(
			rig,
			"RightElbow",
			CFrame.Angles(elbowBase * move + math.max(0, s) * 0.3 * run + carryElbow, 0, 0)
		)
		set(
			rig,
			"LeftElbow",
			CFrame.Angles(elbowBase * move + math.max(0, -s) * 0.3 * run + carryElbow, 0, 0)
		)
	else
		-- R6: each limb is one piece; joints hinge about their own Z axis, and the left
		-- side's joint frames are mirrored (same sign, opposite swing), as in Roblox's
		-- classic animation.
		set(rig, "RightShoulder", CFrame.Angles(0, 0, s * (armAmp + 0.1 * move) + carryShoulder))
		set(rig, "LeftShoulder", CFrame.Angles(0, 0, s * (armAmp + 0.1 * move) - carryShoulder))
		set(rig, "RightHip", CFrame.Angles(0, 0, -s * hipAmp))
		set(rig, "LeftHip", CFrame.Angles(0, 0, -s * hipAmp))
		set(rig, "Neck", CFrame.Angles(0, 0, rig.GlanceYaw))
	end
end

-- The local player's own body in first person ---------------------------------------------------

-- Parts that would block the view from inside the head: the head itself and anything
-- worn on it (hats, hair, glasses).
local function onHead(part: BasePart, head: BasePart): boolean
	if part == head then
		return true
	end
	local accessory = part:FindFirstAncestorOfClass("Accessory")
	if accessory then
		local weld = part:FindFirstChild("AccessoryWeld")
		if weld and weld:IsA("Weld") then
			return weld.Part0 == head or weld.Part1 == head
		end
	end
	return false
end

local bobTime = 0

local function firstPerson(dt: number)
	local player = Players.LocalPlayer
	local character = player.Character
	local camera = Workspace.CurrentCamera
	if not character or not camera then
		return
	end
	local head = character:FindFirstChild("Head")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not head or not head:IsA("BasePart") or not humanoid then
		return
	end
	local firstPersonView = (camera.CFrame.Position - head.Position).Magnitude < 2
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- Roblox hides the whole body in first person; show everything but the head.
			descendant.LocalTransparencyModifier = if firstPersonView and onHead(descendant, head)
				then 1
				else 0
		end
	end

	-- The eyes sit a little in front of the face, so looking down shows the chest and
	-- legs instead of the inside of the torso; a small bob while walking.
	local rig = rigs[character]
	local bob = Vector3.zero
	if rig and Settings.Get("CameraShake") >= 0.5 then
		bobTime += dt
		local amount = rig.Move * (0.05 + 0.08 * rig.Run)
		bob = Vector3.new(math.cos(rig.Phase) * amount * 0.6, math.abs(math.sin(rig.Phase)) * amount, 0)
	end
	humanoid.CameraOffset = if firstPersonView then Vector3.new(0, -0.1, -0.85) + bob else Vector3.zero
end

-- Frame -------------------------------------------------------------------------------------------

-- Joints are posed after Roblox's Animator has run for the frame (PreSimulation):
-- earlier, the Animator would reset them to the rest pose before they are drawn.
local function frame(dt: number)
	local camera = Workspace.CurrentCamera
	local origin = if camera then camera.CFrame.Position else Vector3.zero
	local now = os.clock()
	for model, rig in rigs do
		if not model.Parent then
			-- Gone (respawned, left, customer walked out).
			rigs[model] = nil
			continue
		end
		if rig.Humanoid.Health <= 0 then
			continue
		end
		if (rig.Root.Position - origin).Magnitude <= MAX_DISTANCE then
			pose(rig, dt, now)
		end
	end
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(function(character: Model)
		track(character, player)
	end)
	if player.Character then
		task.spawn(track, player.Character, player)
	end
end

function CharacterAnimator.Start()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, player in Players:GetPlayers() do
		watchPlayer(player)
	end
	-- Customer NPCs (and anything else the server tags as an animated character).
	CollectionService:GetInstanceAddedSignal("AnimatedCharacter"):Connect(function(model: Instance)
		if model:IsA("Model") then
			track(model, nil)
		end
	end)
	for _, model in CollectionService:GetTagged("AnimatedCharacter") do
		if model:IsA("Model") then
			task.spawn(track, model, nil)
		end
	end
	RunService.Stepped:Connect(function(_time: number, dt: number)
		frame(dt)
	end)
	-- The first-person view (camera offset, own body) goes with the camera.
	RunService.RenderStepped:Connect(firstPerson)
end

-- For tests.
CharacterAnimator.GetRigs = function()
	return rigs
end

return CharacterAnimator
