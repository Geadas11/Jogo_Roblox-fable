--!strict
-- Global tuning values. Anything a designer may want to change lives under Config;
-- gameplay code reads from here instead of hard-coding numbers.

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

return deepFreeze({
	-- Printed by the server and every client at boot, so it is obvious whether Studio
	-- is running the code that is currently in the repository. Bump on every delivery.
	BuildVersion = "0.4.0",

	-- Intended server size. The real limit is set in Studio (Game Settings > Places);
	-- the server only reports when the two disagree.
	MaxPlayers = 6,

	Shift = {
		-- Real seconds per in-game hour. Six hours: 240 s gives a 24 minute shift.
		HourDurationSeconds = 240,
		-- The shift runs from 12 AM to 6 AM.
		Hours = 6,
		-- How long the results stay up before the session returns to the lobby.
		ResultsSeconds = 20,
	},

	Interaction = {
		-- Extra studs allowed beyond a prompt's range before the server rejects a
		-- trigger. Covers the gap between where the client and the server see a player.
		DistanceTolerance = 4,
		-- Minimum seconds between two interactions by the same player.
		CooldownSeconds = 0.25,
	},

	Doors = {
		TweenSeconds = 0.35,
		PromptDistance = 9,
	},

	Debug = {
		-- Prints Debug-level log lines. Turn off before release.
		VerboseLogging = true,
	},

	Boot = {
		-- Seconds a client waits for server-created objects (remotes, session state)
		-- before failing with a readable error instead of hanging forever.
		ReplicationTimeout = 15,
	},

	Net = {
		-- Minimum seconds between "rejected request" warnings for the same player,
		-- so a spamming client cannot flood the server log.
		ViolationLogInterval = 5,
	},
})
