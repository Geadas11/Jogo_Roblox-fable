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
	Hold: number, -- 0..1: a bin bag in the right hand
	Broom: number, -- 0..1: a broom in the right hand
	Sweep: number, -- 0..1: sweeping (holding the key on a spill)
	SweepPhase: number,
	GlanceYaw: number,
	GlanceTarget: number,
	NextGlance: number,
	Player: Player?,
	-- This character's footsteps (a loop at the feet, driven by its speed).
	Steps: Sound?,
	-- 1 the moment a foot lands, fading to 0: the head dips with each step.
	StepDip: number,
	-- 0..1: curled up under a desk (eased towards CurlTarget).
	Curl: number,
	CurlTarget: number,
}

-- The curled-up pose under a desk (R15 joint transforms), found by measuring the joints
-- of a standard avatar: sitting on the floor with the knees drawn up to the chest, back
-- hunched over them (about 57 degrees), face up to watch the room, hands in front of the
-- knees. Seat and feet both rest on the floor and the whole body is about 2.3 studs
-- tall, so it fits under the desk top (HidingService puts the root 1.33 above the floor).
local CURL = {
	Root = CFrame.Angles(0.6, 0, 0),
	Waist = CFrame.Angles(-1.6, 0, 0),
	Neck = CFrame.Angles(0.9, 0, 0),
	RightHip = CFrame.Angles(2.4, 0, 0.12),
	LeftHip = CFrame.Angles(2.4, 0, -0.12),
	Knee = CFrame.Angles(-2.0, 0, 0),
	RightShoulder = CFrame.Angles(1.7, 0, -0.3),
	LeftShoulder = CFrame.Angles(1.7, 0, 0.3),
	Elbow = CFrame.Angles(1.4, 0, 0),
}
-- The "HeadTilt" anomaly: the head lolls over sideways and a little back.
local HEAD_TILT = CFrame.Angles(0.25, 0, 1.25)

-- Holding a bin bag by its knot: the right arm raised forward, the elbow a little bent.
-- (Lower than straight out: a raised arm sits right beside the first-person camera and
-- fills the corner of the screen.)
local HOLD_SHOULDER = 1.05
local HOLD_ELBOW = 0.25

-- Carrying the broom: just in the right hand at your side, the arm a little forward, the
-- handle sloping up in front of you and the straw trailing behind, clear of the floor.
-- (The broom hangs from the right hand, see CarryService's BROOM_GRIP; CARRY_GRIP turns
-- it in the hand from the sweeping angle to this one - solved in Studio.)
local BROOM_CARRY = {
	RightShoulder = CFrame.Angles(0.25, 0, 0.06),
	RightElbow = 0.35,
}
local CARRY_GRIP = CFrame.Angles(-0.877, -0.141, 0.198)
-- Sweeping (only while the key is held on a spill): both arms forward and down, the
-- right hand low on the handle, the left one higher up and across. Only the arms and the
-- broom move - the body stays still.
local BROOM_SWEEP = {
	RightShoulder = CFrame.Angles(0.5, 0, 0.05),
	RightElbow = 0.55,
	LeftShoulder = CFrame.Angles(1.0, 0, -0.45),
	LeftElbow = 0.95,
}
-- How far the arms push the broom out each way (radians at the shoulder), and the arc the
-- straw swings through at the wrist.
local SWEEP_ARMS = 0.08
local SWEEP_ARC = 0.5
-- How far the broom is tipped (about its wide axis, at the hand) while sweeping, so the
-- straw brushes the floor. Measured in Studio on an R15 avatar: through the whole stroke
-- the straw stays 0.02-0.15 studs above the floor, about 2.5 studs in front of you.
local BROOM_PITCH_SWEEP = 0.15
local SWEEP_SPEED = 7
-- Carrying a bag in the right hand, the body leans this far (radians) to the other side.
local BAG_LEAN = 0.07

-- Where the eyes are in that pose, as a camera offset (relative to the standing view).
local CURL_EYES = Vector3.new(0, -0.66, -1.3)

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
		Hold = 0,
		Broom = 0,
		Sweep = 0,
		SweepPhase = 0,
		GlanceYaw = 0,
		GlanceTarget = 0,
		NextGlance = os.clock() + math.random(3, 7),
		Player = player,
		Steps = AudioController.LoopAt("Footsteps", root, 55),
		StepDip = 0,
		Curl = 0,
		CurlTarget = 0,
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

	-- Footsteps: the shuffle of shoes (a loop following the speed) and, when running, the
	-- thump of each foot landing, fired exactly on the stride below so the sound matches
	-- the legs. Roblox's default running sound (made by its character sound script) is
	-- muted so steps are not doubled.
	local onFloor = rig.Humanoid.FloorMaterial ~= Enum.Material.Air
	local steps = rig.Steps
	if steps then
		local walking = speed > 1 and onFloor
		local runAmount = math.clamp((speed - 9) / 6, 0, 1)
		-- Running: quicker steps, only a little louder (heavy, loud steps are the monster's).
		steps.PlaybackSpeed = math.clamp(speed / 10, 0.6, 1.15)
		steps.Volume = if walking then AudioConfig.Sounds.Footsteps.Volume * (0.7 + 0.25 * runAmount) else 0
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
	-- What is in their hands: a box in both arms, or a bin bag hanging from the right hand.
	local carriedKind = if rig.Player then (rig.Player :: Player):GetAttribute("Carrying") else nil
	local holdingBag = carriedKind == "Trash"
	local holdingBroom = carriedKind == "Mop"
	local carrying = (
		type(carriedKind) == "string"
		and carriedKind ~= ""
		and not holdingBag
		and not holdingBroom
	) or rig.Model:GetAttribute("Carrying") == true
	rig.Carry = ease(rig.Carry, if carrying then 1 else 0, 10, dt)
	rig.Hold = ease(rig.Hold, if holdingBag then 1 else 0, 10, dt)
	rig.Broom = ease(rig.Broom, if holdingBroom then 1 else 0, 8, dt)
	local sweeping = holdingBroom
		and rig.Player ~= nil
		and (rig.Player :: Player):GetAttribute("Sweeping") == true
	rig.Sweep = ease(rig.Sweep, if sweeping then 1 else 0, 6, dt)
	if rig.Sweep > 0.01 then
		rig.SweepPhase = (rig.SweepPhase + dt * SWEEP_SPEED) % (math.pi * 2)
	end

	-- One full stride cycle (two steps) per this many studs: longer when running.
	local cycleLength = 4.6 + 2.6 * rig.Run
	local before = rig.Phase
	rig.Phase = (rig.Phase + speed * dt / cycleLength * math.pi * 2) % (math.pi * 2)
	-- A foot lands twice per cycle, when the legs pass each other (phase 0 and pi).
	local landed = math.floor(before / math.pi) ~= math.floor(rig.Phase / math.pi)
	if landed and onFloor and speed > 11 then
		local volume = 0.6 + 0.5 * math.clamp((speed - 11) / 5, 0, 1)
		AudioController.PlayAt(
			"RunStep",
			rig.Root.Position - Vector3.new(0, 2.6, 0),
			volume,
			60,
			0.92 + math.random() * 0.16
		)
	end
	if landed then
		rig.StepDip = 1
	end

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
	-- Holding a bag: the right arm out in front, the hand up at the knot (CarryService
	-- hangs the bag there); it stops swinging. The left arm swings as usual.
	local hold = rig.Hold
	local broom = rig.Broom
	local sweep = rig.Sweep
	-- (With a broom in hand the right arm barely swings; sweeping, neither arm does.)
	local rightSwing = armAmp * (1 - hold) * (1 - 0.7 * broom)
	local leftSwing = armAmp * (1 - sweep)
	local holdShoulder = HOLD_SHOULDER * hold
	local holdElbow = HOLD_ELBOW * hold
	-- A full bag is heavy: the arm dips with every step and comes back up, the elbow gives
	-- a little, and the body leans away from the weight.
	local bagBounce = math.cos(p * 2) * 0.08 * move * hold
	local bagElbow = math.abs(math.sin(p)) * 0.12 * move * hold
	local bagLean = BAG_LEAN * hold
	-- Sweeping: the arms push the broom from side to side and the straw swings.
	local sweepSin = math.sin(rig.SweepPhase) * sweep

	-- Curled up on the floor under a desk: sitting, knees drawn up, arms around them,
	-- back hunched, face up to watch the room. Blended in and out.
	local curlTarget = if rig.Player
			and (rig.Player :: Player):GetAttribute("HidingKind") == "UnderDesk"
			and (rig.Player :: Player):GetAttribute("Status") == "Hiding"
		then 1
		else 0
	rig.CurlTarget = curlTarget
	rig.Curl = ease(rig.Curl, curlTarget, 7, dt)
	local curl = rig.Curl
	local function blend(normal: CFrame, curled: CFrame): CFrame
		return if curl < 0.001 then normal else normal:Lerp(curled, curl)
	end

	if rig.R15 then
		set(rig, "Root", blend(CFrame.new(0, bob - 0.04 * move, 0) * CFrame.Angles(-lean, 0, 0), CURL.Root))
		set(
			rig,
			"Waist",
			blend(CFrame.Angles(-0.05 * run * move + breath * 0.02, -s * 0.08 * move, bagLean), CURL.Waist)
		)
		-- A suspicious customer's head hanging over at an angle no neck allows.
		local headTilt = if rig.Model:GetAttribute("Anomaly") == "HeadTilt"
			then HEAD_TILT
			else CFrame.identity
		set(
			rig,
			"Neck",
			blend(CFrame.Angles(lean * 0.6 + breath * 0.015, rig.GlanceYaw, 0), CURL.Neck) * headTilt
		)
		set(rig, "RightHip", blend(CFrame.Angles(-s * hipAmp, 0, 0), CURL.RightHip))
		set(rig, "LeftHip", blend(CFrame.Angles(s * hipAmp, 0, 0), CURL.LeftHip))
		set(rig, "RightKnee", blend(CFrame.Angles(-kneeRight, 0, 0), CURL.Knee))
		set(rig, "LeftKnee", blend(CFrame.Angles(-kneeLeft, 0, 0), CURL.Knee))
		local rightShoulder = CFrame.Angles(
			s * rightSwing + carryShoulder + holdShoulder + bagBounce,
			0,
			0.04 * (1 - carry) - 0.12 * hold
		)
		local leftShoulder = CFrame.Angles(-s * leftSwing + carryShoulder, 0, -0.04 * (1 - carry))
		local rightElbow = elbowBase * move * (1 - hold)
			+ math.max(0, s) * 0.3 * run * (1 - hold)
			+ carryElbow
			+ holdElbow
			+ bagElbow
		local leftElbow = elbowBase * move + math.max(0, -s) * 0.3 * run + carryElbow
		if broom > 0.001 then
			-- The right arm: at your side holding the broom, or forward sweeping, pushing
			-- it from side to side (the arm swinging as you walk stays on top).
			local push = CFrame.Angles(0, sweepSin * SWEEP_ARMS, 0)
			local rightTarget = BROOM_CARRY.RightShoulder:Lerp(BROOM_SWEEP.RightShoulder * push, sweep)
				* CFrame.Angles(s * rightSwing, 0, 0)
			rightShoulder = rightShoulder:Lerp(rightTarget, broom)
			local rightBend = BROOM_CARRY.RightElbow
				+ (BROOM_SWEEP.RightElbow - BROOM_CARRY.RightElbow) * sweep
			rightElbow += (rightBend - rightElbow) * broom
			-- The left hand only joins in to sweep.
			if sweep > 0.001 then
				leftShoulder = leftShoulder:Lerp(BROOM_SWEEP.LeftShoulder * push, sweep)
				leftElbow += (BROOM_SWEEP.LeftElbow - leftElbow) * sweep
			end
		end
		set(rig, "RightShoulder", blend(rightShoulder, CURL.RightShoulder))
		set(rig, "LeftShoulder", blend(leftShoulder, CURL.LeftShoulder))
		set(rig, "RightElbow", blend(CFrame.Angles(rightElbow, 0, 0), CURL.Elbow))
		set(rig, "LeftElbow", blend(CFrame.Angles(leftElbow, 0, 0), CURL.Elbow))
	else
		-- R6: each limb is one piece; joints hinge about their own Z axis, and the left
		-- side's joint frames are mirrored (same sign, opposite swing), as in Roblox's
		-- classic animation.
		set(
			rig,
			"RightShoulder",
			blend(
				CFrame.Angles(0, 0, s * (rightSwing + 0.1 * move * (1 - hold)) + carryShoulder + 1.4 * hold),
				CFrame.Angles(0, 0, 1.2)
			)
		)
		set(
			rig,
			"LeftShoulder",
			blend(CFrame.Angles(0, 0, s * (armAmp + 0.1 * move) - carryShoulder), CFrame.Angles(0, 0, -1.2))
		)
		set(rig, "RightHip", blend(CFrame.Angles(0, 0, -s * hipAmp), CFrame.Angles(0, 0, 1.45)))
		set(rig, "LeftHip", blend(CFrame.Angles(0, 0, -s * hipAmp), CFrame.Angles(0, 0, -1.45)))
		set(rig, "Neck", CFrame.Angles(0, 0, rig.GlanceYaw))
	end

	-- The broom in the hand: it sways a little as you walk, and swings while sweeping.
	if broom > 0.001 then
		local hand = rig.Model:FindFirstChild("RightHand") or rig.Model:FindFirstChild("Right Arm")
		local grip = if hand then hand:FindFirstChild("ToolGrip") else nil
		if hand and hand:IsA("BasePart") and grip and grip:IsA("Motor6D") then
			-- Carried, it turns in the hand to the carrying angle and sways with the walk;
			-- sweeping, it tips to the floor and swings.
			-- The stroke turns the broom about the upright through the hand, so the straw
			-- slides from side to side at the same distance in front and the same height
			-- (turning it in its own tilted plane pulled the straw back to the feet).
			local stroke = math.sin(rig.SweepPhase)
			local up = (hand.CFrame * grip.C0):VectorToObjectSpace(rig.Root.CFrame.UpVector)
			local sweeping = CFrame.fromAxisAngle(up, stroke * SWEEP_ARC)
				* CFrame.Angles(BROOM_PITCH_SWEEP, 0, 0)
			local carried = CARRY_GRIP * CFrame.Angles(s * 0.06 * move, 0, 0)
			grip.Transform = carried:Lerp(sweeping, sweep)
		end
	end

	-- Your own bag hangs from your actual hand (CarryService hangs it from a point in front
	-- of you; you simulate it, so moving that point to where the hand is this frame makes
	-- the bag rise and dip with the arm). Everyone else sees the bag you simulated.
	if hold > 0.5 and rig.Player == Players.LocalPlayer then
		local hand = rig.Model:FindFirstChild("RightHand")
		local point = rig.Root:FindFirstChild("CarryHand")
		if hand and hand:IsA("BasePart") and point and point:IsA("Attachment") then
			local closed = hand.CFrame * Vector3.new(0, -hand.Size.Y * 0.35, -0.1)
			point.Position = rig.Root.CFrame:PointToObjectSpace(closed)
		end
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
local roll = 0

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
	-- Holding a bag out in front, the right arm passes right beside the camera and would
	-- fill the corner of the screen: you see your hand and the bag, the rest of the arm
	-- is hidden (on your own screen only).
	local holding = rigs[character] ~= nil and rigs[character].Hold > 0.5
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			-- Roblox hides the whole body in first person; show everything but the head.
			local hidden = firstPersonView
				and (
					onHead(descendant, head)
					or (
						holding
						and (descendant.Name == "RightUpperArm" or descendant.Name == "RightLowerArm")
					)
				)
			descendant.LocalTransparencyModifier = if hidden then 1 else 0
		end
	end

	-- The eyes sit a little in front of the face, so looking down shows the chest and
	-- legs instead of the inside of the torso. Walking, the head rises and falls with
	-- the stride, dips as each foot lands and sways from side to side; running, all of
	-- it is stronger, so you feel the steps you hear.
	local rig = rigs[character]
	local bob = Vector3.zero
	roll = 0
	if rig and Settings.Get("CameraShake") >= 0.5 then
		bobTime += dt
		rig.StepDip = math.max(0, rig.StepDip - dt * 6)
		-- Running is only a little stronger than walking: more would get in the way of
		-- seeing where you are going.
		-- Kept small: enough to feel the steps, never enough to shake the view.
		local amount = rig.Move * (0.05 + 0.02 * rig.Run)
		local rise = math.abs(math.sin(rig.Phase)) - 0.5
		local dip = rig.StepDip * rig.StepDip * rig.Move * (0.015 + 0.01 * rig.Run)
		bob = Vector3.new(math.cos(rig.Phase) * amount * 0.3, rise * amount - dip, 0)
		roll = math.cos(rig.Phase) * rig.Move * math.rad(0.25 + 0.1 * rig.Run)
	end
	local eyes = Vector3.new(0, -0.1, -0.85)
	if rig then
		eyes = eyes:Lerp(CURL_EYES, rig.Curl)
		-- Curled up, the body keeps facing out of the hiding spot while you look around.
		local curled = rig.CurlTarget > 0
		if humanoid.AutoRotate == curled then
			humanoid.AutoRotate = not curled
		end
	end
	humanoid.CameraOffset = if firstPersonView then eyes + bob else Vector3.zero
	if not firstPersonView then
		roll = 0
	end
end

-- The sway of the head, applied as a small roll right after Roblox's camera has been
-- placed for the frame.
local function applyRoll()
	local camera = Workspace.CurrentCamera
	if camera and roll ~= 0 and camera.CameraType == Enum.CameraType.Custom then
		camera.CFrame *= CFrame.Angles(0, 0, roll)
	end
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
	RunService:BindToRenderStep("NSSHeadSway", Enum.RenderPriority.Camera.Value + 2, applyRoll)
end

-- For tests.
CharacterAnimator.GetRigs = function()
	return rigs
end

return CharacterAnimator
