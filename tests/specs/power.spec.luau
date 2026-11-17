-- Electricity on the real map: random trips, the 4 AM failure, restoring it, the lights
-- each client draws, the flashlight, and darkness in the monster's sight.

local SERVER_MAIN = "ServerScriptService.Server.Main"
local CLIENT_MAIN = "StarterPlayer.StarterPlayerScripts.Client.Main"
local SERVICES = "ServerScriptService.Server.Services."

local function boot()
	local world = Engine.new({ map = true })
	local server = world.side("server")
	server.load(SERVER_MAIN)
	return {
		world = world,
		server = server,
		config = server.load("ReplicatedStorage.Shared.Config.GameConfig"),
		powerConfig = server.load("ReplicatedStorage.Shared.Config.PowerConfig"),
		state = server.load("ReplicatedStorage.Shared.SessionState"),
		shift = server.load(SERVICES .. "ShiftManager"),
		power = server.load(SERVICES .. "PowerManager"),
		tasks = server.load(SERVICES .. "TaskManager"),
		monster = server.load(SERVICES .. "MonsterManager"),
		noise = server.load(SERVICES .. "NoiseService"),
	}
end

local function join(s, name, userId)
	local player = s.world.addPlayer(name, userId)
	s.world.spawnCharacter(player, 2)
	local client = s.world.side("client", player)
	client.load(CLIENT_MAIN)
	return player, client
end

local function tagged(s, tag)
	return s.world.getService("CollectionService"):GetTagged(tag)
end

local function promptOf(instance)
	return instance:FindFirstChildOfClass("ProximityPrompt")
end

local function use(s, player, instance)
	task.wait(0.3)
	s.world.moveTo(player, instance)
	s.world.trigger(promptOf(instance), player)
end

local function startShift(s, player)
	use(s, player, tagged(s, "TimeClock")[1])
end

local function advanceHours(s, hours)
	s.world.now += s.config.Shift.HourDurationSeconds * hours
	s.shift.Update()
end

local function breaker(s, circuit)
	for _, part in tagged(s, "Breaker") do
		if part:GetAttribute("Circuit") == circuit then
			return part
		end
	end
	error("no breaker " .. circuit)
end

local function generator(s)
	for _, part in tagged(s, "RepairPoint") do
		if part:GetAttribute("Kind") == "Generator" then
			return part
		end
	end
	error("no generator")
end

local function restoreTask(s)
	for _, task in s.tasks.GetSnapshot() do
		if task.Title == "Restore the power" then
			return task
		end
	end
	return nil
end

local function fixturesOf(client, circuit)
	local list = {}
	local controller = client.load("StarterPlayer.StarterPlayerScripts.Client.Controllers.LightingController")
	for _, fixture in controller.GetFixtures() do
		if fixture.Circuit == circuit then
			table.insert(list, fixture)
		end
	end
	return list
end

test("everything is on at the start, and the breakers have nothing to do", function()
	local s = boot()
	expect.truthy(s.power.AllOn())
	for _, circuit in s.powerConfig.Circuits do
		expect.equal(promptOf(breaker(s, circuit)).Enabled, false, circuit)
	end
	expect.equal(promptOf(generator(s)).Enabled, false)
end)

test("at 4 AM the store goes dark; the generator, then each breaker, bring it back", function()
	local s = boot()
	local player, client = join(s, "Tester", 1)
	startShift(s, player)
	advanceHours(s, 4)

	expect.falsy(s.power.IsGeneratorOn())
	expect.equal(#s.power.GetOff(), #s.powerConfig.Circuits)
	local task = restoreTask(s)
	expect.truthy(task, "no task to restore the power")
	expect.truthy(string.find(task.Detail, "generator", 1, true))

	-- Every client turns the shop lights off; the electrical room stays lit.
	for _, fixture in fixturesOf(client, "Shop") do
		expect.equal(fixture.Light.Enabled, false)
	end
	for _, fixture in fixturesOf(client, "Emergency") do
		expect.equal(fixture.Light.Enabled, true)
	end
	expect.truthy(#fixturesOf(client, "Emergency") >= 1)

	-- Breakers do nothing until the generator runs.
	use(s, player, breaker(s, "Shop"))
	expect.falsy(s.power.IsOn("Shop"))

	use(s, player, generator(s))
	expect.truthy(s.power.IsGeneratorOn())
	expect.equal(promptOf(generator(s)).Enabled, false)
	for _, circuit in s.powerConfig.Circuits do
		use(s, player, breaker(s, circuit))
		expect.truthy(s.power.IsOn(circuit), circuit)
	end
	expect.truthy(s.power.AllOn())
	expect.truthy(restoreTask(s).Completed)
	for _, fixture in fixturesOf(client, "Shop") do
		expect.equal(fixture.Light.Enabled, true)
	end
end)

test("a random trip takes one circuit down and makes a task; never more than the limit", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	local tripped = s.power.TripRandom()
	expect.truthy(tripped)
	expect.falsy(s.power.IsOn(tripped))
	expect.equal(promptOf(breaker(s, tripped)).Enabled, true)
	expect.truthy(restoreTask(s))
	expect.truthy(string.find(restoreTask(s).Detail, tripped, 1, true))

	for _ = 1, 10 do
		s.power.TripRandom()
	end
	expect.equal(#s.power.GetOff(), s.powerConfig.MaxTripped)
	-- Still one task, not one per trip.
	local count = 0
	for _, task in s.tasks.GetSnapshot() do
		if task.Title == "Restore the power" then
			count += 1
		end
	end
	expect.equal(count, 1)

	for _, circuit in s.power.GetOff() do
		use(s, player, breaker(s, circuit))
	end
	expect.truthy(restoreTask(s).Completed)
end)

test("random trips follow the chance for the hour: none at midnight or 1 AM, some later", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	for _ = 1, 200 do
		s.power.MaybeTrip(0)
		s.power.MaybeTrip(1)
	end
	expect.truthy(s.power.AllOn())
	for _ = 1, 200 do
		s.power.MaybeTrip(5)
	end
	expect.falsy(s.power.AllOn())
end)

test("the power task is never handed out at random, even when nothing else is left", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	local definitions = s.server.load("ReplicatedStorage.Shared.Config.TaskDefinitions")
	for typeName, definition in definitions.Types do
		if definition.Weight > 0 then
			s.tasks.Issue(typeName, definition.Min)
		end
	end
	-- Power off without a failure being announced: only the random draw could add the task.
	s.power.SetCircuit("Cold", false)
	advanceHours(s, 1)
	expect.equal(restoreTask(s), nil)
end)

test("the generator is loud: the monster comes to listen", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	advanceHours(s, 4)
	-- In the storage room, about 35 studs from the generator.
	s.monster.Spawn(-10, -50)
	local brain = s.monster.GetBrain()
	brain.FaceX, brain.FaceZ = -1, 0
	use(s, player, generator(s))
	s.monster.Step(0.1)
	expect.equal(brain.State, "Investigate")
end)

test("the shift ending puts the power back", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	advanceHours(s, 4)
	expect.falsy(s.power.AllOn())
	advanceHours(s, 2)
	expect.truthy(s.power.AllOn())
end)

test("dark areas: lit by circuit, and the monster sees less far there", function()
	local s = boot()
	expect.truthy(s.power.IsLit(19, 20))
	expect.equal(s.power.CircuitAt(19, 20), "Shop")
	expect.equal(s.power.CircuitAt(86, -66), "Cold", "the freezer, inside cold storage")
	expect.equal(s.power.CircuitAt(25, -69), "Emergency")

	-- Down an aisle, 40 studs away: seen with the lights on, not in the dark.
	local player = join(s, "Tester", 1)
	startShift(s, player)
	s.power.SetCircuit("Shop", false)
	expect.falsy(s.power.IsLit(19, 20))
	s.world.moveTo(player, -23, 3, 25)
	s.monster.Spawn(-23, -15)
	local brain = s.monster.GetBrain()
	local function aimAndWait()
		brain.FaceX, brain.FaceZ = 0, 1
		local seen = false
		for _ = 1, 5 do
			s.monster.Step(0.1)
			brain.FaceX, brain.FaceZ = 0, 1
			if brain:AwarenessOf(1) > 0 then
				seen = true
			end
		end
		return seen
	end
	expect.falsy(aimAndWait(), "saw a player standing in the dark at 40 studs")

	-- With the flashlight on, the player is visible again.
	s.world.fireServerAs(player, "Flashlight", true)
	expect.equal(player:GetAttribute("FlashlightOn"), true)
	expect.truthy(aimAndWait(), "did not see a lit flashlight")
end)

test("the flashlight lights up for everyone, and goes off when hiding", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	s.world.fireServerAs(player, "Flashlight", true)
	local light = player.Character.HumanoidRootPart:FindFirstChild("Flashlight")
	expect.truthy(light, "no light on the character")
	expect.equal(light.Enabled, true)
	s.world.fireServerAs(player, "Flashlight", false)
	expect.equal(light.Enabled, false)

	s.world.fireServerAs(player, "Flashlight", true)
	use(s, player, tagged(s, "HidingSpot")[1])
	expect.equal(player:GetAttribute("Status"), "Hiding")
	expect.equal(player:GetAttribute("FlashlightOn"), false)
	expect.equal(light.Enabled, false)

	-- Cannot be switched on from inside a hiding spot.
	s.world.fireServerAs(player, "Flashlight", true)
	expect.equal(player:GetAttribute("FlashlightOn"), false)
	expect.equal(light.Enabled, false)

	-- Malformed requests are refused.
	s.world.fireServerAs(player, "Flashlight", "on")
	expect.equal(player:GetAttribute("FlashlightOn"), false)
end)

test("the store dims as the night goes on, and flickers start after midnight", function()
	local s = boot()
	local player, client = join(s, "Tester", 1)
	local lighting = s.world.getService("Lighting")
	local controller = client.load("StarterPlayer.StarterPlayerScripts.Client.Controllers.LightingController")
	startShift(s, player)
	controller.Apply()
	local midnight = lighting.Ambient.R
	advanceHours(s, 5)
	controller.Apply()
	expect.truthy(lighting.Ambient.R < midnight * 0.7, "not darker at 5 AM")

	-- (The 4 AM failure has the shop dark: put it back to see a light flicker.)
	s.power.RestoreAll()
	local fixture = fixturesOf(client, "Shop")[1]
	controller.Flicker(fixture)
	expect.equal(fixture.Flickering, true)
end)

test("a whole night with the power failing runs without warnings", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	for hour = 1, 6 do
		advanceHours(s, 1)
		s.power.MaybeTrip(hour)
	end
	expect.equal(#s.world.lines("warn"), 0, "warnings: " .. table.concat(s.world.lines("warn"), " | "))
end)
