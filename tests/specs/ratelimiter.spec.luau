-- Server.Net.RateLimiter: token bucket per sender.

local RateLimiter = Engine.new().side("server").load("ServerScriptService.Server.Net.RateLimiter")

local function fakeClock()
	local now = 0
	return function()
		return now
	end, function(seconds)
		now += seconds
	end
end

test("allows a burst, then refuses", function()
	local clock = fakeClock()
	local limiter = RateLimiter.new(3, 1, clock)
	expect.truthy(limiter:Try("a"))
	expect.truthy(limiter:Try("a"))
	expect.truthy(limiter:Try("a"))
	expect.falsy(limiter:Try("a"))
	expect.falsy(limiter:Try("a"))
end)

test("refills over time, never above the burst size", function()
	local clock, advance = fakeClock()
	local limiter = RateLimiter.new(2, 0.5, clock)
	expect.truthy(limiter:Try("a"))
	expect.truthy(limiter:Try("a"))
	expect.falsy(limiter:Try("a"))

	advance(1) -- half a token
	expect.falsy(limiter:Try("a"))
	advance(1) -- one full token
	expect.truthy(limiter:Try("a"))
	expect.falsy(limiter:Try("a"))

	advance(1000) -- a long silence only earns `burst` tokens
	expect.truthy(limiter:Try("a"))
	expect.truthy(limiter:Try("a"))
	expect.falsy(limiter:Try("a"))
end)

test("keys do not share a budget", function()
	local clock = fakeClock()
	local limiter = RateLimiter.new(1, 1, clock)
	expect.truthy(limiter:Try("a"))
	expect.falsy(limiter:Try("a"))
	expect.truthy(limiter:Try("b"))
end)

test("Forget resets a key", function()
	local clock = fakeClock()
	local limiter = RateLimiter.new(1, 1, clock)
	expect.truthy(limiter:Try("a"))
	expect.falsy(limiter:Try("a"))
	limiter:Forget("a")
	expect.truthy(limiter:Try("a"))
end)

test("a clock that goes backwards never grants tokens", function()
	local clock, advance = fakeClock()
	local limiter = RateLimiter.new(1, 1, clock)
	expect.truthy(limiter:Try("a"))
	advance(-50)
	expect.falsy(limiter:Try("a"))
end)

test("rejects nonsensical settings", function()
	expect.throws(function()
		RateLimiter.new(0, 1)
	end, "burst")
	expect.throws(function()
		RateLimiter.new(1, 0)
	end, "perSecond")
end)
