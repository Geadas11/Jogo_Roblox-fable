--!strict
-- Token bucket rate limiter, one bucket per key (in practice: per player).
-- A bucket holds up to `burst` tokens and refills at `perSecond`. Each accepted call
-- costs one token; with no token left the call is refused.

export type RateLimiter = {
	Try: (self: RateLimiter, key: any) -> boolean,
	Forget: (self: RateLimiter, key: any) -> (),
}

type Bucket = {
	tokens: number,
	updatedAt: number,
}

local RateLimiter = {}

-- `clock` exists so tests can control time; the game uses the default.
function RateLimiter.new(burst: number, perSecond: number, clock: (() -> number)?): RateLimiter
	assert(burst >= 1, "RateLimiter: burst must be >= 1")
	assert(perSecond > 0, "RateLimiter: perSecond must be > 0")

	local now: () -> number = clock or os.clock
	local buckets: { [any]: Bucket } = {}
	local limiter = {}

	function limiter.Try(_self: any, key: any): boolean
		local time = now()
		local bucket = buckets[key]
		if bucket then
			local elapsed = math.max(0, time - bucket.updatedAt)
			bucket.tokens = math.min(burst, bucket.tokens + elapsed * perSecond)
			bucket.updatedAt = time
		else
			bucket = { tokens = burst, updatedAt = time }
			buckets[key] = bucket
		end

		if bucket.tokens < 1 then
			return false
		end
		bucket.tokens -= 1
		return true
	end

	-- Drops the bucket for a key. Call when a player leaves.
	function limiter.Forget(_self: any, key: any)
		buckets[key] = nil
	end

	return (limiter :: any) :: RateLimiter
end

return RateLimiter
