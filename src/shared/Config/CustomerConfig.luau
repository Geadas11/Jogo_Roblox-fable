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

	-- From this hour a customer may stop and stare at a player instead of shopping, and
	-- vanish once nobody is looking at it.
	StarerFromHour = 1,
	StarerChance = 0.35,
	StareSeconds = 25,

	-- Clothes: shirt and trousers colours are picked from these.
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
