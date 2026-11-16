--!strict
-- A small script-side event, for communication between our own modules
-- (e.g. PlayerManager.PlayerReady). Handlers run immediately, in connection order,
-- each in its own thread so one failing or yielding handler cannot block the others.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal<T...> = {
	Connect: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Once: (self: Signal<T...>, handler: (T...) -> ()) -> Connection,
	Wait: (self: Signal<T...>) -> T...,
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
}

local Signal = {}

function Signal.new<T...>(): Signal<T...>
	-- Connections in the order they were made.
	local connections: { any } = {}
	local signal = {}

	function signal.Connect(_self: any, handler: (...any) -> ()): Connection
		local connection = { Connected = true, _handler = handler }

		function connection.Disconnect(_connection: any)
			if not connection.Connected then
				return
			end
			connection.Connected = false
			local index = table.find(connections, connection)
			if index then
				table.remove(connections, index)
			end
		end

		table.insert(connections, connection)
		return connection :: any
	end

	function signal.Once(self: any, handler: (...any) -> ()): Connection
		local connection: Connection
		connection = self:Connect(function(...)
			connection:Disconnect()
			handler(...)
		end)
		return connection
	end

	function signal.Fire(_self: any, ...: any)
		-- Iterate a snapshot: handlers may connect or disconnect while we fire.
		for _, connection in table.clone(connections) do
			if connection.Connected then
				task.spawn(connection._handler, ...)
			end
		end
	end

	function signal.Wait(self: any): ...any
		local thread = coroutine.running()
		self:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function signal.DisconnectAll(_self: any)
		for _, connection in connections do
			connection.Connected = false
		end
		table.clear(connections)
	end

	return (signal :: any) :: Signal<T...>
end

return Signal
