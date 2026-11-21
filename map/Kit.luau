--[[
	Building kit for the map generator: a thin layer over the Roblox Instance API that
	creates anchored parts from min/max corners, walls with openings, doors, lights and
	text, and keeps a record of every part it made (used to verify and draw the map).

	Runs at build time under Lune (tools/build.luau). Coordinates are in studs:
	X grows east, Z grows SOUTH (the storefront faces +Z), Y is up, floor level is Y = 0.
]]

local roblox = require("@lune/roblox")
local Instance, Vector3, CFrame, Color3, Enum, UDim2, Font =
	roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum, roblox.UDim2, roblox.Font

local Kit = {}
Kit.__index = Kit

Kit.Instance, Kit.Vector3, Kit.CFrame, Kit.Color3, Kit.Enum = Instance, Vector3, CFrame, Color3, Enum
Kit.UDim2, Kit.UDim, Kit.Font, Kit.Vector2 = UDim2, roblox.UDim, Font, roblox.Vector2

-- Compass direction -> face of an unrotated part.
local FACE = { N = "Front", S = "Back", W = "Left", E = "Right", U = "Top", D = "Bottom" }

-- A style describes how a part looks and behaves.
--   collide (default true)   players and AI are blocked by it
--   shadow  (default = collide)
--   alpha   transparency
function Kit.style(r, g, b, material, extra)
	local style = { color = Color3.fromRGB(r, g, b), material = Enum.Material[material or "SmoothPlastic"] }
	if extra then
		for key, value in extra do
			style[key] = value
		end
	end
	return style
end

-- Same look, but purely decorative: no collision, no shadow.
function Kit.decor(style)
	local copy = table.clone(style)
	copy.collide = false
	return copy
end

function Kit.new(seed)
	return setmetatable({ seed = seed, records = {}, partCount = 0, lightCount = 0, tagCounts = {} }, Kit)
end

-- Deterministic random numbers (Park-Miller), so every build produces the same map.
function Kit:rand()
	self.seed = (self.seed * 48271) % 2147483647
	return self.seed / 2147483647
end

function Kit:range(a, b)
	return a + (b - a) * self:rand()
end

function Kit:int(a, b)
	return a + math.floor(self:rand() * (b - a + 1))
end

function Kit:pick(list)
	return list[self:int(1, #list)]
end

function Kit:chance(probability)
	return self:rand() < probability
end

function Kit:folder(parent, name)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	return folder
end

function Kit:model(parent, name)
	local model = Instance.new("Model")
	model.Name = name
	model.Parent = parent
	return model
end

function Kit:_apply(part, style)
	part.Anchored = true
	part.Color = style.color
	part.Material = style.material
	if style.alpha then
		part.Transparency = style.alpha
	end
	if style.reflect then
		part.Reflectance = style.reflect
	end
	local collide = style.collide ~= false
	part.CanCollide = collide
	if not collide then
		part.CanTouch = false
		part.CanQuery = false
	end
	local shadow = style.shadow
	if shadow == nil then
		shadow = collide
	end
	part.CastShadow = shadow
end

function Kit:_record(name, x1, y1, z1, x2, y2, z2, style)
	self.partCount += 1
	table.insert(self.records, {
		name = name,
		x1 = x1,
		y1 = y1,
		z1 = z1,
		x2 = x2,
		y2 = y2,
		z2 = z2,
		collide = style.collide ~= false,
		color = {
			math.floor(style.color.R * 255),
			math.floor(style.color.G * 255),
			math.floor(style.color.B * 255),
		},
		invisible = style.alpha == 1,
		glass = style.alpha ~= nil and style.alpha > 0 and style.alpha < 1,
	})
end

-- Axis-aligned box from two opposite corners.
function Kit:span(parent, name, x1, y1, z1, x2, y2, z2, style)
	if x1 > x2 then
		x1, x2 = x2, x1
	end
	if y1 > y2 then
		y1, y2 = y2, y1
	end
	if z1 > z2 then
		z1, z2 = z2, z1
	end
	assert(x2 - x1 > 0.01 and y2 - y1 > 0.01 and z2 - z1 > 0.01, "degenerate part: " .. name)
	assert(x2 - x1 <= 2048 and z2 - z1 <= 2048, "part too large: " .. name)

	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(x2 - x1, y2 - y1, z2 - z1)
	part.CFrame = CFrame.new((x1 + x2) / 2, (y1 + y2) / 2, (z1 + z2) / 2)
	self:_apply(part, style)
	part.Parent = parent
	self:_record(name, x1, y1, z1, x2, y2, z2, style)
	return part
end

-- Box given by centre and size.
function Kit:box(parent, name, cx, cy, cz, sx, sy, sz, style)
	return self:span(
		parent,
		name,
		cx - sx / 2,
		cy - sy / 2,
		cz - sz / 2,
		cx + sx / 2,
		cy + sy / 2,
		cz + sz / 2,
		style
	)
end

-- Cylinder standing on (cx, y1, cz). `axis` is the direction of its length:
-- "y" (default, upright), "x" or "z".
function Kit:cyl(parent, name, cx, y1, cz, diameter, length, style, axis)
	axis = axis or "y"
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(length, diameter, diameter)
	local r = diameter / 2
	if axis == "y" then
		part.CFrame = CFrame.new(cx, y1 + length / 2, cz) * CFrame.Angles(0, 0, math.pi / 2)
		self:_record(name, cx - r, y1, cz - r, cx + r, y1 + length, cz + r, style)
	elseif axis == "x" then
		part.CFrame = CFrame.new(cx, y1 + r, cz)
		self:_record(name, cx - length / 2, y1, cz - r, cx + length / 2, y1 + diameter, cz + r, style)
	else
		part.CFrame = CFrame.new(cx, y1 + r, cz) * CFrame.Angles(0, math.pi / 2, 0)
		self:_record(name, cx - r, y1, cz - length / 2, cx + r, y1 + diameter, cz + length / 2, style)
	end
	self:_apply(part, style)
	part.Parent = parent
	return part
end

function Kit:ball(parent, name, cx, cy, cz, diameter, style)
	local part = Instance.new("Part")
	part.Name = name
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(diameter, diameter, diameter)
	part.CFrame = CFrame.new(cx, cy, cz)
	self:_apply(part, style)
	part.Parent = parent
	local r = diameter / 2
	self:_record(name, cx - r, cy - r, cz - r, cx + r, cy + r, cz + r, style)
	return part
end

local function sortedOpenings(openings)
	local list = table.clone(openings or {})
	table.sort(list, function(a, b)
		return a[1] < b[1]
	end)
	return list
end

-- Wall running along X at depth `z`. Each opening is { from, to, top, bottom? }:
-- a doorway when bottom is omitted, a window otherwise. Ends are extended by half the
-- thickness so corners close.
function Kit:wallX(parent, name, z, x1, x2, y1, y2, style, openings, thickness)
	local t = (thickness or 1) / 2
	local cursor = x1 - t
	for _, o in sortedOpenings(openings) do
		local a, b, top, bottom = o[1], o[2], o[3], o[4] or y1
		if a > cursor then
			self:span(parent, name, cursor, y1, z - t, a, y2, z + t, style)
		end
		if bottom > y1 then
			self:span(parent, name .. "Sill", a, y1, z - t, b, bottom, z + t, style)
		end
		if top < y2 then
			self:span(parent, name .. "Lintel", a, top, z - t, b, y2, z + t, style)
		end
		cursor = b
	end
	if cursor < x2 + t then
		self:span(parent, name, cursor, y1, z - t, x2 + t, y2, z + t, style)
	end
end

-- Wall running along Z at `x`. Same openings format as wallX.
function Kit:wallZ(parent, name, x, z1, z2, y1, y2, style, openings, thickness)
	local t = (thickness or 1) / 2
	local cursor = z1 - t
	for _, o in sortedOpenings(openings) do
		local a, b, top, bottom = o[1], o[2], o[3], o[4] or y1
		if a > cursor then
			self:span(parent, name, x - t, y1, cursor, x + t, y2, a, style)
		end
		if bottom > y1 then
			self:span(parent, name .. "Sill", x - t, y1, a, x + t, bottom, b, style)
		end
		if top < y2 then
			self:span(parent, name .. "Lintel", x - t, top, a, x + t, y2, b, style)
		end
		cursor = b
	end
	if cursor < z2 + t then
		self:span(parent, name, x - t, y1, cursor, x + t, y2, z2 + t, style)
	end
end

-- Adds a tag and attributes, and counts the tag for the build report.
function Kit:mark(instance, tag, attributes)
	instance:AddTag(tag)
	self.tagCounts[tag] = (self.tagCounts[tag] or 0) + 1
	if attributes then
		for key, value in attributes do
			instance:SetAttribute(key, value)
		end
	end
	return instance
end

-- Hinged door leaf in a wall opening, created in its OPEN pose (swung 90 degrees) so the
-- map can be walked before doors become interactive. Both poses are stored as attributes.
--   wallAxis  "x": the wall runs along X at depth `at`, the opening spans from..to on X
--             "z": the wall runs along Z at x = `at`, the opening spans from..to on Z
--   swing     +1 / -1: side of the wall the leaf opens towards
--   hingeAtFrom  true: hinge at `from`, false: hinge at `to`
function Kit:door(parent, name, wallAxis, at, from, to, swing, hingeAtFrom, style, opts)
	opts = opts or {}
	local height = opts.height or 7.4
	local thick = opts.thick or 0.3
	local width = to - from
	local closed = opts.closed == true
	local hinge = if hingeAtFrom then from + thick / 2 else to - thick / 2
	local closedCFrame, openCFrame

	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(width, height, thick)
	if wallAxis == "x" then
		closedCFrame = CFrame.new((from + to) / 2, height / 2, at)
		openCFrame = CFrame.new(hinge, height / 2, at + swing * width / 2) * CFrame.Angles(0, math.pi / 2, 0)
		if closed then
			self:_record(name, from, 0, at - thick / 2, to, height, at + thick / 2, style)
		else
			local zFar = at + swing * width
			self:_record(
				name,
				hinge - thick / 2,
				0,
				math.min(at, zFar),
				hinge + thick / 2,
				height,
				math.max(at, zFar),
				style
			)
		end
	else
		closedCFrame = CFrame.new(at, height / 2, (from + to) / 2) * CFrame.Angles(0, math.pi / 2, 0)
		openCFrame = CFrame.new(at + swing * width / 2, height / 2, hinge)
		if closed then
			self:_record(name, at - thick / 2, 0, from, at + thick / 2, height, to, style)
		else
			local xFar = at + swing * width
			self:_record(
				name,
				math.min(at, xFar),
				0,
				hinge - thick / 2,
				math.max(at, xFar),
				height,
				hinge + thick / 2,
				style
			)
		end
	end
	part.CFrame = if closed then closedCFrame else openCFrame
	self:_apply(part, style)
	part.Parent = parent

	-- Three hinge knuckles on the hinge edge (the leaf turns about them: DoorService).
	local knuckle = {
		color = Color3.fromRGB(64, 64, 68),
		material = Enum.Material.Metal,
		collide = false,
		shadow = false,
	}
	for _, y in { 1.1, height / 2, height - 1.1 } do
		local hx, hz = if wallAxis == "x" then hinge else at, if wallAxis == "x" then at else hinge
		self:cyl(parent, "Hinge", hx, y - 0.25, hz, thick * 0.75, 0.5, knuckle)
	end
	self:mark(part, "Door", {
		ClosedCFrame = closedCFrame,
		OpenCFrame = openCFrame,
		Open = not closed,
		Zone = opts.zone or "",
	})
	return part
end

-- Text on one face of an unrotated part. `side` is a compass letter (N, S, E, W, U, D).
--   glow   number: unaffected by scene light and this bright (for lit signs)
--   bg     Color3: opaque background
function Kit:text(part, side, text, opts)
	opts = opts or {}
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Label"
	gui.Face = Enum.NormalId[FACE[side]]
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = opts.pps or 24
	if opts.glow then
		gui.LightInfluence = 0
		gui.Brightness = opts.glow
	else
		gui.LightInfluence = 1
	end
	gui.Parent = part

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.new(1, 0, 1, 0)
	label.BorderSizePixel = 0
	if opts.bg then
		label.BackgroundTransparency = 0
		label.BackgroundColor3 = opts.bg
	else
		label.BackgroundTransparency = 1
	end
	label.Text = text
	label.TextScaled = true
	label.TextWrapped = true
	label.TextColor3 = opts.color or Color3.new(1, 1, 1)
	label.FontFace = Font.fromEnum(Enum.Font[opts.font or "GothamBold"])
	label.Parent = gui
	return gui
end

-- Light attached to `part`, named "Light". kind: "SurfaceLight", "SpotLight" or "PointLight".
function Kit:light(part, kind, props)
	local light = Instance.new(kind)
	light.Name = "Light"
	light.Brightness = props.brightness
	light.Range = props.range
	light.Color = props.color or Color3.fromRGB(255, 255, 255)
	light.Shadows = props.shadows == true
	if kind ~= "PointLight" then
		light.Angle = props.angle or 120
		light.Face = Enum.NormalId[FACE[props.side or "D"]]
	end
	light.Parent = part
	self.lightCount += 1
	return light
end

-- Ceiling fluorescent fixture: a housing, a glowing tube and a downward light.
-- The tube is tagged LightFixture so the power and lighting systems can drive it.
--   axis  "x" or "z": direction of the tube
function Kit:fixture(parent, zone, circuit, cx, cz, ceiling, axis, props)
	local half = (props.length or 8) / 2
	local hx, hz = half, 0.7
	if axis == "z" then
		hx, hz = 0.7, half
	end
	self:span(
		parent,
		"FixtureHousing",
		cx - hx,
		ceiling - 0.35,
		cz - hz,
		cx + hx,
		ceiling,
		cz + hz,
		props.housing
	)
	local tubeStyle = {
		color = props.color,
		material = Enum.Material.Neon,
		collide = false,
		shadow = false,
	}
	local tube = self:span(
		parent,
		"FixtureTube",
		cx - hx + 0.2,
		ceiling - 0.5,
		cz - hz + 0.25,
		cx + hx - 0.2,
		ceiling - 0.35,
		cz + hz - 0.25,
		tubeStyle
	)
	self:light(tube, "SurfaceLight", {
		brightness = props.brightness,
		range = props.range,
		angle = props.angle or 130,
		color = props.color,
		shadows = props.shadows,
		side = "D",
	})
	self:mark(tube, "LightFixture", { Zone = zone, Circuit = circuit, BaseBrightness = props.brightness })
	return tube
end

-- Small decorative part with an arbitrary orientation (e.g. a camera aimed at a target).
function Kit:oriented(parent, name, cframe, sx, sy, sz, style)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(sx, sy, sz)
	part.CFrame = cframe
	self:_apply(part, style)
	part.Parent = parent
	local reach = math.max(sx, sy, sz) / 2
	local p = cframe.Position
	self:_record(name, p.X - reach, p.Y - reach, p.Z - reach, p.X + reach, p.Y + reach, p.Z + reach, style)
	return part
end

-- Invisible spawn pad at floor level.
function Kit:spawn(parent, x, z)
	local pad = Instance.new("SpawnLocation")
	pad.Name = "PlayerSpawn"
	pad.Size = Vector3.new(4, 1, 4)
	pad.CFrame = CFrame.new(x, 0.5, z)
	pad.Anchored = true
	pad.Transparency = 1
	pad.CanCollide = false
	pad.CanTouch = false
	pad.CanQuery = false
	pad.CastShadow = false
	pad.Neutral = true
	pad.Duration = 0
	pad.Enabled = true
	pad.Parent = parent
	self:mark(pad, "PlayerSpawn")
	return pad
end

-- Small invisible anchor used for navigation and task positions.
function Kit:marker(parent, name, x, y, z, tag, attributes)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = Vector3.new(1, 1, 1)
	part.CFrame = CFrame.new(x, y, z)
	part.Anchored = true
	part.Transparency = 1
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = parent
	if tag then
		self:mark(part, tag, attributes)
	end
	return part
end

return Kit
