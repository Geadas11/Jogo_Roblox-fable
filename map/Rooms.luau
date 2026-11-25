-- Everything behind the shop floor: storage, maintenance, electrical room, cold storage,
-- the staff corridor, office, employee room and the two restrooms.

local Kit = require("./Kit")
local Layout = require("./Layout")
local P = require("./Palette")

local Color3 = Kit.Color3

return function(k, root)
	-- Shared pieces ---------------------------------------------------------------------

	local function cardboardBox(parent, x, y, z, sx, sy, sz)
		local style = table.clone(P.dCardboard)
		local shade = k:range(0.85, 1.1)
		style.color =
			Color3.fromRGB(math.min(255, 164 * shade), math.min(255, 126 * shade), math.min(255, 84 * shade))
		k:span(parent, "Box", x, y, z, x + sx, y + sy, z + sz, style)
	end

	-- Fills a footprint with a loose row of cardboard boxes standing on height `y`.
	-- `solid`: a full row of full-height boxes (something will be stacked on it).
	local function boxRow(parent, x1, z1, x2, z2, y, maxHeight, solid)
		local alongX = (x2 - x1) >= (z2 - z1)
		local cursor = if alongX then x1 else z1
		local limit = if alongX then x2 else z2
		local depth = if alongX then z2 - z1 else x2 - x1
		while cursor < limit - 1.2 do
			local length = math.min(k:range(1.6, 3.2), limit - cursor)
			if solid or not k:chance(0.12) then
				local d = k:range(depth * 0.6, depth * 0.95)
				local h = if solid then maxHeight else k:range(maxHeight * 0.45, maxHeight)
				if alongX then
					cardboardBox(parent, cursor, y, z1 + (depth - d) / 2, length - 0.15, h, d)
				else
					cardboardBox(parent, x1 + (depth - d) / 2, y, cursor, d, h, length - 0.15)
				end
			end
			cursor += length
		end
	end

	-- Heavy-duty storage rack with two shelves of boxes above floor level.
	local function rack(parent, x1, z1, x2, z2)
		local unit = k:folder(parent, "Rack")
		k:span(unit, "Collider", x1, 0, z1, x2, 12, z2, P.collider)
		local alongX = (x2 - x1) >= (z2 - z1)
		local from, to = if alongX then x1 else z1, if alongX then x2 else z2
		local position = from
		while position <= to + 0.01 do
			if alongX then
				k:span(unit, "Upright", position - 0.15, 0, z1, position + 0.15, 12, z1 + 0.3, P.dBlue)
				k:span(unit, "Upright", position - 0.15, 0, z2 - 0.3, position + 0.15, 12, z2, P.dBlue)
			else
				k:span(unit, "Upright", x1, 0, position - 0.15, x1 + 0.3, 12, position + 0.15, P.dBlue)
				k:span(unit, "Upright", x2 - 0.3, 0, position - 0.15, x2, 12, position + 0.15, P.dBlue)
			end
			position += (to - from) / math.max(1, math.floor((to - from) / 9 + 0.5))
		end
		for _, y in { 4, 8 } do
			k:span(unit, "Deck", x1, y - 0.25, z1, x2, y, z2, Kit.decor(P.yellow))
		end
		for _, y in { 0, 4, 8 } do
			boxRow(unit, x1 + 0.3, z1 + 0.2, x2 - 0.3, z2 - 0.2, y, 3.2)
		end
	end

	-- Pallet with a stack of boxes.
	local function pallet(parent, x, z, layers)
		local unit = k:folder(parent, "Pallet")
		k:span(unit, "Pallet", x, 0, z, x + 5, 0.5, z + 5, P.wood)
		if layers > 0 then
			k:span(unit, "Collider", x + 0.2, 0.5, z + 0.2, x + 4.8, 0.5 + layers * 1.6, z + 4.8, P.collider)
			-- Every layer but the top one is a full layer, so nothing above it floats.
			for layer = 0, layers - 1 do
				local solid = layer < layers - 1
				boxRow(unit, x + 0.2, z + 0.2, x + 4.8, z + 2.4, 0.5 + layer * 1.6, 1.6, solid)
				boxRow(unit, x + 0.2, z + 2.6, x + 4.8, z + 4.8, 0.5 + layer * 1.6, 1.6, solid)
			end
		end
	end

	-- Row of metal lockers. `hiding` lists the lockers players can hide in.
	--   facing  compass direction the doors face
	local function lockers(parent, x1, z1, x2, z2, facing, zone, hiding)
		local alongX = facing == "N" or facing == "S"
		local count = math.floor(((if alongX then x2 - x1 else z2 - z1) + 0.01) / 3)
		for index = 1, count do
			local a = (index - 1) * 3
			local lx1, lz1, lx2, lz2
			if alongX then
				lx1, lx2, lz1, lz2 = x1 + a, x1 + a + 3, z1, z2
			else
				lx1, lx2, lz1, lz2 = x1, x2, z1 + a, z1 + a + 3
			end
			local locker = k:span(parent, "Locker", lx1 + 0.05, 0, lz1, lx2 - 0.05, 7, lz2, P.grey)
			-- Door seam and vents on the front face.
			local fx = if facing == "E" then lx2 elseif facing == "W" then lx1 else nil
			local fz = if facing == "S" then lz2 elseif facing == "N" then lz1 else nil
			if fx then
				local out = if facing == "E" then 0.05 else -0.05
				k:span(locker, "Vent", fx, 5.6, lz1 + 0.6, fx + out, 6.2, lz2 - 0.6, P.dDarkSteel)
				k:span(locker, "Handle", fx, 3.4, lz2 - 0.7, fx + out * 3, 3.9, lz2 - 0.5, P.dDarkSteel)
			else
				local out = if facing == "S" then 0.05 else -0.05
				k:span(locker, "Vent", lx1 + 0.6, 5.6, fz, lx2 - 0.6, 6.2, fz + out, P.dDarkSteel)
				k:span(locker, "Handle", lx2 - 0.7, 3.4, fz, lx2 - 0.5, 3.9, fz + out * 3, P.dDarkSteel)
			end
			if table.find(hiding, index) then
				k:mark(locker, "HidingSpot", { Kind = "Locker", Zone = zone })
			end
		end
	end

	local function chair(parent, x, z, backSide)
		local unit = k:folder(parent, "Chair")
		k:span(unit, "Seat", x - 0.9, 1.5, z - 0.9, x + 0.9, 1.75, z + 0.9, P.dBlack)
		for _, lx in { x - 0.8, x + 0.65 } do
			for _, lz in { z - 0.8, z + 0.65 } do
				k:span(unit, "Leg", lx, 0, lz, lx + 0.15, 1.5, lz + 0.15, P.dDarkSteel)
			end
		end
		if backSide == "N" then
			k:span(unit, "Back", x - 0.9, 1.75, z - 0.9, x + 0.9, 3.6, z - 0.7, P.dBlack)
		elseif backSide == "S" then
			k:span(unit, "Back", x - 0.9, 1.75, z + 0.7, x + 0.9, 3.6, z + 0.9, P.dBlack)
		elseif backSide == "W" then
			k:span(unit, "Back", x - 0.9, 1.75, z - 0.9, x - 0.7, 3.6, z + 0.9, P.dBlack)
		else
			k:span(unit, "Back", x + 0.7, 1.75, z - 0.9, x + 0.9, 3.6, z + 0.9, P.dBlack)
		end
	end

	-- Open shelving: invisible collider, corner posts and decks. Callers place goods on it.
	local function openShelf(parent, name, x1, z1, x2, z2, height, deckHeights, style)
		local unit = k:folder(parent, name)
		k:span(unit, "Collider", x1, 0, z1, x2, height, z2, P.collider)
		for _, x in { x1, x2 - 0.2 } do
			for _, z in { z1, z2 - 0.2 } do
				k:span(unit, "Post", x, 0, z, x + 0.2, height, z + 0.2, style)
			end
		end
		for _, y in deckHeights do
			k:span(unit, "Deck", x1, y - 0.12, z1, x2, y, z2, style)
		end
		return unit
	end

	local function bin(parent, x, z)
		k:cyl(parent, "TrashBin", x, 0, z, 1.6, 2.4, P.darkSteel)
	end

	-- Storage room ------------------------------------------------------------------------
	local storage = k:folder(root, "Storage")
	rack(storage, -98, -34, -72, -31)
	rack(storage, -58, -34, -30, -31)
	rack(storage, -95, -54, -45, -50)
	rack(storage, -99, -76, -96, -58)
	pallet(storage, -74, -73, 2)
	pallet(storage, -66, -72, 1)
	pallet(storage, -44, -73, 3)
	pallet(storage, -36, -66, 1)
	pallet(storage, -56, -64, 0)
	pallet(storage, 0, -58, 2)
	pallet(storage, -22, -66, 2)
	lockers(storage, 7.4, -78, 9.5, -63, "W", "Storage", { 2, 4 })

	-- Pallet jack.
	local jack = k:folder(storage, "PalletJack")
	k:span(jack, "ForkA", -62, 0.1, -64, -61.3, 0.4, -59, P.yellow)
	k:span(jack, "ForkB", -60.2, 0.1, -64, -59.5, 0.4, -59, P.yellow)
	k:span(jack, "Body", -62.2, 0, -58.9, -59.3, 1.6, -57.8, P.yellow)
	k:span(jack, "Handle", -60.9, 1.6, -58.5, -60.6, 4.4, -58.2, P.dDarkSteel)

	-- Receiving desk by the stock doors.
	k:span(storage, "ReceivingDesk", -12, 0, -33.6, -5, 3, -31, P.wood)
	k:span(storage, "Clipboard", -10.5, 3, -33, -9.3, 3.06, -31.6, P.dWhite)
	k:span(storage, "LabelPrinter", -7.6, 3, -33, -6, 3.8, -31.8, P.dGrey)

	for index, x in { -71, -41 } do
		k:marker(storage, "DeliveryPoint" .. index, x, 0.5, -76, "DeliveryPoint", { Zone = "Storage" })
	end
	k:marker(storage, "DeliveryPoint3", -52, 0.5, -68, "DeliveryPoint", { Zone = "Storage" })

	-- Maintenance room --------------------------------------------------------------------
	local maintenance = k:folder(root, "Maintenance")
	k:span(maintenance, "Workbench", 14, 0, -33.2, 30, 3, -30.6, P.wood)
	k:span(maintenance, "ToolBoard", 15, 4, -30.7, 29, 8, -30.55, Kit.decor(P.woodDark))
	for index = 0, 5 do
		local x = 16 + index * 2.2
		k:span(
			maintenance,
			"Tool",
			x,
			4.6 + (index % 2) * 0.6,
			-30.85,
			x + k:range(0.3, 0.9),
			7.2,
			-30.7,
			P.dSteel
		)
	end
	local toolbox = k:span(maintenance, "Toolbox", 26, 3, -32.6, 28.6, 4, -31.4, Kit.decor(P.red))
	k:mark(toolbox, "ToolPickup", { Tool = "Toolbox", Zone = "Maintenance" })

	local supply = openShelf(maintenance, "SupplyShelf", 30, -57.4, 39, -55.4, 7, { 1.2, 3.2, 5.2 }, P.dSteel)
	for _, y in { 1.2, 3.2, 5.2 } do
		local x = 30.4
		while x < 38.4 do
			local style = {
				color = Color3.fromHSV(k:rand(), 0.6, 0.8),
				material = Kit.Enum.Material.SmoothPlastic,
				collide = false,
			}
			k:cyl(supply, "Bottle", x + 0.35, y, -56.1, 0.6, k:range(0.9, 1.4), style)
			x += k:range(0.8, 1.3)
		end
	end
	local bucket = k:span(maintenance, "MopBucket", 34, 0, -53, 36, 1.5, -51, P.yellow)
	k:cyl(bucket, "MopHandle", 35.6, 0.6, -52, 0.18, 5.2, P.dWood)
	k:mark(bucket, "ToolPickup", { Tool = "Mop", Zone = "Maintenance" })
	local tubes = k:span(maintenance, "LightTubeCrate", 30.5, 0, -53.5, 32.5, 1.2, -49.5, P.cardboard)
	k:mark(tubes, "ToolPickup", { Tool = "LightTube", Zone = "Maintenance" })
	lockers(maintenance, 11, -57.4, 17, -55.4, "S", "Maintenance", { 1, 2 })
	local danger = k:span(maintenance, "DangerSign", 17.6, 4, -57.45, 21.6, 6.4, -57.3, P.dYellow)
	k:text(danger, "S", "DANGER\nHIGH VOLTAGE", { color = Color3.fromRGB(20, 20, 20) })

	-- Electrical room ---------------------------------------------------------------------
	local electrical = k:folder(root, "Electrical")
	local panel = k:span(electrical, "MainPanel", 19, 1, -79.5, 31, 8.5, -78.3, P.grey)
	k:mark(panel, "ElectricalPanel", { Zone = "Electrical" })
	k:span(panel, "PanelDoor", 19.4, 1.4, -78.3, 30.6, 8.1, -78.22, P.dDarkSteel)
	local plate = k:span(panel, "NamePlate", 21, 6.6, -78.22, 29, 7.6, -78.18, P.dWhite)
	k:text(plate, "S", "MAIN DISTRIBUTION", { color = Color3.fromRGB(20, 20, 20) })
	for index = 0, 2 do
		k:span(
			panel,
			"StatusLamp",
			22.5 + index * 2.2,
			5.4,
			-78.22,
			23.3 + index * 2.2,
			6.0,
			-78.14,
			P.neon(80, 220, 110)
		)
	end
	for index = 0, 2 do
		k:cyl(electrical, "Conduit", 21 + index * 4, 8.5, -78.9, 0.5, 2.5, P.dSteel)
	end

	for index, circuit in { "Shop", "BackOfHouse", "Cold", "Staff", "Exterior" } do
		local z = -77.5 + (index - 1) * 3.4
		local breaker = k:span(electrical, "Breaker" .. circuit, 38.8, 3, z, 39.5, 6, z + 2.2, P.darkSteel)
		k:mark(breaker, "Breaker", { Circuit = circuit, On = true })
		local label = k:span(breaker, "Label", 38.7, 6.1, z, 38.8, 6.9, z + 2.2, P.dWhite)
		k:text(label, "W", string.upper(circuit), { color = Color3.fromRGB(20, 20, 20) })
		k:span(breaker, "Switch", 38.6, 4, z + 0.8, 38.8, 5.2, z + 1.4, P.dRed)
	end

	local generator = k:span(electrical, "Generator", 11, 0, -78, 17, 5, -70, P.green)
	k:mark(generator, "RepairPoint", { Kind = "Generator", Zone = "Electrical" })
	k:cyl(generator, "Exhaust", 12.5, 5, -76, 0.8, 5.5, P.dDarkSteel)
	k:span(generator, "ControlBox", 17, 2, -76, 17.3, 4, -73, P.dGrey)

	-- Cold storage ------------------------------------------------------------------------
	local cold = k:folder(root, "ColdStorage")
	for index = 0, 3 do
		local x = 42 + index * 7
		local unit = k:span(cold, "IndustrialFridge" .. (index + 1), x, 0, -79.5, x + 6.8, 9, -76, P.steel)
		k:mark(unit, "FridgeUnit", { Kind = "Industrial", Working = true })
		k:span(unit, "Seam", x + 3.35, 0.4, -76, x + 3.45, 8.6, -75.95, P.dDarkSteel)
		k:span(unit, "HandleA", x + 2.7, 3.5, -76, x + 2.9, 5.5, -75.8, P.dDarkSteel)
		k:span(unit, "HandleB", x + 3.9, 3.5, -76, x + 4.1, 5.5, -75.8, P.dDarkSteel)
		k:span(unit, "Display", x + 0.6, 7.6, -76, x + 2, 8.2, -75.95, P.neon(90, 200, 230))
	end

	local compressor = k:span(cold, "Compressor", 40.5, 0, -72, 44.5, 5, -60, P.darkSteel)
	k:mark(compressor, "RepairPoint", { Kind = "Compressor", Zone = "Refrigeration" })
	k:cyl(compressor, "Fan", 44.5, 1.2, -69, 2.6, 0.3, P.dSteel, "x")
	k:cyl(compressor, "Fan", 44.5, 1.2, -63, 2.6, 0.3, P.dSteel, "x")
	k:cyl(compressor, "Pipe", 42, 5, -66, 0.6, 9, P.dSteel)

	local shelfSouth = openShelf(cold, "WireShelfSouth", 44, -33.6, 62, -30.6, 7, { 0.4, 2.6, 4.8 }, P.dSteel)
	local shelfEast = openShelf(cold, "WireShelfEast", 96.5, -52, 99.5, -34, 7, { 0.4, 2.6, 4.8 }, P.dSteel)
	for _, y in { 0.4, 2.6, 4.8 } do
		boxRow(shelfSouth, 44.3, -33.3, 61.7, -30.9, y, 1.8)
		boxRow(shelfEast, 96.8, -51.7, 99.2, -34.3, y, 1.8)
	end
	pallet(cold, 50, -58, 2)

	k:span(cold, "CeilingCooler", 52, 12.4, -50, 62, 14, -44, P.dSteel)
	k:cyl(cold, "CoolerFan", 54.5, 12.2, -47, 2.6, 0.25, P.dDarkSteel)
	k:cyl(cold, "CoolerFan", 59.5, 12.2, -47, 2.6, 0.25, P.dDarkSteel)

	-- Walk-in freezer.
	local fz = Layout.Freezer
	local freezer = k:folder(cold, "Freezer")
	k:span(
		freezer,
		"FrostFloor",
		fz.x1 + 0.5,
		0,
		fz.z1 + 0.5,
		fz.x2 - 0.5,
		0.05,
		fz.z2 - 0.5,
		Kit.decor(P.frost)
	)
	openShelf(freezer, "ShelfNorth", 74, -79.5, 96, -77, 7, { 0.4, 2.6, 4.8 }, P.dSteel)
	openShelf(freezer, "ShelfEast", 97, -76, 99.5, -58, 7, { 0.4, 2.6, 4.8 }, P.dSteel)
	for _, y in { 0.4, 2.6, 4.8 } do
		local frozen = table.clone(P.dWhite)
		frozen.color = Color3.fromRGB(200, 216, 226)
		local x = 74.3
		while x < 95 do
			local length = k:range(1.8, 3.4)
			k:span(freezer, "FrozenCase", x, y, -79.2, x + length - 0.2, y + k:range(0.9, 1.7), -77.3, frozen)
			x += length
		end
		local z = -75.7
		while z < -59.5 do
			local length = k:range(1.8, 3.4)
			k:span(freezer, "FrozenCase", 97.3, y, z, 99.2, y + k:range(0.9, 1.7), z + length - 0.2, frozen)
			z += length
		end
	end
	local freezerSign =
		k:span(freezer, "FreezerSign", 80.5, 7.9, fz.z2 + 0.5, 88.5, 9.1, fz.z2 + 0.65, P.dBlue)
	k:text(freezerSign, "S", "FREEZER  -18°C")

	-- Staff corridor ----------------------------------------------------------------------
	local corridor = k:folder(root, "StaffCorridor")
	k:cyl(corridor, "FireExtinguisher", -61.1, 2, 12, 0.8, 2.2, Kit.decor(P.red))
	local board = k:span(corridor, "SafetyBoard", -60.7, 3.6, -2, -60.55, 7.4, 6, P.dWhite)
	k:text(board, "W", "SAFETY FIRST\n\n0 DAYS\nSINCE LAST INCIDENT", { color = Color3.fromRGB(30, 30, 30) })
	bin(corridor, -61.6, 37.6)

	-- Office ------------------------------------------------------------------------------
	local office = k:folder(root, "Office")
	k:span(office, "DeskTop", -97.5, 2.8, 19, -91.5, 3.05, 31, P.woodDark)
	k:span(office, "DeskSideA", -97.5, 0, 19, -91.5, 2.8, 19.3, P.woodDark)
	k:span(office, "DeskSideB", -97.5, 0, 30.7, -91.5, 2.8, 31, P.woodDark)
	k:span(office, "DeskDrawers", -97.5, 0, 28, -92, 2.8, 30.7, Kit.decor(P.woodDark))
	-- Under the desk, facing out of its open side (east, towards the chair).
	local underDesk =
		k:marker(office, "UnderDesk", -94.5, 1.4, 23, "HidingSpot", { Kind = "UnderDesk", Zone = "Office" })
	underDesk.CFrame = Kit.CFrame.lookAt(Kit.Vector3.new(-94.5, 1.4, 23), Kit.Vector3.new(-93.5, 1.4, 23))
	chair(office, -89.6, 25, "E")

	local monitor = k:span(office, "ComputerMonitor", -96.5, 3.6, 23.4, -96.3, 5.4, 26.6, P.dBlack)
	k:mark(monitor, "OfficeComputer", { Zone = "Office" })
	k:span(monitor, "Screen", -96.3, 3.75, 23.55, -96.26, 5.25, 26.45, P.neon(40, 70, 90))
	k:span(monitor, "Stand", -96.7, 3.05, 24.6, -96.2, 3.6, 25.4, P.dBlack)
	k:span(office, "Keyboard", -95.4, 3.05, 24, -94.6, 3.15, 26, P.dBlack)
	for index, z in { 20.2, 21.6, 28.2 } do
		k:span(office, "Document" .. index, -95.6, 3.05, z, -94.4, 3.08, z + 0.9, P.dWhite)
	end

	-- Wall of CCTV monitors above the desk.
	for row = 0, 1 do
		for column = 0, 2 do
			local z = 19.4 + column * 4
			local y = 5.9 + row * 2.3
			local screen = k:span(office, "SecurityMonitor", -99.45, y, z, -99.25, y + 2, z + 3.6, P.dBlack)
			k:mark(screen, "SecurityMonitor", { Index = row * 3 + column + 1, Zone = "Office" })
			k:span(
				screen,
				"Screen",
				-99.25,
				y + 0.12,
				z + 0.12,
				-99.2,
				y + 1.88,
				z + 3.48,
				P.neon(34, 52, 60)
			)
		end
	end

	for index = 0, 2 do
		local x = -98 + index * 3
		local cabinet = k:span(office, "FilingCabinet", x, 0, 37.3, x + 2.9, 5.2, 39.4, P.grey)
		for drawer = 0, 2 do
			k:span(
				cabinet,
				"Drawer",
				x + 0.2,
				0.4 + drawer * 1.6,
				37.24,
				x + 2.7,
				1.8 + drawer * 1.6,
				37.3,
				P.dDarkSteel
			)
		end
	end
	local bookshelf =
		openShelf(office, "Bookshelf", -98, 10.6, -84, 12.4, 7, { 0.6, 2.7, 4.8 }, Kit.decor(P.woodDark))
	k:span(bookshelf, "BackPanel", -98, 0, 10.6, -84, 7, 10.75, Kit.decor(P.woodDark))
	for _, y in { 0.6, 2.7, 4.8 } do
		local x = -97.6
		while x < -84.8 do
			local width = k:range(0.35, 0.7)
			local style = {
				color = Color3.fromHSV(k:rand(), 0.45, k:range(0.35, 0.7)),
				material = Kit.Enum.Material.SmoothPlastic,
				collide = false,
			}
			k:span(bookshelf, "Binder", x, y, 11.2, x + width - 0.05, y + k:range(1.3, 1.8), 12.3, style)
			x += width
		end
	end
	k:span(office, "Safe", -74.5, 0, 11, -71, 3.4, 14.4, P.darkSteel)
	local storeMap = k:span(office, "StoreMap", -70.7, 3.5, 30, -70.55, 8, 38, P.dWhite)
	k:text(storeMap, "W", "STORE MAP", { color = Color3.fromRGB(30, 30, 30) })
	chair(office, -80, 34, "S")
	bin(office, -88, 33)

	-- Employee room -----------------------------------------------------------------------
	local staff = k:folder(root, "EmployeeRoom")
	k:span(staff, "Counter", -98, 0, -29.5, -82, 3, -27, P.offWhite)
	k:span(staff, "Sink", -90, 3, -29.2, -87, 3.05, -27.4, P.dDarkSteel)
	k:span(staff, "Microwave", -97, 3, -29.3, -94.2, 4.6, -27.6, P.dBlack)
	k:span(staff, "CoffeeMachine", -93, 3, -29.2, -91.6, 4.8, -27.8, P.dDarkSteel)
	local staffMonitor = k:span(staff, "SecurityMonitor", -85.6, 3, -29.3, -83, 4.9, -29.1, P.dBlack)
	k:mark(staffMonitor, "SecurityMonitor", { Index = 7, Zone = "EmployeeRoom" })
	k:span(staffMonitor, "Screen", -85.5, 3.1, -29.1, -83.1, 4.8, -29.05, P.neon(34, 52, 60))
	k:span(staff, "Fridge", -81.5, 0, -29.5, -78, 7, -26.5, P.white)

	-- Snack and drink machine against the west wall, facing east (+X).
	-- Seen from the front: the glass window with the goods on the left, the keypad
	-- column on the right, the pick-up flap underneath. Purely visual.
	do
		local vending = k:model(staff, "VendingMachine")
		local body = P.darkSteel
		local trim = P.dSteel
		local front = -96.5
		-- Back block, the keypad column (right, -Z side), the narrow left jamb, base and top.
		k:span(vending, "Cabinet", -99.5, 0, -22, -97.9, 7.5, -17.5, body)
		k:span(vending, "KeypadColumn", -97.9, 0, -22, front, 7.5, -20.3, body)
		k:span(vending, "Jamb", -97.9, 2.1, -17.8, front, 6.9, -17.5, body)
		k:span(vending, "Base", -97.9, 0, -20.3, front, 2.1, -17.5, body)
		k:span(vending, "Header", -97.9, 6.9, -20.3, front, 7.5, -17.5, body)
		-- Lit sign on top of the front.
		local sign =
			k:span(vending, "Sign", front, 6.95, -21.9, front + 0.06, 7.45, -17.6, P.neon(70, 140, 225))
		k:text(sign, "E", "COLD DRINKS  ·  SNACKS", { glow = 1.6, pps = 30 })

		-- Inside the window: a light back panel, five shelves of goods, price tags.
		k:span(vending, "BackPanel", -97.95, 2.1, -20.3, -97.85, 6.9, -17.8, P.dSteel)
		k:span(vending, "InnerLight", -97.8, 6.75, -20.25, front - 0.15, 6.85, -17.85, P.neon(235, 245, 255))
		-- The cabinet is lit from inside only, like a real machine: a short light strip just
		-- behind the glass under the top and under every shelf (hidden behind the price-tag
		-- lips), each shining back onto the row beneath it. Their reach is short, so the
		-- light leaves only through the window and never lands on the cabinet's outside.
		for _, stripY in { 6.7, 5.86, 4.94, 4.02, 3.1 } do
			local strip = k:span(
				vending,
				"LightStrip",
				-96.76,
				stripY - 0.05,
				-20.25,
				-96.66,
				stripY,
				-17.85,
				P.neon(235, 245, 255)
			)
			-- Facing back into the machine, at the goods' fronts, never out of the glass.
			local light = k:light(strip, "SurfaceLight", {
				brightness = 1.1,
				range = 1.8,
				angle = 180,
				color = Color3.fromRGB(225, 238, 255),
				shadows = false,
				side = "W",
			})
			light.Name = "VendingLight"
		end
		local rows = { "A", "B", "C", "D", "E" }
		local snackColors = {
			Color3.fromRGB(210, 40, 40),
			Color3.fromRGB(240, 190, 40),
			Color3.fromRGB(40, 110, 200),
			Color3.fromRGB(60, 160, 70),
			Color3.fromRGB(230, 110, 30),
			Color3.fromRGB(120, 60, 160),
			Color3.fromRGB(240, 240, 235),
			Color3.fromRGB(30, 30, 34),
		}
		for row = 1, #rows do
			local y = 2.25 + (row - 1) * 0.92
			k:span(vending, "Tray", -97.85, y - 0.06, -20.3, front - 0.1, y, -17.8, P.dSteel)
			local tag = k:span(
				vending,
				"PriceTag",
				front - 0.12,
				y - 0.2,
				-20.25,
				front - 0.1,
				y - 0.04,
				-17.85,
				P.dBlack
			)
			k:text(
				tag,
				"E",
				string.format("%s1   %s2   %s3   %s4", rows[row], rows[row], rows[row], rows[row]),
				{
					pps = 40,
					color = Color3.fromRGB(230, 230, 220),
					font = "RobotoMono",
				}
			)
			for column = 1, 4 do
				local cz = -17.8 - (column - 0.5) * 0.625
				local color = snackColors[k:int(1, #snackColors)]
				local item = {
					color = color,
					material = Kit.Enum.Material.SmoothPlastic,
					collide = false,
					shadow = false,
				}
				if row <= 2 then
					-- Drinks: cans in the top rows, two deep.
					for depth = 0, 1 do
						local can = Kit.style(196, 198, 202, "Metal", { collide = false, shadow = false })
						k:cyl(vending, "Can", -97.0 - depth * 0.45, y, cz, 0.36, 0.62, can)
						k:cyl(vending, "CanLabel", -97.0 - depth * 0.45, y + 0.06, cz, 0.38, 0.5, item)
					end
				else
					-- Snack packets standing up in a row, a thin wire guide under them.
					for depth = 0, 2 do
						k:box(vending, "Snack", -96.85 - depth * 0.32, y + 0.38, cz, 0.12, 0.7, 0.46, item)
					end
					local wire = Kit.style(160, 164, 168, "Metal", { collide = false, shadow = false })
					k:cyl(vending, "Wire", -97.3, y, cz, 0.06, 1.1, wire, "x")
				end
			end
		end
		-- The window (solid: you cannot reach in) and its frame.
		k:span(
			vending,
			"Window",
			front - 0.06,
			2.1,
			-20.3,
			front,
			6.9,
			-17.8,
			Kit.style(190, 210, 220, "Glass", { alpha = 0.6, shadow = false })
		)
		k:span(vending, "FrameTop", front, 6.75, -20.35, front + 0.08, 6.9, -17.75, trim)
		k:span(vending, "FrameBottom", front, 2.1, -20.35, front + 0.08, 2.25, -17.75, trim)
		k:span(vending, "FrameLeft", front, 2.1, -17.85, front + 0.08, 6.9, -17.75, trim)
		k:span(vending, "FrameRight", front, 2.1, -20.35, front + 0.08, 6.9, -20.25, trim)

		-- Keypad column: display, a 3 x 4 grid of buttons, coin slot and note reader.
		local display =
			k:span(vending, "Display", front, 5.7, -21.7, front + 0.05, 6.3, -20.6, P.neon(40, 200, 120))
		k:text(
			display,
			"E",
			"SELECT",
			{ glow = 1.2, color = Color3.fromRGB(10, 40, 20), font = "RobotoMono", pps = 40 }
		)
		local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "A", "0", "B" }
		for index, label in keys do
			local column = (index - 1) % 3
			local row = (index - 1) // 3
			local cz = -20.75 - column * 0.38
			local cy = 5.35 - row * 0.38
			local button = k:span(
				vending,
				"Button",
				front,
				cy - 0.15,
				cz - 0.15,
				front + 0.07,
				cy + 0.15,
				cz + 0.15,
				P.dSteel
			)
			k:text(button, "E", label, { pps = 60, color = Color3.fromRGB(30, 30, 30), font = "GothamBold" })
		end
		k:span(vending, "CoinSlot", front, 3.65, -21.45, front + 0.06, 3.95, -21.25, P.dBlack)
		k:span(vending, "CoinSlotLip", front, 3.6, -21.5, front + 0.04, 4.0, -21.2, P.dSteel)
		k:span(vending, "NoteReader", front, 3.0, -21.6, front + 0.06, 3.35, -20.7, P.dBlack)
		k:span(vending, "CoinReturn", front, 2.3, -21.4, front + 0.08, 2.6, -21.0, P.dSteel)

		-- Pick-up flap under the window.
		k:span(vending, "FlapRecess", front - 0.02, 0.6, -20.0, front + 0.01, 1.6, -18.1, P.dBlack)
		k:span(vending, "Flap", front, 1.15, -20.0, front + 0.06, 1.6, -18.1, P.dSteel)
		local push =
			k:span(vending, "PushLabel", front + 0.06, 1.3, -19.35, front + 0.085, 1.45, -18.75, P.dWhite)
		k:text(push, "E", "PUSH", { pps = 60, color = Color3.fromRGB(30, 30, 30) })
	end

	k:span(staff, "TableTop", -91, 2.8, -20, -81, 3.05, -15, P.wood)
	for _, x in { -90.6, -81.8 } do
		for _, z in { -19.6, -15.8 } do
			k:span(staff, "TableLeg", x, 0, z, x + 0.4, 2.8, z + 0.4, P.dDarkSteel)
		end
	end
	chair(staff, -88.5, -22, "N")
	chair(staff, -83.5, -22, "N")
	chair(staff, -88.5, -13, "S")
	chair(staff, -83.5, -13, "S")

	k:span(staff, "SofaSeat", -99.5, 0, -12, -96.5, 1.7, -3, P.fabric)
	k:span(staff, "SofaBack", -99.5, 1.7, -12, -98.7, 3.6, -3, Kit.decor(P.fabric))

	lockers(staff, -98, 7.4, -80, 9.5, "N", "EmployeeRoom", { 2, 5 })

	local notices = k:span(staff, "NoticeBoard", -70.7, 3.4, -4, -70.55, 7.6, 6, Kit.decor(P.wood))
	k:text(
		notices,
		"W",
		"STAFF NOTICES\n\nNIGHT SHIFT  12 AM – 6 AM\nDo not leave the building.\nDo not open the doors for anyone.",
		{
			color = Color3.fromRGB(240, 236, 220),
			font = "Gotham",
			pps = 20,
		}
	)
	local clock = k:span(staff, "TimeClock", -71, 3.8, -17.4, -70.55, 5.8, -15.4, P.dBlack)
	k:mark(clock, "TimeClock", { Zone = "EmployeeRoom" })
	local clockDisplay = k:span(clock, "Display", -71.04, 4.9, -17.2, -71, 5.6, -15.6, P.neon(90, 220, 120))
	k:text(clockDisplay, "W", "CLOCK IN", { glow = 1.5, color = Color3.fromRGB(10, 40, 20) })
	bin(staff, -72.6, -27.6)

	-- A filthy public restroom ------------------------------------------------------------
	-- Old square tiles up to shoulder height (yellowed, grout gone black, some cracked,
	-- some missing, black mould creeping up from the floor), stained plaster above them
	-- with rust running down, a grimy floor, and bare pipes along the walls.
	-- Stall walls: old dark wood partitions gone black with grime; the counter yellowed.
	local STALL = Kit.style(60, 46, 32, "Wood")
	local COUNTER = Kit.style(150, 138, 108, "Concrete")
	-- An old mirror: clouded, dark and stained, barely reflecting.
	local MIRROR = Kit.style(70, 72, 66, "Glass", { reflect = 0.25 })
	-- A fitting the game dresses with a sculpted mesh (RestroomService): the plain part
	-- stays as its shape, and records where the mesh goes - its base on the floor or the
	-- wall, and which way it faces (dir: +1 / -1 along Z for the sinks, 0 = facing +X).
	local function fitting(part, kind, x, y, z, dir)
		k:mark(part, "Fitting", { Kind = kind, BaseX = x, BaseY = y, BaseZ = z, Facing = dir })
	end

	-- A thin layer laid over a wall or the floor, in one of the restroom materials. The
	-- materials are MaterialVariants generated in Studio and kept in the place's
	-- MaterialService (FilthyWallTiles, FilthyFloorTiles, StainedPlaster); a place
	-- without them shows the plain base material instead.
	local function surface(parent, name, x1, y1, z1, x2, y2, z2, material, variant, color)
		local part = k:span(
			parent,
			name,
			x1,
			y1,
			z1,
			x2,
			y2,
			z2,
			Kit.style(
				color.R * 255,
				color.G * 255,
				color.B * 255,
				material,
				{ collide = false, shadow = false }
			)
		)
		part.MaterialVariant = variant
		return part
	end

	-- Blood ------------------------------------------------------------------------------
	local BLOOD = Color3.fromRGB(104, 8, 10)

	-- A transparent sheet laid on a face, with a SurfaceGui to draw blood on. `side` is the
	-- way the face looks (N/S/E/W); returns the gui and the sheet's size along the face.
	local function bloodSheet(parent, x1, y1, z1, x2, y2, z2, side)
		local part = k:span(
			parent,
			"BloodLayer",
			x1,
			y1,
			z1,
			x2,
			y2,
			z2,
			Kit.style(0, 0, 0, "SmoothPlastic", { collide = false, shadow = false, alpha = 1 })
		)
		local gui = Kit.Instance.new("SurfaceGui")
		gui.Name = "Blood"
		gui.Face = Kit.Enum.NormalId[({ N = "Front", S = "Back", W = "Left", E = "Right" })[side]]
		gui.SizingMode = Kit.Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 50
		gui.LightInfluence = 1
		gui.Parent = part
		local along = if side == "N" or side == "S" then x2 - x1 else z2 - z1
		return gui, along, y2 - y1
	end

	local function stroke(gui, W, H, cx, cy, w, h, rotation, alpha, round)
		local frame = Kit.Instance.new("Frame")
		frame.AnchorPoint = Kit.Vector2.new(0.5, 0.5)
		-- (cy counts up from the bottom of the face; the gui counts down from the top.)
		frame.Position = Kit.UDim2.new(cx / W, 0, 1 - cy / H, 0)
		frame.Size = Kit.UDim2.new(w / W, 0, h / H, 0)
		frame.Rotation = rotation
		frame.BackgroundColor3 = BLOOD
		frame.BackgroundTransparency = alpha
		frame.BorderSizePixel = 0
		frame.Parent = gui
		if round then
			local corner = Kit.Instance.new("UICorner")
			corner.CornerRadius = Kit.UDim.new(0.5, 0)
			corner.Parent = frame
		end
		return frame
	end

	-- A bloody handprint, `size` studs tall, centred at (cx, cy) in studs on the face,
	-- tilted `angle` degrees, a smear dragged down from it and a few runs.
	local function handprint(gui, W, H, cx, cy, size, angle, mirrored)
		local a = math.rad(angle)
		local function at(dx, dy)
			-- Turn a point of the hand (studs, relative to the palm, y up) by the hand's angle.
			local x = dx * math.cos(a) + dy * math.sin(a)
			local y = -dx * math.sin(a) + dy * math.cos(a)
			return cx + x, cy + y
		end
		local s = size
		local px, py = at(0, -0.12 * s)
		stroke(gui, W, H, px, py, 0.5 * s, 0.55 * s, angle, k:range(0.05, 0.2), true)
		local flip = if mirrored then -1 else 1
		-- Thumb, then four fingers fanning out.
		local fingers = {
			{ -0.33 * flip, -0.02, 0.13, 0.32, -40 * flip },
			{ -0.18 * flip, 0.36, 0.12, 0.38, -10 * flip },
			{ -0.04 * flip, 0.42, 0.12, 0.42, -2 * flip },
			{ 0.1 * flip, 0.39, 0.12, 0.4, 6 * flip },
			{ 0.22 * flip, 0.3, 0.1, 0.32, 16 * flip },
		}
		for _, f in fingers do
			local fx, fy = at(f[1] * s, f[2] * s)
			stroke(gui, W, H, fx, fy, f[3] * s, f[4] * s, angle + f[5], k:range(0.05, 0.25), true)
		end
		-- The hand slid down a little, and blood ran.
		local sx, sy = at(0, -0.5 * s)
		stroke(gui, W, H, sx, sy, 0.42 * s, 0.5 * s, angle, 0.55, true)
		for _ = 1, k:int(2, 4) do
			local dx = k:range(-0.2, 0.2) * s
			local length = k:range(0.3, 1.4)
			local rx, ry = at(dx, -0.3 * s)
			stroke(gui, W, H, rx, ry - length / 2, k:range(0.025, 0.05), length, 0, k:range(0.15, 0.4), false)
		end
	end

	-- Splatter: a burst of drops of different sizes.
	local function splatter(gui, W, H, cx, cy, spread)
		for _ = 1, k:int(8, 16) do
			local r = k:range(0.04, 0.2)
			stroke(
				gui,
				W,
				H,
				cx + k:range(-spread, spread),
				cy + k:range(-spread, spread) * 0.7,
				r,
				r,
				0,
				k:range(0.1, 0.5),
				true
			)
		end
	end

	-- Dirties one restroom whose walls are x = -100 (W) and x = -60 (E), z = zA (north)
	-- and zB (south): tiles to shoulder height, stained plaster above, a filthy floor.
	-- The east wall has the door opening, doorFrom..doorTo along Z, 7.5 tall.
	local function filthyRoom(room, zA, zB, doorFrom, doorTo)
		local tileTop = 5.2
		local d = 0.5
		local t = 0.04
		local doorTop = 7.5
		local TILES = Color3.fromRGB(196, 186, 156)
		local PLASTER = Color3.fromRGB(112, 104, 92)
		local function wallX(x, z1, z2, y1, y2)
			if z2 - z1 < 0.05 or y2 - y1 < 0.05 then
				return
			end
			if y2 <= tileTop then
				surface(room, "Tiles", x, y1, z1, x + t, y2, z2, "CeramicTiles", "FilthyWallTiles", TILES)
			elseif y1 >= tileTop then
				surface(room, "Plaster", x, y1, z1, x + t, y2, z2, "Plaster", "StainedPlaster", PLASTER)
			else
				surface(
					room,
					"Tiles",
					x,
					y1,
					z1,
					x + t,
					tileTop,
					z2,
					"CeramicTiles",
					"FilthyWallTiles",
					TILES
				)
				surface(room, "Plaster", x, tileTop, z1, x + t, y2, z2, "Plaster", "StainedPlaster", PLASTER)
			end
		end
		-- West wall: whole.
		wallX(-100 + d, zA + d, zB - d, 0, 11)
		-- East wall: either side of the door, and above it.
		local ex = -60 - d - t
		wallX(ex, zA + d, doorFrom, 0, 11)
		wallX(ex, doorTo, zB - d, 0, 11)
		wallX(ex, doorFrom, doorTo, doorTop, 11)
		for _, z in { zA + d, zB - d - t } do
			surface(
				room,
				"Tiles",
				-100 + d,
				0,
				z,
				-60 - d,
				tileTop,
				z + t,
				"CeramicTiles",
				"FilthyWallTiles",
				TILES
			)
			surface(
				room,
				"Plaster",
				-100 + d,
				tileTop,
				z,
				-60 - d,
				11,
				z + t,
				"Plaster",
				"StainedPlaster",
				PLASTER
			)
		end
		surface(
			room,
			"FloorTiles",
			-100 + d,
			0.01,
			zA + d,
			-60 - d,
			0.04,
			zB - d,
			"CeramicTiles",
			"FilthyFloorTiles",
			Color3.fromRGB(122, 114, 100)
		)
		-- The tile edge: a bead along the top of the tiling on the stall wall.
		k:span(
			room,
			"TileEdge",
			-99.5,
			tileTop - 0.05,
			zA + 0.5,
			-99.35,
			tileTop + 0.1,
			zB - 0.5,
			Kit.decor(Kit.style(150, 140, 110, "SmoothPlastic"))
		)
		-- Bare pipes: a thick rusty one along the west wall near the ceiling, dropping
		-- down in the corner, and a thin one along the floor.
		local pipe = Kit.decor(Kit.style(84, 62, 46, "CorrodedMetal"))
		k:cyl(room, "Pipe", -99.1, 9.2, (zA + zB) / 2, 0.6, zB - zA - 1.2, pipe, "z")
		k:cyl(room, "Pipe", -99.1, 0, zA + 1.2, 0.6, 9.5, pipe)
		k:cyl(room, "PipeLow", -99.3, 0.3, (zA + zB) / 2, 0.25, zB - zA - 1.2, pipe, "z")

		-- Blood: handprints dragged along the east wall by the door and on the far wall.
		local gui, W, H = bloodSheet(room, ex - 0.03, 0.5, doorTo + 0.3, ex - 0.01, 7, zB - d - 0.5, "W")
		handprint(gui, W, H, 1.2, 4.1, 0.9, -12, false)
		handprint(gui, W, H, 2.3, 3.6, 0.85, 8, true)
		splatter(gui, W, H, 3.6, 2.6, 0.7)
		-- The far wall is the one across from the plumbing wall (z = 60).
		local farZ = if zA == 60 then zB - d - t - 0.02 else zA + d + t + 0.02
		local side = if zA == 60 then "N" else "S"
		local gui2, W2, H2 = bloodSheet(room, -80, 0.5, farZ - 0.01, -66, 7, farZ + 0.01, side)
		handprint(gui2, W2, H2, 3.5, 3.9, 0.95, 20, false)
		splatter(gui2, W2, H2, 9, 1.4, 0.9)
	end

	-- Restrooms -----------------------------------------------------------------------------
	-- Both alike: four stalls along the back (west) wall, each with a toilet, a roll of
	-- toilet paper on its holder and a small bin; the sinks under a mirror on the plumbing
	-- wall (z = 60) with the hand dryer, towels and a towel bin to their right. The men's
	-- room has a row of urinals along the far wall, each with a privacy panel; the women's
	-- a baby changing table there. `dir` is +1 when the room extends south of the plumbing
	-- wall, -1 north. Fittings are dressed with sculpted meshes by RestroomService.
	local function restroom(zoneId, dir, men, doorFrom, doorTo)
		local room = k:folder(root, zoneId)
		local wall = 60 + dir * 0.5
		local far = 60 + dir * 19.5

		-- Sinks and mirror on the plumbing wall.
		k:span(room, "SinkCounter", -90, 2.4, wall, -72, 3, wall + dir * 2.5, COUNTER)
		k:span(
			room,
			"CounterFront",
			-90,
			0.8,
			wall + dir * 2.3,
			-72,
			2.4,
			wall + dir * 2.5,
			Kit.decor(COUNTER)
		)
		for index = 0, 2 do
			local x = -88 + index * 6
			local basin = k:span(room, "Basin", x, 3, wall + dir * 0.5, x + 3, 3.05, wall + dir * 2, P.dGrey)
			fitting(basin, "Sink", x + 1.5, 3.05, wall + dir * 1.1, dir)
			k:span(room, "Tap", x + 1.3, 3, wall + dir * 0.1, x + 1.7, 3.7, wall + dir * 0.5, P.dSteel)
		end
		local mirror = k:span(room, "Mirror", -90, 3.8, wall, -72, 7.4, wall + dir * 0.08, MIRROR)
		k:mark(mirror, "Mirror", { Zone = zoneId, Normal = Kit.Vector3.new(0, 0, dir) })
		-- Blood on the mirror: a handprint and a smear across it.
		local mz = wall + dir * 0.09
		local mgui, MW, MH = bloodSheet(
			room,
			-90,
			3.8,
			math.min(mz, mz + dir * 0.02),
			-72,
			7.4,
			math.max(mz, mz + dir * 0.02),
			if dir > 0 then "S" else "N"
		)
		handprint(mgui, MW, MH, 5.5, 2.2, 0.95, -8, false)
		handprint(mgui, MW, MH, 12.6, 1.6, 0.9, 25, true)
		splatter(mgui, MW, MH, 9, 2.9, 0.6)

		-- Right of the sinks: the hand dryer, the paper towel dispenser and the towel bin.
		local dryer = k:span(room, "HandDryer", -70, 3.6, wall, -68, 5.2, wall + dir * 0.8, P.dWhite)
		fitting(dryer, "HandDryer", -69, 3.4, wall, dir)
		local dispenser =
			k:span(room, "PaperDispenser", -66.6, 3.8, wall, -65, 5.4, wall + dir * 0.6, P.dGrey)
		fitting(dispenser, "TowelDispenser", -65.8, 3.6, wall, dir)
		local towelBin = k:span(
			room,
			"TowelBinBase",
			-67,
			0,
			wall + dir * 0.2,
			-65,
			2.6,
			wall + dir * 1.4,
			Kit.decor(P.dSteel)
		)
		fitting(towelBin, "TowelBin", -66, 0, wall + dir * 0.05, dir)

		-- Stalls along the west wall.
		for index = 0, 3 do
			local z1 = math.min(60, 60 + dir * 20) + 0.5 + index * 4.5 + (if dir > 0 then 1 else 0)
			local z2 = z1 + 4.5
			local middle = (z1 + z2) / 2
			if index > 0 then
				k:span(room, "StallDivider", -99.5, 0.5, z1 - 0.1, -93, 6.5, z1 + 0.1, STALL)
			end
			k:span(room, "StallFront", -93.1, 0.5, z1, -92.9, 6.5, z1 + 1.7, STALL)
			k:span(room, "StallDoor", -95.6, 0.5, z2 - 0.4, -93.1, 6.5, z2 - 0.25, Kit.decor(STALL))
			local bowl = k:span(room, "ToiletBowl", -98.6, 0, middle - 0.8, -96.6, 1.6, middle + 0.8, P.white)
			fitting(bowl, "Toilet", -99.4, 0, middle, 0)
			k:span(room, "ToiletTank", -99.4, 1.6, middle - 0.9, -98.6, 3.3, middle + 0.9, Kit.decor(P.white))
			-- Toilet paper on the stall wall beside the toilet (a task can ask for refills).
			local holder =
				k:span(room, "PaperHolder", -97.3, 2.3, z1 + 0.1, -96.3, 2.9, z1 + 0.5, Kit.decor(P.dSteel))
			fitting(holder, "PaperHolder", -96.8, 2.2, z1 + 0.12, 1)
			k:mark(holder, "PaperHolder", { Zone = zoneId })
			-- A small bin by the stall door.
			local stallBin =
				k:span(room, "StallBinBase", -95.4, 0, z2 - 1.3, -94.6, 1.1, z2 - 0.5, Kit.decor(P.dGrey))
			fitting(stallBin, "StallBin", -95, 0, z2 - 0.9, -1)
		end

		if men then
			-- Urinals spaced along the far wall, each between privacy panels.
			local facing = -dir
			for index = 0, 4 do
				local x = -88.5 + index * 3.6
				local urinal = k:span(
					room,
					"Urinal",
					x - 0.45,
					1.6,
					far - dir * 0.8,
					x + 0.45,
					3.6,
					far,
					Kit.decor(P.white)
				)
				fitting(urinal, "Urinal", x, 1.2, far, facing)
				k:span(
					room,
					"UrinalLip",
					x - 0.4,
					1.6,
					far - dir * 1.2,
					x + 0.4,
					1.9,
					far - dir * 0.8,
					Kit.decor(P.white)
				)
				k:span(
					room,
					"FlushPipe",
					x - 0.05,
					3.6,
					far - dir * 0.15,
					x + 0.05,
					4.6,
					far - dir * 0.05,
					P.dSteel
				)
			end
			for index = 0, 5 do
				local x = -90.3 + index * 3.6
				k:span(room, "UrinalPanel", x - 0.05, 1.2, far - dir * 1.9, x + 0.05, 5, far, STALL)
			end
		else
			-- A fold-down baby changing table on the far wall.
			k:span(room, "ChangingTable", -86, 2.6, far, -82.5, 3.1, far - dir * 1.8, Kit.decor(P.offWhite))
			k:span(
				room,
				"ChangingTableBack",
				-86,
				2.6,
				far,
				-82.5,
				4.4,
				far - dir * 0.2,
				Kit.decor(P.offWhite)
			)
		end
		filthyRoom(room, math.min(60, 60 + dir * 20), math.max(60, 60 + dir * 20), doorFrom, doorTo)
	end
	restroom("BathroomA", 1, true, 67, 72)
	restroom("BathroomB", -1, false, 47, 52)
end
