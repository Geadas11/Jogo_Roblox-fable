--[[
	Builds the complete place file. From the repository root:

		lune run tools/build

	1. `rojo build` turns src/ into a place that contains only the code.
	2. The map generator (map/) builds the supermarket into Workspace.
	3. The base lighting profile is written into Lighting so the map looks right in
	   Studio's edit mode too (the server applies the same profile again at runtime).
	4. The result is checked: every navigation and task point must be reachable on foot
	   from the player spawn, every interactive object must be approachable, and every
	   indoor zone must have light and a patrol point.
	5. The place is saved to releases/NightShiftSupermarket.rbxl and a floor plan to
	   docs/floor-plan.svg.

	Exits with code 1 if any check fails; nothing is saved in that case.
]]

local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local stdio = require("@lune/stdio")

local Engine = require("../tests/engine")
local Layout = require("../map/Layout")
local Map = require("../map/Map")

local OUTPUT = "releases/NightShiftSupermarket.rbxl"
local PLAN = "docs/floor-plan.svg"

-- A character is about 2 studs wide and 5 tall, and steps over small ledges.
local PLAYER_RADIUS = 1
local PLAYER_HEIGHT = 5.2
local STEP_HEIGHT = 0.6
-- How close a player must be able to get to something to use it.
local REACH = 6

local problems = {}
local function problem(message)
	table.insert(problems, message)
end

-- 1. Code ---------------------------------------------------------------------------------
fs.writeDir("build")
local built = process.exec("rojo", { "build", "default.project.json", "--output", "build/code.rbxl" })
if not built.ok then
	error("rojo build failed:\n" .. built.stderr)
end
local game = roblox.deserializePlace(fs.readFile("build/code.rbxl"))
local workspace = game:GetService("Workspace")

-- 2. Map ----------------------------------------------------------------------------------
local kit, root = Map.build(workspace)

-- 3. Lighting -----------------------------------------------------------------------------
local profile = Engine.new().side("server").load("ReplicatedStorage.Shared.Config.LightingConfig").Base
local lighting = game:GetService("Lighting")
local skipped = {}
for name, value in profile.Lighting do
	local ok = pcall(function()
		if name == "ClockTime" then
			-- The file format stores the time of day as text.
			lighting.TimeOfDay = string.format("%02d:00:00", value)
		else
			lighting[name] = value
		end
	end)
	if not ok then
		table.insert(skipped, "Lighting." .. name)
	end
end
for _, spec in profile.Children do
	local child = roblox.Instance.new(spec.ClassName)
	child.Name = spec.Name
	for name, value in spec.Properties do
		local ok = pcall(function()
			child[name] = value
		end)
		if not ok then
			table.insert(skipped, spec.Name .. "." .. name)
		end
	end
	child.Parent = lighting
end

-- 4. Checks -------------------------------------------------------------------------------
local g = Layout.Grounds
local originX, originZ = g.x1 - 4, g.z1 - 4
local width, depth = (g.x2 - g.x1) + 8, (g.z2 - g.z1) + 8

local blocked = table.create(width * depth, false)
local function cellIndex(x, z)
	local i, j = math.floor(x - originX), math.floor(z - originZ)
	if i < 0 or j < 0 or i >= width or j >= depth then
		return nil
	end
	return j * width + i + 1
end

for _, record in kit.records do
	if record.collide and record.y2 > STEP_HEIGHT and record.y1 < PLAYER_HEIGHT then
		-- Block every cell whose centre lies inside the obstacle grown by the player radius.
		local i1 = math.ceil(record.x1 - PLAYER_RADIUS - originX - 0.5)
		local i2 = math.floor(record.x2 + PLAYER_RADIUS - originX - 0.5)
		local j1 = math.ceil(record.z1 - PLAYER_RADIUS - originZ - 0.5)
		local j2 = math.floor(record.z2 + PLAYER_RADIUS - originZ - 0.5)
		for j = math.max(j1, 0), math.min(j2, depth - 1) do
			for i = math.max(i1, 0), math.min(i2, width - 1) do
				blocked[j * width + i + 1] = true
			end
		end
	end
end

-- Everything tagged, with a position.
local tagged = {}
local function positionOf(instance)
	if instance:IsA("BasePart") then
		return instance.CFrame.Position
	end
	for _, child in instance:GetChildren() do
		if child:IsA("BasePart") then
			return child.CFrame.Position
		end
	end
	return nil
end
for _, instance in root:GetDescendants() do
	for _, tag in instance:GetTags() do
		local position = positionOf(instance)
		if position then
			tagged[tag] = tagged[tag] or {}
			table.insert(tagged[tag], { instance = instance, x = position.X, y = position.Y, z = position.Z })
		else
			problem(string.format("%s tagged %s has no position", instance.Name, tag))
		end
	end
end

-- Flood fill from the first player spawn.
local reachable = table.create(width * depth, false)
local spawns = tagged.PlayerSpawn or {}
if #spawns == 0 then
	problem("the map has no PlayerSpawn")
else
	local start = cellIndex(spawns[1].x, spawns[1].z)
	if not start or blocked[start] then
		problem("the first player spawn is inside an obstacle")
	else
		local queue, head = { start }, 1
		reachable[start] = true
		while head <= #queue do
			local cell = queue[head]
			head += 1
			local i = (cell - 1) % width
			for _, neighbour in
				{
					cell - width,
					cell + width,
					if i > 0 then cell - 1 else 0,
					if i < width - 1 then cell + 1 else 0,
				}
			do
				if
					neighbour >= 1
					and neighbour <= width * depth
					and not blocked[neighbour]
					and not reachable[neighbour]
				then
					reachable[neighbour] = true
					table.insert(queue, neighbour)
				end
			end
		end
	end
end

local function isReachable(x, z, within)
	if within == 0 then
		local cell = cellIndex(x, z)
		return cell ~= nil and reachable[cell]
	end
	for dz = -within, within do
		for dx = -within, within do
			if dx * dx + dz * dz <= within * within then
				local cell = cellIndex(x + dx, z + dz)
				if cell and reachable[cell] then
					return true
				end
			end
		end
	end
	return false
end

-- Points a character must be able to stand on.
for _, tag in
	{
		"PlayerSpawn",
		"PatrolNode",
		"CustomerNode",
		"SpillPoint",
		"TrashPoint",
		"CartPoint",
		"CartReturn",
		"DeliveryPoint",
	}
do
	for _, entry in tagged[tag] or {} do
		if not isReachable(entry.x, entry.z, 0) then
			problem(string.format("%s at (%.0f, %.0f) cannot be reached on foot", tag, entry.x, entry.z))
		end
	end
end
-- Objects a character must be able to get close to.
for _, tag in
	{
		"ShelfBay",
		"FridgeUnit",
		"CheckoutRegister",
		"ElectricalPanel",
		"Breaker",
		"OfficeComputer",
		"TimeClock",
		"ToolPickup",
		"RepairPoint",
		"Dumpster",
		"HidingSpot",
		"Door",
		"EmergencyExit",
		"EntranceDoor",
	}
do
	for _, entry in tagged[tag] or {} do
		if not isReachable(entry.x, entry.z, REACH) then
			problem(
				string.format(
					"%s %s at (%.0f, %.0f) cannot be approached",
					tag,
					entry.instance.Name,
					entry.x,
					entry.z
				)
			)
		end
	end
end

-- Every zone needs a patrol point; every indoor zone needs light.
local function zonesOf(tag)
	local set = {}
	for _, entry in tagged[tag] or {} do
		set[entry.instance:GetAttribute("Zone")] = true
	end
	return set
end
local patrolZones, litZones = zonesOf("PatrolNode"), zonesOf("LightFixture")
local zoneCount = 0
for _, entry in tagged.Zone or {} do
	zoneCount += 1
	local id = entry.instance:GetAttribute("ZoneId")
	-- A sealed zone cannot be entered during the shift, so nothing patrols it.
	if not patrolZones[id] and not entry.instance:GetAttribute("Sealed") then
		problem("zone " .. id .. " has no PatrolNode")
	end
	if entry.instance:GetAttribute("Indoor") and not litZones[id] then
		problem("indoor zone " .. id .. " has no LightFixture")
	end
end

-- Cameras are numbered 1..8 without gaps.
local cameraIds = {}
for _, entry in tagged.CCTVCamera or {} do
	cameraIds[entry.instance:GetAttribute("CameraId")] = true
end
for id = 1, 8 do
	if not cameraIds[id] then
		problem("security camera " .. id .. " is missing")
	end
end

-- Minimum amount of content the game systems rely on.
for tag, minimum in
	{
		PlayerSpawn = 6,
		ShelfBay = 100,
		FridgeUnit = 20,
		CheckoutRegister = 4,
		HidingSpot = 8,
		SpillPoint = 12,
		Breaker = 5,
		ElectricalPanel = 1,
		OfficeComputer = 1,
		TimeClock = 1,
	}
do
	local count = #(tagged[tag] or {})
	if count < minimum then
		problem(string.format("expected at least %d %s, found %d", minimum, tag, count))
	end
end

-- 5. Floor plan ---------------------------------------------------------------------------
local SCALE = 4
local planX1, planZ1, planX2, planZ2 = g.x1 - 6, g.z1 - 6, g.x2 + 6, g.z2 + 6
local svg = {
	string.format(
		'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d" font-family="sans-serif">',
		(planX2 - planX1) * SCALE,
		(planZ2 - planZ1) * SCALE
	),
	'<rect width="100%" height="100%" fill="#1c1c20"/>',
}
local drawn = {}
for _, record in kit.records do
	-- Skip ceilings, the roof, anything overhead, zone volumes and individual products.
	if not record.invisible and record.y1 < 7 and record.name ~= "Product" and record.name ~= "Produce" then
		table.insert(drawn, record)
	end
end
table.sort(drawn, function(a, b)
	return a.y2 < b.y2
end)
for _, record in drawn do
	local x1, z1 = math.max(record.x1, planX1), math.max(record.z1, planZ1)
	local x2, z2 = math.min(record.x2, planX2), math.min(record.z2, planZ2)
	if x2 > x1 and z2 > z1 then
		table.insert(
			svg,
			string.format(
				'<rect x="%.1f" y="%.1f" width="%.1f" height="%.1f" fill="rgb(%d,%d,%d)"%s/>',
				(x1 - planX1) * SCALE,
				(z1 - planZ1) * SCALE,
				(x2 - x1) * SCALE,
				(z2 - z1) * SCALE,
				record.color[1],
				record.color[2],
				record.color[3],
				if record.glass then ' fill-opacity="0.5"' else ""
			)
		)
	end
end
-- Free cells nobody can walk to (sealed or enclosed pockets), hatched in red.
for j = 0, depth - 1 do
	for i = 0, width - 1 do
		local cell = j * width + i + 1
		local x, z = originX + i, originZ + j
		if
			not blocked[cell]
			and not reachable[cell]
			and x >= g.x1
			and x < g.x2
			and z >= g.z1
			and z < g.z2
		then
			table.insert(
				svg,
				string.format(
					'<rect x="%d" y="%d" width="%d" height="%d" fill="#ff2020" fill-opacity="0.35"/>',
					(x - planX1) * SCALE,
					(z - planZ1) * SCALE,
					SCALE,
					SCALE
				)
			)
		end
	end
end

local function dot(entry, radius, fill)
	table.insert(
		svg,
		string.format(
			'<circle cx="%.1f" cy="%.1f" r="%d" fill="%s"/>',
			(entry.x - planX1) * SCALE,
			(entry.z - planZ1) * SCALE,
			radius,
			fill
		)
	)
end
for _, entry in tagged.LightFixture or {} do
	dot(entry, 3, "#ffe680")
end
for _, entry in tagged.PatrolNode or {} do
	dot(entry, 3, "#ff5050")
end
for _, entry in tagged.CCTVCamera or {} do
	dot(entry, 5, "#40c8ff")
end
for _, entry in tagged.PlayerSpawn or {} do
	dot(entry, 4, "#60e080")
end
for _, entry in tagged.HidingSpot or {} do
	dot(entry, 4, "#c080ff")
end
for _, zone in Layout.Zones do
	table.insert(
		svg,
		string.format(
			'<text x="%.1f" y="%.1f" font-size="22" font-weight="bold" fill="#ffffff" stroke="#000000" stroke-width="4" paint-order="stroke" text-anchor="middle">%s</text>',
			((zone.x1 + zone.x2) / 2 - planX1) * SCALE,
			((zone.z1 + zone.z2) / 2 - planZ1) * SCALE,
			string.upper(zone.name)
		)
	)
end
table.insert(svg, "</svg>")

-- Walkable area, as a sanity figure for the report.
local blockedCount, reachableCount = 0, 0
for index = 1, width * depth do
	if blocked[index] then
		blockedCount += 1
	end
	if reachable[index] then
		reachableCount += 1
	end
end

-- 6. Report and save ------------------------------------------------------------------------
local instanceCount = #root:GetDescendants()
print(
	string.format(
		"Map: %d parts, %d lights, %d instances, %d zones",
		kit.partCount,
		kit.lightCount,
		instanceCount,
		zoneCount
	)
)
local tags = {}
for tag, count in kit.tagCounts do
	table.insert(tags, string.format("%s=%d", tag, count))
end
table.sort(tags)
print("Tags: " .. table.concat(tags, "  "))
print(
	string.format(
		"Walkability: %d cells reachable from the spawn, %d blocked, of %d",
		reachableCount,
		blockedCount,
		width * depth
	)
)
if #skipped > 0 then
	print(
		"Lighting properties this tool could not write (the server sets them at runtime): "
			.. table.concat(skipped, ", ")
	)
end

if #problems > 0 then
	print("")
	for _, message in problems do
		print(stdio.color("red") .. "PROBLEM " .. stdio.color("reset") .. message)
	end
	print(string.format("\n%d problems. Nothing was saved.", #problems))
	process.exit(1)
end

fs.writeDir("releases")
local bytes = roblox.serializePlace(game)
fs.writeFile(OUTPUT, bytes)
fs.writeFile(PLAN, table.concat(svg, "\n"))
-- Raw part list, for external previews and debugging (not committed).
fs.writeFile("build/map-records.json", require("@lune/serde").encode("json", kit.records))
print(
	string.format(
		"%sSaved %s (%d KB) and %s%s",
		stdio.color("green"),
		OUTPUT,
		math.floor(#bytes / 1024),
		PLAN,
		stdio.color("reset")
	)
)
