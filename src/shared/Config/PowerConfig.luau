--!strict
-- The store's electricity and how the lights behave as the night goes on.

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

return deepFreeze({
	-- Circuits that can fail, as named on the breakers in the electrical room. The
	-- "Emergency" circuit (electrical room, exit signs) never fails.
	Circuits = { "Shop", "BackOfHouse", "Cold", "Staff", "Exterior" },

	-- The main failure: every circuit goes down at the start of this hour (4 = 4 AM).
	-- The generator must be restarted, then each breaker reset.
	MainFailureHour = 4,

	-- Random breaker trips: chance per check (once a minute), by hour
	-- (index 1 = 1 AM ... 5 = 5 AM; midnight never trips). 0 = no trips that hour.
	TripChanceByHour = { 0, 0.2, 0.3, 0.3, 0.45 },
	-- Never more than this many circuits down from random trips at once.
	MaxTripped = 2,
	TripCheckSeconds = 60,

	-- Seconds the key is held.
	GeneratorHold = 4,
	BreakerHold = 1.5,
	-- How far the generator and a breaker are heard (the monster comes to look).
	GeneratorNoise = 45,
	BreakerNoise = 20,

	-- Lights, per hour (index 1 = 12 AM ... 6 = 5 AM):
	--   Ambient   multiplier on the base indoor/outdoor ambient light
	--   Flicker   average seconds between flickers somewhere in the store (0 = none)
	Hours = {
		{ Ambient = 1.0, Flicker = 0 },
		{ Ambient = 1.0, Flicker = 40 },
		{ Ambient = 0.95, Flicker = 18 },
		{ Ambient = 0.85, Flicker = 10 },
		{ Ambient = 0.75, Flicker = 7 },
		{ Ambient = 0.6, Flicker = 4 },
	},
})
