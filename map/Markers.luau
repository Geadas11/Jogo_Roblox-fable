-- Things the game code needs to find but players do not see as props: ceiling lights,
-- zone volumes, navigation points, task positions, security cameras and spawns.

local Kit = require("./Kit")
local Layout = require("./Layout")
local P = require("./Palette")

local Color3, CFrame, Vector3 = Kit.Color3, Kit.CFrame, Kit.Vector3

local AISLE_X = { -51.5, -37, -23, -9, 5, 19, 33, 47 }

return function(k, root)
	local markers = k:folder(root, "Markers")

	-- Ceiling lights ----------------------------------------------------------------------
	local lights = k:folder(root, "Lights")
	local function fixtures(zone, circuit, ceiling, axis, positions, props)
		local folder = k:folder(lights, zone)
		for index, position in positions do
			local options = table.clone(props)
			options.housing = P.dWhite
			if props.shadowEvery then
				options.shadows = index % props.shadowEvery == 0
			end
			local tube = k:fixture(folder, zone, circuit, position[1], position[2], ceiling, axis, options)
			if position[3] then
				tube:SetAttribute("Flicker", true)
			end
		end
	end

	local shopLights = {}
	for _, x in { -51, -23, 5, 33, 61, 89 } do
		for _, z in { -16, 10, 36, 62 } do
			table.insert(shopLights, { x, z })
		end
	end
	fixtures("ShopFloor", "Shop", 16, "z", shopLights, {
		color = Color3.fromRGB(232, 240, 255),
		brightness = 1.8,
		range = 36,
		angle = 140,
		shadowEvery = 3,
	})
	fixtures(
		"Entrance",
		"Shop",
		12,
		"x",
		{ { 20, 86 } },
		{ color = Color3.fromRGB(232, 240, 255), brightness = 1.1, range = 22 }
	)

	local storageLights = {}
	for _, x in { -84, -56, -28, 0 } do
		for _, z in { -66, -44 } do
			table.insert(storageLights, { x, z })
		end
	end
	-- Storage is lit more sparsely and slightly green, like old industrial tubes.
	fixtures("Storage", "BackOfHouse", 15, "x", storageLights, {
		color = Color3.fromRGB(214, 236, 214),
		brightness = 1.1,
		range = 32,
		shadowEvery = 2,
	})
	fixtures(
		"Maintenance",
		"BackOfHouse",
		11,
		"x",
		{ { 25, -44 } },
		{ color = Color3.fromRGB(226, 236, 226), brightness = 1, range = 24 }
	)
	-- The electrical room stays on the emergency circuit so the panel can always be found.
	fixtures(
		"Electrical",
		"Emergency",
		11,
		"x",
		{ { 25, -69 } },
		{ color = Color3.fromRGB(255, 226, 190), brightness = 0.8, range = 22 }
	)
	fixtures("Refrigeration", "Cold", 14, "x", { { 55, -42 }, { 86, -42 }, { 55, -68 } }, {
		color = Color3.fromRGB(214, 232, 255),
		brightness = 1.2,
		range = 30,
	})
	fixtures(
		"Freezer",
		"Cold",
		10,
		"x",
		{ { 86, -67 } },
		{ color = Color3.fromRGB(200, 225, 255), brightness = 1, range = 24 }
	)
	fixtures("StaffCorridor", "Staff", 11, "z", { { -65, -20 }, { -65, 5, true }, { -65, 30 } }, {
		color = Color3.fromRGB(236, 236, 226),
		brightness = 0.9,
		range = 24,
		shadowEvery = 1,
		length = 5,
	})
	fixtures(
		"Office",
		"Staff",
		11,
		"x",
		{ { -85, 18 }, { -85, 32 } },
		{ color = Color3.fromRGB(255, 240, 220), brightness = 1, range = 24 }
	)
	-- Warm light: the employee room should feel like the safe place.
	fixtures(
		"EmployeeRoom",
		"Staff",
		11,
		"x",
		{ { -85, -20 }, { -85, 0 } },
		{ color = Color3.fromRGB(255, 226, 190), brightness = 1.1, range = 26 }
	)
	fixtures(
		"BathroomA",
		"Shop",
		11,
		"x",
		{ { -88, 70 }, { -70, 70, true } },
		{ color = Color3.fromRGB(226, 240, 236), brightness = 0.9, range = 22 }
	)
	fixtures(
		"BathroomB",
		"Shop",
		11,
		"x",
		{ { -88, 50, true }, { -70, 50 } },
		{ color = Color3.fromRGB(226, 240, 236), brightness = 0.9, range = 22 }
	)

	-- Zones -------------------------------------------------------------------------------
	local zones = k:folder(markers, "Zones")
	local zoneStyle = Kit.style(255, 255, 255, "SmoothPlastic", { alpha = 1, collide = false })
	local function zoneVolume(id, name, x1, z1, x2, z2, height, indoor, circuit, sealed)
		local volume = k:span(zones, id, x1, 0, z1, x2, height, z2, zoneStyle)
		k:mark(
			volume,
			"Zone",
			{ ZoneId = id, DisplayName = name, Indoor = indoor, Circuit = circuit, Sealed = sealed == true }
		)
	end
	for _, zone in Layout.Zones do
		zoneVolume(
			zone.id,
			zone.name,
			zone.x1,
			zone.z1,
			zone.x2,
			zone.z2,
			zone.ceiling,
			zone.indoor,
			zone.circuit,
			zone.sealed
		)
	end
	local fz = Layout.Freezer
	zoneVolume("Freezer", "Walk-in Freezer", fz.x1, fz.z1, fz.x2, fz.z2, fz.ceiling, true, "Cold")

	-- Monster patrol points ------------------------------------------------------------------
	local patrol = k:folder(markers, "PatrolNodes")
	local function patrolNodes(zone, points)
		for _, point in points do
			k:marker(patrol, zone, point[1], 3, point[2], "PatrolNode", { Zone = zone })
		end
	end
	local shopNodes = {}
	for _, x in AISLE_X do
		for _, z in { -22, 11, 46 } do
			table.insert(shopNodes, { x, z })
		end
	end
	for _, point in { { 64, -22 }, { 64, 11 }, { 64, 46 }, { 86, -22 }, { 86, 11 }, { 86, 46 } } do
		table.insert(shopNodes, point)
	end
	for _, point in { { -50, 70 }, { -20, 70 }, { 20, 72 }, { 60, 68 }, { 90, 74 }, { -36, 58 }, { -8, 58 } } do
		table.insert(shopNodes, point)
	end
	patrolNodes("ShopFloor", shopNodes)
	patrolNodes("Storage", {
		{ -85, -42 },
		{ -88, -66 },
		{ -50, -42 },
		{ -58, -72 },
		{ -20, -42 },
		{ -12, -70 },
		{ 2, -44 },
		{ -30, -56 },
	})
	patrolNodes("Maintenance", { { 25, -44 } })
	patrolNodes("Electrical", { { 25, -67 } })
	patrolNodes("Refrigeration", { { 55, -42 }, { 86, -42 }, { 60, -66 } })
	patrolNodes("Freezer", { { 86, -66 } })
	patrolNodes("StaffCorridor", { { -65, -20 }, { -65, 10 }, { -65, 35 } })
	patrolNodes("Office", { { -82, 25 } })
	patrolNodes("EmployeeRoom", { { -84, -8 }, { -76, -22 } })
	patrolNodes("BathroomA", { { -78, 70 } })
	patrolNodes("BathroomB", { { -78, 50 } })
	patrolNodes(
		"ParkingLot",
		{ { -60, 100 }, { 20, 100 }, { 80, 100 }, { -60, 153 }, { 20, 153 }, { 80, 153 } }
	)
	patrolNodes("EastAlley", { { 113, 60 }, { 113, 0 }, { 113, -60 } })
	patrolNodes("BackLot", { { 60, -105 }, { 0, -105 }, { -40, -112 }, { -100, -105 } })
	patrolNodes("WestAlley", { { -113, -60 }, { -113, 0 }, { -113, 60 } })

	-- Customer points ------------------------------------------------------------------------
	local customers = k:folder(markers, "CustomerNodes")
	for _, x in AISLE_X do
		for _, z in { -8, 28 } do
			k:marker(customers, "Browse", x, 3, z, "CustomerNode", { Kind = "Browse", Zone = "ShopFloor" })
		end
	end
	for _, point in { { 20, -24 }, { 88, 6 }, { 79, 57 }, { 64, 28 } } do
		k:marker(
			customers,
			"Browse",
			point[1],
			3,
			point[2],
			"CustomerNode",
			{ Kind = "Browse", Zone = "ShopFloor" }
		)
	end
	for lane, x in { -50, -36, -22, -8 } do
		k:marker(
			customers,
			"Queue",
			x,
			3,
			55,
			"CustomerNode",
			{ Kind = "Queue", Lane = lane, Zone = "ShopFloor" }
		)
	end
	k:marker(customers, "Entry", 20, 3, 74, "CustomerNode", { Kind = "Entry", Zone = "ShopFloor" })

	-- Task positions -------------------------------------------------------------------------
	local tasks = k:folder(markers, "TaskPoints")
	local function taskPoints(tag, zone, points)
		for _, point in points do
			k:marker(tasks, tag, point[1], 0.5, point[2], tag, { Zone = zone })
		end
	end
	local spills = {}
	for index, x in AISLE_X do
		table.insert(spills, { x, if index % 2 == 0 then -10 else 24 })
	end
	for _, point in
		{
			{ 64, -10 },
			{ 86, 24 },
			{ 20, -24 },
			{ -20, 47 },
			{ 40, 60 },
			{ -30, 68 },
			{ 70, 72 },
			{ -51, 40 },
		}
	do
		table.insert(spills, point)
	end
	taskPoints("SpillPoint", "ShopFloor", spills)
	taskPoints("SpillPoint", "BathroomA", { { -80, 68 } })
	taskPoints("SpillPoint", "BathroomB", { { -80, 52 } })
	taskPoints("SpillPoint", "Refrigeration", { { 70, -44 } })

	taskPoints(
		"TrashPoint",
		"ShopFloor",
		{ { -55, 46 }, { -9, -24 }, { 47, 11 }, { 90, 42 }, { 60, 46 }, { 10, 70 }, { -40, 68 } }
	)
	taskPoints("TrashPoint", "StaffCorridor", { { -65, 0 } })
	taskPoints("TrashPoint", "Storage", { { -30, -44 } })
	taskPoints("TrashPoint", "ParkingLot", { { -20, 99 }, { 50, 100 }, { -80, 150 }, { 30, 160 } })

	taskPoints("CartPoint", "ShopFloor", { { -37, 30 }, { 19, -12 }, { 64, 24 }, { 86, -10 } })
	taskPoints(
		"CartPoint",
		"ParkingLot",
		{ { -30, 150 }, { 60, 150 }, { -85, 100 }, { 100, 170 }, { -20, 160 } }
	)

	-- Security cameras -----------------------------------------------------------------------
	-- The tagged part's CFrame is the view; it looks along its own -Z axis like a Camera.
	local cctv = k:folder(markers, "CCTV")
	local cameraStyle = Kit.decor(P.darkSteel)
	for id, camera in
		{
			{ "ENTRANCE", "ShopFloor", { 20, 14.5, 62 }, { 20, 2, 82 } },
			{ "CHECKOUT", "ShopFloor", { -57, 14.5, 46 }, { -20, 2, 60 } },
			{ "AISLE 3", "ShopFloor", { -23, 15, -27 }, { -23, 2, 20 } },
			{ "AISLE 6", "ShopFloor", { 19, 15, 46 }, { 19, 2, -10 } },
			{ "STORAGE", "Storage", { 7, 14.5, -33 }, { -55, 1, -62 } },
			{ "EMPLOYEE ROOM", "EmployeeRoom", { -72, 10, 7.5 }, { -90, 2, -18 } },
			{ "PARKING LOT", "ParkingLot", { 20, 17, 94 }, { 20, 0, 150 } },
			{ "COLD STORAGE", "Refrigeration", { 97, 13, -33 }, { 58, 1, -62 } },
		}
	do
		local from = Vector3.new(camera[3][1], camera[3][2], camera[3][3])
		local to = Vector3.new(camera[4][1], camera[4][2], camera[4][3])
		local view = CFrame.lookAt(from, to)
		local body = k:oriented(cctv, string.format("Camera%02d", id), view, 0.9, 0.9, 1.8, cameraStyle)
		k:mark(body, "CCTVCamera", {
			CameraId = id,
			DisplayName = string.format("CAM %02d - %s", id, camera[1]),
			Zone = camera[2],
			Online = true,
		})
	end

	-- Player spawns: the employee room ----------------------------------------------------------
	local spawns = k:folder(markers, "Spawns")
	for _, point in { { -92, -8 }, { -86, -8 }, { -80, -8 }, { -92, -1 }, { -86, -1 }, { -80, -1 } } do
		k:spawn(spawns, point[1], point[2])
	end
end
