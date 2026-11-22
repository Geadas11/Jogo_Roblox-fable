--!strict
-- Carrying things. A player holds one item at a time - a stock box, a mop - which is
-- what forces choices ("drop the mop to restock, or let someone else do it").
--
-- An item is an ordinary anchored part lying in the world with a "Pick up" prompt.
-- While carried it is welded in front of the player and its prompt is off. Carried and
-- dropped items never block movement, so nobody can wall a doorway with boxes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.Config.CollisionGroups)
local GameConfig = require(Shared.Config.GameConfig)
local Signal = require(Shared.Util.Signal)
local Net = require(script.Parent.Parent.Net)
local InteractionService = require(script.Parent.InteractionService)
local PlayerManager = require(script.Parent.PlayerManager)

type Pickup = {
	Kind: string,
	Prompt: ProximityPrompt,
}

type Held = {
	Item: BasePart,
	Kind: string,
	-- What holds it to the player (removed on letting go).
	Joints: { Instance },
}

-- Where the right hand is (from the root) when it holds something out by a handle - the
-- arm pose is CharacterAnimator's (measured on an R15 avatar).
local HAND_GRIP = CFrame.new(1.23, 0.06, -1.55)

-- The broom is held in the right hand by a joint ("ToolGrip", in the hand) that
-- CharacterAnimator turns while sweeping; the arms' pose carries it along. C1 is the
-- point on the broom the hand closes round (up the handle from the broom's middle), C0
-- how the broom lies in the hand: angled down and forward, so in the arms' "ready" pose
-- the straw is just off the floor about 2.7 studs in front of you (solved in Studio on
-- an R15 avatar: straw 0.12 above the floor, slightly to the right of centre).
local BROOM_GRIP_C0 = CFrame.Angles(-0.606, 0, -0.253)
local BROOM_GRIP_C1 = CFrame.new(0, 0.52, 0)

local CarryService = {}

-- Fired when a player picks an item up or lets go of it: (player, item, kind).
-- Dropped also says whether it was a noisy drop (the player let go of it on purpose)
-- or a quiet one (set down to hide, or left behind when caught / gone).
CarryService.PickedUp = Signal.new() :: Signal.Signal<Player, BasePart, string>
CarryService.Dropped = Signal.new() :: Signal.Signal<Player, BasePart, string, boolean>

local pickups: { [BasePart]: Pickup } = {}
local held: { [Player]: Held } = {}

-- Where an item sits relative to the player's root part while carried.
local function carryOffset(kind: string): CFrame
	if kind == "Mop" then
		return CFrame.new(1.3, -0.3, -1.4)
	end
	return CFrame.new(0, -0.7, -2.4)
end

local function displayName(kind: string): string
	return (GameConfig.Carry.Names :: any)[kind] or kind
end

-- Detaches the item from the player without placing it anywhere.
local function release(player: Player, entry: Held)
	held[player] = nil
	for _, joint in entry.Joints do
		joint:Destroy()
	end
	entry.Item.AssemblyLinearVelocity = Vector3.zero
	entry.Item.AssemblyAngularVelocity = Vector3.zero
	entry.Item:SetAttribute("CarriedBy", nil)
	player:SetAttribute("Carrying", "")
end

-- Kind of item the player is carrying, or nil.
function CarryService.GetKind(player: Player): string?
	local entry = held[player]
	return if entry then entry.Kind else nil
end

-- Turns `item` into something players can pick up.
function CarryService.Register(item: BasePart, kind: string)
	if pickups[item] then
		return
	end
	item.Anchored = true
	item.CanCollide = false
	item:SetAttribute("CarryKind", kind)
	local prompt = InteractionService.AddPrompt(item, {
		action = "Pick up",
		object = displayName(kind),
		distance = GameConfig.Carry.PickupDistance,
	}, function(player: Player)
		if held[player] then
			Net.FireClient(
				player,
				"Notify",
				"Your hands are full. Drop what you are carrying first.",
				"Warning"
			)
			return
		end
		CarryService.Pickup(player, item)
	end)
	pickups[item] = { Kind = kind, Prompt = prompt }
end

function CarryService.Pickup(player: Player, item: BasePart): boolean
	local pickup = pickups[item]
	local root = PlayerManager.GetRoot(player)
	if not pickup or not root or held[player] or item:GetAttribute("CarriedBy") ~= nil then
		return false
	end

	pickup.Prompt.Enabled = false
	item.Anchored = false
	item.CollisionGroup = CollisionGroups.Names.CarriedItem

	local joints: { Instance } = {}
	local grip = item:GetAttribute("GripHeight")
	local character = player.Character
	local hand = if character then character:FindFirstChild("RightHand") else nil
	if pickup.Kind == "Mop" and hand and hand:IsA("BasePart") then
		-- In the right hand (see BROOM_GRIP_C0).
		item.Massless = true
		item.CFrame = hand.CFrame * BROOM_GRIP_C0 * BROOM_GRIP_C1:Inverse()
		local joint = Instance.new("Motor6D")
		joint.Name = "ToolGrip"
		joint.Part0 = hand
		joint.Part1 = item
		joint.C0 = BROOM_GRIP_C0
		joint.C1 = BROOM_GRIP_C1
		joint.Parent = hand
		joints = { joint }
	elseif type(grip) == "number" then
		-- Hung by its handle from the hand, free to swing: it lags behind when you set
		-- off or turn and sways back, a soft spring settling it. Light, so it does not
		-- pull the player about; it never collides (CarriedItem, CanCollide off).
		item.Massless = false
		item.CustomPhysicalProperties = PhysicalProperties.new(0.2, 0.3, 0)
		item.CFrame = root.CFrame * HAND_GRIP * CFrame.new(0, -grip, 0)
		local hand = Instance.new("Attachment")
		hand.Name = "CarryHand"
		hand.CFrame = HAND_GRIP
		hand.Parent = root
		local handle = Instance.new("Attachment")
		handle.Name = "CarryHandle"
		handle.Position = Vector3.new(0, grip, 0)
		handle.Parent = item
		local socket = Instance.new("BallSocketConstraint")
		socket.Attachment0 = hand
		socket.Attachment1 = handle
		socket.LimitsEnabled = true
		socket.UpperAngle = 30
		socket.TwistLimitsEnabled = true
		socket.TwistLowerAngle = -25
		socket.TwistUpperAngle = 25
		socket.Parent = item
		local settle = Instance.new("AlignOrientation")
		settle.Mode = Enum.OrientationAlignmentMode.TwoAttachment
		settle.Attachment0 = handle
		settle.Attachment1 = hand
		-- Measured: setting off tilts it ~20 degrees, it settles about a second after you stop.
		settle.Responsiveness = 9
		settle.MaxTorque = 90
		settle.Parent = item
		joints = { socket, settle, hand, handle }
		-- Simulated by the holder's own computer, so the swing is smooth for them.
		pcall(function()
			item:SetNetworkOwner(player)
		end)
	else
		item.Massless = true
		item.CFrame = root.CFrame * carryOffset(pickup.Kind)
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = root
		weld.Part1 = item
		weld.Parent = item
		joints = { weld }
	end

	held[player] = { Item = item, Kind = pickup.Kind, Joints = joints }
	item:SetAttribute("CarriedBy", player.UserId)
	player:SetAttribute("Carrying", pickup.Kind)
	CarryService.PickedUp:Fire(player, item, pickup.Kind)
	return true
end

-- Puts the carried item down. With `inPlace` it stays exactly where it is (used when
-- the character is disappearing); otherwise it is set on the floor in front of the player.
-- Only a deliberate drop (not in place, not `quiet`) makes a noise the monster hears.
function CarryService.Drop(player: Player, inPlace: boolean?, quiet: boolean?): boolean
	local entry = held[player]
	if not entry then
		return false
	end
	release(player, entry)

	local item = entry.Item
	local root = if inPlace then nil else PlayerManager.GetRoot(player)
	if root then
		local look = root.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		local forward = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
		-- The root part's centre is about 3 studs above the floor.
		local floor = root.Position.Y - 3
		local spot = root.Position + forward * 3
		item.CFrame = CFrame.new(spot.X, floor + item.Size.Y / 2, spot.Z)
	end
	item.Anchored = true

	local pickup = pickups[item]
	if pickup then
		pickup.Prompt.Enabled = true
	end
	CarryService.Dropped:Fire(player, item, entry.Kind, not inPlace and not quiet)
	return true
end

-- Uses up the carried item if it is of the given kind (e.g. a stock box placed on a
-- shelf). Returns whether the player had one.
function CarryService.Consume(player: Player, kind: string): boolean
	local entry = held[player]
	if not entry or entry.Kind ~= kind then
		return false
	end
	CarryService.Remove(entry.Item)
	return true
end

-- Removes an item from the game, wherever it is - on the floor or in someone's hands.
function CarryService.Remove(item: BasePart)
	for player, entry in held do
		if entry.Item == item then
			release(player, entry)
			break
		end
	end
	pickups[item] = nil
	item:Destroy()
end

function CarryService.Init()
	Net.On("DropItem", function(player: Player)
		CarryService.Drop(player)
	end)
end

function CarryService.Start()
	-- Nothing a player holds may vanish with them: it stays where they were.
	PlayerManager.PlayerLeft:Connect(function(player: Player)
		CarryService.Drop(player, true)
	end)
	PlayerManager.PlayerReady:Connect(function(player: Player)
		player:SetAttribute("Carrying", "")
		player.CharacterRemoving:Connect(function()
			CarryService.Drop(player, true)
		end)
	end)
end

return CarryService
