--!strict
-- The store's electricity.
--
-- Each light belongs to a circuit (attribute Circuit, from the map). A circuit can trip
-- at random (chance per hour in Config.PowerConfig), and at 4 AM the whole store loses power. Breakers and the
-- generator are in the electrical room, which runs on the emergency circuit so it can
-- always be found.
--
--   Breaker tripped     hold E on its breaker to reset it
--   Main failure        restart the generator first, then reset every breaker
--
-- The state of every circuit is replicated through SessionState ("Power<Circuit>",
-- "Generator"); clients switch their lights from it.

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local PowerConfig = require(Shared.Config.PowerConfig)
local Tags = require(Shared.Config.Tags)
local SessionState = require(Shared.SessionState)
local Log = require(Shared.Util.Log)
local Rng = require(Shared.Util.Rng)
local Signal = require(Shared.Util.Signal)
local Net = require(script.Parent.Parent.Net)
local GameManager = require(script.Parent.GameManager)
local InteractionService = require(script.Parent.InteractionService)
local NoiseService = require(script.Parent.NoiseService)
local ShiftManager = require(script.Parent.ShiftManager)

local log = Log.new("Power")

type Zone = { X1: number, X2: number, Z1: number, Z2: number, Area: number, Circuit: string }

local PowerManager = {}

-- Fired when a circuit or the generator changes: (name, on). Name is a circuit or "Generator".
PowerManager.Changed = Signal.new() :: Signal.Signal<string, boolean>
-- Fired when power is lost: ("Main" | "Trip", circuit or nil).
PowerManager.Failure = Signal.new() :: Signal.Signal<string, string?>

local zones: { Zone } = {}
local breakerPrompts: { [string]: ProximityPrompt } = {}
local breakerParts: { [string]: BasePart } = {}
local generatorPrompt: ProximityPrompt? = nil
local rng = Rng.new(os.time() + 31)

local function isCircuit(name: string): boolean
	return table.find(PowerConfig.Circuits, name) ~= nil
end

function PowerManager.IsOn(circuit: string): boolean
	if circuit == "Emergency" or not isCircuit(circuit) then
		return true
	end
	return SessionState.Get("Power" .. circuit) == true
end

function PowerManager.IsGeneratorOn(): boolean
	return SessionState.Get("Generator") == true
end

function PowerManager.AllOn(): boolean
	if not PowerManager.IsGeneratorOn() then
		return false
	end
	for _, circuit in PowerConfig.Circuits do
		if not PowerManager.IsOn(circuit) then
			return false
		end
	end
	return true
end

-- Circuits that are currently off.
function PowerManager.GetOff(): { string }
	local off = {}
	for _, circuit in PowerConfig.Circuits do
		if not PowerManager.IsOn(circuit) then
			table.insert(off, circuit)
		end
	end
	return off
end

local function refreshPrompts()
	local generatorOn = PowerManager.IsGeneratorOn()
	for circuit, prompt in breakerPrompts do
		prompt.Enabled = not PowerManager.IsOn(circuit)
	end
	if generatorPrompt then
		generatorPrompt.Enabled = not generatorOn
	end
end

function PowerManager.SetCircuit(circuit: string, on: boolean)
	if not isCircuit(circuit) or PowerManager.IsOn(circuit) == on then
		return
	end
	SessionState.Set("Power" .. circuit, on)
	local part = breakerParts[circuit]
	if part then
		part:SetAttribute("On", on)
	end
	refreshPrompts()
	PowerManager.Changed:Fire(circuit, on)
end

function PowerManager.SetGenerator(on: boolean)
	if PowerManager.IsGeneratorOn() == on then
		return
	end
	SessionState.Set("Generator", on)
	refreshPrompts()
	PowerManager.Changed:Fire("Generator", on)
end

-- 4 AM: everything goes dark except the emergency circuit.
function PowerManager.MainFailure()
	PowerManager.SetGenerator(false)
	for _, circuit in PowerConfig.Circuits do
		PowerManager.SetCircuit(circuit, false)
	end
	log:Info("Main power failure")
	Net.FireAllClients(
		"Notify",
		"MAIN POWER FAILURE. Restart the generator in the electrical room, then reset the breakers.",
		"Warning"
	)
	PowerManager.Failure:Fire("Main", nil)
end

-- Trips one working circuit. Returns its name, or nil when none can trip right now.
function PowerManager.TripRandom(): string?
	if not PowerManager.IsGeneratorOn() then
		return nil
	end
	local on = {}
	for _, circuit in PowerConfig.Circuits do
		if PowerManager.IsOn(circuit) then
			table.insert(on, circuit)
		end
	end
	if #on == 0 or #PowerManager.GetOff() >= PowerConfig.MaxTripped then
		return nil
	end
	local circuit = rng:Pick(on)
	PowerManager.SetCircuit(circuit, false)
	log:Info("Breaker tripped: %s", circuit)
	Net.FireAllClients(
		"Notify",
		string.format("A breaker tripped: %s. Reset it in the electrical room.", circuit),
		"Warning"
	)
	PowerManager.Failure:Fire("Trip", circuit)
	return circuit
end

-- Everything back on, without fuss (a new night, or back to the lobby).
function PowerManager.RestoreAll()
	PowerManager.SetGenerator(true)
	for _, circuit in PowerConfig.Circuits do
		PowerManager.SetCircuit(circuit, true)
	end
end

-- The circuit lighting a point on the map (the smallest zone that contains it).
function PowerManager.CircuitAt(x: number, z: number): string?
	local best: Zone? = nil
	for _, zone in zones do
		if x >= zone.X1 and x <= zone.X2 and z >= zone.Z1 and z <= zone.Z2 then
			if best == nil or zone.Area < best.Area then
				best = zone
			end
		end
	end
	return if best then best.Circuit else nil
end

-- Whether the lights are on where (x, z) is.
function PowerManager.IsLit(x: number, z: number): boolean
	local circuit = PowerManager.CircuitAt(x, z)
	return circuit == nil or PowerManager.IsOn(circuit)
end

-- Checks for a random trip; called once a minute during the shift.
function PowerManager.MaybeTrip(hour: number)
	local chance = PowerConfig.TripChanceByHour[hour] or 0
	if rng:Next() < chance then
		PowerManager.TripRandom()
	end
end

local function registerBreaker(part: BasePart)
	local circuit = tostring(part:GetAttribute("Circuit"))
	if not isCircuit(circuit) or breakerPrompts[circuit] then
		return
	end
	breakerParts[circuit] = part
	breakerPrompts[circuit] = InteractionService.AddPrompt(part, {
		action = "Reset",
		object = circuit .. " breaker",
		hold = PowerConfig.BreakerHold,
		distance = 7,
	}, function(player: Player)
		if not PowerManager.IsGeneratorOn() then
			Net.FireClient(player, "Notify", "Nothing happens. Restart the generator first.", "Warning")
			return
		end
		PowerManager.SetCircuit(circuit, true)
		NoiseService.Emit(part.Position, PowerConfig.BreakerNoise, "Breaker")
	end)
end

local function registerGenerator(part: BasePart)
	if generatorPrompt then
		return
	end
	generatorPrompt = InteractionService.AddPrompt(part, {
		action = "Restart",
		object = "Generator",
		hold = PowerConfig.GeneratorHold,
		distance = 9,
	}, function(player: Player)
		PowerManager.SetGenerator(true)
		Net.FireAllClients(
			"Notify",
			player.Name .. " restarted the generator. Now reset the breakers.",
			"Info"
		)
		-- Loud: everything in the back of the store hears it.
		NoiseService.Emit(part.Position, PowerConfig.GeneratorNoise, "Generator")
	end)
end

function PowerManager.Start()
	for _, volume in CollectionService:GetTagged(Tags.Zone) do
		if volume:IsA("BasePart") then
			local position, size = volume.Position, volume.Size
			table.insert(zones, {
				X1 = position.X - size.X / 2,
				X2 = position.X + size.X / 2,
				Z1 = position.Z - size.Z / 2,
				Z2 = position.Z + size.Z / 2,
				Area = size.X * size.Z,
				Circuit = tostring(volume:GetAttribute("Circuit")),
			})
		end
	end
	for _, part in CollectionService:GetTagged(Tags.Breaker) do
		if part:IsA("BasePart") then
			registerBreaker(part)
		end
	end
	for _, part in CollectionService:GetTagged(Tags.RepairPoint) do
		if part:IsA("BasePart") and part:GetAttribute("Kind") == "Generator" then
			registerGenerator(part)
		end
	end
	if not generatorPrompt or next(breakerPrompts) == nil then
		log:Warn("The map has no generator or breakers: power cannot be restored")
	end
	refreshPrompts()

	ShiftManager.HourChanged:Connect(function(hour: number)
		if hour == 0 then
			PowerManager.RestoreAll()
		elseif hour == PowerConfig.MainFailureHour then
			PowerManager.MainFailure()
		end
	end)
	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase ~= "Shift" then
			PowerManager.RestoreAll()
		end
	end)

	while true do
		task.wait(PowerConfig.TripCheckSeconds)
		if GameManager.GetPhase() == "Shift" then
			PowerManager.MaybeTrip(ShiftManager.GetHour())
		end
	end
end

return PowerManager
