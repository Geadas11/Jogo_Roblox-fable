-- The night's strange events (EventManager), player settings (SettingsService) and the
-- single-player request (MatchService), on the real map through the real server and
-- client code. Carts are not tested here: the simulated engine has no models to clone.

local SERVER_MAIN = "ServerScriptService.Server.Main"
local CLIENT_MAIN = "StarterPlayer.StarterPlayerScripts.Client.Main"
local SERVICES = "ServerScriptService.Server.Services."
local CONTROLLERS = "StarterPlayer.StarterPlayerScripts.Client.Controllers."

local function boot()
	local world = Engine.new({ map = true })
	local server = world.side("server")
	server.load(SERVER_MAIN)
	return {
		world = world,
		server = server,
		config = server.load("ReplicatedStorage.Shared.Config.GameConfig"),
		eventConfig = server.load("ReplicatedStorage.Shared.Config.EventConfig"),
		shift = server.load(SERVICES .. "ShiftManager"),
		events = server.load(SERVICES .. "EventManager"),
		game = server.load(SERVICES .. "GameManager"),
	}
end

local function join(s, name, userId)
	local player = s.world.addPlayer(name, userId)
	s.world.spawnCharacter(player, 2)
	local client = s.world.side("client", player)
	client.load(CLIENT_MAIN)
	return player, client
end

local function startShift(s, player)
	task.wait(0.3)
	local clock = s.world.getService("CollectionService"):GetTagged("TimeClock")[1]
	s.world.moveTo(player, clock)
	s.world.trigger(clock:FindFirstChildOfClass("ProximityPrompt"), player)
end

-- In the middle of aisle 3, looking north along it.
local function standInAisle(s, player)
	local roblox = require("@lune/roblox")
	player.Character.HumanoidRootPart.CFrame =
		roblox.CFrame.lookAt(roblox.Vector3.new(-23, 3, 40), roblox.Vector3.new(-23, 3, -20))
end

test("nothing strange happens outside the shift", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	expect.falsy(s.events.Trigger("Flicker", player), "an event in the lobby")
end)

test("every event runs on the real map without errors, and clients receive it", function()
	local s = boot()
	local player, client = join(s, "Tester", 1)
	startShift(s, player)
	standInAisle(s, player)

	local received = {}
	client.load("StarterPlayer.StarterPlayerScripts.Client.Net").On("HorrorEvent", function(kind)
		table.insert(received, kind)
	end)

	local happened = {}
	for name in s.eventConfig.Events do
		if name ~= "CartRoll" and s.events.Trigger(name, player) then
			table.insert(happened, name)
		end
	end
	task.wait(0.1)
	table.sort(happened)
	-- Standing in a stocked aisle every one of these has somewhere to happen.
	for _, name in { "Announcement", "Blackout", "Flicker", "Footsteps", "ItemFall", "Knock", "Silhouette" } do
		expect.truthy(table.find(happened, name), name .. " did not happen")
	end
	expect.truthy(#received >= 6, "clients were told about " .. #received .. " events")
	expect.equal(#s.world.lines("warn"), 0, "warnings: " .. table.concat(s.world.lines("warn"), " | "))
end)

test("the intercom shows its line on the HUD", function()
	local s = boot()
	local player, client = join(s, "Tester", 1)
	startShift(s, player)
	s.world.now += s.config.Shift.HourDurationSeconds * 2
	s.shift.Update()
	expect.truthy(s.events.Trigger("Announcement", player))
	task.wait(0.1)
	expect.equal(player.PlayerGui.HUD.Announcement.Visible, true)
	local _ = client
end)

test("a whole night of scheduled events runs without warnings", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	startShift(s, player)
	standInAisle(s, player)
	for _ = 1, 6 do
		s.world.now += s.config.Shift.HourDurationSeconds / 4
		s.events.Update()
		s.world.now += s.config.Shift.HourDurationSeconds * 3 / 4
		s.shift.Update()
	end
	expect.equal(#s.world.lines("warn"), 0, "warnings: " .. table.concat(s.world.lines("warn"), " | "))
end)

-- Settings ----------------------------------------------------------------------------------

test("settings start at their defaults and a change reaches the server", function()
	local s = boot()
	local player, client = join(s, "Tester", 1)
	task.wait(0.1)
	expect.equal(player:GetAttribute("Setting_MusicVolume"), 0.8)
	local settings = client.load("StarterPlayer.StarterPlayerScripts.Client.Settings")
	-- What Settings.Set sends; the client then follows the saved value back.
	s.world.fireServerAs(player, "SetSetting", "MusicVolume", 0.25)
	task.wait(0.05)
	expect.equal(player:GetAttribute("Setting_MusicVolume"), 0.25)
	expect.equal(settings.Get("MusicVolume"), 0.25)
end)

test("forged settings are refused", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	task.wait(0.1)
	s.world.fireServerAs(player, "SetSetting", "MusicVolume", 50)
	s.world.fireServerAs(player, "SetSetting", "Money", 1)
	s.world.fireServerAs(player, "SetSetting", "MusicVolume", 0 / 0)
	expect.equal(player:GetAttribute("Setting_MusicVolume"), 0.8)
	expect.equal(player:GetAttribute("Setting_Money"), nil)
end)

-- Menu ----------------------------------------------------------------------------------------

test("the menu opens with the warning and hides the HUD until a mode is chosen", function()
	local s = boot()
	local player, client = join(s, "Tester", 1)
	task.wait(0.1)
	expect.equal(player.PlayerGui.Menu.Warning.Visible, true)
	expect.equal(player.PlayerGui.HUD.Enabled, false)
	expect.truthy(client.load(CONTROLLERS .. "MenuController").IsOpen())
end)

test("asking to play alone while alone keeps the player here", function()
	local s = boot()
	local player = join(s, "Tester", 1)
	local match = s.server.load(SERVICES .. "MatchService")
	expect.truthy(match.PlaySolo(player))
	expect.equal(#s.world.lines("warn"), 0)
end)
