--!strict
-- Night customers (CustomerManager): ordinary people doing late shopping in the first
-- hours, and, as the night goes on, one who does not behave quite right.

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

return deepFreeze({
	-- Customers come in during these hours (0 = 12 AM). From LeaveHour everyone leaves,
	-- so the store is empty when the monster arrives.
	FirstHour = 0,
	LeaveHour = 2,
	-- At most this many in the store at once: a base, plus one per two players.
	MaxBase = 2,
	MaxPerTwoPlayers = 1,
	MaxTotal = 4,
	-- Seconds between arrivals (random between the two).
	ArrivalMin = 25,
	ArrivalMax = 60,
	-- Shelves a customer looks at before heading to the checkout, and how long at each.
	StopsMin = 2,
	StopsMax = 5,
	BrowseMin = 4,
	BrowseMax = 10,
	WalkSpeed = 6,

	-- Suspicious customers ---------------------------------------------------------------
	-- Some "customers" are not what they seem: each has one thing wrong with it. They have
	-- to be spotted and asked to leave. Chance an arrival is one of them, by hour (index 1
	-- = 12 AM). From LeaveHour the store is closed: anyone who still comes in is one.
	SuspiciousChanceByHour = { 0.15, 0.35, 1, 1, 1, 1 },
	-- After closing, now and then one of them still walks in, until this hour.
	LateUntilHour = 5,
	LateArrivalMin = 70,
	LateArrivalMax = 150,
	-- What is wrong with them, picked by weight:
	--   Backwards   walks backwards, facing where it came from
	--   Floating    hovers a hand's width above the floor
	--   TooTall     a head taller than anyone should be
	--   HeadTilt    its head hangs over at an impossible angle
	--   NoFace      a blank, smooth face
	--   Staring     stops and stares at you; gone once nobody looks at it
	--   CameraOnly  looks normal - but on the security cameras it has no head
	Anomalies = {
		{ Name = "Backwards", Weight = 2 },
		{ Name = "Floating", Weight = 2 },
		{ Name = "TooTall", Weight = 2 },
		{ Name = "HeadTilt", Weight = 2 },
		{ Name = "NoFace", Weight = 2 },
		{ Name = "Staring", Weight = 2 },
		{ Name = "CameraOnly", Weight = 3 },
	},
	StareSeconds = 25,
	-- Asking someone to leave: hold the key this long, within this distance.
	ExpelHold = 1.2,
	ExpelDistance = 9,
	-- How fast an expelled one heads for the door.
	ExpelledWalkSpeed = 13,
	-- A suspicious one left alone this long is gone - and the monster hears where.
	LingerSeconds = 150,
	-- ...within this radius the monster hears it go.
	LingerNoiseRadius = 70,

	-- What they wear: free catalog items made by Roblox itself (creator "Roblox", price 0,
	-- looked up in the Roblox catalog on 21/11/2026), so every customer looks like an
	-- ordinary avatar: a hairstyle, a shirt and trousers.
	Hair = {
		63690008, -- Pal Hair
		9243992729, -- Short and neat, black
		9244021842, -- Side part, black
		3814474927, -- Side shave
		376524487, -- Spiky blond
		376526888, -- Straight blond
		7193442167, -- Ponytail, black
		7193448258, -- Wavy middle part, brown
		9174355709, -- Styled dreads, black
		9244095135, -- Ponytail, blond
		9174354743, -- Tied up, black
		9244089488, -- Mid-length middle part, black
		6993754725, -- Straight fringe, black
		7193386173, -- Side part, blond
		9244111257, -- Wavy middle part, black
		1103003368, -- Orange beanie with black hair
		2956239660, -- Long red hair
	},
	ShirtIds = {
		607785314, -- Roblox jacket
		398633584, -- Denim jacket over a white hoodie
		144076358, -- Blue and black biker shirt
		382538059, -- Green windbreaker
		398635081, -- Blue plaid flannel
		4047886060, -- Purple and teal tee
		144076436, -- Striped shirt with denim jacket
		382537702, -- Teal shirt
		4047884046, -- Guitar tee with black jacket
		3670737444, -- Plain pattern shirt
	},
	PantsIds = {
		398633812, -- Black jeans, white shoes
		398635338, -- Ripped skater trousers
		144076760, -- Dark green jeans
		382538503, -- Black jeans with trainers
		382537569, -- Black jeans
		382537950, -- Denim shorts with white shoes
		382537806, -- Denim shorts
	},

	-- Body colours (used under the clothes, and if the clothes fail to load).
	Shirts = {
		{ 120, 32, 36 },
		{ 46, 70, 120 },
		{ 60, 96, 66 },
		{ 170, 150, 110 },
		{ 90, 90, 96 },
		{ 196, 120, 40 },
		{ 230, 226, 214 },
		{ 30, 30, 34 },
	},
	Trousers = { { 36, 40, 56 }, { 70, 60, 50 }, { 28, 28, 30 }, { 100, 104, 110 }, { 52, 66, 90 } },
	Skin = {
		{ 255, 220, 190 },
		{ 234, 192, 160 },
		{ 198, 146, 108 },
		{ 160, 110, 76 },
		{ 110, 74, 52 },
		{ 74, 50, 36 },
	},
})
