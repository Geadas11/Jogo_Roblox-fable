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
local ShiftClock = require(Shared.ShiftClock)
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
	-- Other systems add their own fields (see AddResultsContributor).
	[string]: any,
}

local GameManager = {}

-- Fired with the new phase name whenever it changes.
GameManager.PhaseChanged = Signal.new() :: Signal.Signal<string>

local clockPrompts: { ProximityPrompt } = {}
local contributors: { (results: Results) -> () } = {}
-- Players who clocked out during this shift: each one is a vote to end it early.
local clockedOut: { [Player]: boolean } = {}
-- Bumped on every phase change so a delayed callback from an earlier phase can tell
-- it is stale.
local phaseSerial = 0

-- Lets another system add its own figures to the end-of-shift results (tasks done,
-- money earned...). Only stores the callback, so it is safe to call from Init.
function GameManager.AddResultsContributor(contribute: (results: Results) -> ())
	table.insert(contributors, contribute)
end

function GameManager.GetPhase(): string
	return SessionState.Get("Phase")
end

-- The time clock starts the shift from the lobby and, during the shift, lets the team
-- end it early. It does nothing while the results are showing.
local function updateClockPrompt(prompt: ProximityPrompt, phase: string)
	prompt.Enabled = phase ~= "Results"
	if phase == "Shift" then
		prompt.ActionText = "Clock out"
		prompt.ObjectText = "End the shift early"
		prompt.HoldDuration = 2
	else
		prompt.ActionText = "Clock in"
		prompt.ObjectText = "Start the night shift"
		prompt.HoldDuration = 1
	end
end

local function setPhase(phase: string)
	phaseSerial += 1
	clockedOut = {}
	SessionState.Set("Phase", phase)
	for _, prompt in clockPrompts do
		updateClockPrompt(prompt, phase)
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
	-- Announce first, so the tasks handed out at 12 AM appear after it.
	Net.FireAllClients(
		"Notify",
		if startedBy
			then startedBy.Name .. " clocked in. The night shift has begun. It ends at 6 AM."
			else "The night shift has begun. It ends at 6 AM.",
		"Info"
	)
	ShiftManager.Begin()
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
		ClockOutTime = ShiftClock.format(
			durationSeconds,
			GameConfig.Shift.HourDurationSeconds,
			GameConfig.Shift.Hours
		),
	}
	for _, contribute in contributors do
		contribute(results)
	end
	Net.FireAllClients("ShiftEnded", results)

	local serial = phaseSerial
	task.delay(GameConfig.Shift.ResultsSeconds, function()
		if phaseSerial == serial then
			GameManager.ReturnToLobby()
		end
	end)
end

-- Ends the shift before 6 AM. The results count it as not completed.
function GameManager.EndShiftEarly(): boolean
	if GameManager.GetPhase() ~= "Shift" then
		return false
	end
	local elapsed, hour = ShiftManager.GetElapsed(), ShiftManager.GetHour()
	ShiftManager.Stop()
	log:Info("Shift ended early at hour %d", hour)
	showResults(false, hour, elapsed)
	return true
end

-- Ends the shift once every player in the session has clocked out. `voter` is the
-- player who just did, if any.
local function resolveClockOut(voter: Player?)
	local ready = PlayerManager.GetReadyPlayers()
	local votes = 0
	for _, player in ready do
		if clockedOut[player] then
			votes += 1
		end
	end
	if #ready > 0 and votes >= #ready then
		Net.FireAllClients("Notify", "Everyone clocked out. The shift ended early.", "Info")
		GameManager.EndShiftEarly()
	elseif voter then
		Net.FireAllClients(
			"Notify",
			string.format(
				"%s clocked out (%d/%d). Clock out too to end the shift early.",
				voter.Name,
				votes,
				#ready
			),
			"Info"
		)
	end
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
		local phase = GameManager.GetPhase()
		if phase == "Lobby" then
			GameManager.StartShift(player)
		elseif phase == "Shift" then
			if clockedOut[player] then
				Net.FireClient(
					player,
					"Notify",
					"You already clocked out. Waiting for the rest of the team.",
					"Info"
				)
				return
			end
			clockedOut[player] = true
			resolveClockOut(player)
		end
	end)
	updateClockPrompt(prompt, GameManager.GetPhase())
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

	PlayerManager.PlayerLeft:Connect(function(player: Player)
		clockedOut[player] = nil
		if GameManager.GetPhase() ~= "Lobby" and #PlayerManager.GetReadyPlayers() == 0 then
			-- A shift with nobody left in it is abandoned.
			log:Info("Everyone left; returning to the lobby")
			GameManager.ReturnToLobby()
		elseif GameManager.GetPhase() == "Shift" then
			-- The player who left may have been the only one still working.
			resolveClockOut(nil)
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
