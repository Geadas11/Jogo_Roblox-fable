--!strict
-- Every "press E on something" in the game goes through here.
--
-- A ProximityPrompt is convenient (keyboard, gamepad and touch for free) but the server
-- cannot trust that the player who triggered it was actually nearby: an exploit can fire
-- any prompt from anywhere. So prompts are only ever created by this service, and their
-- handlers only run after the server itself has checked that the player is alive, close
-- enough, and not interacting faster than a person can.
--
-- Usage:
--   InteractionService.AddPrompt(part, { action = "Open", object = "Door" }, function(player, prompt)
--       ...
--   end)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Log = require(Shared.Util.Log)
local PlayerManager = require(script.Parent.PlayerManager)

local log = Log.new("Interaction")

export type Options = {
	-- Verb shown on the prompt: "Open", "Restock", "Clean".
	action: string,
	-- What it acts on: "Door", "Shelf".
	object: string?,
	-- Seconds the key must be held. 0 = a single press.
	hold: number?,
	-- Range in studs.
	distance: number?,
	-- Whether something between the camera and the prompt hides it.
	lineOfSight: boolean?,
}

export type Handler = (player: Player, prompt: ProximityPrompt) -> ()

local InteractionService = {}

local lastInteractionAt: { [Player]: number } = {}

-- World position of whatever a prompt is attached to.
local function positionOf(holder: Instance): Vector3?
	if holder:IsA("BasePart") then
		return holder.Position
	elseif holder:IsA("Attachment") then
		return holder.WorldPosition
	end
	return nil
end

-- Returns nil when the trigger is legitimate, otherwise the reason it is not.
local function rejection(player: Player, prompt: ProximityPrompt): string?
	if not prompt.Enabled then
		return "prompt is disabled"
	end
	if not PlayerManager.IsReady(player) then
		return "player is not in the session"
	end

	local root = PlayerManager.GetRoot(player)
	if not root then
		return "player has no living character"
	end

	local holder = prompt.Parent
	local position = if holder then positionOf(holder) else nil
	if not position then
		return "prompt has no position"
	end
	local limit = prompt.MaxActivationDistance + GameConfig.Interaction.DistanceTolerance
	if (root.Position - position).Magnitude > limit then
		return "too far away"
	end

	local now = os.clock()
	local last = lastInteractionAt[player]
	if last and now - last < GameConfig.Interaction.CooldownSeconds then
		return "interacting too fast"
	end
	lastInteractionAt[player] = now
	return nil
end

-- Creates a prompt on `holder` (a part or an attachment). `handler` only runs for
-- triggers the server accepts.
function InteractionService.AddPrompt(holder: Instance, options: Options, handler: Handler): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = options.action
	prompt.ObjectText = options.object or ""
	prompt.HoldDuration = options.hold or 0
	prompt.MaxActivationDistance = options.distance or 8
	prompt.RequiresLineOfSight = options.lineOfSight == true
	-- Drawn by the client's PromptController in the game's own style.
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = holder

	prompt.Triggered:Connect(function(player: Player)
		local reason = rejection(player, prompt)
		if reason then
			log:Debug("Ignored %s on %s by %s: %s", options.action, holder.Name, player.Name, reason)
			return
		end
		local ok, message = xpcall(handler, debug.traceback, player, prompt)
		if not ok then
			log:Warn("Handler for %s on %s failed: %s", options.action, holder.Name, tostring(message))
		end
	end)

	return prompt
end

function InteractionService.Start()
	PlayerManager.PlayerLeft:Connect(function(player: Player)
		lastInteractionAt[player] = nil
	end)
end

return InteractionService
