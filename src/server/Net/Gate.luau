--!strict
-- Decides whether one incoming client call is allowed through.
--
-- Pure logic with no engine objects, so it can be tested outside Roblox. The Net
-- module owns the actual RemoteEvents and asks the gate before running any handler.
--
-- Order of checks:
--   1. the remote exists and is one clients are allowed to send
--   2. the sender still has rate budget (checked before validation, so malformed
--      spam also burns the sender's budget)
--   3. the arguments match the declared validators

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Check = require(ReplicatedStorage.Shared.Net.Check)
local RateLimiter = require(script.Parent.RateLimiter)

export type Definition = {
	kind: string,
	from: string,
	args: { Check.Validator },
	rate: { burst: number, perSecond: number }?,
}

export type Gate = {
	Admit: (self: Gate, sender: any, name: string, ...any) -> (boolean, string?),
	Violations: (self: Gate, sender: any) -> number,
	Forget: (self: Gate, sender: any) -> (),
}

local Gate = {}

function Gate.new(definitions: { [string]: Definition }, clock: (() -> number)?): Gate
	local limiters: { [string]: RateLimiter.RateLimiter } = {}
	local violations: { [any]: number } = {}

	for name, definition in definitions do
		if definition.kind ~= "Event" and definition.kind ~= "Function" then
			error(string.format("Net: remote %q has invalid kind %q", name, tostring(definition.kind)), 0)
		end
		if definition.from ~= "Client" and definition.from ~= "Server" then
			error(string.format("Net: remote %q has invalid sender %q", name, tostring(definition.from)), 0)
		end
		if definition.kind == "Function" and definition.from ~= "Client" then
			error(string.format("Net: function %q must be sent by clients", name), 0)
		end
		if definition.from == "Client" then
			local rate = definition.rate
			if not rate then
				error(string.format("Net: remote %q is sent by clients and must declare a rate", name), 0)
			end
			limiters[name] = RateLimiter.new(rate.burst, rate.perSecond, clock)
		end
	end

	local gate = {}

	local function reject(sender: any, reason: string): (boolean, string?)
		violations[sender] = (violations[sender] or 0) + 1
		return false, reason
	end

	function gate.Admit(_self: any, sender: any, name: string, ...: any): (boolean, string?)
		local definition = definitions[name]
		if not definition then
			return reject(sender, "unknown remote")
		end
		if definition.from ~= "Client" then
			return reject(sender, "clients may not send this remote")
		end

		if not limiters[name]:Try(sender) then
			return reject(sender, "rate limit exceeded")
		end

		local ok, reason = Check.args(definition.args, ...)
		if not ok then
			return reject(sender, reason or "invalid arguments")
		end

		return true
	end

	-- How many calls from this sender have been rejected so far.
	function gate.Violations(_self: any, sender: any): number
		return violations[sender] or 0
	end

	-- Releases everything stored for a sender. Call when a player leaves.
	function gate.Forget(_self: any, sender: any)
		violations[sender] = nil
		for _, limiter in limiters do
			limiter:Forget(sender)
		end
	end

	return (gate :: any) :: Gate
end

return Gate
