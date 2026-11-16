--!strict
-- Groups things that must be cleaned up together (connections, instances, callbacks,
-- threads) so a system can release everything it owns with one call.
-- Used, for example, for everything tied to one player or one character.

export type Trove = {
	Add: <T>(self: Trove, item: T) -> T,
	Connect: (self: Trove, signal: RBXScriptSignal, handler: (...any) -> ()) -> RBXScriptConnection,
	Clean: (self: Trove) -> (),
}

-- Returns the function that cleans `item`, or nil when we do not know how.
local function cleanerFor(item: any): ((any) -> ())?
	local kind = typeof(item)
	if kind == "function" then
		return function(callback)
			callback()
		end
	elseif kind == "thread" then
		return function(thread)
			-- Cancelling a finished thread throws; that is fine to ignore.
			pcall(task.cancel, thread)
		end
	elseif kind == "RBXScriptConnection" then
		return function(connection)
			connection:Disconnect()
		end
	elseif kind == "Instance" then
		return function(instance)
			instance:Destroy()
		end
	elseif kind == "table" then
		if type(item.Destroy) == "function" then
			return function(object)
				object:Destroy()
			end
		elseif type(item.Disconnect) == "function" then
			return function(object)
				object:Disconnect()
			end
		elseif type(item.Clean) == "function" then
			return function(object)
				object:Clean()
			end
		end
	end
	return nil
end

local Trove = {}

function Trove.new(): Trove
	local items: { { item: any, clean: (any) -> () } } = {}
	local trove = {}

	function trove.Add(_self: any, item: any): any
		local clean = cleanerFor(item)
		if not clean then
			error(string.format("Trove: do not know how to clean up a %s", typeof(item)), 2)
		end
		table.insert(items, { item = item, clean = clean })
		return item
	end

	function trove.Connect(self: any, signal: RBXScriptSignal, handler: (...any) -> ()): RBXScriptConnection
		return self:Add(signal:Connect(handler))
	end

	-- Cleans everything in reverse order of addition. The trove can be reused afterwards.
	function trove.Clean(_self: any)
		local pending = items
		items = {}
		for index = #pending, 1, -1 do
			local entry = pending[index]
			local ok, message = pcall(entry.clean, entry.item)
			if not ok then
				warn(string.format("Trove: cleanup failed: %s", tostring(message)))
			end
		end
	end

	return (trove :: any) :: Trove
end

return Trove
