--!strict
-- Every sound in the game. All of them come from Roblox's licensed partners on the
-- Creator Store (Pro Sound Effects, APM Music, DistroKid), which Roblox makes free to use
-- in any experience. Before adding a sound, check who uploaded it: a random upload "from
-- YouTube" or ripped from another game is not ours to use.
--
--   Id       rbxassetid number
--   Volume   base volume (0..1) before the player's settings
--   Group    SoundGroup: Ambient, Music or Effects
--   Speed    optional PlaybackSpeed (pitch)

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

export type SoundSpec = {
	Id: number,
	-- A sound that ships with Roblox itself (rbxasset://...), used instead of Id.
	Content: string?,
	Volume: number,
	Group: string,
	Speed: number?,
	-- Only this part of the file (seconds from, to) is played / looped.
	Region: { number }?,
	Credit: string,
}

-- Volumes are set from each file's measured loudness (Sound.PlaybackLoudness in Studio,
-- 21/11/2026): the files differ by up to 100x, so equal numbers do not mean equal sound.
-- Heard level = loudness x Volume x group volume; aimed at about 12 for your footsteps,
-- 14 for distant building noises, 35-45 for horror events, 2-3.5 for the constant
-- layers, 8-14 for music and 60-70 for the stinger and the catch. Measure a new sound
-- the same way before choosing its volume.
local Sounds: { [string]: SoundSpec } = {
	-- Ambience -------------------------------------------------------------------------
	-- The buzz of the fluorescent tubes; fades with the lights. Kept very low: as a
	-- constant layer it quickly becomes an annoying drone.
	-- (From every few lamps, heard within a few studs.)
	Hum = { Id = 9119997638, Volume = 0.046, Group = "Ambient", Speed = 0.8, Credit = "Pro Sound Effects" },
	-- Compressor drone, placed at a few coolers (heard only close to them).
	ColdHum = {
		Id = 9125767459,
		Volume = 0.09,
		Group = "Ambient",
		Speed = 0.6,
		Credit = "Pro Sound Effects",
	},
	-- Now and then the nearest fridge shudders (a rattle of glass, pitched down).
	FridgeRattle = {
		Id = 9114612518,
		Volume = 0.16,
		Group = "Ambient",
		Speed = 0.8,
		Credit = "Pro Sound Effects",
	},
	-- A low presence that grows hour by hour (silent at midnight).
	Dread = { Id = 9112795463, Volume = 0.13, Group = "Ambient", Credit = "Pro Sound Effects" },
	-- Rain outside, muffled.
	-- (All around you outside; inside only a trace of it, see RainIndoors.)
	Rain = { Id = 85976478711506, Volume = 1.6, Group = "Ambient", Credit = "DistroKid" },
	-- The same rain heard from the windows and the outer doors, louder as you get close.
	RainWindow = { Id = 85976478711506, Volume = 0.18, Group = "Ambient", Credit = "DistroKid" },
	-- The doorbell at the entrance when a customer comes in.
	DoorChime = { Id = 1840084286, Volume = 0.11, Group = "Effects", Credit = "APM Music" },

	-- Random distant sounds of an old building at night (see AmbientPool below).
	Creak1 = { Id = 9125563505, Volume = 3, Group = "Effects", Credit = "Pro Sound Effects" },
	Creak2 = { Id = 9114496277, Volume = 0.69, Group = "Effects", Credit = "Pro Sound Effects" },
	Creak3 = { Id = 9125563589, Volume = 2.3, Group = "Effects", Credit = "Pro Sound Effects" },
	Settle = { Id = 9126238879, Volume = 0.57, Group = "Effects", Speed = 0.8, Credit = "Pro Sound Effects" },
	WindowRattle = { Id = 9120764646, Volume = 0.19, Group = "Effects", Credit = "Pro Sound Effects" },
	GlassRattle = { Id = 9114612518, Volume = 0.17, Group = "Effects", Credit = "Pro Sound Effects" },
	Thunder = { Id = 9120015808, Volume = 0.21, Group = "Ambient", Credit = "Pro Sound Effects" },
	Drip = { Id = 9112900988, Volume = 3, Group = "Effects", Credit = "Pro Sound Effects" },
	MetalTap = { Id = 9113757491, Volume = 0.48, Group = "Effects", Credit = "Pro Sound Effects" },
	DistantDrag = {
		Id = 9116623943,
		Volume = 0.06,
		Group = "Effects",
		Speed = 0.85,
		Credit = "Pro Sound Effects",
	},

	-- Music -----------------------------------------------------------------------------
	-- It is looking for someone near you.
	Tension = { Id = 1843967372, Volume = 0.14, Group = "Music", Credit = "APM Music" },
	-- It is chasing you.
	Chase = { Id = 88275367596456, Volume = 0.15, Group = "Music", Credit = "DistroKid" },
	-- One hit when it starts chasing you.
	Stinger = { Id = 1841353894, Volume = 0.28, Group = "Music", Credit = "APM Music" },
	-- The catch.
	Catch = { Id = 1845391028, Volume = 0.41, Group = "Music", Credit = "APM Music" },

	-- Effects (mostly placed in the world) --------------------------------------------
	-- Its footsteps: a heavy, dull thud (Roblox's own landing sound, pitched down).
	MonsterStep = {
		Id = 0,
		Content = "rbxasset://sounds/action_jump_land.mp3",
		Volume = 0.9,
		Group = "Effects",
		Speed = 0.72,
		Credit = "Roblox",
	},
	Presence = { Id = 9114574159, Volume = 0.35, Group = "Effects", Credit = "Pro Sound Effects" },
	Knock = { Id = 9114141413, Volume = 0.29, Group = "Effects", Credit = "Pro Sound Effects" },
	Bumps = { Id = 9113136235, Volume = 0.61, Group = "Effects", Credit = "Pro Sound Effects" },
	Steps = { Id = 9113134455, Volume = 0.68, Group = "Effects", Credit = "Pro Sound Effects" },
	MetalHit = { Id = 9116699396, Volume = 0.38, Group = "Effects", Credit = "Pro Sound Effects" },
	CartRoll = { Id = 9120266878, Volume = 1.3, Group = "Effects", Credit = "Pro Sound Effects" },
	DoorBang = { Id = 9114748237, Volume = 0.33, Group = "Effects", Credit = "Pro Sound Effects" },
	ItemFall = { Id = 9113768971, Volume = 0.11, Group = "Effects", Credit = "Pro Sound Effects" },
	PowerDown = {
		Id = 9125784811,
		Volume = 0.3,
		Group = "Effects",
		Speed = 0.7,
		Credit = "Pro Sound Effects",
	},
	-- Footsteps of every character, synced to their walk. Roblox's own footstep sound
	-- (it ships with the engine; the partner libraries have no clean single steps).
	Footsteps = {
		Id = 0,
		Content = "rbxasset://sounds/action_footsteps_plastic.mp3",
		Volume = 0.32,
		Group = "Effects",
		Credit = "Roblox",
	},
	-- A running foot hitting the floor, one per stride: the same sound as the monster's
	-- steps but light (quiet and pitched up), so yours never sound like its.
	RunStep = {
		Id = 0,
		Content = "rbxasset://sounds/action_jump_land.mp3",
		Volume = 0.07,
		Group = "Effects",
		Speed = 1.3,
		Credit = "Roblox",
	},
	-- The main menu: sparse low piano with hanging vocal textures, no hits.
	MenuMusic = { Id = 9038330695, Volume = 0.23, Group = "Music", Credit = "APM Music" },
	-- Your own breathing when out of stamina: heavy panting, and a gasp when it runs out.
	-- Only the heavy breathing (1.0-3.4 s of the file: before it a soft start, after it a
	-- silence, measured in Studio), looped.
	Panting = {
		Id = 9113243294,
		Volume = 0.3,
		Group = "Effects",
		Region = { 1.0, 3.4 },
		Credit = "Pro Sound Effects",
	},
	Gasp = { Id = 9114555843, Volume = 0.3, Group = "Effects", Credit = "Pro Sound Effects" },
	Intercom = {
		Id = 9119997818,
		Volume = 0.25,
		Group = "Effects",
		Speed = 1.6,
		Credit = "Pro Sound Effects",
	},
}

return deepFreeze({
	Sounds = Sounds,

	-- Volume of each group (the player's settings scale these).
	Groups = {
		Ambient = 0.7,
		Music = 0.6,
		Effects = 0.75,
	},

	-- Now and then, somewhere out of sight, the building makes a sound: one of these,
	-- picked by weight, played at a random spot `Near`..`Far` studs from the player
	-- (Outside = heard everywhere, from outside the walls). `Repeat` plays it a few times
	-- in a row (a slow drip). Gap is the pause between two of them, in seconds.
	AmbientPool = {
		{ Sound = "Creak1", Weight = 3 },
		{ Sound = "Creak2", Weight = 2 },
		{ Sound = "Creak3", Weight = 3 },
		{ Sound = "Settle", Weight = 2 },
		{ Sound = "WindowRattle", Weight = 1 },
		{ Sound = "GlassRattle", Weight = 2 },
		{ Sound = "Thunder", Weight = 1, Outside = true },
		{ Sound = "Drip", Weight = 2, Repeat = 5 },
		{ Sound = "MetalTap", Weight = 2 },
		{ Sound = "DistantDrag", Weight = 1 },
		{ Sound = "FridgeRattle", Weight = 3, Near = "FridgeUnit" },
	},
	-- How close a "Near" thing must be for its sound (otherwise another is picked).
	NearRadius = 35,

	-- The building's walls: outside them the rain is all around.
	Building = { MinX = -101, MaxX = 101, MinZ = -83, MaxZ = 93 },
	-- How much of the rain is heard everywhere indoors (the rest comes from the windows).
	RainIndoors = 0.07,
	-- One rain emitter every this many studs along each big window.
	RainEmitterSpacing = 18,
	-- Outer doors that let the rain in.
	RainDoors = { "BackDoor", "EmergencyExitDoor" },
	-- Every Nth lamp buzzes.
	HumEveryNthLamp = 3,
	-- Sounds from outside the walls (thunder) are heard at this level indoors.
	OutsideHeardIndoors = 0.35,
	-- A customer vanishing within this distance of the entrance walked out through it.
	EntranceRadius = 14,
	AmbientGap = { 10, 28 },
	AmbientNear = 16,
	AmbientFar = 40,

	-- How loud the Dread layer is at each hour (index 1 = 12 AM ... 6 = 5 AM).
	DreadByHour = { 0, 0.15, 0.3, 0.5, 0.75, 1 },

	-- Within this distance of the monster the tension music starts.
	TensionRange = 55,
	-- Seconds for music to fade in and out.
	MusicFade = 2.5,
	-- The monster's footsteps: one every this many studs walked.
	StepEvery = 4.2,
})
