--!strict
-- Tuning for the main monster, "The Customer", and for the player movement it is
-- balanced against. Speeds are in studs per second.

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

return deepFreeze({
	-- The monster appears at the start of this hour (3 = 3 AM, "the hunt").
	ActiveFromHour = 3,
	-- Extra speed per hour after it appears (0.08 = +8% each hour).
	SpeedGrowthPerHour = 0.08,

	Speed = {
		Patrol = 6.5,
		Investigate = 10,
		Search = 7,
		Chase = 14.5,
	},

	-- Player movement. Walking is silent; running is faster than the monster's chase
	-- but noisy and limited by stamina.
	Player = {
		WalkSpeed = 10,
		RunSpeed = 17,
		StaminaSeconds = 5,
		-- Seconds without running before stamina comes back, and how long a full refill takes.
		StaminaRegenDelay = 1,
		StaminaRefillSeconds = 6,
	},

	Senses = {
		-- How far it can see, and how wide (degrees, total).
		VisionRange = 70,
		FieldOfView = 120,
		-- Seconds of continuous sight, at mid range, before it is sure and gives chase.
		-- Closer is quicker, further is slower.
		DetectSeconds = 1.4,
		-- Awareness lost per second while nobody is in sight.
		AwarenessDecay = 0.5,
		-- Anyone this close is noticed even behind it.
		ProximityRange = 6,
		-- During a chase: seconds without sight before it gives up and searches.
		LoseSightSeconds = 5,
		-- A player who hides less than this many seconds after being seen was seen hiding.
		SeenHidingWindow = 1.5,
		-- In an unlit area it sees this much less far, unless you carry a lit flashlight.
		DarkVisionFactor = 0.5,
		-- A lit flashlight makes you easier to notice.
		FlashlightNoticeFactor = 1.3,
	},

	-- How far noises carry, in studs.
	Noise = {
		Running = 30,
		Door = 32,
		DropItem = 22,
	},

	Behaviour = {
		-- Chance to stop and stare when it first notices someone far away.
		ObserveChance = 0.5,
		ObserveMinDistance = 35,
		-- Seconds spent standing still and looking around at a patrol point.
		PauseMin = 2,
		PauseMax = 5,
		PauseChance = 0.35,
		-- Points visited while searching an area, and how far apart.
		SearchPoints = 3,
		SearchRadius = 16,
		-- Chance to check a hiding spot near where it is searching.
		CheckHidingSpotChance = 0.3,
		HidingSpotCheckRange = 22,
		-- How far from the nearest player it appears.
		SpawnMinDistance = 70,
		-- After catching someone it disappears for this long, then returns somewhere else.
		VanishSeconds = 20,
		-- Paths are searched at most this often.
		RepathSeconds = 0.5,
	},

	CatchDistance = 3.5,
	-- Seconds the catch sequence lasts before the player is moved on.
	CatchSequenceSeconds = 3.5,
	-- Closed doors within this distance are opened as it walks.
	DoorOpenDistance = 6,

	Survival = {
		-- Playing alone: times a player can be caught and keep working, per shift.
		SoloSecondChances = 1,
	},
})
