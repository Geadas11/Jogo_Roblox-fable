--!strict
-- Single player / multiplayer, as chosen in the main menu.
--
--   Multiplayer     play in this server, with whoever else is here (up to 6).
--   Single player   play alone: the player is teleported to a private (reserved) server
--                   of their own. Nobody can join a reserved server without its code, so
--                   the night is theirs.
--
-- Teleports only work in a published game. In Studio, or when the player is already
-- alone here, they simply keep playing in this server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")

local Shared = ReplicatedStorage.Shared
local Log = require(Shared.Util.Log)
local Net = require(script.Parent.Parent.Net)

local log = Log.new("Match")

local MatchService = {}

-- Players with a teleport already on its way.
local leaving: { [Player]: boolean } = {}

local function tell(player: Player, text: string)
	Net.FireClient(player, "Notify", text, "Info")
end

-- Moves one player to a reserved server of their own. Returns whether it started.
function MatchService.PlaySolo(player: Player): boolean
	if leaving[player] then
		return false
	end
	if #Players:GetPlayers() <= 1 then
		-- Already alone: this server is their single-player game.
		return true
	end
	if RunService:IsStudio() then
		tell(player, "Single player needs the published game; playing in this server instead.")
		return false
	end
	leaving[player] = true
	local ok, message = pcall(function()
		local options = Instance.new("TeleportOptions")
		options.ShouldReserveServer = true
		options:SetTeleportData({ Mode = "Solo" })
		TeleportService:TeleportAsync(game.PlaceId, { player }, options)
	end)
	if not ok then
		leaving[player] = nil
		log:Warn("Solo teleport for %s failed: %s", player.Name, tostring(message))
		tell(player, "Could not start a private game. Playing in this server instead.")
		return false
	end
	tell(player, "Taking you to your own store...")
	return true
end

function MatchService.Init()
	Net.On("RequestSolo", function(player: Player)
		MatchService.PlaySolo(player)
	end)
end

function MatchService.Start()
	Players.PlayerRemoving:Connect(function(player: Player)
		leaving[player] = nil
	end)
	TeleportService.TeleportInitFailed:Connect(function(player: Player, _result, message: string)
		if leaving[player] then
			leaving[player] = nil
			log:Info("Teleport for %s failed: %s", player.Name, message)
			tell(player, "Could not start a private game. Playing in this server instead.")
		end
	end)
end

return MatchService
