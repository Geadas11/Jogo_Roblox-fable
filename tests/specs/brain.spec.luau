-- Server.Monster.Brain driven tick by tick on the real map grid, with scripted players.

local world = Engine.new({ map = true })
local server = world.side("server")
local NavGrid = server.load("ServerScriptService.Server.Monster.NavGrid")
local Brain = server.load("ServerScriptService.Server.Monster.Brain")
local config = server.load("ReplicatedStorage.Shared.Config.MonsterConfig")
local grid = NavGrid.new(Engine.grids())

local patrolPoints = {}
for _, node in world.getService("CollectionService"):GetTagged("PatrolNode") do
	table.insert(patrolPoints, { x = node.Position.X, z = node.Position.Z })
end

local DT = 0.1

-- A scripted world: `targets` is edited by each test; randomness is seeded.
local function setup(options)
	options = options or {}
	-- Spread small test seeds out: the generator's first outputs from tiny seeds are tiny.
	local seed = (options.seed or 7) * 104729 + 1000003
	local state = { targets = {}, caught = {}, states = {}, spots = options.spots or {}, occupants = {} }
	local brainWorld = {
		Targets = function()
			return state.targets
		end,
		PatrolPoints = patrolPoints,
		HidingSpots = state.spots,
		OccupantOf = function(spot)
			return state.occupants[spot]
		end,
		OnCatch = function(id)
			table.insert(state.caught, id)
		end,
		OnStateChanged = function(name)
			table.insert(state.states, name)
		end,
		ChooseSpawn = function()
			return { x = 86, z = 11 }
		end,
		Random = function()
			seed = (seed * 48271) % 2147483647
			return seed / 2147483647
		end,
	}
	local brain = Brain.new(grid, brainWorld, config)
	return brain, state
end

local function run(brain, seconds, each)
	for _ = 1, math.floor(seconds / DT) do
		brain:Step(DT)
		if each and each() then
			return true
		end
	end
	return false
end

local function dist(brain, x, z)
	return math.sqrt((brain.X - x) ^ 2 + (brain.Z - z) ^ 2)
end

local function face(brain, x, z)
	local dx, dz = x - brain.X, z - brain.Z
	local length = math.sqrt(dx * dx + dz * dz)
	brain.FaceX, brain.FaceZ = dx / length, dz / length
end

local function player(id, x, z)
	return { Id = id, X = x, Z = z, Running = false, Hidden = false }
end

test("it patrols: keeps moving, visits different parts of the store, never stands in a wall", function()
	local brain = setup()
	brain:Appear(19, -22)
	local visited, moved, previousX, previousZ = {}, 0, brain.X, brain.Z
	run(brain, 240, function()
		expect.truthy(
			grid:IsWalkable(brain.X, brain.Z),
			string.format("inside an obstacle at %.1f, %.1f", brain.X, brain.Z)
		)
		moved += math.sqrt((brain.X - previousX) ^ 2 + (brain.Z - previousZ) ^ 2)
		previousX, previousZ = brain.X, brain.Z
		visited[string.format("%d,%d", brain.X // 40, brain.Z // 40)] = true
	end)
	local areas = 0
	for _ in visited do
		areas += 1
	end
	expect.equal(brain.State, "Patrol")
	expect.truthy(moved > 600, "moved only " .. moved)
	expect.truthy(areas >= 8, "only roamed " .. areas .. " areas")
end)

test("a player in plain sight down an aisle is noticed and chased", function()
	local brain, state = setup()
	brain:Appear(-23, -20)
	face(brain, -23, 40)
	state.targets = { player(1, -23, 10) }
	run(brain, 3, function()
		return brain.State == "Chase"
	end)
	expect.equal(brain.State, "Chase")
	expect.equal(brain.TargetId, 1)
end)

test("noticing takes a moment at a distance, and is instant up close", function()
	local brain, state = setup()
	brain:Appear(-23, -20)
	face(brain, -23, 40)
	state.targets = { player(1, -23, 35) }
	brain:Step(DT)
	expect.truthy(brain.State ~= "Chase")

	local close = setup()
	close:Appear(-23, -20)
	face(close, 0, 1) -- looking away
	local closeState = select(2, setup())
	close.World.Targets = function()
		return { player(2, -23, -16) }
	end
	close:Step(DT)
	close:Step(DT)
	expect.equal(close.State, "Chase")
	expect.equal(closeState.targets[1], nil)
end)

test("a player behind shelving or behind its back is not seen", function()
	local brain, state = setup()
	brain:Appear(-23, -6)
	face(brain, 1, 0) -- looking east, into the gondola
	state.targets = { player(1, -9, -6) } -- next aisle over
	run(brain, 3)
	expect.truthy(brain.State ~= "Chase", "saw through a gondola")

	local other, otherState = setup()
	other:Appear(-23, 20)
	face(other, -23, 40) -- looking south
	otherState.targets = { player(1, -23, 0) } -- behind it, 20 studs away
	other:Step(DT)
	expect.equal(other:AwarenessOf(1), 0, "noticed someone behind itself")
	expect.truthy(other.State ~= "Chase", "saw behind itself")
end)

test("a hidden player is not seen, even right next to it", function()
	local brain, state = setup()
	brain:Appear(-80, -20)
	local hidden = player(1, -79, -20)
	hidden.Hidden = true
	hidden.Spot = 1
	state.targets = { hidden }
	local everChased = run(brain, 3, function()
		return brain.State == "Chase" or brain:AwarenessOf(1) > 0
	end)
	expect.falsy(everChased, "noticed a hidden player")
	expect.equal(#state.caught, 0)
end)

test("it walks to a noise and searches there", function()
	local brain, state = setup()
	brain:Appear(-51, -22)
	brain:Hear(47, 46)
	brain:Step(DT)
	expect.equal(brain.State, "Investigate")
	local arrived = run(brain, 40, function()
		return brain.State == "Search"
	end)
	expect.truthy(arrived, "never reached the noise")
	expect.truthy(dist(brain, 47, 46) < 4)
	run(brain, 60, function()
		return brain.State == "Patrol"
	end)
	expect.equal(brain.State, "Patrol")
	expect.equal(state.states[1], "Patrol")
end)

test("a standing player is caught once it reaches them", function()
	local brain, state = setup()
	brain:Appear(-23, -20)
	face(brain, -23, 40)
	state.targets = { player(1, -23, 25) }
	run(brain, 20, function()
		return #state.caught > 0
	end)
	expect.equal(state.caught[1], 1)
	expect.equal(brain.State, "Catch")
	expect.truthy(dist(brain, -23, 25) <= config.CatchDistance + 0.01)
end)

test("a player who gets out of sight is lost: it goes to where they were last seen and searches", function()
	local brain, state = setup()
	brain:Appear(-23, -20)
	face(brain, -23, 40)
	local runner = player(1, -23, 8)
	state.targets = { runner }
	run(brain, 2, function()
		return brain.State == "Chase"
	end)
	expect.equal(brain.State, "Chase")
	local lastX, lastZ = runner.X, runner.Z

	-- Gone behind the walls of the storage room, out of sight and out of reach.
	runner.X, runner.Z = -88, -66
	local lost = run(brain, 20, function()
		return brain.State == "Search"
	end)
	expect.truthy(lost, "still " .. brain.State)
	expect.truthy(dist(brain, lastX, lastZ) < 4, "searching away from the last sighting")
	expect.equal(#state.caught, 0)
end)

test("hiding in plain view of it does not help: it opens the spot", function()
	local brain, state = setup({ spots = { { Id = 5, X = -95, Z = 8.5 } } })
	brain:Appear(-84, -20)
	face(brain, 0, 1)
	local target = player(1, -86, -5)
	state.targets = { target }
	run(brain, 2, function()
		return brain.State == "Chase"
	end)
	expect.equal(brain.State, "Chase")

	-- Hides in the locker straight away.
	target.Hidden = true
	target.Spot = 5
	target.X, target.Z = -95, 8.5
	state.occupants[5] = 1
	run(brain, 15, function()
		return #state.caught > 0
	end)
	expect.equal(state.caught[1], 1)
end)

test("a player who hid unseen is safe unless it happens to check that spot", function()
	local spots = { { Id = 5, X = -95, Z = 8.5 } }
	local found, safe = 0, 0
	for seed = 1, 30 do
		local brain, state = setup({ seed = seed, spots = spots })
		brain:Appear(-84, -20)
		state.occupants[5] = 1
		local hidden = player(1, -95, 8.5)
		hidden.Hidden = true
		hidden.Spot = 5
		state.targets = { hidden }
		brain:Hear(-88, 0)
		run(brain, 40, function()
			return #state.caught > 0 or brain.State == "Patrol"
		end)
		if #state.caught > 0 then
			found += 1
		else
			safe += 1
		end
	end
	-- Sometimes, not always.
	expect.truthy(found >= 2, "never checked the spot in 30 searches")
	expect.truthy(safe >= 15, "found the player " .. found .. " times out of 30")
end)

test("after a catch it vanishes, then reappears somewhere else", function()
	local brain, state = setup()
	brain:Appear(-23, -20)
	face(brain, -23, 40)
	state.targets = { player(1, -23, -10) }
	run(brain, 10, function()
		return #state.caught > 0
	end)
	state.targets = {}
	run(brain, config.CatchSequenceSeconds + 0.2)
	expect.equal(brain.State, "Vanished")
	expect.falsy(brain.Present)
	run(brain, config.Behaviour.VanishSeconds + 0.5)
	expect.truthy(brain.Present)
	expect.equal(brain.State, "Patrol")
	-- Somewhere else entirely, not where it caught them.
	expect.truthy(dist(brain, -23, -10) > 50)
end)

test("sometimes it stops and stares at someone far away before deciding", function()
	local stared = 0
	for seed = 1, 20 do
		local brain, state = setup({ seed = seed })
		brain:Appear(-23, -22)
		face(brain, -23, 40)
		state.targets = { player(1, -23, 45) }
		run(brain, 1, function()
			if brain.State == "Observe" then
				stared += 1
				return true
			end
		end)
	end
	expect.truthy(stared >= 4 and stared <= 18, "stared " .. stared .. " times out of 20")
end)
