-- The hunt on the real map, through the real server and client code: the monster
-- appearing, hiding, being caught, second chances, spectating and losing the shift.

local roblox = require("@lune/roblox")

local SERVER_MAIN = "ServerScriptService.Server.Main"
local CLIENT_MAIN = "StarterPlayer.StarterPlayerScripts.Client.Main"
local SERVICES = "ServerScriptService.Server.Services."

local function boot()
	local world = Engine.new({ map = true })
	local server = world.side("server")
	server.load(SERVER_MAIN)
	local s = {
		world = world,
		server = server,
		config = server.load("ReplicatedStorage.Shared.Config.GameConfig"),
		monsterConfig = server.load("ReplicatedStorage.Shared.Config.MonsterConfig"),
		state = server.load("ReplicatedStorage.Shared.SessionState"),
		shift = server.load(SERVICES .. "ShiftManager"),
		game = server.load(SERVICES .. "GameManager"),
		monster = server.load(SERVICES .. "MonsterManager"),
		survival = server.load(SERVICES .. "SurvivalService"),
		hiding = server.load(SERVICES .. "HidingService"),
		noise = server.load(SERVICES .. "NoiseService"),
		doors = server.load(SERVICES .. "DoorService"),
	}
	return s
end

local function join(s, name, userId)
	local player = s.world.addPlayer(name, userId)
	s.world.spawnCharacter(player, 2)
	s.world.side("client", player).load(CLIENT_MAIN)
	return player
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
	expect.equal(s.state.Get("Phase"), "Shift")
end

local function advanceHours(s, hours)
	s.world.now += s.config.Shift.HourDurationSeconds * hours
	s.shift.Update()
end

local function root(player)
	return player.Character.HumanoidRootPart
end

-- Steps the monster until `done()` or the time runs out.
local function hunt(s, seconds, done)
	for _ = 1, math.floor(seconds / 0.1) do
		s.monster.Step(0.1)
		if done and done() then
			return true
		end
	end
	return false
end

local function aim(brain, x, z)
	local dx, dz = x - brain.X, z - brain.Z
	local length = math.sqrt(dx * dx + dz * dz)
	brain.FaceX, brain.FaceZ = dx / length, dz / length
end

local function monsterPart(s)
	return s.world.getService("Workspace"):FindFirstChild("TheCustomer")
end

-- Appearing -------------------------------------------------------------------------------

test("the monster is not in the store before 3 AM; at 3 AM it appears far away and unseen", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	s.world.moveTo(player, -23, 3, 20)

	advanceHours(s, 2)
	expect.falsy(s.monster.GetBrain().Present)
	expect.equal(monsterPart(s):GetAttribute("Present"), false)

	advanceHours(s, 1)
	local brain = s.monster.GetBrain()
	expect.truthy(brain.Present)
	expect.equal(brain.State, "Patrol")
	local part = monsterPart(s)
	expect.equal(part:GetAttribute("Present"), true)
	expect.equal(part.Transparency, 1, "the server part is invisible; clients draw the body")
	local distance = math.sqrt((brain.X + 23) ^ 2 + (brain.Z - 20) ^ 2)
	expect.truthy(
		distance >= s.monsterConfig.Behaviour.SpawnMinDistance,
		"appeared " .. distance .. " studs away"
	)
	expect.truthy(math.abs(part.Position.X - brain.X) < 0.01, "the part follows the brain")
end)

test("the monster is gone when the shift ends", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	advanceHours(s, 3)
	expect.truthy(s.monster.GetBrain().Present)
	advanceHours(s, 3)
	expect.equal(s.state.Get("Phase"), "Results")
	expect.falsy(s.monster.GetBrain().Present)
	expect.equal(monsterPart(s):GetAttribute("Present"), false)
end)

-- Hiding -------------------------------------------------------------------------------------

test("a player hides in a locker, cannot be seen, and steps out somewhere walkable", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	local locker
	for _, spot in tagged(s, "HidingSpot") do
		if spot:GetAttribute("Kind") == "Locker" and spot:GetAttribute("Zone") == "EmployeeRoom" then
			locker = spot
		end
	end
	expect.truthy(locker)
	expect.equal(promptOf(locker).ActionText, "Hide")

	use(s, player, locker)
	expect.equal(player:GetAttribute("Status"), "Hiding")
	expect.equal(root(player).Anchored, true)
	expect.truthy(math.abs(root(player).Position.X - locker.Position.X) < 0.01)
	expect.equal(locker:GetAttribute("Occupied"), true)
	expect.equal(promptOf(locker).Enabled, false)
	expect.equal(player.PlayerGui.HUD.Hiding.Visible, true)

	-- Someone else cannot get in, through the prompt or otherwise.
	local other = join(s, "Other", 2)
	use(s, other, locker)
	expect.equal(other:GetAttribute("Status"), "Working")
	local spot
	for _, candidate in s.hiding.GetSpots() do
		if candidate.Part == locker then
			spot = candidate
		end
	end
	expect.falsy(s.hiding.Hide(other, spot))
	expect.equal(s.hiding.OccupantOf(spot.Id), player)

	s.world.fireServerAs(player, "LeaveHiding")
	expect.equal(player:GetAttribute("Status"), "Working")
	expect.equal(root(player).Anchored, false)
	expect.equal(player.PlayerGui.HUD.Hiding.Visible, false)
	expect.equal(locker:GetAttribute("Occupied"), false)
	local grid = s.server.load("ServerScriptService.Server.Monster.MapGrid").Get()
	expect.truthy(
		grid:IsWalkable(root(player).Position.X, root(player).Position.Z),
		"stepped out into a wall"
	)
end)

test("hiding drops what you carry, and leaving when not hidden does nothing", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	local mop
	for _, child in s.world.getService("Workspace"):GetChildren() do
		if child.Name == "Mop" then
			mop = child
		end
	end
	use(s, player, mop)
	expect.equal(player:GetAttribute("Carrying"), "Mop")
	for _ = 1, 10 do
		s.world.fireServerAs(player, "LeaveHiding")
	end
	expect.equal(player:GetAttribute("Status"), "Working")

	local spot = tagged(s, "HidingSpot")[1]
	use(s, player, spot)
	expect.equal(player:GetAttribute("Status"), "Hiding")
	expect.equal(player:GetAttribute("Carrying"), "")
end)

test("every hiding spot can be entered and left", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	local grid = s.server.load("ServerScriptService.Server.Monster.MapGrid").Get()
	local count = 0
	for _, spot in s.hiding.GetSpots() do
		use(s, player, spot.Part)
		expect.equal(
			player:GetAttribute("Status"),
			"Hiding",
			spot.Part.Name .. " in " .. tostring(spot.Part:GetAttribute("Zone"))
		)
		s.world.fireServerAs(player, "LeaveHiding")
		task.wait(1.6) -- re-hide cooldown
		expect.truthy(grid:IsWalkable(root(player).Position.X, root(player).Position.Z))
		count += 1
	end
	expect.truthy(count >= 8)
end)

-- Being caught ----------------------------------------------------------------------------------

local function catchHere(s, player, x, z)
	s.world.moveTo(player, x, 3, z)
	s.monster.Spawn(x, z - 25)
	aim(s.monster.GetBrain(), x, z)
	return hunt(s, 15, function()
		return player:GetAttribute("Status") == "Caught"
	end)
end

test("caught alone: the catch sequence plays, then a second chance in the employee room", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)

	expect.truthy(catchHere(s, player, -23, 20), "never caught")
	expect.equal(root(player).Anchored, true, "frozen during the catch")
	expect.equal(player.PlayerGui.HUD.Scare.Visible, true, "catch sequence on screen")
	expect.equal(s.monster.GetBrain().State, "Catch")

	s.survival.ResolveCatch(player)
	expect.equal(player:GetAttribute("Status"), "Working")
	expect.equal(s.state.Get("Phase"), "Shift")
	local position = root(player).Position
	expect.truthy(position.X < -70 and position.Z < 10 and position.Z > -30, "back in the employee room")

	-- The monster vanishes for a while after a catch.
	hunt(s, s.monsterConfig.CatchSequenceSeconds + 0.5)
	expect.equal(s.monster.GetBrain().State, "Vanished")
end)

test("caught alone a second time: the shift is lost", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	catchHere(s, player, -23, 20)
	s.survival.ResolveCatch(player)
	expect.truthy(catchHere(s, player, 19, 20), "second catch")
	s.survival.ResolveCatch(player)

	expect.equal(s.state.Get("Phase"), "Results")
	local results = player.PlayerGui.HUD.Results
	expect.equal(results.Title.Text, "SHIFT ENDED")
	expect.truthy(string.find(results.Body.Text, "You were caught.", 1, true), results.Body.Text)
	expect.truthy(string.find(results.Body.Text, "Caught: 2", 1, true), results.Body.Text)
end)

test("in a team, a caught player watches until the next hour, then is back", function()
	local s = boot()
	local first = join(s, "First", 1)
	local second = join(s, "Second", 2)
	startShift(s, first)
	s.world.moveTo(second, -90, 3, -5)
	advanceHours(s, 3)

	expect.truthy(catchHere(s, first, 19, 20))
	s.survival.ResolveCatch(first)
	expect.equal(first:GetAttribute("Status"), "Spectating")
	expect.equal(first.Character, nil)
	expect.equal(first.PlayerGui.HUD.Spectating.Visible, true)
	expect.equal(s.state.Get("Phase"), "Shift")
	-- The monster no longer counts them.
	for _, target in s.monster.GetBrain().World.Targets() do
		expect.truthy(target.Id ~= 1, "a spectator was hunted")
	end

	advanceHours(s, 1)
	expect.equal(first:GetAttribute("Status"), "Working")
	expect.truthy(first.Character)
	expect.equal(first.PlayerGui.HUD.Spectating.Visible, false)
end)

test("in a team, when nobody is left working the shift is lost", function()
	local s = boot()
	local first = join(s, "First", 1)
	local second = join(s, "Second", 2)
	startShift(s, first)
	catchHere(s, first, 19, 20)
	s.survival.ResolveCatch(first)
	hunt(s, s.monsterConfig.CatchSequenceSeconds + s.monsterConfig.Behaviour.VanishSeconds + 1)
	expect.truthy(catchHere(s, second, -23, 20))
	s.survival.ResolveCatch(second)
	expect.equal(s.state.Get("Phase"), "Results")
	expect.truthy(string.find(second.PlayerGui.HUD.Results.Body.Text, "Everyone was caught.", 1, true))
end)

test("a player seen hiding is pulled out; nobody can be caught twice at once", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	local locker
	for _, spot in s.hiding.GetSpots() do
		if spot.Part:GetAttribute("Zone") == "EmployeeRoom" then
			locker = spot.Part
		end
	end
	s.world.moveTo(player, locker.Position.X, 3, locker.Position.Z - 4)
	s.monster.Spawn(-84, -20)
	aim(s.monster.GetBrain(), locker.Position.X, locker.Position.Z - 4)
	hunt(s, 3, function()
		return s.monster.GetBrain().State == "Chase"
	end)
	expect.equal(s.monster.GetBrain().State, "Chase")

	use(s, player, locker)
	expect.equal(player:GetAttribute("Status"), "Hiding")
	expect.truthy(
		hunt(s, 15, function()
			return player:GetAttribute("Status") == "Caught"
		end),
		"hid in front of it and got away"
	)
	expect.equal(locker:GetAttribute("Occupied"), false)
	expect.falsy(s.survival.Catch(player, 1), "caught twice")
end)

-- Noise and doors --------------------------------------------------------------------------------

test("a slammed door and running feet bring it to investigate", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	s.monster.Spawn(19, 20)
	local brain = s.monster.GetBrain()
	brain.FaceX, brain.FaceZ = 0, 1

	-- The office door is far behind walls: too far to hear.
	local office
	for _, door in tagged(s, "Door") do
		if door.Name == "OfficeDoor" then
			office = door
		end
	end
	use(s, player, office)
	hunt(s, 0.2)
	expect.equal(brain.State, "Patrol", "heard a door 90 studs away")

	-- Running in the next aisle is close enough to hear.
	s.world.moveTo(player, 33, 3, 0)
	root(player).AssemblyLinearVelocity = roblox.Vector3.new(0, 0, 16)
	s.noise.SampleFootsteps()
	hunt(s, 0.2)
	expect.equal(brain.State, "Investigate")

	-- Walking makes no sound.
	local quiet = boot()
	local walker = join(quiet, "Walker", 1)
	startShift(quiet, walker)
	quiet.monster.Spawn(19, 20)
	quiet.world.moveTo(walker, 33, 3, 0)
	root(walker).AssemblyLinearVelocity = roblox.Vector3.new(0, 0, 9)
	quiet.noise.SampleFootsteps()
	hunt(quiet, 0.2)
	expect.truthy(quiet.monster.GetBrain().State ~= "Investigate")
end)

test("it opens closed doors in its way", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	local door
	for _, candidate in tagged(s, "Door") do
		if candidate.Name == "StaffDoor" then
			door = candidate
		end
	end
	s.doors.SetOpen(door, false, nil)
	task.wait(0.1)
	s.monster.Spawn(-63, 31)
	hunt(s, 0.2)
	expect.equal(door:GetAttribute("Open"), true)
end)

-- The client --------------------------------------------------------------------------------------

test("the screen darkens as it comes near, and turns red when it chases you", function()
	local s = boot()
	local player = s.world.addPlayer("Tester", 1)
	s.world.spawnCharacter(player, 2)
	local client = s.world.side("client", player)
	client.load(CLIENT_MAIN)
	local controller = client.load("StarterPlayer.StarterPlayerScripts.Client.Controllers.MonsterController")
	startShift(s, player)

	s.world.moveTo(player, -23, 3, 20)
	s.monster.Spawn(-23, 60)
	for _ = 1, 30 do
		controller.Frame(0.1)
	end
	local edge = player.PlayerGui.HUD.DangerEdge
	expect.truthy(edge.BackgroundTransparency > 0.9, "far: barely any darkening")
	expect.truthy(s.world.getService("Workspace"):FindFirstChild("TheCustomerBody"), "the body is drawn")

	s.monster.Spawn(-23, 8)
	aim(s.monster.GetBrain(), -23, 20)
	expect.truthy(
		hunt(s, 3, function()
			return s.monster.GetBrain().State == "Chase"
		end),
		"never gave chase"
	)
	for _ = 1, 30 do
		controller.Frame(0.1)
	end
	expect.truthy(edge.BackgroundTransparency < 0.7, "close: the edges darken")
	local grade = s.world.getService("Workspace").CurrentCamera.DangerGrade
	expect.truthy(grade.Saturation < -0.1, "chased: colour drains")
end)

test("the hunt runs a whole night without a single warning", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	advanceHours(s, 3)
	hunt(s, 60)
	advanceHours(s, 3)
	expect.equal(#s.world.lines("warn"), 0, "warnings: " .. table.concat(s.world.lines("warn"), " | "))
end)
