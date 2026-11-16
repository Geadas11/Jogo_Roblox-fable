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
}

return table.freeze(Definitions)
