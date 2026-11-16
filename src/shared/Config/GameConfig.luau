--!strict
-- Global tuning values. Anything a designer may want to change lives under Config;
-- gameplay code reads from here instead of hard-coding numbers.

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

return deepFreeze({
	-- Printed by the server and every client at boot, so it is obvious whether Studio
	-- is running the code that is currently in the repository. Bump on every delivery.
	BuildVersion = "0.3.1",

	-- Intended server size. The real limit is set in Studio (Game Settings > Places);
	-- the server only reports when the two disagree.
	MaxPlayers = 6,

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
