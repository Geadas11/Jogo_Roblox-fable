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
	Weld: WeldConstraint,
}

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
	entry.Weld:Destroy()
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
	item.Massless = true
	item.CollisionGroup = CollisionGroups.Names.CarriedItem
	item.CFrame = root.CFrame * carryOffset(pickup.Kind)

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = item
	weld.Parent = item

	held[player] = { Item = item, Kind = pickup.Kind, Weld = weld }
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
