--!strict
-- Small seedable random number generator (Park-Miller). Used wherever the game makes
-- a random choice, so a given seed always produces the same choices - which makes
-- behaviour reproducible when chasing a bug.

export type Rng = {
	Next: (self: Rng) -> number,
	Int: (self: Rng, min: number, max: number) -> number,
	Pick: <T>(self: Rng, list: { T }) -> T,
	Sample: <T>(self: Rng, list: { T }, count: number) -> { T },
	PickWeighted: <T>(self: Rng, list: { T }, weightOf: (T) -> number) -> T?,
}

local Rng = {}

function Rng.new(seed: number): Rng
	local state = math.floor(math.abs(seed)) % 2147483646 + 1
	local rng = {}

	-- A number in [0, 1).
	function rng.Next(_self: any): number
		state = (state * 48271) % 2147483647
		return (state - 1) / 2147483646
	end

	-- A whole number in [min, max].
	function rng.Int(self: any, min: number, max: number): number
		return min + math.floor(self:Next() * (max - min + 1))
	end

	function rng.Pick(self: any, list: { any }): any
		return list[self:Int(1, #list)]
	end

	-- Up to `count` distinct items, in random order. Does not modify `list`.
	function rng.Sample(self: any, list: { any }, count: number): { any }
		local pool = table.clone(list)
		local chosen = {}
		while #chosen < count and #pool > 0 do
			table.insert(chosen, table.remove(pool, self:Int(1, #pool)))
		end
		return chosen
	end

	-- One item, with probability proportional to its weight. nil for an empty list.
	function rng.PickWeighted(self: any, list: { any }, weightOf: (any) -> number): any
		local total = 0
		for _, item in list do
			total += math.max(0, weightOf(item))
		end
		if total <= 0 then
			return list[1]
		end
		local roll = self:Next() * total
		for _, item in list do
			roll -= math.max(0, weightOf(item))
			if roll < 0 then
				return item
			end
		end
		return list[#list]
	end

	return (rng :: any) :: Rng
end

return Rng
