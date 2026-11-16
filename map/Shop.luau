-- The shop floor: aisles of shelving stocked with varied products, refrigerated walls,
-- chest freezers, the checkout line, the front area and signage.

local Kit = require("./Kit")
local Layout = require("./Layout")
local P = require("./Palette")
local Props = require("./Props")

local Color3 = Kit.Color3

-- Shelf levels of a gondola (height of the surface products stand on).
local LEVELS = { 0.5, 2.0, 3.5, 5.0 }
local GONDOLA_HEIGHT = 6.6
local BAY_LENGTH = 6

-- Product silhouettes: w = size along the shelf, h = height, d = depth.
local KINDS = {
	box = { shape = "box", w = { 0.9, 1.3 }, h = { 0.9, 1.25 }, d = 0.75 },
	tall = { shape = "box", w = { 0.7, 0.95 }, h = { 1.1, 1.3 }, d = 0.6 },
	flat = { shape = "box", w = { 1.2, 1.6 }, h = { 0.45, 0.75 }, d = 1.0 },
	bag = { shape = "box", w = { 1.0, 1.3 }, h = { 0.9, 1.25 }, d = 0.5 },
	jug = { shape = "box", w = { 0.85, 1.1 }, h = { 1.05, 1.3 }, d = 0.85 },
	can = { shape = "cyl", w = { 0.6, 0.75 }, h = { 0.7, 0.95 } },
	jar = { shape = "cyl", w = { 0.65, 0.8 }, h = { 0.85, 1.15 } },
	bottle = { shape = "cyl", w = { 0.5, 0.65 }, h = { 1.1, 1.3 } },
}

return function(k, root)
	local shop = k:folder(root, "ShopFloor")
	local shelving = k:folder(shop, "Shelving")
	local chilled = k:folder(shop, "Chilled")
	local checkout = k:folder(shop, "Checkout")
	local front = k:folder(shop, "FrontArea")
	local signs = k:folder(shop, "Signs")

	local function packaging()
		return {
			color = Color3.fromHSV(k:rand(), k:range(0.35, 0.75), k:range(0.5, 0.92)),
			material = Kit.Enum.Material.SmoothPlastic,
			collide = false,
		}
	end

	-- Fills one shelf level with runs of identical products.
	--   place(along, y, kind, width, height, style)  puts one item at `along` on the shelf
	local function stock(from, to, kinds, place)
		local cursor = from + 0.3
		while cursor < to - 0.9 do
			local kind = KINDS[k:pick(kinds)]
			local width = k:range(kind.w[1], kind.w[2])
			local height = k:range(kind.h[1], kind.h[2])
			local style = packaging()
			for _ = 1, k:int(2, 5) do
				if cursor + width > to - 0.3 then
					break
				end
				-- An occasional gap where a customer took the last one.
				if not k:chance(0.07) then
					place(cursor + width / 2, kind, width, height, style)
				end
				cursor += width + 0.12
			end
			cursor += 0.25
		end
	end

	-- One face of shelving running along Z: boards, price strips and stocked bays.
	--   xBack / xFront  where the shelf meets its backing and where it faces the aisle
	local function shelfFace(parent, xBack, xFront, z1, z2, category, aisle)
		local outward = if xFront > xBack then 1 else -1
		for index = 2, #LEVELS do
			local y = LEVELS[index]
			k:span(parent, "Board", xBack, y - 0.15, z1, xFront, y, z2, P.dShelf)
			k:span(parent, "PriceStrip", xFront, y - 0.2, z1, xFront + outward * 0.06, y + 0.05, z2, P.dWhite)
		end

		local z = z1
		while z < z2 - 0.1 do
			local bayEnd = math.min(z + BAY_LENGTH, z2)
			local bay = k:model(parent, "Bay")
			k:mark(bay, "ShelfBay", { Category = category.name, Aisle = aisle, Stocked = true })
			for _, y in LEVELS do
				stock(z, bayEnd, category.kinds, function(along, kind, width, height, style)
					local depth = kind.d or width
					local x = xFront - outward * (0.15 + depth / 2)
					if kind.shape == "cyl" then
						k:cyl(bay, "Product", x, y, along, width, height, style)
					else
						k:box(bay, "Product", x, y + height / 2, along, depth, height, width, style)
					end
				end)
			end
			z = bayEnd
		end
	end

	-- Aisles ----------------------------------------------------------------------------
	local categories = Layout.Categories
	for index, cx in Layout.GondolaX do
		for _, run in Layout.GondolaRuns do
			local z1, z2 = run[1], run[2]
			local gondola = k:folder(shelving, "Gondola" .. index)
			-- One invisible box blocks movement and line of sight for the whole unit;
			-- the visible pieces are decoration.
			k:span(gondola, "Collider", cx - 2, 0, z1, cx + 2, GONDOLA_HEIGHT, z2, P.collider)
			k:span(gondola, "Plinth", cx - 1.9, 0, z1, cx + 1.9, 0.5, z2, Kit.decor(P.plinth))
			k:span(gondola, "Spine", cx - 0.15, 0.5, z1, cx + 0.15, GONDOLA_HEIGHT, z2, P.dShelf)
			k:span(gondola, "EndNorth", cx - 1.9, 0.5, z1, cx + 1.9, GONDOLA_HEIGHT, z1 + 0.2, P.dShelf)
			k:span(gondola, "EndSouth", cx - 1.9, 0.5, z2 - 0.2, cx + 1.9, GONDOLA_HEIGHT, z2, P.dShelf)
			shelfFace(gondola, cx - 0.15, cx - 1.9, z1 + 0.2, z2 - 0.2, categories[index * 2], index)
			shelfFace(gondola, cx + 0.15, cx + 1.9, z1 + 0.2, z2 - 0.2, categories[index * 2 + 1], index + 1)
		end
	end

	-- Single-sided shelving along the west wall.
	local westShelf = k:folder(shelving, "WestWallShelving")
	k:span(westShelf, "Collider", -59.5, 0, -26, -57.4, GONDOLA_HEIGHT, 22, P.collider)
	k:span(westShelf, "Plinth", -59.5, 0, -26, -57.5, 0.5, 22, Kit.decor(P.plinth))
	k:span(westShelf, "Back", -59.5, 0.5, -26, -59.3, GONDOLA_HEIGHT, 22, P.dShelf)
	shelfFace(westShelf, -59.3, -57.5, -26, 22, categories[1], 1)

	-- Aisle signs hanging above the south end of each aisle.
	for aisle = 1, 8 do
		local cx = if aisle == 1 then -51.5 else Layout.GondolaX[aisle - 1] + 7
		local left = categories[aisle * 2 - 1]
		local right = categories[aisle * 2]
		local text =
			string.format("AISLE %d\n%s%s", aisle, left.name, if right then " · " .. right.name else "")
		local board =
			k:span(signs, "AisleSign" .. aisle, cx - 4, 11.2, 43.85, cx + 4, 13.6, 44.15, Kit.decor(P.blue))
		k:text(board, "S", text, { pps = 20 })
		k:text(board, "N", text, { pps = 20 })
		for _, x in { cx - 3.5, cx + 3.5 } do
			k:span(signs, "SignWire", x - 0.04, 13.6, 43.96, x + 0.04, 16, 44.04, P.dDarkSteel)
		end
	end

	-- Upright glass-door coolers ---------------------------------------------------------
	-- `place` maps unit-local coordinates to the world:
	--   u = along the unit's width (0..6), v = depth from the wall (0) to the door (3)
	local function cooler(name, kind, place, cylinderAt)
		local unit = k:model(chilled, name)
		k:mark(unit, "FridgeUnit", { Kind = kind, Working = true })
		place(unit, "Collider", 0, 0, 0, 6, 3, 8.2, P.collider)
		place(unit, "Base", 0, 0, 0, 6, 3, 0.8, Kit.decor(P.darkSteel))
		place(unit, "Back", 0, 0, 0.8, 6, 0.3, 7.4, Kit.decor(P.black))
		place(unit, "SideA", 0, 0.3, 0.8, 0.2, 3, 7.4, P.dWhite)
		place(unit, "SideB", 5.8, 0.3, 0.8, 6, 3, 7.4, P.dWhite)
		place(unit, "Header", 0, 0, 7.4, 6, 3, 8.2, P.dWhite)
		place(unit, "LightStrip", 0.3, 2.5, 7.25, 5.7, 2.7, 7.4, P.neon(225, 240, 255))
		place(unit, "DoorA", 0.25, 2.85, 0.9, 2.95, 2.95, 7.3, P.glassDecor)
		place(unit, "DoorB", 3.05, 2.85, 0.9, 5.75, 2.95, 7.3, P.glassDecor)
		place(unit, "HandleA", 2.7, 2.95, 3.2, 2.85, 3.1, 5.2, P.dDarkSteel)
		place(unit, "HandleB", 3.15, 2.95, 3.2, 3.3, 3.1, 5.2, P.dDarkSteel)

		local kinds = if kind == "Dairy" then { "jug", "bottle", "jar", "box" } else { "box", "flat", "bag" }
		for _, y in { 0.8, 2.9, 5.0 } do
			if y > 0.8 then
				place(unit, "Shelf", 0.2, 0.3, y - 0.12, 5.8, 2.7, y, P.dShelf)
			end
			stock(0.2, 5.8, kinds, function(along, productKind, width, height, style)
				local depth = productKind.d or width
				if productKind.shape == "cyl" then
					cylinderAt(unit, along, 2.5 - depth / 2, y, width, height, style)
				else
					place(
						unit,
						"Product",
						along - width / 2,
						2.5 - depth,
						y,
						along + width / 2,
						2.5,
						y + height,
						style
					)
				end
			end)
		end
	end

	-- Dairy wall along the back of the shop, facing south.
	for index = 0, 10 do
		local x0 = -8 + index * 6
		cooler("DairyCooler" .. (index + 1), "Dairy", function(parent, name, u1, v1, y1, u2, v2, y2, style)
			return k:span(parent, name, x0 + u1, y1, -29.5 + v1, x0 + u2, y2, -29.5 + v2, style)
		end, function(parent, u, v, y, width, height, style)
			k:cyl(parent, "Product", x0 + u, y, -29.5 + v, width, height, style)
		end)
	end
	local dairySign = k:span(signs, "DairySign", 5, 9, -29.45, 45, 11, -29.3, Kit.decor(P.blue))
	k:text(dairySign, "S", "DAIRY  ·  CHILLED", { pps = 16 })

	-- Frozen wall along the east side, facing west.
	for index = 0, 10 do
		local z0 = -26 + index * 6
		cooler("FrozenCooler" .. (index + 1), "Frozen", function(parent, name, u1, v1, y1, u2, v2, y2, style)
			return k:span(parent, name, 99.5 - v1, y1, z0 + u1, 99.5 - v2, y2, z0 + u2, style)
		end, function(parent, u, v, y, width, height, style)
			k:cyl(parent, "Product", 99.5 - v, y, z0 + u, width, height, style)
		end)
	end
	local frozenSign = k:span(signs, "FrozenSign", 99.3, 9, -13, 99.45, 11, 27, Kit.decor(P.blue))
	k:text(frozenSign, "W", "FROZEN FOODS", { pps = 16 })

	-- Chest freezers in two rows.
	for index, cx in Layout.FreezerIslandX do
		for runIndex, run in Layout.GondolaRuns do
			local z1, z2 = run[1], run[2]
			local island = k:model(
				chilled,
				string.format("ChestFreezer%d%s", index, if runIndex == 1 then "North" else "South")
			)
			k:mark(island, "FridgeUnit", { Kind = "Chest", Working = true })
			k:span(island, "Body", cx - 3, 0, z1, cx + 3, 3, z2, P.white)
			k:span(island, "Well", cx - 2.6, 3, z1 + 0.4, cx + 2.6, 3.05, z2 - 0.4, P.dBlack)
			k:span(island, "RimWest", cx - 3, 3, z1, cx - 2.6, 3.7, z2, P.dSteel)
			k:span(island, "RimEast", cx + 2.6, 3, z1, cx + 3, 3.7, z2, P.dSteel)
			k:span(island, "RimNorth", cx - 2.6, 3, z1, cx + 2.6, 3.7, z1 + 0.4, P.dSteel)
			k:span(island, "RimSouth", cx - 2.6, 3, z2 - 0.4, cx + 2.6, 3.7, z2, P.dSteel)
			k:span(island, "Lid", cx - 2.6, 3.55, z1 + 0.4, cx + 2.6, 3.62, z2 - 0.4, P.glassDecor)
			for _, x in { cx - 1.3, cx + 1.3 } do
				stock(z1 + 0.4, z2 - 0.4, { "flat", "box", "bag" }, function(along, _, width, _, style)
					k:box(island, "Product", x, 3.25, along, 2.2, 0.4, width, style)
				end)
			end
		end
	end

	-- Checkout lanes -----------------------------------------------------------------------
	for lane, cx in { -44, -30, -16, -2 } do
		local unit = k:model(checkout, "Checkout" .. lane)
		k:span(unit, "Counter", cx - 1.5, 0, 52, cx + 1.5, 3, 64, P.offWhite)
		k:span(unit, "Belt", cx - 1.1, 3, 52.4, cx + 1.1, 3.06, 59, P.dRubber)
		k:span(unit, "Scanner", cx - 0.8, 3, 59.3, cx + 0.8, 3.08, 60.6, P.dDarkSteel)
		k:span(unit, "BagRack", cx - 1.2, 3, 62, cx + 1.2, 3.8, 63.8, P.dSteel)
		k:span(unit, "CardReader", cx - 1.45, 3, 60.8, cx - 0.9, 3.7, 61.4, P.dBlack)

		local register = k:span(unit, "Register", cx + 0.2, 3, 60.9, cx + 1.4, 3.5, 61.9, P.dDarkSteel)
		k:mark(register, "CheckoutRegister", { Lane = lane })
		k:span(unit, "Screen", cx + 0.3, 3.5, 61.3, cx + 1.3, 4.5, 61.45, P.dBlack)
		k:span(unit, "ReceiptPrinter", cx + 0.3, 3, 62.1, cx + 0.9, 3.4, 62.6, P.dWhite)

		-- Cashier chair on the east side.
		k:span(unit, "ChairSeat", cx + 2.2, 1.6, 59.6, cx + 3.6, 1.9, 61, P.dBlack)
		k:span(unit, "ChairBack", cx + 3.4, 1.9, 59.6, cx + 3.6, 3.6, 61, P.dBlack)
		k:cyl(unit, "ChairPost", cx + 2.9, 0, 60.3, 0.3, 1.6, P.dDarkSteel)

		-- Lane number light.
		k:cyl(unit, "LanePole", cx - 1.2, 3, 52.4, 0.2, 4.6, P.dDarkSteel)
		local lamp = k:span(unit, "LaneLamp", cx - 1.9, 7.6, 51.9, cx - 0.5, 8.8, 52.9, P.neon(120, 220, 140))
		k:text(lamp, "N", tostring(lane), { glow = 1.5, color = Color3.fromRGB(20, 30, 20) })
		k:text(lamp, "S", tostring(lane), { glow = 1.5, color = Color3.fromRGB(20, 30, 20) })

		-- Impulse rack at the head of the lane.
		k:span(unit, "ImpulseRack", cx - 1.5, 0, 50, cx + 1.5, 4, 52, P.plinth)
		for _, y in { 1.2, 2.4, 3.6 } do
			stock(cx - 1.5, cx + 1.5, { "box", "bag", "flat" }, function(along, _, width, _, style)
				k:box(unit, "Product", along, y, 49.85, width, 0.7, 0.35, style)
			end)
		end
	end

	-- Front area ---------------------------------------------------------------------------
	k:span(front, "EntranceMat", 12, 0, 71, 28, 0.06, 79.5, P.dRubber)
	k:span(front, "VestibuleMat", 12, 0, 81, 28, 0.06, 91, P.dRubber)

	-- Shopping carts nested in a row, and the return point for abandoned ones.
	for index = 0, 7 do
		Props.cart(k, front, 42 + index * 1.6, 75.5, true)
	end
	k:marker(front, "CartReturn", 48, 2, 72, "CartReturn", { Zone = "ShopFloor" })
	for level = 0, 5 do
		k:span(front, "Basket", 36.5, 0.2 + level * 0.5, 75, 38.5, 0.65 + level * 0.5, 77.5, Kit.decor(P.red))
	end

	-- Produce tables in the south-east corner.
	for row = 0, 1 do
		for column = 0, 1 do
			local x1, z1 = 64 + column * 16, 48 + row * 12
			local display = k:model(front, "ProduceTable")
			k:span(display, "Table", x1, 0, z1, x1 + 10, 2.6, z1 + 5, P.wood)
			for crate = 0, 2 do
				local cx = x1 + 0.4 + crate * 3.2
				k:span(display, "Crate", cx, 2.6, z1 + 0.4, cx + 2.8, 3.3, z1 + 4.6, P.dWood)
				local style = packaging()
				style.color = Color3.fromHSV(
					k:pick({ 0.02, 0.08, 0.15, 0.3, 0.95 }),
					k:range(0.6, 0.85),
					k:range(0.55, 0.9)
				)
				for bx = 0, 2 do
					for bz = 0, 4 do
						k:ball(display, "Produce", cx + 0.5 + bx * 0.9, 3.55, z1 + 0.9 + bz * 0.8, 0.8, style)
					end
				end
			end
		end
	end

	-- Promotional pallet stacks against the south end of some gondolas.
	for _, x in { -30, -2, 26 } do
		local stack = k:model(front, "PromoStack")
		k:span(stack, "Pallet", x - 2, 0, 40.2, x + 2, 0.5, 43.4, P.wood)
		local style = packaging()
		for layer = 0, 3 do
			local inset = layer * 0.2
			k:span(
				stack,
				"Boxes",
				x - 1.9 + inset,
				0.5 + layer * 1.1,
				40.3 + inset,
				x + 1.9 - inset,
				1.6 + layer * 1.1,
				43.3 - inset,
				style
			)
		end
		local card = k:span(stack, "SaleCard", x - 1.6, 5.1, 43.2, x + 1.6, 6.9, 43.4, P.dYellow)
		k:text(card, "S", "SPECIAL\nOFFER", { color = Color3.fromRGB(150, 20, 20) })
	end

	-- Hanging banners over the front area.
	for index, banner in
		{ { -30, "LOW PRICES EVERY DAY" }, { 20, "THANK YOU FOR SHOPPING WITH US" }, { 70, "FRESH PRODUCE" } }
	do
		local board = k:span(
			signs,
			"Banner" .. index,
			banner[1] - 9,
			11.5,
			67.9,
			banner[1] + 9,
			13.5,
			68.1,
			Kit.decor(P.red)
		)
		k:text(board, "S", banner[2], { pps = 16 })
		k:text(board, "N", banner[2], { pps = 16 })
	end

	-- Wall signs.
	local staffOnly = k:span(signs, "StaffOnlySign", -59.45, 7.8, 29.5, -59.3, 9, 33.5, P.dRed)
	k:text(staffOnly, "E", "STAFF ONLY")
	local restrooms = k:span(signs, "RestroomSign", -59.45, 7.8, 55, -59.3, 9.2, 64, P.dBlue)
	k:text(restrooms, "E", "RESTROOMS")
	local stockSign = k:span(signs, "StockRoomSign", -24, 8.8, -29.45, -16, 9.8, -29.3, P.dRed)
	k:text(stockSign, "S", "EMPLOYEES ONLY")

	local exitSign = k:span(signs, "ExitSignEast", 99.3, 7.8, 53, 99.45, 8.8, 56, P.neon(70, 220, 110))
	k:text(exitSign, "W", "EXIT", { glow = 2, color = Color3.fromRGB(10, 40, 20) })
	local entranceExit =
		k:span(signs, "ExitSignEntrance", 17, 9.3, 79.3, 23, 10.5, 79.45, P.neon(70, 220, 110))
	k:text(entranceExit, "N", "EXIT", { glow = 2, color = Color3.fromRGB(10, 40, 20) })

	local hours = k:span(signs, "OpeningHours", 27, 3.5, 79.3, 33, 8, 79.45, P.dWhite)
	k:text(
		hours,
		"N",
		"OPENING HOURS\n\nMON – SUN\n7 AM – 11 PM",
		{ color = Color3.fromRGB(30, 30, 30), font = "Gotham" }
	)
	local helpWanted = k:span(signs, "HelpWantedPoster", 7, 4, 79.3, 12, 8, 79.45, P.dYellow)
	k:text(helpWanted, "N", "NOW HIRING\nNIGHT SHIFT\n\nAsk inside", { color = Color3.fromRGB(30, 30, 30) })

	-- Ceiling air vents.
	for _, vent in { { -37, -8 }, { 19, -8 }, { 75, -8 }, { -9, 26 }, { 47, 26 }, { 19, 58 }, { 75, 58 } } do
		k:span(
			shop,
			"AirVent",
			vent[1] - 1.5,
			15.9,
			vent[2] - 1.5,
			vent[1] + 1.5,
			16,
			vent[2] + 1.5,
			P.dDarkSteel
		)
	end
end
