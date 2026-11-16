-- The building shell: floors, walls with door and window openings, ceilings, roof,
-- doors, shop windows and the glass entrance vestibule.

local Layout = require("./Layout")
local P = require("./Palette")

local H = Layout.Building.wallHeight
local DOOR_TOP = 7.5

local FLOORS = {
	ShopFloor = P.floorShop,
	Entrance = P.floorShop,
	Storage = P.floorBack,
	Maintenance = P.floorBack,
	Electrical = P.floorBack,
	Refrigeration = P.floorCold,
	StaffCorridor = P.floorStaff,
	Office = P.floorOffice,
	EmployeeRoom = P.floorStaff,
	BathroomA = P.floorBath,
	BathroomB = P.floorBath,
}

local BACK_OF_HOUSE = { Storage = true, Maintenance = true, Electrical = true, Refrigeration = true }

return function(k, root)
	local structure = k:folder(root, "Structure")
	local floors = k:folder(structure, "Floors")
	local ceilings = k:folder(structure, "Ceilings")
	local walls = k:folder(structure, "Walls")
	local doors = k:folder(structure, "Doors")
	local glazing = k:folder(structure, "Glazing")

	-- Floors and ceilings, one slab per indoor zone -------------------------------------
	for _, zone in Layout.Zones do
		if zone.indoor then
			k:span(floors, zone.id .. "Floor", zone.x1, -1, zone.z1, zone.x2, 0, zone.z2, FLOORS[zone.id])
			if zone.id ~= "Entrance" then
				local style = if BACK_OF_HOUSE[zone.id] then P.ceilingBack else P.ceiling
				k:span(
					ceilings,
					zone.id .. "Ceiling",
					zone.x1,
					zone.ceiling,
					zone.z1,
					zone.x2,
					zone.ceiling + 0.4,
					zone.z2,
					style
				)
			end
		end
	end
	local fz = Layout.Freezer
	k:span(
		ceilings,
		"FreezerCeiling",
		fz.x1,
		fz.ceiling,
		fz.z1,
		fz.x2,
		fz.ceiling + 0.4,
		fz.z2,
		P.ceilingBack
	)

	local b = Layout.Building
	k:span(structure, "Roof", b.x1 - 0.5, H, b.z1 - 0.5, b.x2 + 0.5, H + 1, b.z2 + 0.5, P.roof)

	-- Exterior walls -------------------------------------------------------------------
	-- North: two loading docks and the staff back door.
	k:wallX(walls, "NorthWall", -80, -100, 100, 0, H, P.facade, {
		{ -80, -62, 12 },
		{ -50, -32, 12 },
		{ -10, -5, DOOR_TOP },
	})
	-- South: shop windows either side of the entrance.
	k:wallX(walls, "SouthWall", 80, -100, 100, 0, H, P.facade, {
		{ -56, 2, 12, 3 },
		{ 14, 26, 9 },
		{ 38, 96, 12, 3 },
	})
	k:wallZ(walls, "WestWall", -100, -80, 80, 0, H, P.facade)
	-- East: emergency exit.
	k:wallZ(walls, "EastWall", 100, -80, 80, 0, H, P.facade, { { 52, 57, DOOR_TOP } })

	-- Interior walls -------------------------------------------------------------------
	-- Shop west wall: staff door and the two restrooms.
	k:wallZ(walls, "ShopWestWall", -60, -30, 80, 0, H, P.wall, {
		{ 29, 34, DOOR_TOP },
		{ 47, 52, DOOR_TOP },
		{ 67, 72, DOOR_TOP },
	})
	-- Back wall: staff corridor, stock doors, cold storage.
	k:wallX(walls, "BackWall", -30, -100, 100, 0, H, P.wall, {
		{ -68, -63, DOOR_TOP },
		{ -25, -15, 8.5 },
		{ 66, 74, 8.5 },
	})
	k:wallZ(walls, "CorridorWestWall", -70, -30, 40, 0, H, P.wall, {
		{ -12, -7, DOOR_TOP },
		{ 22, 27, DOOR_TOP },
	})
	k:wallX(walls, "OfficeNorthWall", 10, -100, -70, 0, H, P.wall)
	k:wallX(walls, "RestroomSouthWall", 40, -100, -60, 0, H, P.wall)
	k:wallX(walls, "RestroomDivider", 60, -100, -60, 0, H, P.wall)

	k:wallZ(walls, "StorageEastWall", 10, -80, -30, 0, H, P.wallBack, { { -47, -42, DOOR_TOP } })
	k:wallZ(walls, "ColdWestWall", 40, -80, -30, 0, H, P.wallBack, { { -47, -42, DOOR_TOP } })
	k:wallX(walls, "ElectricalSouthWall", -58, 10, 40, 0, H, P.wallBack, { { 22, 27, DOOR_TOP } })

	-- Walk-in freezer (insulated panels, lower than the room around it).
	k:wallZ(walls, "FreezerWestWall", fz.x1, fz.z1, fz.z2, 0, fz.ceiling + 0.4, P.wallCold)
	k:wallX(
		walls,
		"FreezerSouthWall",
		fz.z2,
		fz.x1,
		fz.x2,
		0,
		fz.ceiling + 0.4,
		P.wallCold,
		{ { 82, 87, DOOR_TOP } }
	)

	-- Doors (created open, see Kit:door) -------------------------------------------------
	k:door(doors, "StaffDoor", "z", -60, 29, 34, 1, false, P.door, { zone = "StaffCorridor" })
	k:door(doors, "RestroomBDoor", "z", -60, 47, 52, -1, true, P.doorWood, { zone = "BathroomB" })
	k:door(doors, "RestroomADoor", "z", -60, 67, 72, -1, true, P.doorWood, { zone = "BathroomA" })
	k:door(doors, "EmployeeRoomDoor", "z", -70, -12, -7, -1, true, P.doorWood, { zone = "EmployeeRoom" })
	k:door(doors, "OfficeDoor", "z", -70, 22, 27, -1, false, P.doorWood, { zone = "Office" })
	k:door(doors, "CorridorStorageDoor", "x", -30, -68, -63, -1, true, P.door, { zone = "Storage" })
	k:door(doors, "StockDoorWest", "x", -30, -25, -20, -1, true, P.door, { zone = "Storage", height = 8.4 })
	k:door(doors, "StockDoorEast", "x", -30, -20, -15, -1, false, P.door, { zone = "Storage", height = 8.4 })
	k:door(doors, "MaintenanceWestDoor", "z", 10, -47, -42, 1, true, P.door, { zone = "Maintenance" })
	k:door(doors, "MaintenanceEastDoor", "z", 40, -47, -42, 1, true, P.door, { zone = "Refrigeration" })
	k:door(doors, "ElectricalDoor", "x", -58, 22, 27, -1, true, P.door, { zone = "Electrical" })
	k:door(
		doors,
		"FreezerDoor",
		"x",
		fz.z2,
		82,
		87,
		1,
		true,
		P.steel,
		{ zone = "Refrigeration", thick = 0.6 }
	)
	k:door(doors, "BackDoor", "x", -80, -10, -5, -1, false, P.door, { zone = "BackLot" })

	local exitDoor = k:door(
		doors,
		"EmergencyExitDoor",
		"z",
		100,
		52,
		57,
		1,
		true,
		P.red,
		{ zone = "EastAlley", closed = true }
	)
	k:mark(exitDoor, "EmergencyExit")

	-- Loading dock roll-up doors (closed).
	for index, x in { -80, -50 } do
		local dock = k:span(doors, "DockDoor" .. index, x, 0, -80.3, x + 18, 12, -79.7, P.steel)
		for rib = 1, 7 do
			k:span(dock, "Rib", x, rib * 1.5 - 0.1, -79.65, x + 18, rib * 1.5 + 0.1, -79.55, P.dDarkSteel)
		end
	end

	-- Cold storage doorway: hanging plastic strips instead of a door.
	for index = 0, 7 do
		k:span(doors, "StripCurtain", 66 + index, 0.3, -30.1, 66.9 + index, 8.5, -29.9, P.glassDecor)
	end

	-- Shop windows -----------------------------------------------------------------------
	for _, window in { { -56, 2 }, { 38, 96 } } do
		k:span(glazing, "ShopWindow", window[1], 3, 79.9, window[2], 12, 80.1, P.glass)
		local x = window[1]
		while x <= window[2] do
			k:span(glazing, "Mullion", x - 0.2, 3, 79.75, x + 0.2, 12, 80.25, P.dDarkSteel)
			x += 14.5
		end
		k:span(glazing, "WindowSill", window[1], 2.8, 79.4, window[2], 3, 80.6, P.dDarkSteel)
	end

	-- Entrance: inner and outer sliding doors, locked during the night shift --------------
	for _, door in { { "Inner", 80 }, { "Outer", 92 } } do
		for _, leaf in { { "West", 14, 20 }, { "East", 20, 26 } } do
			local panel = k:span(
				doors,
				"Entrance" .. door[1] .. leaf[1],
				leaf[2],
				0,
				door[2] - 0.15,
				leaf[3],
				9,
				door[2] + 0.15,
				P.glass
			)
			k:mark(panel, "EntranceDoor", { Set = door[1], Side = leaf[1] })
			k:span(panel, "Frame", leaf[2], 8.6, door[2] - 0.25, leaf[3], 9, door[2] + 0.25, P.dDarkSteel)
		end
	end

	-- Vestibule: a glass box in front of the entrance.
	local v = Layout.zone("Entrance")
	k:span(glazing, "VestibuleWest", v.x1 - 0.2, 0, v.z1 + 0.5, v.x1 + 0.2, v.ceiling, v.z2, P.glass)
	k:span(glazing, "VestibuleEast", v.x2 - 0.2, 0, v.z1 + 0.5, v.x2 + 0.2, v.ceiling, v.z2, P.glass)
	k:span(glazing, "VestibuleFrontWest", v.x1, 0, v.z2 - 0.2, 14, v.ceiling, v.z2 + 0.2, P.glass)
	k:span(glazing, "VestibuleFrontEast", 26, 0, v.z2 - 0.2, v.x2, v.ceiling, v.z2 + 0.2, P.glass)
	k:span(glazing, "VestibuleFrontTop", 14, 9, v.z2 - 0.2, 26, v.ceiling, v.z2 + 0.2, P.glass)
	k:span(
		structure,
		"VestibuleRoof",
		v.x1 - 0.6,
		v.ceiling,
		v.z1 + 0.5,
		v.x2 + 0.6,
		v.ceiling + 0.7,
		v.z2 + 0.8,
		P.darkSteel
	)
	for _, x in { v.x1, 14, 26, v.x2 } do
		k:span(glazing, "VestibulePost", x - 0.3, 0, v.z2 - 0.3, x + 0.3, v.ceiling, v.z2 + 0.3, P.dDarkSteel)
	end
end
