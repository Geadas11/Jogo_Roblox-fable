-- Server.Monster.NavGrid on the real baked grids: can the monster get everywhere, and
-- does line of sight behave like the building does?

local world = Engine.new({ map = true })
local NavGrid = world.side("server").load("ServerScriptService.Server.Monster.NavGrid")
local grid = NavGrid.new(Engine.grids())

local patrol = {}
for _, node in world.getService("CollectionService"):GetTagged("PatrolNode") do
	table.insert(patrol, { x = node.Position.X, z = node.Position.Z, zone = node:GetAttribute("Zone") })
end

local function distance(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
end

test("every patrol point is somewhere the monster can stand", function()
	expect.truthy(#patrol >= 70)
	for _, node in patrol do
		expect.truthy(
			grid:IsWalkable(node.x, node.z),
			string.format("%s (%.0f, %.0f)", node.zone, node.x, node.z)
		)
	end
end)

test("there is a walkable route between patrol points all over the map", function()
	local checked, longest = 0, 0
	local started = os.clock()
	-- From every node to nodes spread across the list (about 600 routes).
	for index, from in patrol do
		for step = 1, 8 do
			local to = patrol[(index + step * 9 - 1) % #patrol + 1]
			local path = grid:FindPath(from.x, from.z, to.x, to.z)
			expect.truthy(path, string.format("no route %s -> %s", from.zone, to.zone))

			local previous, length = from, 0
			for _, point in path do
				expect.truthy(grid:IsWalkable(point.x, point.z), "waypoint inside an obstacle")
				expect.truthy(
					grid:CanWalkLine(previous.x, previous.z, point.x, point.z),
					"leg crosses an obstacle"
				)
				length += distance(previous, point)
				previous = point
			end
			expect.truthy(distance(previous, to) < 2, "route ends away from its goal")
			longest = math.max(longest, length)
			checked += 1
		end
	end
	local average = (os.clock() - started) / checked * 1000
	print(
		string.format(
			"     navgrid: %d routes, average %.1f ms, longest %.0f studs",
			checked,
			average,
			longest
		)
	)
	expect.truthy(checked >= 500)
	-- The whole outdoor loop around the building is under 900 studs.
	expect.truthy(longest < 900, "longest route " .. longest)
	-- Budget for the interpreter the tests run in. Roblox runs this module natively and
	-- measured about 40% faster here; the monster also searches at most twice a second.
	-- (Measured 29 ms on an idle machine and up to 50 ms with Studio running alongside:
	-- the budget leaves room for that, and still catches a search that got much slower.)
	expect.truthy(average < 70, string.format("average search took %.1f ms", average))
end)

test("a straight clear run is a single waypoint", function()
	-- Down aisle 3, from the back wall to the checkout side.
	local path = grid:FindPath(-23, -22, -23, 46)
	expect.equal(#path, 1)
end)

test("going round shelving takes a detour, never a shortcut through it", function()
	-- Aisle 3 to aisle 4, on either side of a gondola.
	local path = grid:FindPath(-23, -6, -9, -6)
	expect.truthy(#path >= 2)
	local length, previous = 0, { x = -23, z = -6 }
	for _, point in path do
		length += distance(previous, point)
		previous = point
	end
	expect.truthy(length > 20, "a 14 stud gap cannot be crossed in " .. length)
end)

test("a goal inside an obstacle is replaced by the nearest free spot", function()
	-- The middle of a gondola.
	local path = grid:FindPath(-23, 0, -16, 0)
	expect.truthy(path)
	local last = path[#path]
	expect.truthy(grid:IsWalkable(last.x, last.z))
	expect.truthy(distance(last, { x = -16, z = 0 }) < 5)
end)

test("somewhere sealed off is reported as unreachable", function()
	-- The locked glass vestibule at the entrance.
	expect.equal(grid:FindPath(-23, 46, 20, 86), nil)
end)

test("line of sight: shelving and walls block it, an open aisle and glass do not", function()
	-- Along an aisle.
	expect.truthy(grid:CanSee(-23, -22, -23, 46))
	-- Across a gondola.
	expect.falsy(grid:CanSee(-23, -6, -9, -6))
	-- Shop floor into the storage room, through the back wall.
	expect.falsy(grid:CanSee(40, -24, 40, -40))
	-- From the parking lot into the shop, through the window.
	expect.truthy(grid:CanSee(60, 100, 60, 72))
	-- Over a checkout counter (low).
	expect.truthy(grid:CanSee(-50, 58, -38, 58))
	-- Across the building, through its west wall.
	expect.falsy(grid:CanSee(-113, 0, -85, 0))
end)

test("a line squeezing diagonally between two blocked cells is blocked", function()
	-- 3 x 3 grid with cells (1, 0) and (0, 1) blocked: a gap only at their shared corner.
	--   . # .
	--   # . .
	--   . . .
	-- Bits 1 and 3 of the first six cells are set: 2 + 8 = 10 -> character 48 + 10.
	local tiny = NavGrid.new({
		OriginX = 0,
		OriginZ = 0,
		Width = 3,
		Depth = 3,
		Walk = string.char(48 + 10) .. "0",
		Sight = string.char(48 + 10) .. "0",
	})
	expect.falsy(tiny:IsWalkable(1.5, 0.5))
	expect.falsy(tiny:IsWalkable(0.5, 1.5))
	expect.truthy(tiny:IsWalkable(0.5, 0.5))
	expect.truthy(tiny:IsWalkable(1.5, 1.5))
	expect.falsy(tiny:CanWalkLine(0.5, 0.5, 1.5, 1.5), "slipped through the corner")
	expect.falsy(tiny:CanSee(0.5, 0.5, 2.5, 2.5), "saw through the corner")
	expect.truthy(tiny:CanWalkLine(1.5, 1.5, 2.5, 2.5))
	-- And no route: the corner is the only way out of the top-left cell.
	expect.equal(tiny:FindPath(0.5, 0.5, 2.5, 2.5), nil)
end)
