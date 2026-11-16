-- Carrying, tools and tasks on the real map, through the real server and client code.

local SERVER_MAIN = "ServerScriptService.Server.Main"
local CLIENT_MAIN = "StarterPlayer.StarterPlayerScripts.Client.Main"
local SERVICES = "ServerScriptService.Server.Services."

local function boot()
	local world = Engine.new({ map = true })
	local server = world.side("server")
	server.load(SERVER_MAIN)
	return world, server, server.load(SERVICES .. "TaskManager")
end

local function join(world, name, userId)
	local player = world.addPlayer(name, userId)
	world.spawnCharacter(player, 2)
	world.side("client", player).load(CLIENT_MAIN)
	return player
end

local function tagged(world, tag)
	return world.getService("CollectionService"):GetTagged(tag)
end

local function promptOf(instance)
	return instance:FindFirstChildOfClass("ProximityPrompt")
end

local function named(world, name)
	local found = {}
	for _, child in world.getService("Workspace"):GetChildren() do
		if child.Name == name then
			table.insert(found, child)
		end
	end
	return found
end

-- Walks up to something and triggers its prompt, respecting the interaction cooldown.
local function use(world, player, instance)
	task.wait(0.3)
	world.moveTo(player, instance)
	world.trigger(promptOf(instance), player)
end

local function emptyBays(world)
	local bays = {}
	for _, bay in tagged(world, "ShelfBay") do
		if bay:GetAttribute("Stocked") == false then
			table.insert(bays, bay)
		end
	end
	return bays
end

local function productsVisible(bay)
	for _, child in bay:GetChildren() do
		if child:IsA("BasePart") and child.Name ~= "Anchor" and child.Transparency ~= 0 then
			return false
		end
	end
	return true
end

local function lastNotification(player)
	local last
	for _, child in player.PlayerGui.HUD.Notifications:GetChildren() do
		if child.Name == "Notification" then
			last = child
		end
	end
	return last and last.Text or ""
end

local function objectives(player)
	local rows = {}
	for _, child in player.PlayerGui.HUD.Objectives:GetChildren() do
		if child.Name == "Task" then
			table.insert(rows, child.Title.Text)
		end
	end
	return rows
end

-- Carrying -------------------------------------------------------------------------------

test("mops stand by the bucket in the maintenance room", function()
	local world, server = boot()
	local config = server.load("ReplicatedStorage.Shared.Config.GameConfig")
	local mops = named(world, "Mop")
	expect.equal(#mops, config.Carry.MopCount)
	for _, mop in mops do
		expect.truthy(promptOf(mop), "mop has a pick-up prompt")
		expect.truthy(
			mop.Position.X > 10 and mop.Position.X < 40 and mop.Position.Z > -58 and mop.Position.Z < -30,
			"inside Maintenance"
		)
	end
end)

test("a player picks one thing up, cannot take a second, and can drop it", function()
	local world = boot()
	local player = join(world, "Tester", 1)
	local mops = named(world, "Mop")

	use(world, player, mops[1])
	expect.equal(player:GetAttribute("Carrying"), "Mop")
	expect.equal(mops[1].Anchored, false)
	expect.equal(promptOf(mops[1]).Enabled, false)
	expect.truthy(mops[1]:FindFirstChildOfClass("WeldConstraint"), "welded to the player")
	local hud = player.PlayerGui.HUD
	expect.equal(hud.Carrying.Visible, true)
	expect.equal(hud.Carrying.Label.Text, "Carrying: Mop")

	use(world, player, mops[2])
	expect.equal(mops[2]:GetAttribute("CarriedBy"), nil)
	expect.truthy(string.find(lastNotification(player), "hands are full", 1, true))

	world.moveTo(player, 60, 3, 20)
	world.fireServerAs(player, "DropItem")
	expect.equal(player:GetAttribute("Carrying"), "")
	expect.equal(hud.Carrying.Visible, false)
	expect.equal(mops[1].Anchored, true)
	expect.equal(mops[1]:FindFirstChildOfClass("WeldConstraint"), nil)
	expect.equal(promptOf(mops[1]).Enabled, true)
	-- Set down on the floor near the player, not left behind.
	local offset = mops[1].Position - player.Character.HumanoidRootPart.Position
	expect.truthy(math.abs(offset.X) < 5 and math.abs(offset.Z) < 5, "dropped next to the player")
	expect.truthy(math.abs(mops[1].Position.Y - 2.5) < 0.01, "standing on the floor")
end)

test("an item cannot be picked up from far away or by two players", function()
	local world = boot()
	local first = join(world, "First", 1)
	local second = join(world, "Second", 2)
	local mop = named(world, "Mop")[1]

	world.moveTo(first, -90, 3, -5)
	world.trigger(promptOf(mop), first)
	expect.equal(first:GetAttribute("Carrying"), "")

	use(world, first, mop)
	world.moveTo(second, mop)
	world.trigger(promptOf(mop), second)
	expect.equal(first:GetAttribute("Carrying"), "Mop")
	expect.equal(second:GetAttribute("Carrying"), "")
end)

test("what a leaving or dying player holds stays in the world for others", function()
	local world = boot()
	local leaver = join(world, "Leaver", 1)
	local other = join(world, "Other", 2)
	local mops = named(world, "Mop")

	use(world, leaver, mops[1])
	world.removePlayer(leaver)
	expect.equal(mops[1].Anchored, true)
	expect.equal(mops[1]:GetAttribute("CarriedBy"), nil)
	expect.truthy(mops[1].Parent, "still exists")

	use(world, other, mops[1])
	expect.equal(other:GetAttribute("Carrying"), "Mop")

	-- The character is removed (death / respawn): the mop is left where it was.
	other.CharacterRemoving:_fire(other.Character)
	expect.equal(other:GetAttribute("Carrying"), "")
	expect.equal(mops[1].Anchored, true)
end)

test("dropping with empty hands, repeatedly, does nothing harmful", function()
	local world = boot()
	local player = join(world, "Tester", 1)
	for _ = 1, 30 do
		world.fireServerAs(player, "DropItem")
	end
	expect.equal(player:GetAttribute("Carrying"), "")
end)

-- Restock --------------------------------------------------------------------------------

test("restocking: empty shelves, boxes in storage, carried one at a time", function()
	local world, _, taskManager = boot()
	local player = join(world, "Tester", 1)

	expect.truthy(taskManager.Issue("Restock", 2))
	local bays = emptyBays(world)
	local boxes = named(world, "StockBox")
	expect.equal(#bays, 2)
	expect.equal(#boxes, 2)
	expect.falsy(productsVisible(bays[1]))
	for _, box in boxes do
		expect.truthy(box.Position.Z < -30 and box.Position.X < 10, "box is in the storage room")
		expect.truthy(math.abs(box.Position.Y - 0.9) < 0.01, "box sits on the floor")
	end

	-- No box in hand: told what to do, nothing changes.
	use(world, player, bays[1].Anchor)
	expect.equal(bays[1]:GetAttribute("Stocked"), false)
	expect.truthy(string.find(lastNotification(player), "need a stock box", 1, true))

	use(world, player, boxes[1])
	expect.equal(player:GetAttribute("Carrying"), "StockBox")
	use(world, player, bays[1].Anchor)
	expect.equal(bays[1]:GetAttribute("Stocked"), true)
	expect.truthy(productsVisible(bays[1]))
	expect.equal(player:GetAttribute("Carrying"), "")
	expect.equal(boxes[1].Parent, nil, "the box was used up")
	expect.equal(promptOf(bays[1].Anchor), nil, "the restock prompt is gone")

	local snapshot = taskManager.GetSnapshot()
	expect.equal(snapshot[1].Progress, 1)
	expect.equal(snapshot[1].Goal, 2)
	expect.falsy(snapshot[1].Completed)
	expect.equal(objectives(player)[1], "Restock shelves   1/2")

	use(world, player, boxes[2])
	use(world, player, bays[2].Anchor)
	snapshot = taskManager.GetSnapshot()
	expect.truthy(snapshot[1].Completed)
	local completed, total, earned = taskManager.GetStats()
	expect.equal(completed, 1)
	expect.equal(total, 1)
	expect.equal(earned, 60)
	expect.truthy(string.find(lastNotification(player), "Task complete: Restock shelves  +$60", 1, true))
end)

test("a shelf cannot be restocked from far away, with a mop, or twice", function()
	local world, _, taskManager = boot()
	local player = join(world, "Tester", 1)
	taskManager.Issue("Restock", 1)
	local bay = emptyBays(world)[1]
	local prompt = promptOf(bay.Anchor)
	local box = named(world, "StockBox")[1]

	-- Holding the wrong thing.
	use(world, player, named(world, "Mop")[1])
	use(world, player, bay.Anchor)
	expect.equal(bay:GetAttribute("Stocked"), false)
	world.fireServerAs(player, "DropItem")

	-- Holding a box, but nowhere near the shelf.
	use(world, player, box)
	world.moveTo(player, 60, 3, 150)
	task.wait(0.3)
	world.trigger(prompt, player)
	expect.equal(bay:GetAttribute("Stocked"), false)
	expect.equal(player:GetAttribute("Carrying"), "StockBox")

	-- Properly, then again: the reward is paid once.
	use(world, player, bay.Anchor)
	task.wait(0.3)
	world.trigger(prompt, player)
	local completed, _, earned = taskManager.GetStats()
	expect.equal(completed, 1)
	expect.equal(earned, 30)
end)

-- Spills ---------------------------------------------------------------------------------

test("spills need a mop, and the mop is kept afterwards", function()
	local world, _, taskManager = boot()
	local player = join(world, "Tester", 1)
	expect.truthy(taskManager.Issue("CleanSpills", 2))
	local spills = named(world, "Spill")
	expect.equal(#spills, 2)

	use(world, player, spills[1])
	expect.truthy(spills[1].Parent, "still there without a mop")
	expect.truthy(string.find(lastNotification(player), "need a mop", 1, true))

	use(world, player, named(world, "Mop")[1])
	use(world, player, spills[1])
	expect.equal(spills[1].Parent, nil)
	expect.equal(player:GetAttribute("Carrying"), "Mop")
	expect.equal(taskManager.GetSnapshot()[1].Progress, 1)

	use(world, player, spills[2])
	expect.truthy(taskManager.GetSnapshot()[1].Completed)
	expect.equal(#named(world, "Spill"), 0)
end)

test("two spill tasks never share a spot", function()
	local world, _, taskManager = boot()
	taskManager.Issue("CleanSpills", 8)
	taskManager.Issue("CleanSpills", 8)
	local seen = {}
	for _, spill in named(world, "Spill") do
		local key = string.format("%.1f,%.1f", spill.Position.X, spill.Position.Z)
		expect.falsy(seen[key], "two spills at " .. key)
		seen[key] = true
	end
	expect.equal(#named(world, "Spill"), 16)
end)

-- Coolers --------------------------------------------------------------------------------

test("coolers to check show a warning light until inspected", function()
	local world, _, taskManager = boot()
	local player = join(world, "Tester", 1)
	expect.truthy(taskManager.Issue("InspectCoolers", 3))

	local flagged = {}
	for _, unit in tagged(world, "FridgeUnit") do
		local anchor = if unit:IsA("BasePart") then unit else unit:FindFirstChild("Anchor")
		if anchor and anchor:FindFirstChild("WarningLight") then
			table.insert(flagged, anchor)
		end
	end
	expect.equal(#flagged, 3)

	world.moveTo(player, -90, 3, -5)
	world.trigger(promptOf(flagged[1]), player)
	expect.equal(taskManager.GetSnapshot()[1].Progress, 0)

	for _, anchor in flagged do
		use(world, player, anchor)
		expect.equal(anchor:FindFirstChild("WarningLight"), nil)
	end
	expect.truthy(taskManager.GetSnapshot()[1].Completed)
end)

-- The night ------------------------------------------------------------------------------

local function clockIn(world, player)
	use(world, player, tagged(world, "TimeClock")[1])
end

test("tasks are handed out when the shift starts and every hour after", function()
	local world, server, taskManager = boot()
	local config = server.load("ReplicatedStorage.Shared.Config.GameConfig")
	local definitions = server.load("ReplicatedStorage.Shared.Config.TaskDefinitions")
	local shift = server.load(SERVICES .. "ShiftManager")
	local player = join(world, "Tester", 1)

	expect.equal(#taskManager.GetSnapshot(), 0)
	clockIn(world, player)
	local first = taskManager.GetSnapshot()
	expect.equal(#first, definitions.TasksPerHour)
	for _, task in first do
		expect.truthy(task.Goal > 0, task.Title .. " has work to do")
		expect.truthy(task.Detail ~= "", task.Title .. " says where")
	end
	expect.equal(#objectives(player), definitions.TasksPerHour)
	expect.truthy(first[1].Title ~= first[2].Title, "two different kinds of work")

	-- Next hour: more work, but never a second copy of a type that is still unfinished.
	world.now += config.Shift.HourDurationSeconds
	shift.Update()
	local active = {}
	for _, task in taskManager.GetSnapshot() do
		if not task.Completed then
			expect.falsy(active[task.Title], "duplicate active task " .. task.Title)
			active[task.Title] = true
		end
	end
	expect.truthy(#taskManager.GetSnapshot() > #first)
end)

test("more players means more work per task", function()
	local world, _, taskManager = boot()
	local players = {}
	for index = 1, 5 do
		players[index] = join(world, "Player" .. index, index)
	end
	clockIn(world, players[1])
	local solo = Engine.new({ map = true })
	solo.side("server").load(SERVER_MAIN)
	-- With five players every task has at least Min + 2 units.
	local definitions = world.side("server").load("ReplicatedStorage.Shared.Config.TaskDefinitions")
	for _, task in taskManager.GetSnapshot() do
		local minimum = math.huge
		for _, definition in definitions.Types do
			if definition.Title == task.Title then
				minimum = definition.Min
			end
		end
		expect.truthy(task.Goal >= minimum + 2, task.Title .. " scaled up")
	end
end)

test("the end of the shift reports the work done and puts the store back in order", function()
	local world, server, taskManager = boot()
	local config = server.load("ReplicatedStorage.Shared.Config.GameConfig")
	local shift = server.load(SERVICES .. "ShiftManager")
	local gameManager = server.load(SERVICES .. "GameManager")
	local player = join(world, "Tester", 1)
	clockIn(world, player)

	-- Make sure there is one of each kind of leftover, and finish exactly one task.
	taskManager.Issue("Restock", 2)
	taskManager.Issue("CleanSpills", 2)
	taskManager.Issue("InspectCoolers", 1)
	local snapshot = taskManager.GetSnapshot()
	local inspectAnchor
	for _, unit in tagged(world, "FridgeUnit") do
		local anchor = if unit:IsA("BasePart") then unit else unit:FindFirstChild("Anchor")
		if anchor and anchor:FindFirstChild("WarningLight") then
			inspectAnchor = anchor
		end
	end
	-- Carry a box into the results screen: it must not survive the cleanup.
	local boxes = named(world, "StockBox")
	if #boxes > 0 then
		use(world, player, boxes[1])
	end

	world.now += config.Shift.HourDurationSeconds * config.Shift.Hours
	shift.Update()

	local completed, total, earned = taskManager.GetStats()
	local body = player.PlayerGui.HUD.Results.Body.Text
	expect.truthy(
		string.find(body, string.format("Tasks completed: %d of %d", completed, total), 1, true),
		body
	)
	expect.truthy(string.find(body, string.format("Earned: $%d", earned), 1, true), body)
	expect.truthy(total >= #snapshot)

	expect.equal(#emptyBays(world), 0, "shelves restocked")
	expect.equal(#named(world, "StockBox"), 0, "boxes removed")
	expect.equal(#named(world, "Spill"), 0, "spills removed")
	expect.equal(player:GetAttribute("Carrying"), "", "nothing left in hand")
	expect.truthy(
		inspectAnchor == nil or inspectAnchor:FindFirstChild("WarningLight") == nil,
		"warning lights removed"
	)
	expect.equal(#named(world, "Mop"), config.Carry.MopCount, "tools are kept")

	gameManager.ReturnToLobby()
	expect.equal(#taskManager.GetSnapshot(), 0)
	expect.equal(#objectives(player), 0)
	expect.equal(#world.lines("warn"), 0, "warnings: " .. table.concat(world.lines("warn"), " | "))
end)

test("a player who joins mid-shift receives the current objectives", function()
	local world, _, taskManager = boot()
	local first = join(world, "First", 1)
	clockIn(world, first)
	local late = join(world, "Late", 2)
	expect.equal(#objectives(late), #taskManager.GetSnapshot())
	expect.truthy(#objectives(late) > 0)
end)

test("asking for the objectives too often is refused", function()
	local world = boot()
	local player = join(world, "Spammer", 1)
	local refused = 0
	for _ = 1, 20 do
		local ok = world.invokeServerAs(player, "GetTasks")
		if ok == false then
			refused += 1
		end
	end
	expect.truthy(refused >= 15, "refused " .. refused .. " of 20")
	expect.equal(world.invokeServerAs(player, "GetTasks", "unexpected"), false)
end)

-- More kinds of work ---------------------------------------------------------------------

test("registers are cashed up one by one", function()
	local world, _, taskManager = boot()
	local player = join(world, "Tester", 1)
	expect.truthy(taskManager.Issue("CloseRegisters", 2))

	local flagged = {}
	for _, register in tagged(world, "CheckoutRegister") do
		if register:FindFirstChild("WarningLight") then
			table.insert(flagged, register)
		end
	end
	expect.equal(#flagged, 2)
	expect.equal(promptOf(flagged[1]).ActionText, "Cash up")
	expect.equal(taskManager.GetSnapshot()[1].Title, "Cash up the registers")

	use(world, player, flagged[1])
	use(world, player, flagged[2])
	expect.truthy(taskManager.GetSnapshot()[1].Completed)
	expect.equal(flagged[2]:FindFirstChild("WarningLight"), nil)
	expect.equal(promptOf(flagged[2]), nil)
end)

test("coolers and registers can be checked in the same hour without clashing", function()
	local world, _, taskManager = boot()
	expect.truthy(taskManager.Issue("InspectCoolers", 3))
	expect.truthy(taskManager.Issue("CloseRegisters", 4))
	local coolers, registers = 0, 0
	for _, unit in tagged(world, "FridgeUnit") do
		local anchor = if unit:IsA("BasePart") then unit else unit:FindFirstChild("Anchor")
		if anchor and anchor:FindFirstChild("WarningLight") then
			coolers += 1
		end
	end
	for _, register in tagged(world, "CheckoutRegister") do
		if register:FindFirstChild("WarningLight") then
			registers += 1
		end
	end
	expect.equal(coolers, 3)
	expect.equal(registers, 4)
end)

test("trash bags are carried to the dumpsters behind the store", function()
	local world, _, taskManager = boot()
	local player = join(world, "Tester", 1)
	expect.truthy(taskManager.Issue("CollectTrash", 2))
	-- One trash run at a time.
	expect.falsy(taskManager.Issue("CollectTrash", 2))

	local bags = named(world, "TrashBag")
	local dumpsters = tagged(world, "Dumpster")
	expect.equal(#bags, 2)
	expect.equal(#dumpsters, 2)
	for _, dumpster in dumpsters do
		expect.truthy(dumpster.Position.Z < -80, "dumpsters are outside, behind the building")
		expect.equal(promptOf(dumpster).ActionText, "Throw away")
	end

	-- Empty-handed at the dumpster.
	use(world, player, dumpsters[1])
	expect.equal(taskManager.GetSnapshot()[1].Progress, 0)
	expect.truthy(string.find(lastNotification(player), "not carrying a trash bag", 1, true))

	use(world, player, bags[1])
	expect.equal(player:GetAttribute("Carrying"), "Trash")
	expect.equal(player.PlayerGui.HUD.Carrying.Label.Text, "Carrying: Trash bag")
	use(world, player, dumpsters[1])
	expect.equal(bags[1].Parent, nil)
	expect.equal(taskManager.GetSnapshot()[1].Progress, 1)

	use(world, player, bags[2])
	use(world, player, dumpsters[2])
	expect.truthy(taskManager.GetSnapshot()[1].Completed)
	-- The work is done: the dumpsters stop offering the action.
	for _, dumpster in dumpsters do
		expect.equal(promptOf(dumpster), nil)
	end
	-- And another run can be handed out later.
	expect.truthy(taskManager.Issue("CollectTrash", 1))
end)

test("every task type in the catalogue can actually be issued on this map", function()
	local world, server, taskManager = boot()
	local definitions = server.load("ReplicatedStorage.Shared.Config.TaskDefinitions")
	local count = 0
	for typeName, definition in definitions.Types do
		count += 1
		expect.truthy(taskManager.Issue(typeName, definition.Max), typeName .. " could not be issued")
	end
	expect.equal(#taskManager.GetSnapshot(), count)
	for _, task in taskManager.GetSnapshot() do
		expect.truthy(task.Goal > 0, task.Title)
		expect.truthy(task.Detail ~= "", task.Title .. " has no hint")
	end
	expect.equal(#world.lines("warn"), 0, "warnings: " .. table.concat(world.lines("warn"), " | "))
end)
