-- Every room of the building, in studs. X grows east, Z grows SOUTH, floor is Y = 0.
-- `circuit` is the electrical circuit that powers the room's lights.

local Layout = {}

Layout.StoreName = "HOLLOWAY'S MARKET"

-- Outer shell of the building.
Layout.Building = { x1 = -100, x2 = 100, z1 = -80, z2 = 80, wallHeight = 18 }

-- Area players can reach outdoors (a fenced loop around the building).
Layout.Grounds = { x1 = -126, x2 = 126, z1 = -122, z2 = 206 }

Layout.Zones = {
	{
		id = "ShopFloor",
		name = "Shop Floor",
		x1 = -60,
		x2 = 100,
		z1 = -30,
		z2 = 80,
		ceiling = 16,
		circuit = "Shop",
		indoor = true,
	},
	-- The glass vestibule is sealed while the entrance doors are locked (the whole night).
	{
		id = "Entrance",
		name = "Entrance",
		x1 = 5,
		x2 = 35,
		z1 = 80,
		z2 = 92,
		ceiling = 12,
		circuit = "Shop",
		indoor = true,
		sealed = true,
	},
	{
		id = "Storage",
		name = "Storage Room",
		x1 = -100,
		x2 = 10,
		z1 = -80,
		z2 = -30,
		ceiling = 16,
		circuit = "BackOfHouse",
		indoor = true,
	},
	{
		id = "Maintenance",
		name = "Maintenance",
		x1 = 10,
		x2 = 40,
		z1 = -58,
		z2 = -30,
		ceiling = 11,
		circuit = "BackOfHouse",
		indoor = true,
	},
	{
		id = "Electrical",
		name = "Electrical Room",
		x1 = 10,
		x2 = 40,
		z1 = -80,
		z2 = -58,
		ceiling = 11,
		circuit = "Emergency",
		indoor = true,
	},
	{
		id = "Refrigeration",
		name = "Cold Storage",
		x1 = 40,
		x2 = 100,
		z1 = -80,
		z2 = -30,
		ceiling = 14,
		circuit = "Cold",
		indoor = true,
	},
	{
		id = "StaffCorridor",
		name = "Staff Corridor",
		x1 = -70,
		x2 = -60,
		z1 = -30,
		z2 = 40,
		ceiling = 11,
		circuit = "Staff",
		indoor = true,
	},
	{
		id = "Office",
		name = "Office",
		x1 = -100,
		x2 = -70,
		z1 = 10,
		z2 = 40,
		ceiling = 11,
		circuit = "Staff",
		indoor = true,
	},
	{
		id = "EmployeeRoom",
		name = "Employee Room",
		x1 = -100,
		x2 = -70,
		z1 = -30,
		z2 = 10,
		ceiling = 11,
		circuit = "Staff",
		indoor = true,
	},
	{
		id = "BathroomA",
		name = "Restroom A",
		x1 = -100,
		x2 = -60,
		z1 = 60,
		z2 = 80,
		ceiling = 11,
		circuit = "Shop",
		indoor = true,
	},
	{
		id = "BathroomB",
		name = "Restroom B",
		x1 = -100,
		x2 = -60,
		z1 = 40,
		z2 = 60,
		ceiling = 11,
		circuit = "Shop",
		indoor = true,
	},
	{
		id = "ParkingLot",
		name = "Parking Lot",
		x1 = -126,
		x2 = 126,
		z1 = 80,
		z2 = 206,
		ceiling = 40,
		circuit = "Exterior",
		indoor = false,
	},
	{
		id = "BackLot",
		name = "Loading Area",
		x1 = -126,
		x2 = 126,
		z1 = -122,
		z2 = -80,
		ceiling = 40,
		circuit = "Exterior",
		indoor = false,
	},
	{
		id = "WestAlley",
		name = "West Alley",
		x1 = -126,
		x2 = -100,
		z1 = -80,
		z2 = 80,
		ceiling = 40,
		circuit = "Exterior",
		indoor = false,
	},
	{
		id = "EastAlley",
		name = "East Alley",
		x1 = 100,
		x2 = 126,
		z1 = -80,
		z2 = 80,
		ceiling = 40,
		circuit = "Exterior",
		indoor = false,
	},
}

-- The walk-in freezer is a room inside Cold Storage.
Layout.Freezer = { x1 = 72, x2 = 100, z1 = -80, z2 = -54, ceiling = 10 }

function Layout.zone(id)
	for _, zone in Layout.Zones do
		if zone.id == id then
			return zone
		end
	end
	error("unknown zone " .. id)
end

-- Shopping aisles: gondolas are 4 studs wide, centred on these X positions, and split
-- into a north and a south run with a cross aisle between them.
Layout.GondolaX = { -44, -30, -16, -2, 12, 26, 40 }
Layout.GondolaRuns = { { -18, 6 }, { 16, 40 } }
Layout.FreezerIslandX = { 55, 73 }

-- What each shelf face sells. Index 1 is the west wall, then west/east face of each gondola.
Layout.Categories = {
	{ name = "HOUSEHOLD", kinds = { "box", "jug", "bottle" } },
	{ name = "CLEANING", kinds = { "jug", "bottle", "box" } },
	{ name = "PAPER GOODS", kinds = { "bag", "box", "flat" } },
	{ name = "PET FOOD", kinds = { "bag", "can", "box" } },
	{ name = "PERSONAL CARE", kinds = { "bottle", "box", "jar" } },
	{ name = "BABY", kinds = { "box", "jar", "bag" } },
	{ name = "CEREAL", kinds = { "tall", "tall", "box" } },
	{ name = "BREAKFAST", kinds = { "jar", "tall", "box" } },
	{ name = "PASTA & RICE", kinds = { "bag", "box", "tall" } },
	{ name = "SAUCES", kinds = { "jar", "bottle", "can" } },
	{ name = "CANNED GOODS", kinds = { "can", "can", "jar" } },
	{ name = "SOUPS", kinds = { "can", "box", "can" } },
	{ name = "SNACKS", kinds = { "bag", "bag", "box" } },
	{ name = "CANDY", kinds = { "box", "bag", "flat" } },
	{ name = "DRINKS", kinds = { "bottle", "jug", "can" } },
}

return Layout
