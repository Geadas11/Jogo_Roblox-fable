--!strict
-- The night's clock. Decides which hour it is and announces every change; it knows
-- nothing about tasks, monsters or rewards - those systems listen to it.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage.Shared
local GameConfig = require(Shared.Config.GameConfig)
local SessionState = require(Shared.SessionState)
local ShiftClock = require(Shared.ShiftClock)
local Log = require(Shared.Util.Log)
local Signal = require(Shared.Util.Signal)

local log = Log.new("Shift")

local ShiftManager = {}

-- Fired with the new hour: 0 when the shift begins (12 AM), then 1 to 5.
ShiftManager.HourChanged = Signal.new() :: Signal.Signal<number>
-- Fired once when the clock reaches 6 AM.
ShiftManager.Completed = Signal.new() :: Signal.Signal<()>

local running = false
local startTime = 0
local hour = 0

function ShiftManager.IsRunning(): boolean
	return running
end

function ShiftManager.GetHour(): number
	return hour
end

-- Real seconds since the shift began (0 when no shift is running).
function ShiftManager.GetElapsed(): number
	if not running then
		return 0
	end
	return Workspace:GetServerTimeNow() - startTime
end

function ShiftManager.Begin()
	if running then
		return
	end
	running = true
	hour = 0
	startTime = Workspace:GetServerTimeNow()
	SessionState.Set("HourDuration", GameConfig.Shift.HourDurationSeconds)
	SessionState.Set("ShiftStartTime", startTime)
	SessionState.Set("Hour", 0)
	log:Info("Shift started")
	ShiftManager.HourChanged:Fire(0)
end

-- Ends the shift without completing it (for example when everyone has left).
function ShiftManager.Stop()
	running = false
end

-- Advances the hour when enough time has passed. Called a few times per second by the
-- loop in Start; public so tests can drive the clock directly.
function ShiftManager.Update()
	if not running then
		return
	end
	local target = ShiftClock.hourAt(
		Workspace:GetServerTimeNow() - startTime,
		GameConfig.Shift.HourDurationSeconds,
		GameConfig.Shift.Hours
	)
	-- One step at a time, so no hour is ever skipped even after a long stall.
	while running and hour < target do
		hour += 1
		SessionState.Set("Hour", hour)
		if hour >= GameConfig.Shift.Hours then
			running = false
			log:Info("Shift completed")
			ShiftManager.Completed:Fire()
		else
			log:Info("Hour %d of %d", hour, GameConfig.Shift.Hours)
			ShiftManager.HourChanged:Fire(hour)
		end
	end
end

function ShiftManager.Start()
	while true do
		task.wait(0.25)
		ShiftManager.Update()
	end
end

return ShiftManager
