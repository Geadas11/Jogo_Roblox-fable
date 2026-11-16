--!strict
-- The session loop:  Lobby  ->  Shift  ->  Results  ->  Lobby.
--
--   Lobby    everyone is in the building; nothing is happening. A player starts the
--            night by clocking in at the time clock in the employee room.
--   Shift    ShiftManager runs the clock from 12 AM to 6 AM.
--   Results  the shift summary is shown, then the session returns to the lobby.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local Tags = require(Shared.Config.Tags)
local SessionState = require(Shared.SessionState)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)
local Net = require(script.Parent.Parent.Net)
local InteractionService = require(script.Parent.InteractionService)
local PlayerManager = require(script.Parent.PlayerManager)
local ShiftManager = require(script.Parent.ShiftManager)

local log = Log.new("Game")

export type Results = {
	Completed: boolean,
	HoursWorked: number,
	DurationSeconds: number,
}

local GameManager = {}

-- Fired with the new phase name whenever it changes.
GameManager.PhaseChanged = Signal.new() :: Signal.Signal<string>

local clockPrompts: { ProximityPrompt } = {}
-- Bumped on every phase change so a delayed callback from an earlier phase can tell
-- it is stale.
local phaseSerial = 0

function GameManager.GetPhase(): string
	return SessionState.Get("Phase")
end

local function setPhase(phase: string)
	phaseSerial += 1
	SessionState.Set("Phase", phase)
	for _, prompt in clockPrompts do
		prompt.Enabled = phase == "Lobby"
	end
	GameManager.PhaseChanged:Fire(phase)
end

-- Starts the night. Returns false unless the session is in the lobby.
function GameManager.StartShift(startedBy: Player?): boolean
	if GameManager.GetPhase() ~= "Lobby" then
		return false
	end
	log:Info("Shift started by %s", if startedBy then startedBy.Name else "the server")
	setPhase("Shift")
	ShiftManager.Begin()
	Net.FireAllClients(
		"Notify",
		if startedBy
			then startedBy.Name .. " clocked in. The night shift has begun."
			else "The night shift has begun.",
		"Info"
	)
	return true
end

function GameManager.ReturnToLobby()
	if GameManager.GetPhase() == "Lobby" then
		return
	end
	ShiftManager.Stop()
	SessionState.Set("Hour", 0)
	setPhase("Lobby")
end

local function showResults(completed: boolean, hoursWorked: number, durationSeconds: number)
	setPhase("Results")
	local results: Results = {
		Completed = completed,
		HoursWorked = hoursWorked,
		DurationSeconds = math.floor(durationSeconds),
	}
	Net.FireAllClients("ShiftEnded", results)

	local serial = phaseSerial
	task.delay(GameConfig.Shift.ResultsSeconds, function()
		if phaseSerial == serial then
			GameManager.ReturnToLobby()
		end
	end)
end

local function registerClock(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	local prompt = InteractionService.AddPrompt(instance, {
		action = "Clock in",
		object = "Start the night shift",
		hold = 1,
	}, function(player: Player)
		GameManager.StartShift(player)
	end)
	prompt.Enabled = GameManager.GetPhase() == "Lobby"
	table.insert(clockPrompts, prompt)
end

function GameManager.Init()
	ShiftManager.Completed:Connect(function()
		showResults(
			true,
			GameConfig.Shift.Hours,
			GameConfig.Shift.Hours * GameConfig.Shift.HourDurationSeconds
		)
	end)

	-- A shift with nobody left in it is abandoned.
	PlayerManager.PlayerLeft:Connect(function()
		if GameManager.GetPhase() ~= "Lobby" and #PlayerManager.GetReadyPlayers() == 0 then
			log:Info("Everyone left; returning to the lobby")
			GameManager.ReturnToLobby()
		end
	end)
end

function GameManager.Start()
	CollectionService:GetInstanceAddedSignal(Tags.TimeClock):Connect(registerClock)
	for _, instance in CollectionService:GetTagged(Tags.TimeClock) do
		registerClock(instance)
	end
	if #clockPrompts == 0 then
		log:Warn("The map has no TimeClock: nobody can start a shift")
	end
end

return GameManager
