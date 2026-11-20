--!strict
-- Everything the player hears. Sound is decided per client: the server only says what
-- happens (an event, the monster's state); each client plays it from where it is.
--
--   Ambience   fluorescent hum (follows the shop lights), cooler compressors placed in
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
	return sound
end

-- Plays a sound once at a point in the world (heard from where it happens).
function AudioController.PlayAt(name: string, position: Vector3, volume: number?, range: number?)
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

local function ambienceFrame(dt: number)
	local shift = SessionState.Get("Phase") == "Shift"
	local hour = if shift then SessionState.Get("Hour") else 0
	local dread = AudioConfig.DreadByHour[math.clamp(hour + 1, 1, #AudioConfig.DreadByHour)]
	drive("Dread", dread, dt, 6)
	drive("Hum", if SessionState.Get("PowerShop") == true then 1 else 0, dt, 0.4)
	drive("Rain", 1, dt, 3)
end

-- Compressors humming at a few coolers, so the cold aisle sounds alive.
local function placeColdHum()
	local placed = 0
	for _, unit in CollectionService:GetTagged("FridgeUnit") do
		local part: BasePart? = nil
		if unit:IsA("BasePart") then
			part = unit
		else
			for _, child in unit:GetChildren() do
				if child:IsA("BasePart") then
					part = child
					break
				end
			end
		end
		if part and placed < 6 then
			local sound = newSound("ColdHum", true)
			sound.RollOffMode = Enum.RollOffMode.InverseTapered
			sound.RollOffMinDistance = 4
			sound.RollOffMaxDistance = 28
			sound.Parent = part
			sound:Play()
			placed += 1
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
	for _, name in { "Hum", "Dread", "Rain", "Tension", "Chase" } do
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
