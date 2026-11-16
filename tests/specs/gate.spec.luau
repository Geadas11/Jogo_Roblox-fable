-- Server.Net.Gate: the decision every incoming client call goes through.

local side = Engine.new().side("server")
local Gate = side.load("ServerScriptService.Server.Net.Gate")
local Check = side.load("ReplicatedStorage.Shared.Net.Check")

local function fakeClock()
	local now = 0
	return function()
		return now
	end, function(seconds)
		now += seconds
	end
end

local function definitions()
	return {
		Restock = {
			kind = "Event",
			from = "Client",
			args = { Check.integerRange(1, 10), Check.string(8) },
			rate = { burst = 2, perSecond = 1 },
		},
		Query = {
			kind = "Function",
			from = "Client",
			args = {},
			rate = { burst = 1, perSecond = 1 },
		},
		Announce = { kind = "Event", from = "Server", args = {} },
	}
end

test("admits a well-formed call", function()
	local gate = Gate.new(definitions(), fakeClock())
	local ok, reason = gate:Admit("player", "Restock", 3, "milk")
	expect.truthy(ok)
	expect.equal(reason, nil)
	expect.equal(gate:Violations("player"), 0)
end)

test("rejects a remote that does not exist", function()
	local gate = Gate.new(definitions(), fakeClock())
	local ok, reason = gate:Admit("player", "GiveMoney", 999999)
	expect.falsy(ok)
	expect.equal(reason, "unknown remote")
	expect.equal(gate:Violations("player"), 1)
end)

test("rejects a client sending a server -> client remote", function()
	local gate = Gate.new(definitions(), fakeClock())
	local ok, reason = gate:Admit("player", "Announce")
	expect.falsy(ok)
	expect.equal(reason, "clients may not send this remote")
end)

test("rejects malformed arguments", function()
	local gate = Gate.new(definitions(), fakeClock())
	expect.falsy(gate:Admit("p1", "Restock", 0 / 0, "milk"))
	expect.falsy(gate:Admit("p2", "Restock", 99, "milk"))
	expect.falsy(gate:Admit("p3", "Restock", 3, "a very long string"))
	expect.falsy(gate:Admit("p4", "Restock", 3))
	expect.falsy(gate:Admit("p5", "Restock", 3, "milk", "extra"))
	expect.falsy(gate:Admit("p6", "Restock", { 3 }, "milk"))
end)

test("enforces the rate limit per sender and per remote", function()
	local clock, advance = fakeClock()
	local gate = Gate.new(definitions(), clock)
	expect.truthy(gate:Admit("a", "Restock", 1, "x"))
	expect.truthy(gate:Admit("a", "Restock", 1, "x"))
	local ok, reason = gate:Admit("a", "Restock", 1, "x")
	expect.falsy(ok)
	expect.equal(reason, "rate limit exceeded")

	-- Another sender and another remote are unaffected.
	expect.truthy(gate:Admit("b", "Restock", 1, "x"))
	expect.truthy(gate:Admit("a", "Query"))

	advance(1)
	expect.truthy(gate:Admit("a", "Restock", 1, "x"))
end)

test("malformed calls also consume rate budget", function()
	local gate = Gate.new(definitions(), fakeClock())
	expect.falsy(gate:Admit("a", "Restock", "bad"))
	expect.falsy(gate:Admit("a", "Restock", "bad"))
	local ok, reason = gate:Admit("a", "Restock", 1, "x")
	expect.falsy(ok)
	expect.equal(reason, "rate limit exceeded")
	expect.equal(gate:Violations("a"), 3)
end)

test("Forget clears a sender's violations and budget", function()
	local gate = Gate.new(definitions(), fakeClock())
	gate:Admit("a", "Query")
	expect.falsy(gate:Admit("a", "Query"))
	expect.equal(gate:Violations("a"), 1)
	gate:Forget("a")
	expect.equal(gate:Violations("a"), 0)
	expect.truthy(gate:Admit("a", "Query"))
end)

test("refuses definitions that would leave a client remote unprotected", function()
	expect.throws(function()
		Gate.new({ Open = { kind = "Event", from = "Client", args = {} } })
	end, "must declare a rate")
	expect.throws(function()
		Gate.new({ Push = { kind = "Function", from = "Server", args = {} } })
	end, "must be sent by clients")
	expect.throws(function()
		Gate.new({ Odd = { kind = "Stream", from = "Client", args = {} } })
	end, "invalid kind")
	expect.throws(function()
		Gate.new({ Odd = { kind = "Event", from = "Nobody", args = {} } })
	end, "invalid sender")
end)
