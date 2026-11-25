--!strict
-- The single catalog of every remote in the game.
--
-- The server creates one RemoteEvent / RemoteFunction per entry at boot; nothing else
-- in the project is allowed to create remotes. Adding a remote means adding an entry
-- here, which forces us to state who may send it, what it carries and how often.
--
--   kind   "Event"     one-way message
--          "Function"  client asks, server answers. Always client -> server: the
--                      server never invokes a client, because a client can simply
--                      never answer and stall the calling thread.
--   from   "Client"    sent by clients. `args` and `rate` are enforced by the server.
--          "Server"    sent by the server. A client firing it is ignored and logged.
--   args   one validator per argument, in order (see Check).
--   rate   token bucket per player: `burst` calls at once, refilled at `perSecond`.
--          Mandatory for everything sent by clients.
--
-- Only remotes that are actually used belong here.

local Check = require(script.Parent.Check)
local SettingsConfig = require(script.Parent.Parent.Config.SettingsConfig)

export type Rate = {
	burst: number,
	perSecond: number,
}

export type Definition = {
	kind: "Event" | "Function",
	from: "Client" | "Server",
	args: { Check.Validator },
	rate: Rate?,
}

local Definitions: { [string]: Definition } = {
	-- The client has finished loading and started its controllers.
	-- The server waits for this before treating the player as part of the session.
	ClientReady = {
		kind = "Event",
		from = "Client",
		args = {},
		rate = { burst = 2, perSecond = 0.1 },
	},

	-- A short message for the player's HUD: (text: string, kind: "Info" | "Warning").
	Notify = {
		kind = "Event",
		from = "Server",
		args = {},
	},

	-- The objectives list changed. Carries the complete list, so a client never has to
	-- piece it together from partial updates.
	TasksChanged = {
		kind = "Event",
		from = "Server",
		args = {},
	},

	-- Asks for the current objectives list (used once, when a client starts).
	GetTasks = {
		kind = "Function",
		from = "Client",
		args = {},
		rate = { burst = 3, perSecond = 0.2 },
	},

	-- Put down whatever the player is carrying.
	DropItem = {
		kind = "Event",
		from = "Client",
		args = {},
		rate = { burst = 4, perSecond = 2 },
	},

	-- Someone was caught by the monster: (userId: number, name: string, variant: number).
	-- Every client is told; the caught player's client plays the catch sequence.
	Caught = {
		kind = "Event",
		from = "Server",
		args = {},
	},

	-- Turn the player's flashlight on (true) or off (false).
	Flashlight = {
		kind = "Event",
		from = "Client",
		args = { Check.boolean },
		rate = { burst = 6, perSecond = 4 },
	},

	-- Leave the hiding spot the player is in.
	LeaveHiding = {
		kind = "Event",
		from = "Client",
		args = {},
		rate = { burst = 3, perSecond = 2 },
	},

	-- Change one of the player's settings: (key, value 0..1). Saved by SettingsService.
	SetSetting = {
		kind = "Event",
		from = "Client",
		args = { Check.oneOf(SettingsConfig.Keys), Check.numberRange(0, 1) },
		rate = { burst = 20, perSecond = 8 },
	},

	-- Main menu: play alone. The server moves the player to a private server of their
	-- own (or simply lets them play where they are when they are already alone).
	RequestSolo = {
		kind = "Event",
		from = "Client",
		args = {},
		rate = { burst = 2, perSecond = 0.2 },
	},

	-- Something strange happened (EventManager): (kind: string, data: table).
	-- Clients play the sound / effect; anything that changes the world was already done
	-- by the server.
	HorrorEvent = {
		kind = "Event",
		from = "Server",
		args = {},
	},

	-- Security cameras: the server tells the player's client to show the feeds (after
	-- they used a monitor) or to stop showing them (caught, shift over); the client says
	-- when the player looks away from the monitor.
	OpenCameras = {
		kind = "Event",
		from = "Server",
		args = {},
	},
	CloseCameras = {
		kind = "Event",
		from = "Server",
		args = {},
	},
	LeaveCameras = {
		kind = "Event",
		from = "Client",
		args = {},
		rate = { burst = 3, perSecond = 2 },
	},

	-- The way to the player's next step (GuideService): a flat list of points
	-- { x1, z1, x2, z2, ... } along the walkable route, or an empty list for none.
	Guide = {
		kind = "Event",
		from = "Server",
		args = {},
	},

	-- The shift is over. Carries the results table shown on the results screen.
	ShiftEnded = {
		kind = "Event",
		from = "Server",
		args = {},
	},
}

return table.freeze(Definitions)
