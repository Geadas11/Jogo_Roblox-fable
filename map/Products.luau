--[[
	The goods on the shelves. Each product type is a small model built from a few parts
	with a shape you recognise from across the aisle: glass bottles with a liquid inside,
	a shoulder, a neck and a cap; clear plastic bottles of water and soda; jars with their
	contents and a lid; gable-top cartons; jugs with a handle; spray bottles; crisp bags
	with crimped ends; packs of toilet rolls; tall thin cereal boxes; tins.

	Every product is built in its own frame: origin at the bottom centre of the item,
	-Z towards the customer (the front), X along the shelf, Y up. So the same code stocks
	the aisles (facing east or west), the dairy wall (south) and the frozen wall (west).
	Behind the front item a few more of the same stand in rows (just their bodies), so
	the shelves look full and deep.

	The bay's restock task shows and hides every part of the bay, so all parts are direct
	children of the bay: the front item's body is named "Product" (a horror event may
	knock it off the shelf), everything else "ProductDetail". Translucent parts (glass,
	plastic) store their transparency in an "Alpha" attribute, so they come back right.

	Brands and pictures are made up; pictures are emoji (no image assets). Prints are
	SurfaceGuis drawn only within PRINT_DISTANCE studs.
]]

local Kit = require("./Kit")

local Instance, Vector3, CFrame, Color3, Enum, UDim2, UDim =
	Kit.Instance, Kit.Vector3, Kit.CFrame, Kit.Color3, Kit.Enum, Kit.UDim2, Kit.UDim

local Products = {}

local PRINT_DISTANCE = 16
-- Most of a run is hidden behind its front item: at most this many rows behind it.
local MAX_BACK_ROWS = 1
local ROW_GAP = 0.04

-- Colour helpers -------------------------------------------------------------------------------

-- Hue, saturation and value of a colour (written out: the build runs outside Roblox).
local function toHSV(color)
	local r, g, b = color.R, color.G, color.B
	local max, min = math.max(r, g, b), math.min(r, g, b)
	local delta = max - min
	local h = 0
	if delta > 0 then
		if max == r then
			h = ((g - b) / delta) % 6
		elseif max == g then
			h = (b - r) / delta + 2
		else
			h = (r - g) / delta + 4
		end
		h /= 6
	end
	local s = if max > 0 then delta / max else 0
	return h, s, max
end
Products.toHSV = toHSV

local function rgb(r, g, b)
	return Color3.fromRGB(r, g, b)
end

local function solid(color, material, extra)
	local style = {
		color = color,
		material = Enum.Material[material or "SmoothPlastic"],
		collide = false,
		shadow = false,
	}
	if extra then
		for key, value in extra do
			style[key] = value
		end
	end
	return style
end

-- A label colour that stands out from the packaging: light paper, or a darker or
-- complementary print.
local function labelColor(k, color)
	local h, s, v = toHSV(color)
	local roll = k:rand()
	if roll < 0.45 then
		return Color3.fromHSV(h, s * 0.12, 0.95)
	elseif roll < 0.75 then
		return Color3.fromHSV((h + 0.5) % 1, math.min(1, s + 0.2), math.min(1, v + 0.1))
	end
	return Color3.fromHSV(h, math.min(1, s + 0.25), v * 0.45)
end
Products.labelColor = labelColor

local function inkOn(color)
	local _, _, value = toHSV(color)
	return if value > 0.6 then rgb(28, 26, 30) else rgb(245, 242, 232)
end
Products.inkOn = inkOn

-- Brands --------------------------------------------------------------------------------------
-- { name, picture } and, for things you can see into, what is inside.

local BRANDS = {
	cereal = {
		{ "Crunchos", "🥣" },
		{ "Golden Oat", "🌾" },
		{ "Choco Puff", "🍩" },
		{ "Honey Loops", "🍯" },
		{ "Berry Bites", "🍓" },
		{ "Corn Stars", "⭐" },
	},
	box = {
		{ "Nonna's Pasta", "🍝" },
		{ "Biscuit Barn", "🍪" },
		{ "Rice Rocket", "🍚" },
		{ "Tea Time", "🍵" },
		{ "Cracker Jack's", "🧀" },
		{ "Soup Pot", "🍲" },
	},
	smallbox = {
		{ "Brite Smile", "😁" },
		{ "Calm Tabs", "💊" },
		{ "Baby Soft", "👶" },
		{ "Fresh Mint", "🌿" },
	},
	flat = {
		{ "Freezy Pizza", "🍕" },
		{ "Waffle Hut", "🧇" },
		{ "Fish Fingers", "🐟" },
		{ "Ice Dream", "🍨" },
	},
	bag = {
		{ "Snakk", "🍿" },
		{ "Crispers", "🥔" },
		{ "Sugar Rush", "🍬" },
		{ "Nutty", "🥜" },
		{ "Tortilla Joe", "🌮" },
	},
	sack = {
		{ "Loaf & Co", "🍞" },
		{ "Long Grain", "🍚" },
		{ "Penne Pronto", "🍝" },
		{ "Mill Flour", "🌾" },
	},
	petfood = { { "Woof!", "🐶" }, { "Meow Mix-Up", "🐱" }, { "Happy Paws", "🐾" } },
	can = {
		{ "Nite Cola", "🥤" },
		{ "Tomato Joe", "🍅" },
		{ "Bean Co.", "🥫" },
		{ "Sweetcorn", "🌽" },
		{ "Kitty Feast", "🐟" },
		{ "Peach Halves", "🍑" },
	},
	jar = {
		{ "Sunny Jam", "🍓", contents = rgb(150, 20, 40) },
		{ "Honey Hill", "🍯", contents = rgb(214, 142, 28) },
		{ "Pickle Pete", "🥒", contents = rgb(104, 128, 44) },
		{ "Choc Spread", "🌰", contents = rgb(78, 44, 26) },
		{ "Peanut Pal", "🥜", contents = rgb(176, 118, 58) },
		{ "Tomato Sugo", "🍅", contents = rgb(170, 40, 24) },
	},
	glassbottle = {
		{
			"Château Rouge",
			"🍷",
			glass = rgb(38, 70, 44),
			contents = rgb(84, 10, 24),
			cap = rgb(110, 16, 30),
		},
		{
			"Golden Oil",
			"🌻",
			glass = rgb(214, 222, 210),
			contents = rgb(206, 164, 40),
			cap = rgb(40, 90, 40),
		},
		{
			"Old Barrel",
			"🍺",
			glass = rgb(120, 66, 20),
			contents = rgb(150, 86, 18),
			cap = rgb(196, 160, 60),
		},
		{
			"Vinaigre",
			"🍇",
			glass = rgb(214, 222, 210),
			contents = rgb(172, 112, 70),
			cap = rgb(30, 30, 34),
		},
		{
			"Blanc",
			"🍾",
			glass = rgb(90, 120, 70),
			contents = rgb(214, 200, 120),
			cap = rgb(200, 186, 120),
		},
	},
	plasticbottle = {
		{ "Pure Spring", "💧", contents = rgb(176, 214, 240), clear = true, cap = rgb(40, 110, 200) },
		{ "Nite Cola", "🥤", contents = rgb(44, 18, 12), cap = rgb(200, 30, 30) },
		{ "Fizzo", "🍊", contents = rgb(246, 132, 20), cap = rgb(240, 120, 20) },
		{ "Zest!", "🍋", contents = rgb(226, 220, 80), cap = rgb(60, 170, 60) },
		{ "Blue Volt", "⚡", contents = rgb(50, 130, 240), cap = rgb(30, 30, 34) },
	},
	carton = {
		{ "MooFresh", "🥛" },
		{ "Sunny Juice", "🍊" },
		{ "Oaty", "🌾" },
		{ "Apple Farm", "🍎" },
	},
	jug = { { "Sparkle", "✨" }, { "Bleachy", "💧" }, { "Fresh Wash", "🌊" }, { "Lemon Clean", "🍋" } },
	milkjug = {
		{ "MooFresh", "🥛" },
		{ "Orchard", "🍎" },
		{ "Green Meadow", "🐄" },
		{ "Sunny Juice", "🍊" },
	},
	yogurt = { { "Creamy", "🍓" }, { "Greek Gold", "🍯" }, { "Berry Yo", "🍒" }, { "Peachy", "🍑" } },
	spray = {
		{ "Shiny", "✨" },
		{ "Glass Pro", "💎" },
		{ "Kitchen Blast", "🍋" },
		{ "Bath Fresh", "🌊" },
	},
	shampoo = {
		{ "Silky", "🌸" },
		{ "Aqua Fresh", "🌊" },
		{ "Coco Care", "🥥" },
		{ "Mint Body", "🌿" },
	},
	rolls = { { "Cloud Soft", "☁️" }, { "Comfy", "🐻" }, { "Kitchen Pro", "🍽️" } },
}
local BRAND_FONTS = { "FredokaOne", "GothamBlack", "LuckiestGuy", "Bangers", "Oswald", "SourceSansBold" }

-- Prints ---------------------------------------------------------------------------------------

-- Prints onto one face of a part (a SurfaceGui lies flat on the part's surface, so the
-- print moves and hides with it). Everything is drawn inside `region` (x, y, w, h as
-- fractions of the face); `paper` fills the region first (the printed label), `band` is
-- a colour strip along the top of the face.
local function printFace(part, face, brand, ink, region, paper, band)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Print"
	gui.Face = Enum.NormalId[face]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 48
	gui.LightInfluence = 1
	gui.MaxDistance = PRINT_DISTANCE
	gui.ClipsDescendants = true
	gui.Parent = part

	if band then
		local strip = Instance.new("Frame")
		strip.Name = "Band"
		strip.BorderSizePixel = 0
		strip.BackgroundColor3 = band
		strip.Position = UDim2.new(0, 0, 0.04, 0)
		strip.Size = UDim2.new(1, 0, 0.14, 0)
		strip.Parent = gui
	end

	local area = Instance.new("Frame")
	area.Name = "Label"
	area.BorderSizePixel = 0
	area.Position = UDim2.new(region[1], 0, region[2], 0)
	area.Size = UDim2.new(region[3], 0, region[4], 0)
	area.BackgroundColor3 = paper or rgb(0, 0, 0)
	area.BackgroundTransparency = if paper then 0 else 1
	area.Parent = gui
	if paper then
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.12, 0)
		corner.Parent = area
	end

	local picture = Instance.new("TextLabel")
	picture.Name = "Picture"
	picture.BackgroundTransparency = 1
	picture.Position = UDim2.new(0, 0, 0.04, 0)
	picture.Size = UDim2.new(1, 0, 0.5, 0)
	picture.Text = brand.Picture
	picture.TextScaled = true
	picture.Parent = area

	local name = Instance.new("TextLabel")
	name.Name = "Brand"
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0.04, 0, 0.56, 0)
	name.Size = UDim2.new(0.92, 0, 0.38, 0)
	name.Text = brand.Name
	name.TextScaled = true
	name.TextColor3 = ink
	name.FontFace = Kit.Font.fromEnum(Enum.Font[brand.Font])
	name.Parent = area
	return gui
end
Products.printFace = printFace

-- The front of a cereal box: the name big across a band at the top, the picture large
-- in the middle (the bowl), a strip of small print at the bottom and, on some, a burst.
local CEREAL_LINES = { "WHOLE GRAIN", "WITH VITAMINS", "FAMILY SIZE", "NO ADDED COLOURS", "CRUNCHY!" }

local function printCereal(k, part, brand, color, band)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Print"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 52
	gui.LightInfluence = 1
	gui.MaxDistance = PRINT_DISTANCE
	gui.ClipsDescendants = true
	gui.Parent = part

	local top = Instance.new("Frame")
	top.Name = "Band"
	top.BorderSizePixel = 0
	top.BackgroundColor3 = band
	top.Size = UDim2.new(1, 0, 0.3, 0)
	top.Parent = gui
	local name = Instance.new("TextLabel")
	name.Name = "Brand"
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0.05, 0, 0.06, 0)
	name.Size = UDim2.new(0.9, 0, 0.88, 0)
	name.Text = string.upper(brand.Name)
	name.TextScaled = true
	name.TextWrapped = true
	name.TextColor3 = inkOn(band)
	name.FontFace = Kit.Font.fromEnum(Enum.Font[brand.Font])
	name.Parent = top

	local picture = Instance.new("TextLabel")
	picture.Name = "Picture"
	picture.BackgroundTransparency = 1
	picture.Position = UDim2.new(0.08, 0, 0.33, 0)
	picture.Size = UDim2.new(0.84, 0, 0.5, 0)
	picture.Text = brand.Picture
	picture.TextScaled = true
	picture.Parent = gui

	local line = Instance.new("TextLabel")
	line.Name = "Line"
	line.BackgroundTransparency = 1
	line.Position = UDim2.new(0.1, 0, 0.86, 0)
	line.Size = UDim2.new(0.8, 0, 0.1, 0)
	line.Text = k:pick(CEREAL_LINES)
	line.TextScaled = true
	line.TextColor3 = inkOn(color)
	line.FontFace = Kit.Font.fromEnum(Enum.Font.GothamBold)
	line.Parent = gui

	if k:chance(0.35) then
		local burst = Instance.new("TextLabel")
		burst.Name = "Burst"
		burst.BorderSizePixel = 0
		burst.BackgroundColor3 = rgb(250, 214, 40)
		burst.Position = UDim2.new(0.62, 0, 0.3, 0)
		burst.Size = UDim2.new(0.32, 0, 0.18, 0)
		burst.Rotation = 12
		burst.Text = "NEW!"
		burst.TextScaled = true
		burst.TextColor3 = rgb(190, 20, 20)
		burst.FontFace = Kit.Font.fromEnum(Enum.Font.LuckiestGuy)
		burst.Parent = gui
		local round = Instance.new("UICorner")
		round.CornerRadius = UDim.new(0.5, 0)
		round.Parent = burst
	end
end

-- Prints the brand on the curved side of an upright label band, facing `towards` (where
-- the customer stands). A SurfaceGui is flat, so on a cylinder it only lies against the
-- curve along a narrow strip down the middle; the print is kept to that strip. The band
-- is turned about its own axis so its Front face looks at the customer; on that face the
-- canvas is rotated 90 degrees, which the content undoes (-90). Checked in Studio.
local CYLINDER_PPS = 95

local function printCylinder(band, towards, brand, color)
	local up = Vector3.new(0, 1, 0)
	band.CFrame = CFrame.fromMatrix(band.CFrame.Position, up, (-towards):Cross(up))

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Print"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = CYLINDER_PPS
	gui.LightInfluence = 1
	gui.MaxDistance = PRINT_DISTANCE
	gui.Parent = band

	local length = band.Size.X * CYLINDER_PPS
	local diameter = band.Size.Y * CYLINDER_PPS
	local area = Instance.new("Frame")
	area.Name = "Label"
	area.BackgroundTransparency = 1
	area.AnchorPoint = Kit.Vector2.new(0.5, 0.5)
	area.Position = UDim2.new(0.5, 0, 0.5, 0)
	area.Size = UDim2.new(0, diameter * 0.46, 0, length * 0.92)
	area.Rotation = -90
	area.Parent = gui

	local picture = Instance.new("TextLabel")
	picture.Name = "Picture"
	picture.BackgroundTransparency = 1
	picture.Size = UDim2.new(1, 0, 0.48, 0)
	picture.Text = brand.Picture
	picture.TextScaled = true
	picture.Parent = area

	local name = Instance.new("TextLabel")
	name.Name = "Brand"
	name.BackgroundTransparency = 1
	name.Position = UDim2.new(0, 0, 0.5, 0)
	name.Size = UDim2.new(1, 0, 0.48, 0)
	name.Text = brand.Name
	name.TextScaled = true
	name.TextColor3 = inkOn(color)
	name.FontFace = Kit.Font.fromEnum(Enum.Font[brand.Font])
	name.Parent = area
end

-- Parts in the product's frame ------------------------------------------------------------

local function make(k, parent, name, cframe, size, style, className, shape)
	local part = Instance.new(className or "Part")
	part.Name = name
	if shape then
		part.Shape = shape
	end
	part.Size = size
	part.CFrame = cframe
	k:_apply(part, style)
	part.Parent = parent
	if style.alpha and style.alpha > 0 then
		part:SetAttribute("Alpha", style.alpha)
	end
	local p = cframe.Position
	local r = math.max(size.X, size.Y, size.Z) / 2
	k:_record(name, p.X - r, p.Y - r, p.Z - r, p.X + r, p.Y + r, p.Z + r, style)
	return part
end

-- A builder for one item: everything is placed relative to `frame`.
local function builder(k, parent, frame)
	local b = { k = k }
	-- Box with its bottom face centred at local (x, y, z).
	function b.block(name, x, y, z, sx, sy, sz, style)
		return make(k, parent, name, frame * CFrame.new(x, y + sy / 2, z), Vector3.new(sx, sy, sz), style)
	end
	-- Upright cylinder standing on local (x, y, z).
	function b.cyl(name, x, y, z, diameter, height, style)
		return make(
			k,
			parent,
			name,
			frame * CFrame.new(x, y + height / 2, z) * CFrame.Angles(0, 0, math.pi / 2),
			Vector3.new(height, diameter, diameter),
			style,
			"Part",
			Enum.PartType.Cylinder
		)
	end
	-- Ellipsoid centred at local (x, y, z) (a sphere mesh stretched to the part's size).
	function b.blob(name, x, y, z, sx, sy, sz, style)
		local part = make(k, parent, name, frame * CFrame.new(x, y, z), Vector3.new(sx, sy, sz), style)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		return part
	end
	-- Wedge rising from the front (-Z) to the back (+Z), bottom centred at local (x, y, z);
	-- `turn` turns it around Y (math.pi: rising towards the front).
	function b.wedge(name, x, y, z, sx, sy, sz, style, turn)
		return make(
			k,
			parent,
			name,
			frame * CFrame.new(x, y + sy / 2, z) * CFrame.Angles(0, turn or 0, 0),
			Vector3.new(sx, sy, sz),
			style,
			"WedgePart"
		)
	end
	return b
end

-- Product types -----------------------------------------------------------------------------
-- w: width along the shelf, h: height, d: depth (nil = round: same as w). `back` is the
-- body repeated in rows behind the front item.

-- Glass is clear plastic with a shine: the Glass material refracts (expensive with hundreds
-- of bottles) and hides the printed labels behind it.
local GLASS_SHINE = 0.18

-- The packaging itself, in the run's colour.
local function brandStyle(_, run)
	return solid(run.color, "SmoothPlastic")
end

local KINDS = {}

-- Tall, thin cereal box: the brand big on a coloured band, the picture under it.
KINDS.cereal = {
	w = { 0.8, 0.98 },
	h = { 1.0, 1.2 },
	d = 0.3,
	build = function(b, run)
		local body = b.block("Product", 0, 0, 0, run.w, run.h, run.d, brandStyle(nil, run))
		printCereal(b.k, body, run.brand, run.color, run.label)
		return body, "block"
	end,
}

-- Any other box: crackers, pasta, tea, soup.
KINDS.box = {
	w = { 0.7, 0.98 },
	h = { 0.55, 0.85 },
	d = 0.45,
	build = function(b, run)
		local body = b.block("Product", 0, 0, 0, run.w, run.h, run.d, brandStyle(nil, run))
		printFace(body, "Front", run.brand, inkOn(run.label), { 0.1, 0.22, 0.8, 0.62 }, run.label)
		return body, "block"
	end,
}

-- Small boxes stacked two high: toothpaste, tablets, baby wipes.
KINDS.smallbox = {
	w = { 0.55, 0.75 },
	h = { 0.32, 0.42 },
	d = 0.4,
	stackOf = 2,
	build = function(b, run)
		local style = brandStyle(nil, run)
		local body
		for level = 0, 1 do
			local part = b.block(
				if level == 0 then "Product" else "ProductDetail",
				0,
				level * (run.h + 0.01),
				0,
				run.w,
				run.h,
				run.d,
				style
			)
			printFace(part, "Front", run.brand, inkOn(run.label), { 0.05, 0.08, 0.9, 0.84 }, run.label)
			body = body or part
		end
		return body, "block"
	end,
}

-- Flat frozen boxes stacked three high (pizza, waffles); the top one shows its lid.
KINDS.flat = {
	w = { 1.1, 1.35 },
	h = { 0.2, 0.26 },
	d = 0.95,
	stackOf = 3,
	build = function(b, run)
		local style = brandStyle(nil, run)
		local body
		for level = 0, 2 do
			local part = b.block(
				if level == 0 then "Product" else "ProductDetail",
				0,
				level * (run.h + 0.01),
				0,
				run.w,
				run.h,
				run.d,
				style
			)
			printFace(part, "Front", run.brand, inkOn(run.label), { 0.2, 0.05, 0.6, 0.9 }, nil)
			if level == 2 then
				printFace(part, "Top", run.brand, inkOn(run.label), { 0.1, 0.1, 0.8, 0.8 }, run.label)
			end
			body = body or part
		end
		return body, "none"
	end,
}

-- Crisp bag: a puffed body with crimped seals at the top and bottom, leaning back a little.
KINDS.bag = {
	w = { 0.85, 1.02 },
	h = { 0.95, 1.12 },
	d = 0.42,
	lean = true,
	build = function(b, run)
		local style = brandStyle(nil, run)
		style.reflect = 0.06
		local seal = solid(run.label, "SmoothPlastic", { reflect = 0.06 })
		local body = b.block("Product", 0, 0.08, 0, run.w, run.h - 0.16, run.d, style)
		b.block("ProductDetail", 0, 0, 0, run.w + 0.02, 0.09, run.d * 0.3, seal)
		b.block("ProductDetail", 0, run.h - 0.09, 0, run.w + 0.02, 0.09, run.d * 0.3, seal)
		printFace(body, "Front", run.brand, inkOn(run.color), { 0.08, 0.1, 0.84, 0.8 }, nil, run.label)
		return body, "none"
	end,
}

-- Paper or plastic sack with its top folded over: pasta, rice, flour, bread.
KINDS.sack = {
	w = { 0.72, 0.9 },
	h = { 0.85, 1.05 },
	d = 0.38,
	build = function(b, run)
		local body = b.block("Product", 0, 0, 0, run.w, run.h - 0.12, run.d, brandStyle(nil, run))
		b.block("ProductDetail", 0, run.h - 0.12, 0.04, run.w * 0.96, 0.12, run.d * 0.6, solid(run.label))
		printFace(body, "Front", run.brand, inkOn(run.label), { 0.1, 0.2, 0.8, 0.66 }, run.label)
		return body, "block"
	end,
}

-- Big pet food sack.
KINDS.petfood = {
	w = { 1.15, 1.3 },
	h = { 1.15, 1.28 },
	d = 0.6,
	build = function(b, run)
		local body = b.block("Product", 0, 0, 0, run.w, run.h - 0.14, run.d, brandStyle(nil, run))
		b.block("ProductDetail", 0, run.h - 0.14, 0, run.w, 0.14, run.d * 0.35, solid(run.label))
		printFace(body, "Front", run.brand, inkOn(run.color), { 0.06, 0.12, 0.88, 0.8 }, nil, run.label)
		return body, "block"
	end,
}

-- Tin: metal ends, the label round the middle. Short tins come stacked two high.
KINDS.can = {
	w = { 0.46, 0.54 },
	h = { 0.52, 0.72 },
	build = function(b, run)
		local metal = solid(rgb(196, 198, 202), "Metal")
		local paper = solid(run.color)
		local levels = if run.h < 0.62 then 2 else 1
		local body
		for level = 0, levels - 1 do
			local y = level * (run.h + 0.01)
			local tin = b.cyl(if level == 0 then "Product" else "ProductDetail", 0, y, 0, run.w, run.h, metal)
			local band = b.cyl("ProductDetail", 0, y + 0.06, 0, run.w + 0.03, run.h - 0.12, paper)
			printCylinder(band, run.towards, run.brand, run.color)
			body = body or tin
		end
		return body, "cyl"
	end,
}

-- Glass jar: what is inside shows through the glass; lid and label.
KINDS.jar = {
	w = { 0.55, 0.66 },
	h = { 0.6, 0.8 },
	build = function(b, run)
		local glass = solid(rgb(226, 234, 236), "SmoothPlastic", { alpha = 0.5, reflect = GLASS_SHINE })
		local contents = solid(run.brand.contents or run.color)
		local body = b.cyl("Product", 0, 0, 0, run.w, run.h, glass)
		b.cyl("ProductDetail", 0, 0.03, 0, run.w * 0.88, run.h * 0.84, contents)
		b.cyl("ProductDetail", 0, run.h, 0, run.w + 0.03, 0.13, solid(run.cap, "Metal"))
		local band = b.cyl("ProductDetail", 0, run.h * 0.25, 0, run.w + 0.02, run.h * 0.42, solid(run.label))
		printCylinder(band, run.towards, run.brand, run.label)
		return body, "cyl"
	end,
}

-- Glass bottle: wine, oil, beer, vinegar. Tinted glass with the liquid inside, a rounded
-- shoulder, a long neck and a cap or foil; a paper label.
KINDS.glassbottle = {
	w = { 0.34, 0.4 },
	h = { 0.68, 0.8 },
	build = function(b, run)
		local tint = run.brand.glass or rgb(214, 222, 210)
		local glass = solid(tint, "SmoothPlastic", { alpha = 0.4, reflect = GLASS_SHINE })
		local body = b.cyl("Product", 0, 0, 0, run.w, run.h, glass)
		b.cyl("ProductDetail", 0, 0.03, 0, run.w * 0.84, run.h * 0.94, solid(run.brand.contents or run.color))
		local shoulder = run.w * 0.7
		b.blob("ProductDetail", 0, run.h, 0, run.w, shoulder, run.w, glass)
		local neckBottom = run.h + shoulder * 0.3
		b.cyl("ProductDetail", 0, neckBottom, 0, run.w * 0.34, 0.3, glass)
		b.cyl(
			"ProductDetail",
			0,
			neckBottom + 0.22,
			0,
			run.w * 0.4,
			0.12,
			solid(run.brand.cap or run.cap, "Metal")
		)
		local band = b.cyl("ProductDetail", 0, run.h * 0.18, 0, run.w + 0.02, run.h * 0.46, solid(run.label))
		printCylinder(band, run.towards, run.brand, run.label)
		return body, "cyl"
	end,
}

-- Clear plastic bottle: water, cola, orange soda. Lighter, a bright cap, a wrap label.
KINDS.plasticbottle = {
	w = { 0.4, 0.46 },
	h = { 0.76, 0.88 },
	build = function(b, run)
		local plastic = solid(rgb(222, 236, 244), "SmoothPlastic", { alpha = 0.55, reflect = 0.04 })
		local body = b.cyl("Product", 0, 0, 0, run.w, run.h, plastic)
		local liquid = solid(run.brand.contents or run.color, "SmoothPlastic", {
			alpha = if run.brand.clear then 0.45 else nil,
		})
		b.cyl("ProductDetail", 0, 0.02, 0, run.w * 0.9, run.h * 0.92, liquid)
		local shoulder = run.w * 0.55
		b.blob("ProductDetail", 0, run.h, 0, run.w, shoulder, run.w, plastic)
		b.cyl("ProductDetail", 0, run.h + shoulder * 0.3, 0, run.w * 0.36, 0.08, plastic)
		b.cyl(
			"ProductDetail",
			0,
			run.h + shoulder * 0.3 + 0.07,
			0,
			run.w * 0.42,
			0.1,
			solid(run.brand.cap or run.cap)
		)
		local band = b.cyl("ProductDetail", 0, run.h * 0.34, 0, run.w + 0.02, run.h * 0.36, solid(run.label))
		printCylinder(band, run.towards, run.brand, run.label)
		return body, "cyl"
	end,
}

-- Gable-top carton: milk, juice.
KINDS.carton = {
	w = { 0.56, 0.64 },
	h = { 0.82, 0.95 },
	d = 0.58,
	build = function(b, run)
		local style = brandStyle(nil, run)
		local roof = run.w * 0.32
		local body = b.block("Product", 0, 0, 0, run.w, run.h, run.d, style)
		-- Two wedges meeting in a ridge, and the sealed fin on top.
		b.wedge("ProductDetail", 0, run.h, -run.d / 4, run.w, roof, run.d / 2, style)
		b.wedge("ProductDetail", 0, run.h, run.d / 4, run.w, roof, run.d / 2, style, math.pi)
		b.block("ProductDetail", 0, run.h + roof, 0, run.w, 0.1, 0.05, style)
		b.cyl("ProductDetail", run.w * 0.22, run.h + roof * 0.35, -run.d * 0.18, 0.16, 0.08, solid(run.cap))
		printFace(body, "Front", run.brand, inkOn(run.label), { 0.08, 0.12, 0.84, 0.76 }, run.label)
		return body, "block"
	end,
}

-- Jug with a handle on top and a screw cap: milk, detergent, juice.
KINDS.jug = {
	w = { 0.8, 0.92 },
	h = { 0.95, 1.08 },
	d = 0.72,
	build = function(b, run)
		local style = brandStyle(nil, run)
		local body = b.block("Product", 0, 0, 0, run.w, run.h, run.d, style)
		-- The handle: a hump along the top towards the back, with the hand hole under it.
		b.block("ProductDetail", run.w * 0.2, run.h, run.d * 0.12, 0.14, 0.24, run.d * 0.55, style)
		b.cyl("ProductDetail", -run.w * 0.2, run.h, -run.d * 0.18, 0.26, 0.1, style)
		b.cyl("ProductDetail", -run.w * 0.2, run.h + 0.1, -run.d * 0.18, 0.3, 0.12, solid(run.cap))
		printFace(body, "Front", run.brand, inkOn(run.label), { 0.1, 0.16, 0.8, 0.66 }, run.label)
		return body, "block"
	end,
}

-- Spray bottle: flat body, a trigger head pointing at you.
KINDS.spray = {
	w = { 0.5, 0.58 },
	h = { 0.78, 0.9 },
	d = 0.34,
	build = function(b, run)
		local style = brandStyle(nil, run)
		style.reflect = 0.05
		local head = solid(run.cap)
		local body = b.block("Product", 0, 0, 0, run.w, run.h, run.d, style)
		b.cyl("ProductDetail", 0, run.h, 0, 0.18, 0.1, head)
		b.block("ProductDetail", 0, run.h + 0.1, -0.06, 0.2, 0.2, 0.48, head)
		b.block("ProductDetail", 0, run.h - 0.06, -0.24, 0.08, 0.2, 0.06, head)
		printFace(body, "Front", run.brand, inkOn(run.label), { 0.1, 0.24, 0.8, 0.6 }, run.label)
		return body, "block"
	end,
}

-- Shampoo / shower gel: slim bottle standing on a flip cap... the right way up here.
KINDS.shampoo = {
	w = { 0.42, 0.5 },
	h = { 0.78, 0.92 },
	d = 0.28,
	build = function(b, run)
		local style = brandStyle(nil, run)
		style.reflect = 0.08
		local body = b.block("Product", 0, 0, 0, run.w, run.h, run.d, style)
		b.block("ProductDetail", 0, run.h, 0, run.w * 0.62, 0.16, run.d * 0.9, solid(run.cap))
		printFace(body, "Front", run.brand, inkOn(run.label), { 0.08, 0.26, 0.84, 0.6 }, run.label)
		return body, "block"
	end,
}

-- Pack of four toilet rolls in a printed film.
KINDS.rolls = {
	w = { 1.1, 1.1 },
	h = { 0.58, 0.58 },
	d = 1.1,
	build = function(b, run)
		local paper = solid(rgb(242, 242, 238), "SmoothPlastic")
		for _, x in { -0.27, 0.27 } do
			for _, z in { -0.27, 0.27 } do
				b.cyl("ProductDetail", x, 0.01, z, 0.52, 0.56, paper)
			end
		end
		-- Clear film with only a hint of colour: the rolls inside must read white.
		local film =
			solid(run.color:Lerp(rgb(255, 255, 255), 0.6), "SmoothPlastic", { alpha = 0.78, reflect = 0.08 })
		local body = b.block("Product", 0, 0, 0, run.w, run.h, run.d, film)
		printFace(body, "Front", run.brand, inkOn(run.label), { 0.2, 0.15, 0.6, 0.7 }, run.label)
		return body, "none"
	end,
}

-- The same jug in the dairy cooler, with milk and juice brands.
KINDS.milkjug = table.clone(KINDS.jug)

-- Yogurt pots stacked two high, with a foil lid.
KINDS.yogurt = {
	w = { 0.4, 0.46 },
	h = { 0.34, 0.4 },
	stackOf = 2,
	build = function(b, run)
		local pot = solid(run.color)
		local foil = solid(rgb(214, 216, 222), "Foil")
		local body
		for level = 0, 1 do
			local y = level * (run.h + 0.06)
			local part = b.cyl(if level == 0 then "Product" else "ProductDetail", 0, y, 0, run.w, run.h, pot)
			b.cyl("ProductDetail", 0, y + run.h, 0, run.w + 0.03, 0.04, foil)
			local band =
				b.cyl("ProductDetail", 0, y + run.h * 0.15, 0, run.w + 0.02, run.h * 0.7, solid(run.label))
			printCylinder(band, run.towards, run.brand, run.label)
			body = body or part
		end
		return body, "none"
	end,
}

Products.KINDS = KINDS

-- Runs ---------------------------------------------------------------------------------------

-- One run of identical products: picks the size, the colours and the brand once.
function Products.run(k, kindName)
	local kind = assert(KINDS[kindName], "no product kind " .. tostring(kindName))
	local w = k:range(kind.w[1], kind.w[2])
	local h = k:range(kind.h[1], kind.h[2])
	local brand = k:pick(BRANDS[kindName] or BRANDS.box)
	local color = Color3.fromHSV(k:rand(), k:range(0.35, 0.8), k:range(0.5, 0.92))
	local label = labelColor(k, color)
	local stacked = (kind.stackOf or 1)
	local height = if kind.stackOf then h * stacked + 0.01 * (stacked - 1) else h
	return {
		kind = kindName,
		w = w,
		h = h,
		d = kind.d or w,
		height = height,
		color = color,
		label = label,
		cap = labelColor(k, color),
		brand = {
			Name = brand[1],
			Picture = brand[2],
			Font = k:pick(BRAND_FONTS),
			contents = brand.contents,
			glass = brand.glass,
			cap = brand.cap,
			clear = brand.clear,
		},
	}
end

-- Builds one item of `run` standing at `position` (bottom centre), its front towards
-- `towards`, with up to `room` studs of shelf behind it to fill with more of the same.
function Products.place(k, parent, run, position, towards, room)
	local kind = KINDS[run.kind]
	local frame = CFrame.lookAt(position, position + towards)
	if kind.lean then
		-- Bags slump back against the ones behind, each a little differently.
		frame *= CFrame.Angles(k:range(0.04, 0.1), 0, k:range(-0.04, 0.04))
	end
	run.towards = towards
	local b = builder(k, parent, frame)
	local body, backShape = kind.build(b, run)

	-- More of the same behind it, as plain bodies. Seen through the gaps, a bottle or jar
	-- back there reads by its contents, so those are drawn in the colour of what is inside.
	-- (Only boxes: behind a row of bottles the shelf barely shows, and they are many.)
	if backShape == "block" and room and room > run.d then
		local rows = math.min(MAX_BACK_ROWS, math.floor((room - run.d) / (run.d + ROW_GAP)))
		local seeThrough = body.Transparency > 0
		local style = {
			color = if seeThrough then (run.brand.contents or run.color) else body.Color,
			material = if seeThrough then Enum.Material.SmoothPlastic else body.Material,
			collide = false,
			shadow = false,
		}
		for row = 1, rows do
			local z = row * (run.d + ROW_GAP)
			if backShape == "cyl" then
				b.cyl("ProductDetail", 0, 0, z, run.w, run.h, style)
			else
				b.block("ProductDetail", 0, 0, z, run.w, run.height, run.d, style)
			end
		end
	end
	return body
end

return Products
