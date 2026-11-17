--[[
	Turns the list of parts the map generator produced into two top-down grids, one
	stud per cell, that the game uses at runtime:

	  Walk   where the monster can stand: every cell whose centre is clear of anything
	         solid, with a margin for the monster's own width.
	  Sight  what blocks a line of sight at eye level: tall solid things (walls, shelving,
	         racks). Glass and anything low enough to see over does not.

	The same code builds the grids for the place file (tools/build.luau) and for the
	tests (tests/engine.luau), so the tests exercise exactly what ships.

	Each grid is stored as text, six cells per character, row by row from the north-west.
]]

local Grids = {}

-- Half the monster's width plus a little clearance.
Grids.AgentRadius = 1.5
-- The monster is a little over 7 studs tall; anything that starts above that is overhead.
Grids.AgentHeight = 7.0
-- Low ledges it simply steps over.
Grids.StepHeight = 0.6
-- A line of sight runs between about these heights.
Grids.SightLow = 4.0
Grids.SightHigh = 5.0

local function encode(cells, count)
	local characters = table.create(math.ceil(count / 6))
	for start = 1, count, 6 do
		local value = 0
		for bit = 0, 5 do
			if cells[start + bit] then
				value += 2 ^ bit
			end
		end
		table.insert(characters, string.char(48 + value))
	end
	return table.concat(characters)
end

-- grounds: the playable rectangle { x1, x2, z1, z2 } from map/Layout.
function Grids.compute(records, grounds)
	local originX, originZ = grounds.x1 - 4, grounds.z1 - 4
	local width, depth = (grounds.x2 - grounds.x1) + 8, (grounds.z2 - grounds.z1) + 8
	local count = width * depth

	local function rasterize(includes, margin)
		local cells = table.create(count, false)
		for _, record in records do
			if includes(record) then
				local i1 = math.max(0, math.ceil(record.x1 - margin - originX - 0.5))
				local i2 = math.min(width - 1, math.floor(record.x2 + margin - originX - 0.5))
				local j1 = math.max(0, math.ceil(record.z1 - margin - originZ - 0.5))
				local j2 = math.min(depth - 1, math.floor(record.z2 + margin - originZ - 0.5))
				for j = j1, j2 do
					for i = i1, i2 do
						cells[j * width + i + 1] = true
					end
				end
			end
		end
		return cells
	end

	local walk = rasterize(function(record)
		return record.collide and record.y2 > Grids.StepHeight and record.y1 < Grids.AgentHeight
	end, Grids.AgentRadius)

	local sight = rasterize(function(record)
		return record.collide
			and not record.glass
			and record.y1 < Grids.SightLow
			and record.y2 > Grids.SightHigh
	end, 0)

	return {
		OriginX = originX,
		OriginZ = originZ,
		Width = width,
		Depth = depth,
		Walk = encode(walk, count),
		Sight = encode(sight, count),
		-- Raw cells, for checks and drawings at build time (not stored in the place).
		WalkCells = walk,
		SightCells = sight,
	}
end

return Grids
