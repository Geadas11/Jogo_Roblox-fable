-- Shared.ShiftClock: the time maths behind the night clock.

local ShiftClock = Engine.new().side("server").load("ReplicatedStorage.Shared.ShiftClock")

test("the shift starts at 12:00 AM", function()
	expect.equal(ShiftClock.format(0, 240, 6), "12:00 AM")
	expect.equal(ShiftClock.format(-5, 240, 6), "12:00 AM")
	expect.equal(ShiftClock.hourAt(0, 240, 6), 0)
	expect.equal(ShiftClock.hourAt(-5, 240, 6), 0)
end)

test("minutes advance in proportion to the hour length", function()
	expect.equal(ShiftClock.format(4, 240, 6), "12:01 AM")
	expect.equal(ShiftClock.format(120, 240, 6), "12:30 AM")
	expect.equal(ShiftClock.format(239.9, 240, 6), "12:59 AM")
	expect.equal(ShiftClock.format(240, 240, 6), "1:00 AM")
	expect.equal(ShiftClock.format(840, 240, 6), "3:30 AM")
end)

test("hours change exactly on the boundary", function()
	expect.equal(ShiftClock.hourAt(239.9, 240, 6), 0)
	expect.equal(ShiftClock.hourAt(240, 240, 6), 1)
	expect.equal(ShiftClock.hourAt(1199.9, 240, 6), 4)
	expect.equal(ShiftClock.hourAt(1440, 240, 6), 6)
end)

test("the clock stops at the end of the shift", function()
	expect.equal(ShiftClock.format(1440, 240, 6), "6:00 AM")
	expect.equal(ShiftClock.format(99999, 240, 6), "6:00 AM")
	expect.equal(ShiftClock.format(math.huge, 1, 6), "6:00 AM")
	expect.equal(ShiftClock.hourAt(99999, 240, 6), 6)
end)

test("a different hour length gives the same clock", function()
	expect.equal(ShiftClock.format(30, 60, 6), "12:30 AM")
	expect.equal(ShiftClock.format(150, 60, 6), "2:30 AM")
	expect.equal(ShiftClock.hourAt(150, 60, 6), 2)
end)
