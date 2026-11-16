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
	local tween = TweenService:Create(
		door,
		TweenInfo.new(seconds, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = target }
	)
	tween.Completed:Connect(function()
		moving[door] = nil
	end)
	tween:Play()

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
