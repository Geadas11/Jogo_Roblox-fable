-- The session loop on the real map: doors, clocking in, the night clock, the end of the
-- shift and the HUD that shows it. Runs the real server and client against the fake
-- engine (see tests/engine.luau for what that does and does not prove).

local SERVER_MAIN = "ServerScriptService.Server.Main"
local CLIENT_MAIN = "StarterPlayer.StarterPlayerScripts.Client.Main"
local SERVICES = "ServerScriptService.Server.Services."

local function boot()
	local world = Engine.new({ map = true })
	local server = world.side("server")
	server.load(SERVER_MAIN)
	local config = server.load("ReplicatedStorage.Shared.Config.GameConfig")
	return world, server, config
end

-- A ready player with a living character.
local function join(world, name, userId)
	local player = world.addPlayer(name, userId)
	world.spawnCharacter(player, 2)
	local client = world.side("client", player)
	client.load(CLIENT_MAIN)
	return player, client
end

local function tagged(world, tag)
	return world.getService("CollectionService"):GetTagged(tag)
end

local function promptOf(instance)
	return instance:FindFirstChildOfClass("ProximityPrompt")
end

local function findDoor(world, name)
	for _, door in tagged(world, "Door") do
		if door.Name == name then
			return door
		end
	end
	error("no door named " .. name)
end

local function hud(player)
	return player.PlayerGui.HUD
end

-- Doors -------------------------------------------------------------------------------

test("every unlocked door gets a prompt; the locked emergency exit does not", function()
	local world = boot()
	local withPrompt, locked = 0, 0
	for _, door in tagged(world, "Door") do
		if door:GetAttribute("Locked") then
			locked += 1
			expect.equal(promptOf(door), nil, door.Name)
		else
			withPrompt += 1
			expect.truthy(promptOf(door), door.Name .. " has a prompt")
		end
	end
	expect.equal(locked, 1)
	expect.truthy(withPrompt >= 12)
end)

test("a player next to a door can close it and open it again", function()
	local world = boot()
	local player = join(world, "Tester", 1)
	local door = findDoor(world, "StaffDoor")
	local prompt = promptOf(door)
	expect.equal(door:GetAttribute("Open"), true)
	expect.equal(prompt.ActionText, "Close")

	world.moveTo(player, door)
	world.trigger(prompt, player)
	expect.equal(door:GetAttribute("Open"), false)
	expect.equal(door.CFrame, door:GetAttribute("ClosedCFrame"))
	expect.equal(prompt.ActionText, "Open")

	task.wait(0.3) -- interaction cooldown
	world.moveTo(player, door)
	world.trigger(prompt, player)
	expect.equal(door:GetAttribute("Open"), true)
	expect.equal(door.CFrame, door:GetAttribute("OpenCFrame"))
end)

test("a door cannot be operated from across the map", function()
	local world = boot()
	local player = join(world, "Cheater", 2)
	local door = findDoor(world, "FreezerDoor")
	world.moveTo(player, -90, 3, -5) -- the employee room
	world.trigger(promptOf(door), player)
	expect.equal(door:GetAttribute("Open"), true)
end)

test("interactions are ignored for a dead player, a player without a character and a stranger", function()
	local world = boot()
	local door = findDoor(world, "OfficeDoor")
	local prompt = promptOf(door)

	local dead = join(world, "Dead", 3)
	world.moveTo(dead, door)
	dead.Character.Humanoid.Health = 0
	world.trigger(prompt, dead)
	expect.equal(door:GetAttribute("Open"), true)

	local noCharacter = world.addPlayer("NoCharacter", 4)
	world.side("client", noCharacter).load(CLIENT_MAIN)
	world.trigger(prompt, noCharacter)
	expect.equal(door:GetAttribute("Open"), true)

	-- Never sent ClientReady: not part of the session.
	local stranger = world.addPlayer("Stranger", 5)
	world.spawnCharacter(stranger, 2)
	world.moveTo(stranger, door)
	world.trigger(prompt, stranger)
	expect.equal(door:GetAttribute("Open"), true)
end)

test("rapid repeated triggers only count once", function()
	local world = boot()
	local player = join(world, "Masher", 6)
	local door = findDoor(world, "OfficeDoor")
	world.moveTo(player, door)
	for _ = 1, 20 do
		world.trigger(promptOf(door), player)
	end
	expect.equal(door:GetAttribute("Open"), false)
end)

-- Starting the shift --------------------------------------------------------------------

local function clockIn(world, player)
	local clock = tagged(world, "TimeClock")[1]
	world.moveTo(player, clock)
	world.trigger(promptOf(clock), player)
	return clock
end

test("the session starts in the lobby with the clock off", function()
	local world, server = boot()
	local player = join(world, "Tester", 1)
	expect.equal(server.load("ReplicatedStorage.Shared.SessionState").Get("Phase"), "Lobby")
	expect.equal(hud(player).Top.Clock.Text, "OFF SHIFT")
	expect.truthy(string.find(hud(player).Top.Status.Text, "CLOCK IN", 1, true))
end)

test("clocking in starts the shift at 12 AM for everyone", function()
	local world, server = boot()
	local state = server.load("ReplicatedStorage.Shared.SessionState")
	local first = join(world, "First", 1)
	local second, secondClient = join(world, "Second", 2)

	local clock = clockIn(world, first)
	expect.equal(state.Get("Phase"), "Shift")
	expect.equal(state.Get("Hour"), 0)
	expect.equal(state.Get("ShiftStartTime"), world.now)
	-- During the shift the same clock is used to clock out.
	expect.equal(promptOf(clock).Enabled, true)
	expect.equal(promptOf(clock).ActionText, "Clock out")

	secondClient.load("StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController").Refresh()
	expect.equal(hud(second).Top.Clock.Text, "12:00 AM")
	expect.truthy(string.find(hud(second).Top.Status.Text, "NIGHT SHIFT", 1, true))
	expect.truthy(string.find(hud(second).Top.Status.Text, "ENDS AT 6:00 AM", 1, true))

	-- Both players were told who started it.
	local notice = hud(second).Notifications:FindFirstChild("Notification")
	expect.truthy(notice, "notification shown")
	expect.truthy(string.find(notice.Text, "First clocked in", 1, true))
end)

test("the shift cannot be started twice or from far away", function()
	local world, server = boot()
	local state = server.load("ReplicatedStorage.Shared.SessionState")
	local gameManager = server.load(SERVICES .. "GameManager")
	local player = join(world, "Tester", 1)
	local clock = tagged(world, "TimeClock")[1]

	world.moveTo(player, 60, 3, 150) -- the parking lot
	world.trigger(promptOf(clock), player)
	expect.equal(state.Get("Phase"), "Lobby")

	clockIn(world, player)
	local startedAt = state.Get("ShiftStartTime")
	world.now += 50
	expect.falsy(gameManager.StartShift(player))
	expect.equal(state.Get("Phase"), "Shift")
	expect.equal(state.Get("ShiftStartTime"), startedAt)
end)

-- The clock ------------------------------------------------------------------------------

test("hours advance with time and each one is announced exactly once", function()
	local world, server, config = boot()
	local state = server.load("ReplicatedStorage.Shared.SessionState")
	local shift = server.load(SERVICES .. "ShiftManager")
	local player, client = join(world, "Tester", 1)
	local hudController = client.load("StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")

	local hours = {}
	shift.HourChanged:Connect(function(hour)
		table.insert(hours, hour)
	end)
	clockIn(world, player)

	local hourLength = config.Shift.HourDurationSeconds
	world.now += hourLength * 0.5
	shift.Update()
	hudController.Refresh()
	expect.equal(state.Get("Hour"), 0)
	expect.equal(hud(player).Top.Clock.Text, "12:30 AM")

	world.now += hourLength
	shift.Update()
	shift.Update()
	hudController.Refresh()
	expect.equal(state.Get("Hour"), 1)
	expect.equal(hud(player).Top.Clock.Text, "1:30 AM")

	-- A long stall must not skip hours.
	world.now += hourLength * 3
	shift.Update()
	expect.equal(state.Get("Hour"), 4)
	expect.equal(table.concat(hours, ","), "0,1,2,3,4")
end)

test("at 6 AM the shift completes once and everyone sees the results", function()
	local world, server, config = boot()
	local state = server.load("ReplicatedStorage.Shared.SessionState")
	local shift = server.load(SERVICES .. "ShiftManager")
	local gameManager = server.load(SERVICES .. "GameManager")
	local player, client = join(world, "Tester", 1)
	local hudController = client.load("StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")

	local completions = 0
	shift.Completed:Connect(function()
		completions += 1
	end)
	clockIn(world, player)

	world.now += config.Shift.HourDurationSeconds * config.Shift.Hours + 30
	shift.Update()
	shift.Update()
	expect.equal(completions, 1)
	expect.equal(state.Get("Phase"), "Results")
	expect.equal(state.Get("Hour"), 6)
	expect.falsy(shift.IsRunning())

	hudController.Refresh()
	local results = hud(player).Results
	expect.equal(results.Visible, true)
	expect.equal(results.Title.Text, "SHIFT COMPLETE")
	expect.truthy(string.find(results.Body.Text, "Hours worked: 6", 1, true))
	expect.truthy(string.find(results.Body.Text, "Time on shift: 24:00", 1, true))
	expect.equal(hud(player).Top.Clock.Text, "6:00 AM")

	-- Back to the lobby: results hidden, clock off, the time clock usable again.
	gameManager.ReturnToLobby()
	hudController.Refresh()
	expect.equal(state.Get("Phase"), "Lobby")
	expect.equal(state.Get("Hour"), 0)
	expect.equal(results.Visible, false)
	expect.equal(hud(player).Top.Clock.Text, "OFF SHIFT")
	expect.equal(promptOf(tagged(world, "TimeClock")[1]).Enabled, true)

	-- And a second night can start.
	task.wait(0.3)
	clockIn(world, player)
	expect.equal(state.Get("Phase"), "Shift")
	expect.equal(state.Get("Hour"), 0)
end)

-- Ending the shift early ---------------------------------------------------------------------

test("alone, clocking out ends the shift early and says so in the results", function()
	local world, server, config = boot()
	local state = server.load("ReplicatedStorage.Shared.SessionState")
	local shift = server.load(SERVICES .. "ShiftManager")
	local player, client = join(world, "Tester", 1)
	local hudController = client.load("StarterPlayer.StarterPlayerScripts.Client.Controllers.HudController")
	local clock = clockIn(world, player)

	world.now += config.Shift.HourDurationSeconds * 1.5
	shift.Update()
	task.wait(0.3)
	world.trigger(promptOf(clock), player)

	expect.equal(state.Get("Phase"), "Results")
	expect.falsy(shift.IsRunning())
	expect.equal(promptOf(clock).Enabled, false)
	hudController.Refresh()
	local results = hud(player).Results
	expect.equal(results.Visible, true)
	expect.equal(results.Title.Text, "SHIFT ENDED")
	expect.truthy(string.find(results.Body.Text, "Clocked out at 1:30 AM", 1, true), results.Body.Text)
	expect.truthy(string.find(results.Body.Text, "Hours worked: 1", 1, true), results.Body.Text)
	expect.equal(hud(player).Top.Clock.Text, "1:30 AM")

	-- The night can be started again afterwards.
	server.load(SERVICES .. "GameManager").ReturnToLobby()
	expect.equal(promptOf(clock).ActionText, "Clock in")
	task.wait(0.3)
	world.trigger(promptOf(clock), player)
	expect.equal(state.Get("Phase"), "Shift")
end)

test("with a team, the shift only ends early when everyone has clocked out", function()
	local world, server = boot()
	local state = server.load("ReplicatedStorage.Shared.SessionState")
	local first = join(world, "First", 1)
	local second = join(world, "Second", 2)
	local third = join(world, "Third", 3)
	local clock = clockIn(world, first)

	local function clockOut(player)
		task.wait(0.3)
		world.moveTo(player, clock)
		world.trigger(promptOf(clock), player)
	end
	local function lastNotice(player)
		local last = ""
		for _, child in hud(player).Notifications:GetChildren() do
			if child.Name == "Notification" then
				last = child.Text
			end
		end
		return last
	end

	clockOut(first)
	expect.equal(state.Get("Phase"), "Shift")
	expect.truthy(string.find(lastNotice(second), "First clocked out (1/3)", 1, true), lastNotice(second))

	-- Voting again does not count twice.
	clockOut(first)
	expect.equal(state.Get("Phase"), "Shift")
	expect.truthy(string.find(lastNotice(first), "already clocked out", 1, true))

	clockOut(second)
	expect.equal(state.Get("Phase"), "Shift")

	-- The last player still working leaves: everyone who remains has clocked out.
	world.removePlayer(third)
	expect.equal(state.Get("Phase"), "Results")
end)

test("nobody can clock the team out from across the map", function()
	local world, server = boot()
	local state = server.load("ReplicatedStorage.Shared.SessionState")
	local player = join(world, "Cheater", 1)
	local clock = clockIn(world, player)
	task.wait(0.3)
	world.moveTo(player, 60, 3, 150)
	world.trigger(promptOf(clock), player)
	expect.equal(state.Get("Phase"), "Shift")
end)

test("a shift everyone has left is abandoned", function()
	local world, server = boot()
	local state = server.load("ReplicatedStorage.Shared.SessionState")
	local shift = server.load(SERVICES .. "ShiftManager")
	local first = join(world, "First", 1)
	local second = join(world, "Second", 2)
	clockIn(world, first)

	world.removePlayer(first)
	expect.equal(state.Get("Phase"), "Shift", "one player is still working")
	world.removePlayer(second)
	expect.equal(state.Get("Phase"), "Lobby")
	expect.falsy(shift.IsRunning())
end)

test("a player who joins during the shift sees the running clock", function()
	local world, server, config = boot()
	local shift = server.load(SERVICES .. "ShiftManager")
	local first = join(world, "First", 1)
	clockIn(world, first)
	world.now += config.Shift.HourDurationSeconds * 2.25
	shift.Update()

	local late = join(world, "Late", 2)
	expect.equal(hud(late).Top.Clock.Text, "2:15 AM")
	expect.truthy(string.find(hud(late).Top.Status.Text, "NIGHT SHIFT", 1, true))
end)

test("the whole session runs without a single warning", function()
	local world, server, config = boot()
	local shift = server.load(SERVICES .. "ShiftManager")
	local player = join(world, "Tester", 1)
	clockIn(world, player)
	world.now += config.Shift.HourDurationSeconds * config.Shift.Hours
	shift.Update()
	server.load(SERVICES .. "GameManager").ReturnToLobby()
	expect.equal(#world.lines("warn"), 0, "warnings: " .. table.concat(world.lines("warn"), " | "))
end)

-- Security cameras -------------------------------------------------------------------------

test("the cameras are watched from the office computer and the staff-room monitor", function()
	local world = boot()
	local computer = tagged(world, "OfficeComputer")[1]
	expect.equal(promptOf(computer).ActionText, "Watch cameras")
	local staffRoom = 0
	for _, monitor in tagged(world, "SecurityMonitor") do
		if monitor:GetAttribute("Zone") ~= "Office" then
			staffRoom += 1
			expect.equal(promptOf(monitor).ActionText, "Watch cameras")
		else
			expect.equal(promptOf(monitor), nil, "the office wall is watched from the computer")
		end
	end
	expect.equal(staffRoom, 1)
end)

test("watching the cameras: feeds on screen, standing still, until you look away", function()
	local world = boot()
	local player, client = join(world, "Tester", 1)
	clockIn(world, player)
	task.wait(0.3) -- interaction cooldown
	local cctv = client.load("StarterPlayer.StarterPlayerScripts.Client.Controllers.CctvController")
	local computer = tagged(world, "OfficeComputer")[1]

	world.moveTo(player, computer)
	world.trigger(promptOf(computer), player)
	expect.equal(player:GetAttribute("WatchingCameras"), true)
	expect.truthy(cctv.IsWatching())
	expect.equal(player.PlayerGui.Cameras.Enabled, true)
	expect.truthy(string.find(player.PlayerGui.Cameras.CameraName.Text, "CAM 01", 1, true))

	world.fireServerAs(player, "LeaveCameras")
	expect.equal(player:GetAttribute("WatchingCameras"), false)
	expect.falsy(cctv.IsWatching())
	expect.equal(player.PlayerGui.Cameras.Enabled, false)
	expect.equal(#world.lines("warn"), 0, "warnings: " .. table.concat(world.lines("warn"), " | "))
end)

test("being caught or the shift ending takes you off the cameras", function()
	local world, server = boot()
	local player, client = join(world, "Tester", 1)
	clockIn(world, player)
	task.wait(0.3) -- interaction cooldown
	local cctv = client.load("StarterPlayer.StarterPlayerScripts.Client.Controllers.CctvController")
	local computer = tagged(world, "OfficeComputer")[1]
	world.moveTo(player, computer)
	world.trigger(promptOf(computer), player)
	expect.truthy(cctv.IsWatching())
	player:SetAttribute("Status", "Caught")
	expect.equal(player:GetAttribute("WatchingCameras"), false)
	expect.falsy(cctv.IsWatching())
end)
