-- Shared.Util.Trove

local world = Engine.new()
local side = world.side("server")
local Trove = side.load("ReplicatedStorage.Shared.Util.Trove")
local Signal = side.load("ReplicatedStorage.Shared.Util.Signal")

test("cleans items in reverse order of addition", function()
	local trove = Trove.new()
	local order = {}
	trove:Add(function()
		table.insert(order, "a")
	end)
	trove:Add(function()
		table.insert(order, "b")
	end)
	trove:Clean()
	expect.equal(table.concat(order, ","), "b,a")
end)

test("cleans connections, instances, objects and nested troves", function()
	local trove = Trove.new()

	local signal = Signal.new()
	local fired = 0
	trove:Add(signal:Connect(function()
		fired += 1
	end))

	local folder = world.newInstance("Folder", "Parent")
	local part = world.newInstance("Part", "Child")
	part.Parent = folder
	trove:Add(part)

	local destroyed = false
	trove:Add({
		Destroy = function()
			destroyed = true
		end,
	})

	local nestedCleaned = false
	local nested = Trove.new()
	nested:Add(function()
		nestedCleaned = true
	end)
	trove:Add(nested)

	trove:Clean()
	signal:Fire()
	expect.equal(fired, 0)
	expect.equal(part.Parent, nil)
	expect.truthy(destroyed)
	expect.truthy(nestedCleaned)
end)

test("Connect tracks an engine signal connection", function()
	local trove = Trove.new()
	local folder = world.newInstance("Folder", "Watched")
	local added = 0
	trove:Connect(folder.ChildAdded, function()
		added += 1
	end)
	world.newInstance("Part", "One").Parent = folder
	trove:Clean()
	world.newInstance("Part", "Two").Parent = folder
	expect.equal(added, 1)
end)

test("cancels a tracked thread", function()
	local trove = Trove.new()
	local ran = false
	trove:Add(task.delay(0.05, function()
		ran = true
	end))
	trove:Clean()
	task.wait(0.1)
	expect.falsy(ran)
end)

test("one failing cleanup does not block the rest", function()
	local trove = Trove.new()
	local reached = false
	trove:Add(function()
		reached = true
	end)
	trove:Add(function()
		error("boom", 0)
	end)
	trove:Clean()
	expect.truthy(reached)
	expect.anyLine(world.lines("warn"), "cleanup failed: boom")
end)

test("can be reused after Clean and does not clean twice", function()
	local trove = Trove.new()
	local count = 0
	trove:Add(function()
		count += 1
	end)
	trove:Clean()
	trove:Clean()
	expect.equal(count, 1)
	trove:Add(function()
		count += 10
	end)
	trove:Clean()
	expect.equal(count, 11)
end)

test("refuses values it cannot clean", function()
	local trove = Trove.new()
	expect.throws(function()
		trove:Add(42)
	end, "do not know how to clean up")
	expect.throws(function()
		trove:Add({})
	end, "do not know how to clean up")
end)
