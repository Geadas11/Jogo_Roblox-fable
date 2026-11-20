--!strict
-- What happens to players who are caught.
--
--   Status attribute on each player:  Working | Hiding | Caught | Spectating
--
--   Caught, playing alone   back in the employee room, once per shift (a second chance);
--                           caught again, the shift is lost.
--   Caught, in a team       watches a teammate until the next hour, then returns to work.
--                           If nobody is left working, the shift is lost.
--
-- Characters are loaded by this service (CharacterAutoLoads is off) so a caught player
-- is not automatically put back into the store.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local MonsterConfig = require(Shared.Config.MonsterConfig)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Net = require(script.Parent.Parent.Net)
local CarryService = require(script.Parent.CarryService)
local GameManager = require(script.Parent.GameManager)
local HidingService = require(script.Parent.HidingService)
local PlayerManager = require(script.Parent.PlayerManager)
local ShiftManager = require(script.Parent.ShiftManager)

local log = Log.new("Survival")

-- Seconds before someone who died some other way (e.g. reset) is back.
local RESPAWN_SECONDS = 3

local SurvivalService = {}

-- Fired when a player is caught: (player, variant).
SurvivalService.PlayerCaught = Signal.new() :: Signal.Signal<Player, number>

local deaths = 0
local chancesUsed: { [Player]: number } = {}
-- Bumped on every catch, so a delayed resolution can tell it is stale.
local catchToken: { [Player]: number } = {}

local function status(player: Player): string
	return tostring(player:GetAttribute("Status") or "")
end

local function isDown(player: Player): boolean
	local current = status(player)
	return current == "Caught" or current == "Spectating"
end

-- A player the monster can hunt: present, alive, working or hiding.
function SurvivalService.IsHuntable(player: Player): boolean
	local current = status(player)
	return (current == "Working" or current == "Hiding") and PlayerManager.GetRoot(player) ~= nil
end

-- Gives the player a fresh character in the employee room.
function SurvivalService.Respawn(player: Player)
	if not player.Parent then
		return
	end
	HidingService.Release(player)
	player:SetAttribute("Status", "Working")
	player:LoadCharacter()
end

local function everyoneDown(): boolean
	local ready = PlayerManager.GetReadyPlayers()
	if #ready == 0 then
		return false
	end
	for _, player in ready do
		if not isDown(player) then
			return false
		end
	end
	return true
end

-- Decides what happens after the catch sequence. Called after a delay; public for tests.
function SurvivalService.ResolveCatch(player: Player, token: number?)
	if token and catchToken[player] ~= token then
		return
	end
	catchToken[player] = nil
	if not player.Parent or status(player) ~= "Caught" then
		return
	end

	if GameManager.GetPhase() ~= "Shift" then
		SurvivalService.Respawn(player)
		return
	end

	local team = #PlayerManager.GetReadyPlayers()
	if team <= 1 then
		local used = chancesUsed[player] or 0
		if used < MonsterConfig.Survival.SoloSecondChances then
			chancesUsed[player] = used + 1
			SurvivalService.Respawn(player)
			Net.FireClient(player, "Notify", "You got away this time. It will not happen again.", "Warning")
		else
			GameManager.FailShift("You were caught.")
		end
		return
	end

	if everyoneDown() then
		GameManager.FailShift("Everyone was caught.")
		return
	end

	-- Watches the others until the next hour.
	player:SetAttribute("Status", "Spectating")
	local character = player.Character
	if character then
		character:Destroy()
		player.Character = nil
	end
	Net.FireAllClients("Notify", player.Name .. " was caught. They will be back at the next hour.", "Warning")
end

-- The monster caught this player. Returns false when they could not be caught.
function SurvivalService.Catch(player: Player, variant: number): boolean
	if not SurvivalService.IsHuntable(player) then
		return false
	end
	HidingService.Release(player)
	CarryService.Drop(player, true)
	player:SetAttribute("Status", "Caught")
	deaths += 1

	local root = PlayerManager.GetRoot(player)
	if root then
		root.Anchored = true
	end

	log:Info("%s was caught", player.Name)
	Net.FireAllClients("Caught", player.UserId, player.Name, variant)
	SurvivalService.PlayerCaught:Fire(player, variant)

	local token = (catchToken[player] or 0) + 1
	catchToken[player] = token
	task.delay(MonsterConfig.CatchSequenceSeconds, SurvivalService.ResolveCatch, player, token)
	return true
end

local function reviveEveryone(message: string?)
	for _, player in PlayerManager.GetReadyPlayers() do
		if isDown(player) then
			SurvivalService.Respawn(player)
			if message then
				Net.FireClient(player, "Notify", message, "Info")
			end
		end
	end
end

local function onPlayerAdded(player: Player)
	player:SetAttribute("Status", "Working")
	player.CharacterAdded:Connect(function(character: Model)
		local humanoid = character:WaitForChild("Humanoid", 10)
		if humanoid and humanoid:IsA("Humanoid") then
			humanoid.WalkSpeed = MonsterConfig.Player.WalkSpeed
			humanoid.UseJumpPower = true
			humanoid.JumpPower = MonsterConfig.Player.JumpPower
			humanoid.Died:Connect(function()
				-- Not the monster's doing (e.g. the player reset): back in a moment.
				if status(player) == "Working" or status(player) == "Hiding" then
					task.delay(RESPAWN_SECONDS, function()
						if player.Parent and player.Character == character then
							SurvivalService.Respawn(player)
						end
					end)
				end
			end)
		end
	end)
	if not player.Character then
		player:LoadCharacter()
	end
end

function SurvivalService.Init()
	Players.CharacterAutoLoads = false

	GameManager.AddResultsContributor(function(results)
		results.Deaths = deaths
	end)
end

function SurvivalService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end

	ShiftManager.HourChanged:Connect(function(hour: number)
		if hour == 0 then
			deaths = 0
			chancesUsed = {}
		else
			reviveEveryone("You are back on shift.")
		end
	end)
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase == "Lobby" then
			reviveEveryone(nil)
		end
	end)
	PlayerManager.PlayerLeft:Connect(function(player: Player)
		chancesUsed[player] = nil
		catchToken[player] = nil
		if GameManager.GetPhase() == "Shift" and everyoneDown() then
			GameManager.FailShift("Everyone was caught.")
		end
	end)
end

return SurvivalService
