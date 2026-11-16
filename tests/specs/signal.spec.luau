-- Shared.Util.Signal

local Signal = Engine.new().side("server").load("ReplicatedStorage.Shared.Util.Signal")

test("fires connected handlers in order with the arguments", function()
	local signal = Signal.new()
	local calls = {}
	signal:Connect(function(a, b)
		table.insert(calls, "first:" .. a .. b)
	end)
	signal:Connect(function(a, b)
		table.insert(calls, "second:" .. a .. b)
	end)
	signal:Fire("x", "y")
	expect.equal(table.concat(calls, ","), "first:xy,second:xy")
end)

test("a disconnected handler is not called again", function()
	local signal = Signal.new()
	local count = 0
	local connection = signal:Connect(function()
		count += 1
	end)
	signal:Fire()
	expect.truthy(connection.Connected)
	connection:Disconnect()
	expect.falsy(connection.Connected)
	connection:Disconnect() -- twice is harmless
	signal:Fire()
	expect.equal(count, 1)
end)

test("Once runs a single time", function()
	local signal = Signal.new()
	local count = 0
	signal:Once(function()
		count += 1
	end)
	signal:Fire()
	signal:Fire()
	expect.equal(count, 1)
end)

test("a handler may disconnect itself or others while firing", function()
	local signal = Signal.new()
	local calls = {}
	local second
	signal:Connect(function()
		table.insert(calls, "first")
		second:Disconnect()
	end)
	second = signal:Connect(function()
		table.insert(calls, "second")
	end)
	signal:Connect(function()
		table.insert(calls, "third")
	end)
	signal:Fire()
	signal:Fire()
	expect.equal(table.concat(calls, ","), "first,third,first,third")
end)

test("a handler connected while firing only runs on the next fire", function()
	local signal = Signal.new()
	local late = 0
	signal:Connect(function()
		signal:Connect(function()
			late += 1
		end)
	end)
	signal:Fire()
	expect.equal(late, 0)
end)

test("a failing handler does not stop the others", function()
	local signal = Signal.new()
	local reached = false
	signal:Connect(function()
		error("expected test failure: ignore this message", 0)
	end)
	signal:Connect(function()
		reached = true
	end)
	signal:Fire()
	expect.truthy(reached)
end)

test("Wait yields until the next fire and returns its arguments", function()
	local signal = Signal.new()
	task.defer(function()
		signal:Fire("ready", 6)
	end)
	local a, b = signal:Wait()
	expect.equal(a, "ready")
	expect.equal(b, 6)
end)

test("DisconnectAll removes every handler", function()
	local signal = Signal.new()
	local count = 0
	local connection = signal:Connect(function()
		count += 1
	end)
	signal:DisconnectAll()
	signal:Fire()
	expect.equal(count, 0)
	expect.falsy(connection.Connected)
end)
