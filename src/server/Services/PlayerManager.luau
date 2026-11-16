--!strict
-- Owns the server-side record of every player in the session.
--
-- Current responsibilities (Phase 2):
--   * create / destroy a record when a player joins / leaves
--   * mark a player as ready once their client reports it has finished loading
--   * keep every character in the Player collision group
--
-- Gameplay state (alive, hidden, carrying, dead, spectating) is added to the record in
-- Phase 4. Other services ask this module about players instead of keeping their own
-- per-player tables.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.Config.CollisionGroups)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Trove = require(Shared.Util.Trove)
local Net = require(script.Parent.Parent.Net)
local CollisionService = require(script.Parent.CollisionService)

local log = Log.new("Players")

type Record = {
	ClientReady: boolean,
	-- Everything tied to the player; cleaned when they leave.
	Trove: Trove.Trove,
	-- Everything tied to the current character; cleaned on respawn.
	CharacterTrove: Trove.Trove,
}

local PlayerManager = {}

-- Fired once per player, when their client has finished loading.
PlayerManager.PlayerReady = Signal.new() :: Signal.Signal<Player>
-- Fired when a player leaves, after their record has been removed.
PlayerManager.PlayerLeft = Signal.new() :: Signal.Signal<Player>

local records: { [Player]: Record } = {}

local function onCharacterAdded(record: Record, character: Model)
	record.CharacterTrove:Clean()
	record.CharacterTrove:Add(CollisionService.Assign(character, CollisionGroups.Names.Player))
end

local function onPlayerAdded(player: Player)
	if records[player] then
		return
	end

	local trove = Trove.new()
	local characterTrove = Trove.new()
	trove:Add(characterTrove)

	local record: Record = {
		ClientReady = false,
		Trove = trove,
		CharacterTrove = characterTrove,
	}
	records[player] = record

	trove:Connect(player.CharacterAdded, function(character: Model)
		onCharacterAdded(record, character)
	end)
	if player.Character then
		onCharacterAdded(record, player.Character)
	end
end

local function onPlayerRemoving(player: Player)
	local record = records[player]
	if not record then
		return
	end
	records[player] = nil
	record.Trove:Clean()
	PlayerManager.PlayerLeft:Fire(player)
end

local function onClientReady(player: Player)
	local record = records[player]
	-- Unknown player, or a repeated message: nothing to do.
	if not record or record.ClientReady then
		return
	end
	record.ClientReady = true
	log:Info("%s is ready (%d in session)", player.Name, #PlayerManager.GetReadyPlayers())
	PlayerManager.PlayerReady:Fire(player)
end

function PlayerManager.Init()
	Net.On("ClientReady", onClientReady)
end

function PlayerManager.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	-- Players who connected before this code ran (common in Studio).
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
end

function PlayerManager.IsReady(player: Player): boolean
	local record = records[player]
	return record ~= nil and record.ClientReady
end

-- The player's root part while their character is alive, otherwise nil. Every server
-- check that depends on where a player is goes through this.
function PlayerManager.GetRoot(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return nil
end

function PlayerManager.GetReadyPlayers(): { Player }
	local ready = {}
	for player, record in records do
		if record.ClientReady then
			table.insert(ready, player)
		end
	end
	return ready
end

return PlayerManager
