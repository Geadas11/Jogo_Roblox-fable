-- Outside the building: ground, parking lot, loading area, side alleys, the fence that
-- bounds the playable area, and the dark, empty world beyond it.

local Kit = require("./Kit")
local Layout = require("./Layout")
local P = require("./Palette")
local Props = require("./Props")

local Color3 = Kit.Color3

-- Outdoor ground sits slightly below the shop floor.
local GROUND = -0.2

return function(k, root)
	local exterior = k:folder(root, "Exterior")
	local lot = k:folder(exterior, "ParkingLot")
	local back = k:folder(exterior, "BackLot")
	local alleys = k:folder(exterior, "Alleys")
	local bounds = k:folder(exterior, "Bounds")
	local world = k:folder(exterior, "Distance")

	k:span(exterior, "Ground", -420, GROUND - 1, -420, 420, GROUND, 470, P.asphalt)

	-- Pavement in front of the store (split around the vestibule floor).
	k:span(lot, "Sidewalk", -100.5, GROUND, 80.5, 5, 0, 96, P.concrete)
	k:span(lot, "Sidewalk", 35, GROUND, 80.5, 100.5, 0, 96, P.concrete)
	k:span(lot, "Sidewalk", 5, GROUND, 92, 35, 0, 96, P.concrete)

	-- Parking bays: two double rows.
	for _, row in { { 104, 140 }, { 166, 202 } } do
		for index = 0, 20 do
			local x = -90 + index * 9
			k:span(lot, "BayLine", x - 0.2, GROUND, row[1], x + 0.2, GROUND + 0.04, row[2], P.line)
		end
		local middle = (row[1] + row[2]) / 2
		k:span(lot, "BayLine", -90, GROUND, middle - 0.2, 90, GROUND + 0.04, middle + 0.2, P.line)
	end

	-- A handful of cars left overnight.
	for _, spot in
		{
			{ -67.5, 113, true },
			{ -4.5, 113, true },
			{ 67.5, 113, false },
			{ -40.5, 131, false },
			{ 22.5, 131, true },
			{ 76.5, 175, true },
			{ -76.5, 193, false },
			{ 4.5, 193, false },
		}
	do
		Props.car(k, lot, spot[1], spot[2], spot[3], GROUND)
	end

	-- Streetlights on the islands between rows. Two of them are marked to flicker.
	local lampIndex = 0
	for _, z in { 122, 184 } do
		for _, x in { -72, 0, 72 } do
			lampIndex += 1
			local lamp = k:folder(lot, "Streetlight" .. lampIndex)
			k:cyl(lamp, "Base", x, GROUND, z, 2, 1.4, P.concrete)
			k:cyl(lamp, "Pole", x, GROUND + 1.4, z, 0.7, 20.5, P.darkSteel)
			k:span(lamp, "Head", x - 2.6, 21.7, z - 0.9, x + 2.6, 22.4, z + 0.9, P.dDarkSteel)
			local lens =
				k:span(lamp, "Lens", x - 2.3, 21.6, z - 0.7, x + 2.3, 21.7, z + 0.7, P.neon(255, 214, 160))
			k:light(lens, "SpotLight", {
				brightness = 2.2,
				range = 60,
				angle = 120,
				color = Color3.fromRGB(255, 214, 160),
				shadows = true,
				side = "D",
			})
			k:mark(lens, "LightFixture", {
				Zone = "ParkingLot",
				Circuit = "Exterior",
				BaseBrightness = 2.2,
				Flicker = lampIndex == 2 or lampIndex == 4,
			})
		end
	end

	-- Cart corral in the lot.
	local corral = k:folder(lot, "CartCorral")
	k:span(corral, "RailWest", 40, GROUND, 124, 40.3, 3, 138, P.steel)
	k:span(corral, "RailEast", 51.7, GROUND, 124, 52, 3, 138, P.steel)
	k:span(corral, "RailBack", 40, GROUND, 124, 52, 3, 124.3, P.steel)
	local corralSign = k:span(corral, "Sign", 42, 5, 124, 50, 6.6, 124.2, P.dBlue)
	k:text(corralSign, "S", "CART RETURN")
	k:span(corral, "SignPostA", 42.2, 3, 124.05, 42.4, 5, 124.2, P.dDarkSteel)
	k:span(corral, "SignPostB", 49.6, 3, 124.05, 49.8, 5, 124.2, P.dDarkSteel)
	Props.cart(k, corral, 44, 128, false, GROUND)
	Props.cart(k, corral, 48, 127.5, false, GROUND)

	-- Storefront furniture.
	for _, x in { 9, 13, 27, 31 } do
		k:cyl(lot, "Bollard", x, 0, 95, 0.9, 3.4, P.yellow)
	end
	k:cyl(lot, "TrashCan", 1.5, 0, 84, 2, 3, P.darkSteel)
	k:cyl(lot, "TrashCan", 38.5, 0, 84, 2, 3, P.darkSteel)
	k:span(lot, "BenchSeat", -24, 1.4, 82.2, -14, 1.7, 84.2, P.wood)
	k:span(lot, "BenchLegA", -23.6, 0, 82.4, -23.2, 1.4, 84, P.dDarkSteel)
	k:span(lot, "BenchLegB", -14.8, 0, 82.4, -14.4, 1.4, 84, P.dDarkSteel)
	local staffParking = k:span(lot, "StaffParkingSign", 29.5, 5, 103.4, 33.5, 7, 103.6, P.dBlue)
	k:text(staffParking, "S", "STAFF\nPARKING")
	k:cyl(lot, "SignPost", 31.5, GROUND, 103.5, 0.3, 5.2, P.dDarkSteel)

	-- Store sign above the entrance, lit from within.
	local sign = k:span(lot, "StoreSign", -14, 12.9, 80.6, 54, 17.6, 81.4, P.dDarkSteel)
	k:text(sign, "S", Layout.StoreName, { glow = 2.5, color = Color3.fromRGB(255, 238, 214), pps = 16 })
	k:light(sign, "SurfaceLight", {
		brightness = 1.2,
		range = 28,
		angle = 150,
		color = Color3.fromRGB(255, 236, 210),
		side = "S",
	})
	k:mark(
		sign,
		"LightFixture",
		{ Zone = "ParkingLot", Circuit = "Exterior", BaseBrightness = 1.2, Flicker = true }
	)

	-- Wall lights around the building.
	local function wallLight(parent, name, x, y, z, side, zone, flicker)
		local dx, dz = 0, 0
		if side == "S" then
			dz = 1
		elseif side == "N" then
			dz = -1
		elseif side == "E" then
			dx = 1
		else
			dx = -1
		end
		local wide = if dx == 0 then 1.2 else 0.3
		local deep = if dx == 0 then 0.3 else 1.2
		local lamp = k:span(
			parent,
			name,
			x - wide + dx * 0.3,
			y,
			z - deep + dz * 0.3,
			x + wide + dx * 0.3,
			y + 0.8,
			z + deep + dz * 0.3,
			P.neon(240, 232, 214)
		)
		k:light(
			lamp,
			"SurfaceLight",
			{ brightness = 0.9, range = 24, angle = 140, color = Color3.fromRGB(240, 232, 214), side = side }
		)
		k:mark(
			lamp,
			"LightFixture",
			{ Zone = zone, Circuit = "Exterior", BaseBrightness = 0.9, Flicker = flicker == true }
		)
	end
	wallLight(lot, "FrontLightWest", -80, 12, 80.5, "S", "ParkingLot")
	wallLight(lot, "FrontLightEast", 80, 12, 80.5, "S", "ParkingLot")
	wallLight(back, "BackDoorLight", -7.5, 9, -80.5, "N", "BackLot")
	wallLight(back, "DockLight", -56, 13.5, -80.5, "N", "BackLot", true)
	-- Over the dumpsters: without it the trash run ends in pitch darkness.
	wallLight(back, "DumpsterLight", 30, 10, -80.5, "N", "BackLot")
	wallLight(alleys, "EastAlleyLight", 100.5, 11, 54.5, "E", "EastAlley")
	wallLight(alleys, "WestAlleyLight", -100.5, 11, -20, "W", "WestAlley", true)

	-- Loading area ------------------------------------------------------------------------
	-- A trailer left at the first dock.
	local trailer = k:folder(back, "Trailer")
	k:span(trailer, "Box", -76.5, 3.4, -111, -65.5, 15, -81.2, P.white)
	k:span(trailer, "Chassis", -75.5, 2.6, -111, -66.5, 3.4, -82, P.darkSteel)
	for _, z in { -90, -86 } do
		for _, x in { -76.2, -66.8 } do
			k:cyl(trailer, "Wheel", x, GROUND, z, 3, 1.2, P.dBlack, "x")
		end
	end
	k:span(trailer, "LandingGearA", -75, GROUND, -107, -74.4, 2.6, -106.4, P.dDarkSteel)
	k:span(trailer, "LandingGearB", -67.6, GROUND, -107, -67, 2.6, -106.4, P.dDarkSteel)
	for _, x in { -80.5, -62, -50.5, -32 } do
		k:span(back, "DockBumper", x, 1, -81.3, x + 0.6, 4, -80.5, P.dRubber)
	end

	for index, x in { 18, 34 } do
		local dumpster = k:span(back, "Dumpster" .. index, x, GROUND, -97, x + 12, 5, -90, P.green)
		k:mark(dumpster, "Dumpster", { Zone = "BackLot" })
		k:span(dumpster, "Lid", x - 0.2, 5, -97.2, x + 12.2, 5.4, -89.8, P.dBlack)
	end
	for layer = 0, 5 do
		k:span(
			back,
			"PalletStack",
			-30,
			GROUND + layer * 0.6,
			-94,
			-24,
			GROUND + layer * 0.6 + 0.5,
			-88,
			P.wood
		)
	end
	k:span(back, "Crate", 60, GROUND, -92, 64, 3.6, -88, P.wood)
	k:span(back, "Crate", 64.5, GROUND, -91, 67.5, 2.4, -88, P.wood)

	-- Side alleys ---------------------------------------------------------------------------
	for index, z in { -50, 10 } do
		local unit = k:span(alleys, "AirConditioner" .. index, 101, GROUND, z, 107, 5, z + 8, P.steel)
		k:cyl(unit, "Fan", 104, 5, z + 4, 4, 0.4, P.dDarkSteel)
		k:cyl(unit, "Pipe", 100.9, 5, z + 1, 0.6, 12, P.dSteel)
	end
	for _, bag in { { 110, 62 }, { 112, 64.5 }, { 109.5, 65 }, { -112, 30 }, { -110, 32.5 } } do
		k:ball(alleys, "TrashBag", bag[1], GROUND + 1.2, bag[2], 2.6, Kit.decor(P.black))
	end
	k:span(alleys, "OldCrate", -112, GROUND, -40, -108, 3, -36, P.wood)
	k:span(alleys, "OldCrate", -111, GROUND, -35.5, -108.5, 2, -33, P.wood)

	-- Bounds --------------------------------------------------------------------------------
	-- A low wall players can see over, with an invisible barrier above it.
	local g = Layout.Grounds
	local function boundary(name, x1, z1, x2, z2)
		k:span(bounds, name .. "Wall", x1, GROUND, z1, x2, 3.2, z2, P.concrete)
		k:span(bounds, name .. "Barrier", x1, 3.2, z1, x2, 60, z2, P.barrier)
	end
	boundary("North", g.x1, g.z1 - 1, g.x2, g.z1)
	boundary("South", g.x1, g.z2, g.x2, g.z2 + 1)
	boundary("West", g.x1 - 1, g.z1 - 1, g.x1, g.z2 + 1)
	boundary("East", g.x2, g.z1 - 1, g.x2 + 1, g.z2 + 1)

	-- The world beyond ---------------------------------------------------------------------
	-- Road in front of the lot.
	for index = 0, 15 do
		local x = -150 + index * 20
		k:span(world, "RoadDash", x, GROUND, 229.7, x + 9, GROUND + 0.04, 230.3, P.lineYellow)
	end
	k:span(world, "FarSidewalk", -200, GROUND, 250, 200, 0, 258, Kit.decor(P.concrete))

	-- Dark, distant buildings with the odd lit window.
	for _, building in
		{
			{ -150, 330, 90, 50, 46 },
			{ -30, 350, 70, 60, 70 },
			{ 80, 340, 100, 50, 38 },
			{ 190, 320, 60, 60, 56 },
			{ 300, 60, 60, 120, 44 },
			{ 290, -120, 70, 70, 62 },
			{ -300, 20, 60, 140, 40 },
			{ -280, 180, 80, 60, 58 },
			{ -80, -300, 120, 50, 36 },
			{ 90, -310, 90, 60, 50 },
		}
	do
		local cx, cz, sx, sz, height = building[1], building[2], building[3], building[4], building[5]
		local block = k:span(
			world,
			"DistantBuilding",
			cx - sx / 2,
			GROUND,
			cz - sz / 2,
			cx + sx / 2,
			height,
			cz + sz / 2,
			P.distant
		)
		-- Windows on the face that looks towards the store.
		local facesZ = math.abs(cz) > math.abs(cx)
		for _ = 1, k:int(1, 4) do
			local y = k:range(8, height - 6)
			local window = P.neon(190, 170, 120)
			if facesZ then
				local wx = cx + k:range(-sx / 2 + 4, sx / 2 - 8)
				local face = if cz > 0 then cz - sz / 2 else cz + sz / 2
				k:span(block, "Window", wx, y, face - 0.1, wx + 3, y + 4, face + 0.1, window)
			else
				local wz = cz + k:range(-sz / 2 + 4, sz / 2 - 8)
				local face = if cx > 0 then cx - sx / 2 else cx + sx / 2
				k:span(block, "Window", face - 0.1, y, wz, face + 0.1, y + 4, wz + 3, window)
			end
		end
	end
end
