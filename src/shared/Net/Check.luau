--!strict
-- Runtime validators for values that cross the network.
--
-- A client can send ANYTHING through a remote: wrong types, NaN, infinity, megabyte
-- strings, extra arguments. Every remote declares one validator per argument (see
-- Definitions) and the server drops any call that does not match, before gameplay
-- code ever sees it.
--
-- A validator returns `true`, or `false` plus a short reason.
-- These only check SHAPE. Whether the request makes sense (is the player close enough,
-- alive, allowed to do this now) is the job of the gameplay code that handles it.

export type Validator = (value: any) -> (boolean, string?)

local Check = {}

local function isFinite(value: number): boolean
	return value == value and value ~= math.huge and value ~= -math.huge
end

function Check.boolean(value: any): (boolean, string?)
	if type(value) == "boolean" then
		return true
	end
	return false, "expected boolean"
end

-- A finite number. NaN and infinity are rejected: they poison any math they touch.
function Check.number(value: any): (boolean, string?)
	if type(value) == "number" and isFinite(value) then
		return true
	end
	return false, "expected finite number"
end

function Check.integer(value: any): (boolean, string?)
	if type(value) == "number" and isFinite(value) and math.floor(value) == value then
		return true
	end
	return false, "expected integer"
end

function Check.numberRange(min: number, max: number): Validator
	assert(min <= max, "Check.numberRange: min must be <= max")
	return function(value: any): (boolean, string?)
		if type(value) == "number" and isFinite(value) and value >= min and value <= max then
			return true
		end
		return false, string.format("expected number in [%s, %s]", tostring(min), tostring(max))
	end
end

function Check.integerRange(min: number, max: number): Validator
	assert(min <= max, "Check.integerRange: min must be <= max")
	return function(value: any): (boolean, string?)
		if
			type(value) == "number"
			and isFinite(value)
			and math.floor(value) == value
			and value >= min
			and value <= max
		then
			return true
		end
		return false, string.format("expected integer in [%s, %s]", tostring(min), tostring(max))
	end
end

-- A valid UTF-8 string of at most `maxBytes` bytes. The limit is mandatory on purpose:
-- an unbounded string is a free way to waste server memory.
function Check.string(maxBytes: number): Validator
	assert(maxBytes >= 0, "Check.string: maxBytes must be >= 0")
	return function(value: any): (boolean, string?)
		if type(value) ~= "string" then
			return false, "expected string"
		end
		if #value > maxBytes then
			return false, string.format("string longer than %d bytes", maxBytes)
		end
		if utf8.len(value) == nil then
			return false, "string is not valid UTF-8"
		end
		return true
	end
end

-- One of a fixed list of strings, numbers or booleans (e.g. a difficulty name).
function Check.oneOf(options: { any }): Validator
	local allowed: { [any]: boolean } = {}
	for _, option in options do
		allowed[option] = true
	end
	return function(value: any): (boolean, string?)
		if value ~= nil and value == value and allowed[value] then
			return true
		end
		return false, "value is not one of the allowed options"
	end
end

-- An Instance of the given class (or a subclass). An instance the server cannot see
-- arrives as nil and is therefore rejected.
function Check.instance(className: string): Validator
	return function(value: any): (boolean, string?)
		if typeof(value) == "Instance" and value:IsA(className) then
			return true
		end
		return false, "expected " .. className
	end
end

-- Accepts nil, otherwise defers to `inner`.
function Check.optional(inner: Validator): Validator
	return function(value: any): (boolean, string?)
		if value == nil then
			return true
		end
		return inner(value)
	end
end

-- Validates a whole argument list against one validator per position.
-- Extra arguments are rejected; missing ones are passed to their validator as nil.
function Check.args(validators: { Validator }, ...: any): (boolean, string?)
	local count = select("#", ...)
	if count > #validators then
		return false, string.format("expected at most %d arguments, got %d", #validators, count)
	end

	local values = table.pack(...)
	for index, validator in validators do
		local ok, reason = validator(values[index])
		if not ok then
			return false, string.format("argument %d: %s", index, reason or "invalid")
		end
	end
	return true
end

return Check
