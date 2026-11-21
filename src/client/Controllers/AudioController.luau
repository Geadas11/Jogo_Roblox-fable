--!strict
-- Everything the player hears. Sound is decided per client: the server only says what
-- happens (an event, the monster's state); each client plays it from where it is.
--
--   Ambience   everything steady comes from a place and grows louder as you approach:
--              the buzz of some lamps (only while lit), a compressor in every fridge,
--              rain at the windows and outer doors (all around you outside), the doorbell
--              when a customer comes in. Before that: fluorescent hum, cooler compressors placed in
--              the world, rain outside, and a low "dread" layer that grows every hour.
--              Midnight is deliberately close to silent.
--   Monster    footsteps and a presence sound that travel with its body, so you hear
--              where it is before you see it.
--   Music      nothing most of the time; a tension layer when it is hunting near you,
--              a chase track and a stinger when it is after you, fading out after.
--   One-shots  AudioController.PlayAt / Play, used by the horror events.
--
-- Sound ids and volumes live in Config.AudioConfig.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AudioConfig = require(Shared.Config.AudioConfig)
local PowerConfig = require(Shared.Config.PowerConfig)
local SessionState = require(Shared.SessionState)
local Net = require(script.Parent.Parent.Net)
local Settings = require(script.Parent.Parent.Settings)

local AudioController = {}

local groups: { [string]: SoundGroup } = {}
-- Looping 2D layers, by name.
local layers: { [string]: Sound } = {}
-- Current level (0..1) of each music layer, eased towards its target every frame.
local levels: { [string]: number } = {}

local monsterRoot: BasePart? = nil
local presence: Sound? = nil
local lastStepPosition: Vector3? = nil
local wasChasingMe = false

-- Sounds -------------------------------------------------------------------------------------

local function newSound(name: string, looped: boolean): Sound
	local spec = AudioConfig.Sounds[name]
	assert(spec, "AudioConfig has no sound named " .. name)
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = spec.Content or ("rbxassetid://" .. tostring(spec.Id))
	sound.Volume = spec.Volume
	sound.PlaybackSpeed = spec.Speed or 1
	sound.Looped = looped
	sound.SoundGroup = groups[spec.Group]
	if spec.Region then
		local region = NumberRange.new(spec.Region[1], spec.Region[2])
		sound.PlaybackRegionsEnabled = true
		sound.PlaybackRegion = region
		sound.LoopRegion = region
	end
	return sound
end

-- Plays a sound once at a point in the world (heard from where it happens).
function AudioController.PlayAt(
	name: string,
	position: Vector3,
	volume: number?,
	range: number?,
	pitch: number?
)
	local holder = Instance.new("Part")
	holder.Name = "SoundAt_" .. name
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(position)
	local sound = newSound(name, false)
	sound.Volume *= volume or 1
	sound.PlaybackSpeed *= pitch or 1
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 6
	sound.RollOffMaxDistance = range or 90
	sound.Parent = holder
	holder.Parent = Workspace
	sound:Play()
	task.delay(15, function()
		holder:Destroy()
	end)
end

-- Plays a sound once, not placed anywhere (the intercom, the catch).
function AudioController.Play(name: string, volume: number?)
	local sound = newSound(name, false)
	sound.Volume *= volume or 1
	sound.Parent = SoundService
	sound:Play()
	task.delay(15, function()
		sound:Destroy()
	end)
end

-- A looping sound attached to a part (heard from there), starting silent.
function AudioController.LoopAt(name: string, part: BasePart, range: number?): Sound
	local sound = newSound(name, true)
	sound.Volume = 0
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = range or 60
	sound.Parent = part
	return sound
end

-- A looping sound, not placed anywhere, starting silent: the caller sets its volume.
function AudioController.Loop(name: string): Sound
	local sound = newSound(name, true)
	sound.Volume = 0
	sound.Parent = SoundService
	return sound
end

local function layer(name: string): Sound
	local sound = newSound(name, true)
	sound.Volume = 0
	sound.Parent = SoundService
	layers[name] = sound
	levels[name] = 0
	return sound
end

-- Eases a looping layer towards `target` (0..1 of its configured volume).
local function drive(name: string, target: number, dt: number, fade: number)
	local sound = layers[name]
	if not sound then
		return
	end
	local level = levels[name] or 0
	local step = dt / math.max(fade, 0.01)
	if level < target then
		level = math.min(target, level + step)
	else
		level = math.max(target, level - step)
	end
	levels[name] = level
	sound.Volume = AudioConfig.Sounds[name].Volume * level
	if level > 0.001 and not sound.IsPlaying then
		sound:Play()
	elseif level <= 0.001 and sound.IsPlaying then
		sound:Stop()
	end
end

-- The monster ----------------------------------------------------------------------------------

local function attachMonster(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	monsterRoot = instance
	local sound = newSound("Presence", true)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 4
	sound.RollOffMaxDistance = 45
	sound.Parent = instance
	presence = sound
end

local function monsterFrame(dt: number)
	local root = monsterRoot
	local player = Players.LocalPlayer
	local present = root ~= nil and root.Parent ~= nil and root:GetAttribute("Present") == true
	local state = if root then tostring(root:GetAttribute("State")) else ""
	local chasingMe = present
		and state == "Chase"
		and root ~= nil
		and root:GetAttribute("Target") == player.UserId

	-- Footsteps: one every few studs it walks.
	if root and present then
		local position = root.Position
		local last = lastStepPosition
		if last == nil or (position - last).Magnitude > 30 then
			lastStepPosition = position
		elseif (position - last).Magnitude >= AudioConfig.StepEvery then
			lastStepPosition = position
			local floor = position - Vector3.new(0, 3.5, 0)
			AudioController.PlayAt("MonsterStep", floor, if state == "Chase" then 1.4 else 1, 60)
		end
	else
		lastStepPosition = nil
	end
	if presence then
		local sound = presence :: Sound
		if present and not sound.IsPlaying then
			sound:Play()
		elseif not present and sound.IsPlaying then
			sound:Stop()
		end
	end

	-- Music.
	local distance = math.huge
	local character = player.Character
	local myRoot = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if root and present and myRoot and myRoot:IsA("BasePart") then
		distance = (myRoot.Position - root.Position).Magnitude
	end
	local hunting = state == "Investigate" or state == "Search" or state == "Chase" or state == "Observe"
	local tension = if present
			and hunting
			and distance < AudioConfig.TensionRange
			and not chasingMe
		then 1
		else 0
	drive("Chase", if chasingMe then 1 else 0, dt, if chasingMe then 0.6 else AudioConfig.MusicFade)
	drive("Tension", tension, dt, AudioConfig.MusicFade)

	if chasingMe and not wasChasingMe then
		AudioController.Play("Stinger")
	end
	wasChasingMe = chasingMe
end

-- Ambience -------------------------------------------------------------------------------------

-- Outside the building (the car park in front, the loading area behind): the rain is
-- all around you there. Inside it comes from the windows and outer doors (emitters).
local function outdoors(): boolean
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return false
	end
	local p = root.Position
	local b = AudioConfig.Building
	return p.X < b.MinX or p.X > b.MaxX or p.Z < b.MinZ or p.Z > b.MaxZ
end

local function ambienceFrame(dt: number)
	local shift = SessionState.Get("Phase") == "Shift"
	local hour = if shift then SessionState.Get("Hour") else 0
	local dread = AudioConfig.DreadByHour[math.clamp(hour + 1, 1, #AudioConfig.DreadByHour)]
	drive("Dread", dread, dt, 6)
	drive("Rain", if outdoors() then 1 else AudioConfig.RainIndoors, dt, 2)
end

-- Sounds that belong to places ----------------------------------------------------------------
-- Every steady sound comes from somewhere, so it gets louder as you walk up to it: the
-- rain at the windows and outer doors, a compressor in every fridge, the buzz of some of
-- the lamps (only while they are lit).

local ambienceFolder: Folder? = nil

local function emitter(name: string, position: Vector3, minDistance: number, maxDistance: number): Sound
	if not ambienceFolder then
		local folder = Instance.new("Folder")
		folder.Name = "Ambience"
		folder.Parent = Workspace
		ambienceFolder = folder
	end
	local holder = Instance.new("Part")
	holder.Name = name
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.CFrame = CFrame.new(position)
	local sound = newSound(name, true)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = minDistance
	sound.RollOffMaxDistance = maxDistance
	-- Not all in step: each loop starts somewhere else in the file.
	sound.TimePosition = math.random() * 10
	sound.Parent = holder
	holder.Parent = ambienceFolder
	sound:Play()
	return sound
end

-- Rain against the shop windows and the outer doors: points every few studs along each
-- big pane of glass, and one at each outer door.
local function placeRain()
	local map = Workspace:FindFirstChild("Map")
	local glazing = map and map:FindFirstChild("Glazing", true)
	local step = AudioConfig.RainEmitterSpacing
	if glazing then
		for _, pane in glazing:GetChildren() do
			if pane:IsA("BasePart") then
				local long = math.max(pane.Size.X, pane.Size.Z)
				local alongX = pane.Size.X >= pane.Size.Z
				local count = math.max(1, math.floor(long / step))
				for index = 1, count do
					local offset = (index - 0.5) / count * long - long / 2
					local position = pane.Position
						+ (if alongX then Vector3.new(offset, 0, 0) else Vector3.new(0, 0, offset))
					emitter("RainWindow", position, 6, 42)
				end
			end
		end
	end
	for _, door in CollectionService:GetTagged("Door") do
		if door:IsA("BasePart") and table.find(AudioConfig.RainDoors, door.Name) then
			emitter("RainWindow", door.Position, 6, 42)
		end
	end
end

-- Where a tagged thing is: a part's position, or a model's "Anchor" (fridges have one at
-- their front, where the prompt is), or its first part.
local function placeOf(thing: Instance): Vector3?
	if thing:IsA("BasePart") then
		return thing.Position
	end
	local anchor = thing:FindFirstChild("Anchor")
	if anchor and anchor:IsA("BasePart") then
		return anchor.Position
	end
	for _, child in thing:GetChildren() do
		if child:IsA("BasePart") then
			return child.Position
		end
	end
	return nil
end

-- A compressor in every fridge and freezer, heard up close - silent while their circuit
-- is down (a blackout is quieter than the night around it).
local coldHums: { Sound } = {}

local function coldPowered(): boolean
	return SessionState.Get("PowerCold") ~= false
end

local function placeColdHum()
	for _, unit in CollectionService:GetTagged("FridgeUnit") do
		local position = placeOf(unit)
		if position then
			table.insert(coldHums, emitter("ColdHum", position, 2.5, 18))
		end
	end
end

local function updateColdHum()
	local on = coldPowered()
	for _, sound in coldHums do
		if on and not sound.IsPlaying then
			sound:Play()
		elseif not on and sound.IsPlaying then
			sound:Stop()
		end
	end
end

-- The buzz of the tubes, from every few fixtures, silent when the lamp is dark.
local lampHums: { { Sound: Sound, Light: Light? } } = {}

local function placeLampHum()
	-- Only lamps inside the building (the car park lights do not buzz at you).
	local b = AudioConfig.Building
	local indoor = {}
	for _, tube in CollectionService:GetTagged("LightFixture") do
		if tube:IsA("BasePart") then
			local p = tube.Position
			if p.X > b.MinX and p.X < b.MaxX and p.Z > b.MinZ and p.Z < b.MaxZ then
				table.insert(indoor, tube)
			end
		end
	end
	for index, tube in indoor do
		if index % AudioConfig.HumEveryNthLamp == 0 then
			-- (The tubes are up at the ceiling, 8-10 studs above your ears.)
			local sound = emitter("Hum", tube.Position, 6, 24)
			-- (The map names every lamp's light "Light".)
			local light = tube:FindFirstChild("Light")
			table.insert(lampHums, { Sound = sound, Light = light :: any })
		end
	end
end

local function updateLampHum()
	for _, hum in lampHums do
		local light = hum.Light
		local lit = light ~= nil and light.Enabled and light.Brightness > 0.05
		if lit and not hum.Sound.IsPlaying then
			hum.Sound:Play()
		elseif not lit and hum.Sound.IsPlaying then
			hum.Sound:Stop()
		end
	end
end

-- The doorbell at the entrance when a customer comes in (or walks out through it).
local function entrancePosition(): Vector3?
	local sum, count = Vector3.zero, 0
	for _, door in CollectionService:GetTagged("EntranceDoor") do
		if door:IsA("BasePart") then
			sum += door.Position
			count += 1
		end
	end
	return if count > 0 then sum / count else nil
end

local function watchCustomers()
	local entrance = entrancePosition()
	if not entrance then
		return
	end
	local function nearEntrance(model: Instance): boolean
		local root = if model:IsA("Model") then model:FindFirstChild("HumanoidRootPart") else nil
		return root ~= nil
			and root:IsA("BasePart")
			and Vector3.new(root.Position.X - entrance.X, 0, root.Position.Z - entrance.Z).Magnitude
				< AudioConfig.EntranceRadius
	end
	CollectionService:GetInstanceAddedSignal("Customer"):Connect(function(model: Instance)
		AudioController.PlayAt("DoorChime", entrance, 1, 110)
		-- Remember where it last was: it is gone from the map when it is removed.
		local last = false
		task.spawn(function()
			while model.Parent do
				last = nearEntrance(model)
				task.wait(0.5)
			end
			if last then
				AudioController.PlayAt("DoorChime", entrance, 1, 110)
			end
		end)
	end)
end

-- The building at night: every so often a creak, a rattle, a drip, a far-off clank or
-- thunder outside, somewhere around the player, never twice the same in a row. Keeps the
-- quiet from becoming one flat drone.
local function pickAmbient(last: string?): any
	local pool = AudioConfig.AmbientPool
	local total = 0
	for _, entry in pool do
		if entry.Sound ~= last then
			total += entry.Weight
		end
	end
	local roll = math.random() * total
	for _, entry in pool do
		if entry.Sound ~= last then
			roll -= entry.Weight
			if roll <= 0 then
				return entry
			end
		end
	end
	return pool[1]
end

local function ambientSpot(): Vector3?
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not root or not root:IsA("BasePart") then
		return nil
	end
	local angle = math.random() * math.pi * 2
	local distance = AudioConfig.AmbientNear
		+ math.random() * (AudioConfig.AmbientFar - AudioConfig.AmbientNear)
	return root.Position
		+ Vector3.new(math.cos(angle) * distance, math.random(0, 6), math.sin(angle) * distance)
end

local function runAmbience()
	local last: string? = nil
	while true do
		local gap = AudioConfig.AmbientGap
		task.wait(gap[1] + math.random() * (gap[2] - gap[1]))
		local entry = pickAmbient(last)
		last = entry.Sound
		local pitch = 0.88 + math.random() * 0.24
		if entry.Outside then
			-- From outside the walls: full out there, muffled indoors.
			local level = if outdoors() then 1 else AudioConfig.OutsideHeardIndoors
			AudioController.Play(entry.Sound, level * (0.7 + math.random() * 0.5))
		elseif entry.Near then
			-- From the nearest of those things (a fridge shuddering), if one is close.
			local character = Players.LocalPlayer.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			local best: Vector3? = nil
			local bestDistance = AudioConfig.NearRadius
			-- (A fridge without power does not shudder.)
			if root and root:IsA("BasePart") and (entry.Near ~= "FridgeUnit" or coldPowered()) then
				for _, thing in CollectionService:GetTagged(entry.Near) do
					local position = placeOf(thing)
					if position and (position - root.Position).Magnitude < bestDistance then
						bestDistance = (position - root.Position).Magnitude
						best = position
					end
				end
			end
			if best then
				AudioController.PlayAt(entry.Sound, best, 0.8 + math.random() * 0.3, 40, pitch)
			end
		else
			local spot = ambientSpot()
			if spot then
				for _ = 1, entry.Repeat or 1 do
					AudioController.PlayAt(entry.Sound, spot, 0.75 + math.random() * 0.4, 70, pitch)
					if entry.Repeat then
						task.wait(1.1 + math.random() * 0.9)
					end
				end
			end
		end
	end
end

-- Player volume settings: every group sits inside a Master group, so the master slider
-- scales everything.
local SETTING_OF_GROUP = { Music = "MusicVolume", Ambient = "AmbientVolume", Effects = "EffectsVolume" }

local function applyVolumes()
	local master = groups.Master
	if master then
		master.Volume = Settings.Get("MasterVolume")
	end
	for name, settingKey in SETTING_OF_GROUP do
		local group = groups[name]
		if group then
			group.Volume = (AudioConfig.Groups :: any)[name] * Settings.Get(settingKey)
		end
	end
end

function AudioController.Init()
	local master = Instance.new("SoundGroup")
	master.Name = "Master"
	master.Parent = SoundService
	groups.Master = master
	for name, volume in AudioConfig.Groups do
		local group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = volume
		group.Parent = master
		groups[name] = group
	end
	-- Echo: the store is a big hard-floored hall. Footsteps, knocks and bangs ring a
	-- little down the aisles; music and the ambient layers stay dry.
	local echo = Instance.new("ReverbSoundEffect")
	echo.Name = "StoreEcho"
	echo.DecayTime = 1.7
	echo.Density = 0.9
	echo.Diffusion = 0.8
	echo.DryLevel = 0
	echo.WetLevel = -9
	echo.Parent = groups.Effects
	applyVolumes()
	Settings.Changed:Connect(applyVolumes)
	-- (The lamp hum is not a layer any more: it comes from the lamps.)
	for _, name in { "Dread", "Rain", "Tension", "Chase" } do
		layer(name)
	end

	Net.On("Caught", function(userId: any)
		if userId == Players.LocalPlayer.UserId then
			AudioController.Play("Catch")
		end
	end)
end

function AudioController.Start()
	CollectionService:GetInstanceAddedSignal("Monster"):Connect(attachMonster)
	for _, instance in CollectionService:GetTagged("Monster") do
		attachMonster(instance)
	end
	placeColdHum()
	placeRain()
	placeLampHum()
	watchCustomers()
	task.spawn(runAmbience)
	task.spawn(function()
		while true do
			updateLampHum()
			updateColdHum()
			task.wait(0.5)
		end
	end)

	-- The lights going out is heard as well as seen (once, even when every circuit
	-- drops at the same moment).
	local lastPowerDown = -math.huge
	for _, circuit in PowerConfig.Circuits do
		local wasOn = true
		SessionState.Observe("Power" .. circuit, function(on: any)
			if
				wasOn
				and on == false
				and SessionState.Get("Phase") == "Shift"
				and os.clock() - lastPowerDown > 2
			then
				lastPowerDown = os.clock()
				AudioController.Play("PowerDown", 0.6)
			end
			wasOn = on == true
		end)
	end

	RunService.RenderStepped:Connect(function(dt: number)
		ambienceFrame(dt)
		monsterFrame(dt)
	end)
end

return AudioController
