-- End-to-end boot of the real entry points against the fake engine:
-- server Main, then a player joining, then that player's client Main.
--
-- This runs the actual project code, but on a simulated engine. It proves the scripts
-- execute and cooperate; it cannot prove anything about real Roblox behaviour.

local roblox = require("@lune/roblox")

local SERVER_MAIN = "ServerScriptService.Server.Main"
local CLIENT_MAIN = "StarterPlayer.StarterPlayerScripts.Client.Main"
local PLAYER_MANAGER = "ServerScriptService.Server.Services.PlayerManager"

local function bootServer()
	local world = Engine.new()
	local server = world.side("server")
	server.load(SERVER_MAIN)
	return world, server
end

local function joinAndBootClient(world, name, userId)
	local player = world.addPlayer(name, userId)
	local client = world.side("client", player)
	client.load(CLIENT_MAIN)
	return player, client
end

test("the server boots without warnings and announces it is ready", function()
	local world = bootServer()
	expect.equal(#world.lines("warn"), 0, "warnings: " .. table.concat(world.lines("warn"), " | "))
	expect.anyLine(world.lines("print"), "[NSS/Server/Main] Server ready (build ")
end)

test("the server creates the replicated objects clients depend on", function()
	local world, server = bootServer()
	local definitions = server.load("ReplicatedStorage.Shared.Net.Definitions")
	local config = server.load("ReplicatedStorage.Shared.Config.GameConfig")

	for name, definition in definitions do
		local folder = if definition.kind == "Event" then "Events" else "Functions"
		local remote = world.find("ReplicatedStorage.Remotes." .. folder .. "." .. name)
		expect.equal(remote.ClassName, if definition.kind == "Event" then "RemoteEvent" else "RemoteFunction")
	end

	local state = world.find("ReplicatedStorage.State")
	expect.equal(state:GetAttribute("Phase"), "Lobby")
	expect.equal(state:GetAttribute("BuildVersion"), config.BuildVersion)
end)

test("collision groups are registered and the configured pairs do not collide", function()
	local world, server = bootServer()
	local groups = server.load("ReplicatedStorage.Shared.Config.CollisionGroups")

	for _, groupName in groups.Names do
		expect.truthy(world.collisionGroups[groupName], groupName .. " registered")
	end
	local pairCount = 0
	for _ in world.nonCollidingPairs do
		pairCount += 1
	end
	expect.equal(pairCount, #groups.NonColliding)
	expect.truthy(world.nonCollidingPairs["Monster|Player"])
	expect.truthy(world.nonCollidingPairs["Player|Player"])
end)

test("the base lighting profile is applied over whatever the place contained", function()
	local world = Engine.new()
	local lighting = world.getService("Lighting")

	-- What a Studio template typically leaves behind.
	local templateAtmosphere = world.newInstance("Atmosphere", "Atmosphere")
	templateAtmosphere.Density = 0.9
	templateAtmosphere.Parent = lighting
	local sunRays = world.newInstance("SunRaysEffect", "SunRays")
	sunRays.Enabled = true
	sunRays.Parent = lighting
	local sky = world.newInstance("Sky", "Sky")
	sky.Parent = lighting

	local server = world.side("server")
	server.load(SERVER_MAIN)
	local profile = server.load("ReplicatedStorage.Shared.Config.LightingConfig").Base

	expect.equal(lighting.ClockTime, 0)
	expect.equal(lighting.LightingStyle, roblox.Enum.LightingStyle.Realistic)
	expect.equal(lighting.PrioritizeLightingQuality, true)
	expect.equal(lighting.Ambient, profile.Lighting.Ambient)

	-- The existing Atmosphere is reused, not duplicated.
	local atmospheres = 0
	for _, child in lighting:GetChildren() do
		if child.ClassName == "Atmosphere" then
			atmospheres += 1
		end
	end
	expect.equal(atmospheres, 1)
	expect.equal(templateAtmosphere.Density, 0.38)

	expect.equal(lighting.Grade.ClassName, "ColorCorrectionEffect")
	expect.equal(lighting.Bloom.Intensity, 0.4)

	-- Effects outside the profile are switched off; non-effects are left alone.
	expect.equal(sunRays.Enabled, false)
	expect.equal(sky.Parent, lighting)
	expect.anyLine(world.lines("print"), "Disabled SunRays (SunRaysEffect)")
	expect.equal(#world.lines("warn"), 0)
end)

test("a client boots, locks first person and is marked ready on the server", function()
	local world, server = bootServer()
	local playerManager = server.load(PLAYER_MANAGER)

	local readySignals = {}
	playerManager.PlayerReady:Connect(function(player)
		table.insert(readySignals, player.Name)
	end)

	local player = world.addPlayer("Tester", 101)
	expect.falsy(playerManager.IsReady(player), "ready before the client booted")

	world.side("client", player).load(CLIENT_MAIN)

	expect.truthy(playerManager.IsReady(player))
	expect.equal(table.concat(readySignals, ","), "Tester")
	expect.equal(player.CameraMode, roblox.Enum.CameraMode.LockFirstPerson)
	expect.anyLine(world.lines("print"), "[NSS/Server/Players] Tester is ready (1 in session)")
	expect.anyLine(world.lines("print"), "[NSS/Client/Main] Client ready (build ")
	expect.equal(#world.lines("warn"), 0, "warnings: " .. table.concat(world.lines("warn"), " | "))
end)

test("several players are tracked independently and leaving cleans up", function()
	local world, server = bootServer()
	local playerManager = server.load(PLAYER_MANAGER)

	local players = {}
	for index = 1, 6 do
		players[index] = joinAndBootClient(world, "Player" .. index, 200 + index)
	end
	expect.equal(#playerManager.GetReadyPlayers(), 6)

	world.removePlayer(players[3])
	expect.falsy(playerManager.IsReady(players[3]))
	expect.equal(#playerManager.GetReadyPlayers(), 5)
	expect.truthy(playerManager.IsReady(players[4]))
end)

test("characters are kept in the Player collision group, including parts added later", function()
	local world = bootServer()
	local player = world.addPlayer("Tester", 101)

	local character = world.spawnCharacter(player, 4)
	for _, part in character:GetChildren() do
		expect.equal(part.CollisionGroup, "Player")
	end

	-- An accessory arriving after the character spawned.
	local accessory = world.newInstance("Model", "Hat")
	local handle = world.newInstance("Part", "Handle")
	handle.CollisionGroup = "Default"
	handle.Parent = accessory
	accessory.Parent = character
	expect.equal(handle.CollisionGroup, "Player")

	-- After a respawn the old character is no longer tracked.
	local respawned = world.spawnCharacter(player, 2)
	local stray = world.newInstance("Part", "Stray")
	stray.CollisionGroup = "Default"
	stray.Parent = character
	expect.equal(stray.CollisionGroup, "Default")
	expect.equal(respawned.Part1.CollisionGroup, "Player")
end)

test("a player who was already connected when the server booted is still tracked", function()
	local world = Engine.new()
	local early = world.addPlayer("Early", 7)
	world.spawnCharacter(early, 2)

	local server = world.side("server")
	server.load(SERVER_MAIN)
	expect.equal(early.Character.Part1.CollisionGroup, "Player")

	world.side("client", early).load(CLIENT_MAIN)
	expect.truthy(server.load(PLAYER_MANAGER).IsReady(early))
end)

test("ClientReady with unexpected arguments is rejected and never reaches gameplay", function()
	local world, server = bootServer()
	local playerManager = server.load(PLAYER_MANAGER)
	local cheater = world.addPlayer("Cheater", 666)

	world.fireServerAs(cheater, "ClientReady", { money = 999999 })
	expect.falsy(playerManager.IsReady(cheater))
	expect.anyLine(
		world.lines("warn"),
		"Rejected ClientReady from Cheater (666): expected at most 0 arguments, got 1"
	)
end)

test("spamming a remote is cut off by the rate limit and logged only once", function()
	local world, server = bootServer()
	local playerManager = server.load(PLAYER_MANAGER)
	local definitions = server.load("ReplicatedStorage.Shared.Net.Definitions")
	local spammer = world.addPlayer("Spammer", 42)

	local readyCount = 0
	playerManager.PlayerReady:Connect(function()
		readyCount += 1
	end)

	for _ = 1, 200 do
		world.fireServerAs(spammer, "ClientReady")
	end

	-- Marked ready exactly once, however many messages arrived.
	expect.equal(readyCount, 1)

	local rejections = 0
	for _, line in world.lines("warn") do
		if string.find(line, "Rejected ClientReady from Spammer", 1, true) then
			rejections += 1
		end
	end
	expect.equal(rejections, 1, "throttled violation log lines")
	expect.anyLine(world.lines("warn"), "rate limit exceeded")
	expect.truthy(definitions.ClientReady.rate.burst < 200)
end)

test("a remote fired by someone who is not in the session does nothing", function()
	local world, server = bootServer()
	local playerManager = server.load(PLAYER_MANAGER)
	local ghost = world.newInstance("Player", "Ghost")
	ghost.UserId = 1

	world.fireServerAs(ghost, "ClientReady")
	expect.falsy(playerManager.IsReady(ghost))
	expect.equal(#playerManager.GetReadyPlayers(), 0)
end)

test("the client fails with a readable error when the server never started", function()
	local world = Engine.new()
	local player = world.addPlayer("Tester", 101)
	expect.throws(function()
		world.side("client", player).load(CLIENT_MAIN)
	end, "Did the server script fail to start?")
end)

test("the server refuses to boot twice", function()
	local world, server = bootServer()
	expect.throws(function()
		server.load(SERVER_MAIN)
	end, "called twice")
	expect.truthy(world.find("ReplicatedStorage.Remotes"))
end)
