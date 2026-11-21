--!strict
-- Makes every door on the map (tag: Door) open and close.
--
-- The map stores both poses of each leaf as attributes (ClosedCFrame, OpenCFrame) and
-- its current state (Open). A door marked Locked gets no prompt.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Tags = require(Shared.Config.Tags)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local InteractionService = require(script.Parent.InteractionService)

local log = Log.new("Doors")

local DoorService = {}

-- Fired after a door starts moving: (door, open, player who did it or nil).
DoorService.DoorMoved = Signal.new() :: Signal.Signal<BasePart, boolean, Player?>

local prompts: { [BasePart]: ProximityPrompt } = {}
local moving: { [BasePart]: boolean } = {}

-- How a leaf swings: about a vertical axis through `Pivot` by `Angle` (radians), from
-- `Closed` (t = 0) to `Open` (t = 1). `T` is where it is now.
type Hinge = { Pivot: Vector3, Angle: number, Closed: CFrame, Open: CFrame, T: number }
local hinges: { [BasePart]: Hinge } = {}

-- Finds the hinge from the two stored poses. Any move of a leaf from one pose to the
-- other that turns it is a rotation about some vertical axis; a door leaf is a box that
-- looks the same turned half a turn, so there are two such rotations (one for each way
-- round). The right one has its axis at an end of the leaf, where the hinges are; the
-- other spins it about a point in the middle of the room.
local function findHinge(door: BasePart, closed: CFrame, open: CFrame): Hinge?
	local best: Hinge? = nil
	local bestDistance = math.huge
	local half = closed.RightVector * (door.Size.X / 2)
	local ends = { closed.Position + half, closed.Position - half }
	for _, flip in { 0, math.pi } do
		local target = open * CFrame.Angles(0, flip, 0)
		local _, angle = (target.Rotation * closed.Rotation:Inverse()):ToOrientation()
		local c, s = math.cos(angle), math.sin(angle)
		-- target = pivot + R * (closed - pivot), so (I - R) * pivot = target - R * closed,
		-- on the floor plane (R about Y: (x, z) -> (x c + z s, -x s + z c)).
		local rx = closed.X * c + closed.Z * s
		local rz = -closed.X * s + closed.Z * c
		local bx, bz = target.X - rx, target.Z - rz
		local a11, a12, a21, a22 = 1 - c, -s, s, 1 - c
		local det = a11 * a22 - a12 * a21
		if math.abs(det) > 1e-6 then
			local px = (bx * a22 - a12 * bz) / det
			local pz = (a11 * bz - a21 * bx) / det
			local distance = math.huge
			for _, point in ends do
				distance = math.min(distance, Vector2.new(point.X - px, point.Z - pz).Magnitude)
			end
			if distance < bestDistance then
				bestDistance = distance
				best = {
					Pivot = Vector3.new(px, closed.Y, pz),
					Angle = angle,
					Closed = closed,
					Open = target,
					T = 0,
				}
			end
		end
	end
	return best
end

-- The leaf at swing fraction t (0 closed, 1 open).
local function poseAt(hinge: Hinge, t: number): CFrame
	local axis = CFrame.new(hinge.Pivot)
	return axis * CFrame.Angles(0, hinge.Angle * t, 0) * axis:Inverse() * hinge.Closed
end

function DoorService.IsOpen(door: BasePart): boolean
	return door:GetAttribute("Open") == true
end

-- Moves a door to the requested state. Returns false when it is already there, locked,
-- or still moving.
function DoorService.SetOpen(door: BasePart, open: boolean, player: Player?): boolean
	if moving[door] or door:GetAttribute("Locked") == true or DoorService.IsOpen(door) == open then
		return false
	end
	local target = door:GetAttribute(if open then "OpenCFrame" else "ClosedCFrame")
	if typeof(target) ~= "CFrame" then
		log:Warn("%s has no %s pose", door.Name, if open then "open" else "closed")
		return false
	end

	moving[door] = true
	door:SetAttribute("Open", open)
	local prompt = prompts[door]
	if prompt then
		prompt.ActionText = if open then "Close" else "Open"
	end

	local seconds = GameConfig.Doors.TweenSeconds
	local hinge = hinges[door]
	if hinge then
		-- Swing on the hinges: the leaf turns about its hinge edge and never cuts through
		-- the wall or the frame.
		local fraction = Instance.new("NumberValue")
		fraction.Value = hinge.T
		fraction.Changed:Connect(function(t: number)
			hinge.T = t
			door.CFrame = poseAt(hinge, t)
		end)
		local tween = TweenService:Create(
			fraction,
			TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
			{ Value = if open then 1 else 0 }
		)
		tween.Completed:Connect(function()
			hinge.T = if open then 1 else 0
			-- The stored pose itself (the same leaf, possibly described half a turn round).
			door.CFrame = target
			fraction:Destroy()
			moving[door] = nil
		end)
		tween:Play()
	else
		local tween = TweenService:Create(
			door,
			TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = target }
		)
		tween.Completed:Connect(function()
			moving[door] = nil
		end)
		tween:Play()
	end

	DoorService.DoorMoved:Fire(door, open, player)
	return true
end

local function register(instance: Instance)
	if not instance:IsA("BasePart") or prompts[instance] then
		return
	end
	local door = instance
	if door:GetAttribute("Locked") == true then
		return
	end
	local closed, open = door:GetAttribute("ClosedCFrame"), door:GetAttribute("OpenCFrame")
	if typeof(closed) == "CFrame" and typeof(open) == "CFrame" then
		local hinge = findHinge(door, closed, open)
		if hinge then
			hinge.T = if DoorService.IsOpen(door) then 1 else 0
			hinges[door] = hinge
		end
	end
	prompts[door] = InteractionService.AddPrompt(door, {
		action = if DoorService.IsOpen(door) then "Close" else "Open",
		object = "Door",
		distance = GameConfig.Doors.PromptDistance,
	}, function(player: Player)
		DoorService.SetOpen(door, not DoorService.IsOpen(door), player)
	end)
end

function DoorService.Start()
	CollectionService:GetInstanceAddedSignal(Tags.Door):Connect(register)
	for _, instance in CollectionService:GetTagged(Tags.Door) do
		register(instance)
	end
	local count = 0
	for _ in prompts do
		count += 1
	end
	log:Info("%d doors ready", count)
end

return DoorService
