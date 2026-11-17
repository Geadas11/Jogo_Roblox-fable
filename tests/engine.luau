--[[
	A deliberately small stand-in for the Roblox engine, so project code can be executed
	outside Studio with Lune.

	What it is good for: catching Luau runtime mistakes (nil indexing, wrong argument
	order, typos, broken boot order) and exercising pure logic and server-side validation.

	What it is NOT: Roblox. It does not simulate physics, rendering, replication delay,
	remote argument serialisation, or the real behaviour of any service. A green run here
	never replaces testing in Studio.

	The instance tree comes from `rojo sourcemap`, so it is exactly the tree Rojo creates.
	The fake is strict: reading a member it does not know raises an error, like Roblox does.
]]

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local task = require("@lune/task")

local builtinTypeof = typeof

-- Just enough class hierarchy for the IsA calls the project makes.
local SUPERCLASS = {
	Part = "BasePart",
	MeshPart = "BasePart",
	SpawnLocation = "Part",
	TextLabel = "GuiObject",
	TextButton = "GuiObject",
	Frame = "GuiObject",
	BasePart = "PVInstance",
	Model = "PVInstance",
	BloomEffect = "PostEffect",
	ColorCorrectionEffect = "PostEffect",
	DepthOfFieldEffect = "PostEffect",
	SunRaysEffect = "PostEffect",
	Script = "LuaSourceContainer",
	LocalScript = "LuaSourceContainer",
	ModuleScript = "LuaSourceContainer",
}

-- Signals that exist on every instance, and per class.
local COMMON_SIGNALS = { DescendantAdded = true, ChildAdded = true }
local CLASS_SIGNALS = {
	RemoteEvent = { OnServerEvent = true, OnClientEvent = true },
	Players = { PlayerAdded = true, PlayerRemoving = true },
	Player = { CharacterAdded = true, CharacterRemoving = true },
	DataModel = { Loaded = true },
	ProximityPrompt = { Triggered = true },
	TextButton = { Activated = true },
	Humanoid = { Died = true },
	UserInputService = { InputBegan = true },
}

-- Property values an instance has before anything sets them (only those the project reads).
local DEFAULTS = {
	ProximityPrompt = { Enabled = true },
	Humanoid = { Health = 100 },
	Frame = { Visible = true },
	TextLabel = { Visible = true, Text = "" },
	TextButton = { Visible = true, Text = "" },
}

-- Properties that legitimately read as nil.
local NULLABLE = { Character = true, LocalPlayer = true, OnServerInvoke = true, PrimaryPart = true }

-- The real generated map, built once per process and mirrored into each world that asks
-- for it. Game code then runs against the same tags and attributes it will find in Studio.
local builtMap = nil
local builtGrids = nil
local function getBuiltMap()
	if not builtMap then
		local Map = require("../map/Map")
		local Layout = require("../map/Layout")
		local Grids = require("../tools/grids")
		local scratch = roblox.Instance.new("DataModel")
		local kit, root = Map.build(scratch:GetService("Workspace"))
		builtMap = root
		builtGrids = Grids.compute(kit.records, Layout.Grounds)
	end
	return builtMap, builtGrids
end

local Engine = {}

-- The navigation and sight grids of the generated map, as the build bakes them.
function Engine.grids()
	local _, grids = getBuiltMap()
	return grids
end

-- Fake RBXScriptSignal --------------------------------------------------------------

local function newSignal()
	local connections = {}
	local signal = { __fakeSignal = true }

	function signal:Connect(handler)
		local connection = { Connected = true, __fakeConnection = true }
		function connection:Disconnect()
			if not connection.Connected then
				return
			end
			connection.Connected = false
			local index = table.find(connections, connection)
			if index then
				table.remove(connections, index)
			end
		end
		connection._handler = handler
		table.insert(connections, connection)
		return connection
	end

	function signal:Once(handler)
		local connection
		connection = signal:Connect(function(...)
			connection:Disconnect()
			handler(...)
		end)
		return connection
	end

	function signal:Wait()
		local thread = coroutine.running()
		signal:Once(function(...)
			task.spawn(thread, ...)
		end)
		return coroutine.yield()
	end

	function signal:_fire(...)
		for _, connection in table.clone(connections) do
			if connection.Connected then
				task.spawn(connection._handler, ...)
			end
		end
	end

	return signal
end

-- World -----------------------------------------------------------------------------

-- options.map = true  mirrors the generated supermarket into Workspace.
function Engine.new(options)
	options = options or {}
	local world = {}

	-- The synchronised clock returned by Workspace:GetServerTimeNow(). Tests move it.
	world.now = 1000

	-- Everything printed by project code: { side, level, text }.
	world.output = {}
	-- Calls made to PhysicsService, for assertions.
	world.collisionGroups = {}
	world.nonCollidingPairs = {}
	-- The player whose client is "running" when a remote is fired from client code.
	world.localPlayer = nil

	local instanceMeta = {}
	local methods = {}

	local function newInstance(className, name)
		local instance = setmetatable({}, instanceMeta)
		rawset(instance, "_class", className)
		rawset(instance, "_name", name or className)
		rawset(instance, "_children", {})
		rawset(instance, "_props", table.clone(DEFAULTS[className] or {}))
		rawset(instance, "_attributes", {})
		rawset(instance, "_signals", {})
		rawset(instance, "_attributeSignals", {})
		return instance
	end

	local function isFake(value)
		return type(value) == "table" and getmetatable(value) == instanceMeta
	end

	local function fakeTypeof(value)
		if isFake(value) then
			return "Instance"
		end
		if type(value) == "table" then
			if rawget(value, "__fakeConnection") then
				return "RBXScriptConnection"
			elseif rawget(value, "__fakeSignal") then
				return "RBXScriptSignal"
			end
		end
		return builtinTypeof(value)
	end

	local function getSignal(instance, name)
		local signals = rawget(instance, "_signals")
		if not signals[name] then
			signals[name] = newSignal()
		end
		return signals[name]
	end

	local function isA(className, target)
		local current = className
		while current do
			if current == target then
				return true
			end
			current = SUPERCLASS[current]
		end
		return target == "Instance"
	end

	local function setParent(instance, parent)
		local old = rawget(instance, "_parent")
		if old == parent then
			return
		end
		if old then
			local siblings = rawget(old, "_children")
			local index = table.find(siblings, instance)
			if index then
				table.remove(siblings, index)
			end
		end
		rawset(instance, "_parent", parent)
		if parent then
			table.insert(rawget(parent, "_children"), instance)
			getSignal(parent, "ChildAdded"):_fire(instance)
			-- The instance and everything under it are new descendants of every ancestor.
			local added = { instance }
			for _, descendant in methods.GetDescendants(instance) do
				table.insert(added, descendant)
			end
			local ancestor = parent
			while ancestor do
				for _, descendant in added do
					getSignal(ancestor, "DescendantAdded"):_fire(descendant)
				end
				ancestor = rawget(ancestor, "_parent")
			end
		end
	end

	function instanceMeta.__index(instance, key)
		if key == "Name" then
			return rawget(instance, "_name")
		elseif key == "ClassName" then
			return rawget(instance, "_class")
		elseif key == "Parent" then
			return rawget(instance, "_parent")
		elseif key == "Position" then
			-- Parts derive Position from CFrame; GUI objects store their own.
			local props = rawget(instance, "_props")
			if props.Position ~= nil then
				return props.Position
			elseif props.CFrame then
				return props.CFrame.Position
			end
		end

		local method = methods[key]
		if method then
			return method
		end

		local className = rawget(instance, "_class")
		local classSignals = CLASS_SIGNALS[className]
		if COMMON_SIGNALS[key] or (classSignals and classSignals[key]) then
			return getSignal(instance, key)
		end

		local value = rawget(instance, "_props")[key]
		if value ~= nil then
			return value
		end

		for _, child in rawget(instance, "_children") do
			if rawget(child, "_name") == key then
				return child
			end
		end

		if NULLABLE[key] then
			return nil
		end
		error(
			string.format(
				"%s is not a valid member of %s %q",
				tostring(key),
				className,
				methods.GetFullName(instance)
			),
			2
		)
	end

	function instanceMeta.__newindex(instance, key, value)
		if key == "Name" then
			rawset(instance, "_name", value)
		elseif key == "Parent" then
			setParent(instance, value)
		elseif key == "Position" and builtinTypeof(value) == "Vector3" then
			rawget(instance, "_props").CFrame = roblox.CFrame.new(value)
		else
			rawget(instance, "_props")[key] = value
		end
	end

	function instanceMeta.__tostring(instance)
		return rawget(instance, "_name")
	end

	function methods.FindFirstChild(instance, name)
		for _, child in rawget(instance, "_children") do
			if rawget(child, "_name") == name then
				return child
			end
		end
		return nil
	end

	function methods.FindFirstChildOfClass(instance, className)
		for _, child in rawget(instance, "_children") do
			if rawget(child, "_class") == className then
				return child
			end
		end
		return nil
	end

	-- Nothing replicates late in the fake: a child is either there or it never will be.
	function methods.WaitForChild(instance, name, timeout)
		local child = methods.FindFirstChild(instance, name)
		if not child and timeout == nil then
			error(
				string.format(
					"Infinite yield possible on %s:WaitForChild(%q)",
					methods.GetFullName(instance),
					name
				),
				2
			)
		end
		return child
	end

	function methods.GetChildren(instance)
		return table.clone(rawget(instance, "_children"))
	end

	function methods.GetDescendants(instance)
		local result = {}
		local function visit(node)
			for _, child in rawget(node, "_children") do
				table.insert(result, child)
				visit(child)
			end
		end
		visit(instance)
		return result
	end

	function methods.IsA(instance, className)
		return isA(rawget(instance, "_class"), className)
	end

	function methods.GetFullName(instance)
		local parts = {}
		local current = instance
		while current and rawget(current, "_class") ~= "DataModel" do
			table.insert(parts, 1, rawget(current, "_name"))
			current = rawget(current, "_parent")
		end
		return table.concat(parts, ".")
	end

	function methods.SetAttribute(instance, name, value)
		local attributes = rawget(instance, "_attributes")
		if attributes[name] == value then
			return
		end
		attributes[name] = value
		local signal = rawget(instance, "_attributeSignals")[name]
		if signal then
			signal:_fire()
		end
	end

	function methods.GetAttribute(instance, name)
		return rawget(instance, "_attributes")[name]
	end

	function methods.GetAttributeChangedSignal(instance, name)
		local signals = rawget(instance, "_attributeSignals")
		if not signals[name] then
			signals[name] = newSignal()
		end
		return signals[name]
	end

	function methods.Destroy(instance)
		setParent(instance, nil)
	end

	-- RemoteEvent ---------------------------------------------------------------
	function methods.FireServer(instance, ...)
		assert(rawget(instance, "_class") == "RemoteEvent", "FireServer on a non-RemoteEvent")
		assert(world.localPlayer, "FireServer called with no local player")
		getSignal(instance, "OnServerEvent"):_fire(world.localPlayer, ...)
	end

	function methods.FireClient(instance, _player, ...)
		assert(rawget(instance, "_class") == "RemoteEvent", "FireClient on a non-RemoteEvent")
		getSignal(instance, "OnClientEvent"):_fire(...)
	end

	function methods.FireAllClients(instance, ...)
		assert(rawget(instance, "_class") == "RemoteEvent", "FireAllClients on a non-RemoteEvent")
		getSignal(instance, "OnClientEvent"):_fire(...)
	end

	-- RemoteFunction ------------------------------------------------------------
	function methods.InvokeServer(instance, ...)
		assert(rawget(instance, "_class") == "RemoteFunction", "InvokeServer on a non-RemoteFunction")
		assert(world.localPlayer, "InvokeServer called with no local player")
		local callback = rawget(instance, "_props").OnServerInvoke
		assert(callback, "RemoteFunction has no OnServerInvoke")
		return callback(world.localPlayer, ...)
	end

	-- Tags ----------------------------------------------------------------------
	local tagSignals = {}

	function methods.AddTag(instance, tag)
		local tags = rawget(instance, "_tags")
		if not tags then
			tags = {}
			rawset(instance, "_tags", tags)
		end
		if not tags[tag] then
			tags[tag] = true
			if tagSignals[tag] then
				tagSignals[tag]:_fire(instance)
			end
		end
	end

	function methods.HasTag(instance, tag)
		local tags = rawget(instance, "_tags")
		return tags ~= nil and tags[tag] == true
	end

	function methods.GetTags(instance)
		local list = {}
		for tag in rawget(instance, "_tags") or {} do
			table.insert(list, tag)
		end
		return list
	end

	-- CollectionService
	function methods.GetTagged(_instance, tag)
		local found = {}
		for _, descendant in methods.GetDescendants(world.game) do
			if methods.HasTag(descendant, tag) then
				table.insert(found, descendant)
			end
		end
		return found
	end

	function methods.GetInstanceAddedSignal(_instance, tag)
		if not tagSignals[tag] then
			tagSignals[tag] = newSignal()
		end
		return tagSignals[tag]
	end

	-- Workspace
	function methods.GetServerTimeNow()
		return world.now
	end

	-- TweenService: a tween jumps straight to its goal when played.
	function methods.Create(_instance, target, _tweenInfo, goals)
		local tween = { Completed = newSignal() }
		function tween:Play()
			for property, value in goals do
				target[property] = value
			end
			tween.Completed:_fire()
		end
		function tween:Cancel() end
		return tween
	end

	-- Players -------------------------------------------------------------------
	function methods.GetPlayers(instance)
		local players = {}
		for _, child in rawget(instance, "_children") do
			if rawget(child, "_class") == "Player" then
				table.insert(players, child)
			end
		end
		return players
	end

	-- PhysicsService ------------------------------------------------------------
	function methods.IsCollisionGroupRegistered(_instance, name)
		return world.collisionGroups[name] == true
	end

	function methods.RegisterCollisionGroup(_instance, name)
		assert(not world.collisionGroups[name], "collision group registered twice: " .. name)
		world.collisionGroups[name] = true
	end

	function methods.CollisionGroupSetCollidable(_instance, a, b, collidable)
		assert(world.collisionGroups[a] and world.collisionGroups[b], "unregistered collision group")
		local key = if a < b then a .. "|" .. b else b .. "|" .. a
		world.nonCollidingPairs[key] = if collidable then nil else true
	end

	-- Tree from Rojo ------------------------------------------------------------

	local result = process.exec("rojo", { "sourcemap", "default.project.json", "--include-non-scripts" })
	if not result.ok then
		error("rojo sourcemap failed: " .. result.stderr)
	end
	local sourcemap = serde.decode("json", result.stdout)

	local function build(node, parent)
		local instance = newInstance(node.className, node.name)
		if node.filePaths then
			for _, path in node.filePaths do
				if string.match(path, "%.luau$") then
					rawset(instance, "_sourcePath", path)
				end
			end
		end
		if parent then
			rawset(instance, "_parent", parent)
			table.insert(rawget(parent, "_children"), instance)
		end
		for _, child in node.children or {} do
			build(child, instance)
		end
		return instance
	end

	local dataModel = build(sourcemap, nil)
	world.game = dataModel

	local function getService(className)
		local service = methods.FindFirstChildOfClass(dataModel, className)
		if not service then
			service = newInstance(className, className)
			setParent(service, dataModel)
		end
		return service
	end

	local players = getService("Players")
	players.MaxPlayers = 50
	getService("Lighting")
	getService("PhysicsService")
	local workspaceService = getService("Workspace")
	getService("CollectionService")
	getService("TweenService")

	-- Mirror of the generated map: names, classes, tags, attributes and the part
	-- properties game code reads.
	if options.map then
		local function mirror(source, parent)
			local copy = newInstance(source.ClassName, source.Name)
			for name, value in source:GetAttributes() do
				rawget(copy, "_attributes")[name] = value
			end
			for _, tag in source:GetTags() do
				methods.AddTag(copy, tag)
			end
			if source:IsA("BasePart") then
				local props = rawget(copy, "_props")
				props.CFrame = source.CFrame
				props.Size = source.Size
				props.Transparency = source.Transparency
				props.CanCollide = source.CanCollide
				props.Anchored = source.Anchored
			elseif source:IsA("Light") then
				local props = rawget(copy, "_props")
				props.Brightness = source.Brightness
				props.Enabled = source.Enabled
			end
			rawset(copy, "_parent", parent)
			table.insert(rawget(parent, "_children"), copy)
			for _, child in source:GetChildren() do
				mirror(child, copy)
			end
		end
		local map, grids = getBuiltMap()
		mirror(map, workspaceService)

		-- The baked grids live in ServerStorage, exactly as tools/build.luau stores them.
		local storage = getService("ServerStorage")
		local holder = newInstance("StringValue", "NavGrid")
		holder.Value = grids.Walk
		rawget(holder, "_attributes").OriginX = grids.OriginX
		rawget(holder, "_attributes").OriginZ = grids.OriginZ
		rawget(holder, "_attributes").Width = grids.Width
		rawget(holder, "_attributes").Depth = grids.Depth
		setParent(holder, storage)
		local sightHolder = newInstance("StringValue", "SightGrid")
		sightHolder.Value = grids.Sight
		setParent(sightHolder, storage)
	end

	world.newInstance = newInstance
	world.getService = getService

	function world.find(path)
		local current = dataModel
		for name in string.gmatch(path, "[^%.]+") do
			current = methods.FindFirstChild(current, name)
			if not current then
				error("no instance at " .. path)
			end
		end
		return current
	end

	-- Adds a player to the session and fires PlayerAdded.
	function world.addPlayer(name, userId)
		local player = newInstance("Player", name)
		player.UserId = userId
		setParent(newInstance("PlayerGui", "PlayerGui"), player)
		setParent(player, players)
		getSignal(players, "PlayerAdded"):_fire(player)
		return player
	end

	function world.removePlayer(player)
		getSignal(players, "PlayerRemoving"):_fire(player)
		setParent(player, nil)
	end

	-- Gives a player a character model with the given number of parts.
	function world.spawnCharacter(player, partCount)
		local character = newInstance("Model", rawget(player, "_name"))
		for index = 1, partCount or 3 do
			local part = newInstance("Part", "Part" .. index)
			part.CollisionGroup = "Default"
			setParent(part, character)
		end
		local root = newInstance("Part", "HumanoidRootPart")
		root.CollisionGroup = "Default"
		root.CFrame = roblox.CFrame.new(0, 3, 0)
		setParent(root, character)
		local humanoid = newInstance("Humanoid", "Humanoid")
		humanoid.Health = 100
		setParent(humanoid, character)
		setParent(character, getService("Workspace"))
		player.Character = character
		getSignal(player, "CharacterAdded"):_fire(character)
		return character
	end

	-- Puts a player's character at a position (or right next to an instance).
	function world.moveTo(player, x, y, z)
		local position = x
		if isFake(x) then
			position = x.Position
		elseif type(x) == "number" then
			position = roblox.Vector3.new(x, y, z)
		end
		player.Character.HumanoidRootPart.CFrame = roblox.CFrame.new(position)
	end

	-- Fires a ProximityPrompt as that player, wherever their character happens to be -
	-- which is also what an exploit can do.
	function world.trigger(prompt, player)
		assert(rawget(prompt, "_class") == "ProximityPrompt", "world.trigger expects a ProximityPrompt")
		getSignal(prompt, "Triggered"):_fire(player)
	end

	-- Sends a remote exactly as a (possibly hostile) client could: any arguments, no
	-- client-side checks.
	function world.fireServerAs(player, remoteName, ...)
		local remote = world.find("ReplicatedStorage.Remotes.Events." .. remoteName)
		getSignal(remote, "OnServerEvent"):_fire(player, ...)
	end

	function world.invokeServerAs(player, remoteName, ...)
		local remote = world.find("ReplicatedStorage.Remotes.Functions." .. remoteName)
		return rawget(remote, "_props").OnServerInvoke(player, ...)
	end

	-- Returns the text of every output line of one level ("print" or "warn").
	function world.lines(level)
		local lines = {}
		for _, entry in world.output do
			if entry.level == level then
				table.insert(lines, entry.text)
			end
		end
		return lines
	end

	-- A side ("server" or "client") has its own module cache and its own view of the
	-- side-dependent services, but shares the instance tree with the other side.
	function world.side(sideName, localPlayer)
		local side = {}
		local cache = {}
		local isServer = sideName == "server"

		local runService = newInstance("RunService", "RunService")
		rawset(runService, "_props", {
			IsServer = function()
				return isServer
			end,
			IsClient = function()
				return not isServer
			end,
			IsStudio = function()
				return true
			end,
		})

		-- Players as seen from this side: LocalPlayer only exists on a client.
		local playersView = setmetatable({}, {
			__index = function(_, key)
				if key == "LocalPlayer" then
					return if isServer then nil else localPlayer
				end
				local value = players[key]
				if type(value) == "function" then
					return function(_self, ...)
						return value(players, ...)
					end
				end
				return value
			end,
		})

		local gameView = setmetatable({}, {
			__index = function(_, key)
				if key == "GetService" then
					return function(_self, className)
						if className == "RunService" then
							return runService
						elseif className == "Players" then
							return playersView
						end
						return getService(className)
					end
				elseif key == "IsLoaded" then
					return function()
						return true
					end
				end
				return dataModel[key]
			end,
		})

		local function record(level)
			return function(...)
				local parts = {}
				for index = 1, select("#", ...) do
					parts[index] = tostring((select(index, ...)))
				end
				table.insert(
					world.output,
					{ side = sideName, level = level, text = table.concat(parts, " ") }
				)
			end
		end

		local function run(instance)
			local path = rawget(instance, "_sourcePath")
			assert(path, methods.GetFullName(instance) .. " has no source file")
			local environment = {
				script = instance,
				game = gameView,
				workspace = getService("Workspace"),
				typeof = fakeTypeof,
				task = task,
				print = record("print"),
				warn = record("warn"),
				Enum = roblox.Enum,
				Color3 = roblox.Color3,
				Vector3 = roblox.Vector3,
				Vector2 = roblox.Vector2,
				CFrame = roblox.CFrame,
				UDim = roblox.UDim,
				UDim2 = roblox.UDim2,
				Font = roblox.Font,
				TweenInfo = {
					new = function(...)
						return { ... }
					end,
				},
				Instance = {
					new = function(className)
						return newInstance(className, className)
					end,
				},
			}
			environment.require = function(target)
				assert(isFake(target), "require expects an instance")
				assert(rawget(target, "_class") == "ModuleScript", "require expects a ModuleScript")
				local cached = cache[target]
				if cached then
					return cached.value
				end
				local value = run(target)
				cache[target] = { value = value }
				return value
			end

			local chunk = luau.load(fs.readFile(path), {
				debugName = path,
				environment = environment,
			})

			local previous = world.localPlayer
			if not isServer then
				world.localPlayer = localPlayer
			end
			local results = table.pack(chunk())
			world.localPlayer = previous
			return table.unpack(results, 1, results.n)
		end

		-- Requires a ModuleScript (cached per side) or runs a Script / LocalScript.
		function side.load(path)
			local instance = world.find(path)
			if rawget(instance, "_class") == "ModuleScript" then
				local cached = cache[instance]
				if cached then
					return cached.value
				end
				local value = run(instance)
				cache[instance] = { value = value }
				return value
			end
			return run(instance)
		end

		return side
	end

	return world
end

return Engine
