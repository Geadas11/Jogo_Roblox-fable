--!strict
-- Recursively freezes a table so configuration cannot be mutated at runtime.
-- Returns the same table for convenience: `return deepFreeze({ ... })`.

local function deepFreeze<T>(value: T): T
	if type(value) == "table" and not table.isfrozen(value :: any) then
		table.freeze(value :: any)
		for _, child in value :: any do
			deepFreeze(child)
		end
	end
	return value
end

return deepFreeze
