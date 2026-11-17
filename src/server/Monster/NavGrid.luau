--!strict
--!native
--!optimize 2
-- Navigation and line of sight on the baked top-down grids (see tools/grids.luau).
--
-- Why not PathfindingService: the map is static and flat, and a grid we bake ourselves
-- behaves identically in Studio and in the automated tests - so every route the monster
-- can take is checked before a build ships. Doors are baked open; the monster opens any
-- door it meets, so a closed door never changes where it can go.
--
-- Pure Luau: no engine objects. Positions are plain numbers (x, z).

export type Spec = {
	OriginX: number,
	OriginZ: number,
	Width: number,
	Depth: number,
	Walk: string,
	Sight: string,
}

export type Point = { x: number, z: number }

export type NavGrid = {
	IsWalkable: (self: NavGrid, x: number, z: number) -> boolean,
	Nearest: (self: NavGrid, x: number, z: number, radius: number) -> Point?,
	CanWalkLine: (self: NavGrid, ax: number, az: number, bx: number, bz: number) -> boolean,
	CanSee: (self: NavGrid, ax: number, az: number, bx: number, bz: number) -> boolean,
	FindPath: (self: NavGrid, ax: number, az: number, bx: number, bz: number) -> { Point }?,
}

local STRAIGHT, DIAGONAL = 10, 14
-- The search leans towards the goal instead of exploring evenly in all directions.
-- Routes can come out slightly longer than the true shortest, which smoothing mostly
-- removes, and the search looks at several times fewer cells.
local GOAL_BIAS = 2
-- Give up on a search that has looked at this many cells: the goal is unreachable.
local MAX_EXPANSIONS = 60000
-- Path smoothing tries shortcuts of these lengths (in cells), longest first. Trying a
-- handful of strides instead of every cell keeps smoothing cheap on long routes.
local SMOOTH_STRIDES = { 64, 32, 16, 8, 4, 2 }

-- Six cells per character; a set bit means "blocked".
local function decode(encoded: string, count: number): buffer
	local cells = buffer.create(count)
	local index = 0
	for position = 1, #encoded do
		local value = string.byte(encoded, position) - 48
		for bit = 0, 5 do
			if index >= count then
				break
			end
			if bit32.band(value, bit32.lshift(1, bit)) ~= 0 then
				buffer.writeu8(cells, index, 1)
			end
			index += 1
		end
	end
	return cells
end

local NavGrid = {}

function NavGrid.new(spec: Spec): NavGrid
	local width, depth = spec.Width, spec.Depth
	local count = width * depth
	local originX, originZ = spec.OriginX, spec.OriginZ
	local walk = decode(spec.Walk, count)
	local sight = decode(spec.Sight, count)

	-- Search scratch space, reused between searches. A cell's entries are valid only
	-- when its stamp equals the current search number.
	local cost = buffer.create(count * 4)
	local parent = buffer.create(count * 4)
	local seen = buffer.create(count * 4)
	local done = buffer.create(count * 4)
	local search = 0

	local function cellAt(x: number, z: number): number?
		local i, j = math.floor(x - originX), math.floor(z - originZ)
		if i < 0 or j < 0 or i >= width or j >= depth then
			return nil
		end
		return j * width + i
	end

	local function centre(cell: number): Point
		return { x = originX + cell % width + 0.5, z = originZ + cell // width + 0.5 }
	end

	local function blockedAt(cells: buffer, i: number, j: number): boolean
		if i < 0 or j < 0 or i >= width or j >= depth then
			return true
		end
		return buffer.readu8(cells, j * width + i) ~= 0
	end

	-- True when every cell the segment touches is clear. Walks the grid cell by cell
	-- (Amanatides & Woo), so a line can never slip between samples across the corner
	-- of a blocked cell. Passing exactly through a corner checks both cells beside it.
	local function lineClear(cells: buffer, ax: number, az: number, bx: number, bz: number): boolean
		local x, z = ax - originX, az - originZ
		local ex, ez = bx - originX, bz - originZ
		local i, j = math.floor(x), math.floor(z)
		local endI, endJ = math.floor(ex), math.floor(ez)
		if blockedAt(cells, i, j) then
			return false
		end

		local dx, dz = ex - x, ez - z
		local stepI = if dx > 0 then 1 elseif dx < 0 then -1 else 0
		local stepJ = if dz > 0 then 1 elseif dz < 0 then -1 else 0
		local deltaX = if dx ~= 0 then 1 / math.abs(dx) else math.huge
		local deltaZ = if dz ~= 0 then 1 / math.abs(dz) else math.huge
		local nextX = if dx > 0 then (i + 1 - x) * deltaX elseif dx < 0 then (x - i) * deltaX else math.huge
		local nextZ = if dz > 0 then (j + 1 - z) * deltaZ elseif dz < 0 then (z - j) * deltaZ else math.huge

		local remaining = math.abs(endI - i) + math.abs(endJ - j) + 2
		while (i ~= endI or j ~= endJ) and remaining > 0 do
			remaining -= 1
			if math.abs(nextX - nextZ) < 1e-9 then
				if blockedAt(cells, i + stepI, j) or blockedAt(cells, i, j + stepJ) then
					return false
				end
				i += stepI
				j += stepJ
				nextX += deltaX
				nextZ += deltaZ
			elseif nextX < nextZ then
				i += stepI
				nextX += deltaX
			else
				j += stepJ
				nextZ += deltaZ
			end
			if blockedAt(cells, i, j) then
				return false
			end
		end
		return true
	end

	local grid = {}

	function grid.IsWalkable(_self: any, x: number, z: number): boolean
		local cell = cellAt(x, z)
		return cell ~= nil and buffer.readu8(walk, cell) == 0
	end

	-- Centre of the closest walkable cell within `radius` studs, or nil.
	function grid.Nearest(_self: any, x: number, z: number, radius: number): Point?
		local best: number? = nil
		local bestDistance = math.huge
		for dz = -radius, radius do
			for dx = -radius, radius do
				local cell = cellAt(x + dx, z + dz)
				if cell ~= nil and buffer.readu8(walk, cell) == 0 then
					local distance = dx * dx + dz * dz
					if distance < bestDistance then
						best, bestDistance = cell, distance
					end
				end
			end
		end
		return if best then centre(best) else nil
	end

	function grid.CanWalkLine(_self: any, ax: number, az: number, bx: number, bz: number): boolean
		return lineClear(walk, ax, az, bx, bz)
	end

	-- Line of sight at eye level between two points.
	function grid.CanSee(_self: any, ax: number, az: number, bx: number, bz: number): boolean
		return lineClear(sight, ax, az, bx, bz)
	end

	-- Waypoints from a to b (not including a), or nil when there is no route.
	function grid.FindPath(self: any, ax: number, az: number, bx: number, bz: number): { Point }?
		local from = self:Nearest(ax, az, 4)
		local to = self:Nearest(bx, bz, 6)
		if not from or not to then
			return nil
		end
		-- Routes are measured from where the walker really stands, not from the centre
		-- of its cell, so the first leg is as safe as the others.
		local origin: Point = if self:IsWalkable(ax, az) then { x = ax, z = az } else from
		if lineClear(walk, origin.x, origin.z, to.x, to.z) then
			return { to }
		end

		local start = cellAt(from.x, from.z) :: number
		local goal = cellAt(to.x, to.z) :: number
		local goalI, goalJ = goal % width, goal // width

		search += 1
		local heapCells: { number } = {}
		local heapScores: { number } = {}
		local heapSize = 0

		local function push(cell: number, score: number)
			heapSize += 1
			local position = heapSize
			while position > 1 do
				local up = position // 2
				if heapScores[up] <= score then
					break
				end
				heapCells[position], heapScores[position] = heapCells[up], heapScores[up]
				position = up
			end
			heapCells[position], heapScores[position] = cell, score
		end

		local function pop(): number
			local top = heapCells[1]
			local cell, score = heapCells[heapSize], heapScores[heapSize]
			heapSize -= 1
			local position = 1
			while true do
				local child = position * 2
				if child > heapSize then
					break
				end
				if child < heapSize and heapScores[child + 1] < heapScores[child] then
					child += 1
				end
				if heapScores[child] >= score then
					break
				end
				heapCells[position], heapScores[position] = heapCells[child], heapScores[child]
				position = child
			end
			heapCells[position], heapScores[position] = cell, score
			return top
		end

		local function estimate(cell: number): number
			local di, dj = math.abs(cell % width - goalI), math.abs(cell // width - goalJ)
			return GOAL_BIAS * (STRAIGHT * (di + dj) + (DIAGONAL - 2 * STRAIGHT) * math.min(di, dj))
		end

		buffer.writeu32(cost, start * 4, 0)
		buffer.writei32(parent, start * 4, -1)
		buffer.writeu32(seen, start * 4, search)
		push(start, estimate(start))

		local found = false
		local expansions = 0
		while heapSize > 0 do
			local current = pop()
			if current == goal then
				found = true
				break
			end
			if buffer.readu32(done, current * 4) ~= search then
				buffer.writeu32(done, current * 4, search)
				expansions += 1
				if expansions > MAX_EXPANSIONS then
					break
				end

				local i, j = current % width, current // width
				local base = buffer.readu32(cost, current * 4)
				for dj = -1, 1 do
					for di = -1, 1 do
						local ni, nj = i + di, j + dj
						if (di ~= 0 or dj ~= 0) and ni >= 0 and nj >= 0 and ni < width and nj < depth then
							local neighbour = nj * width + ni
							local open = buffer.readu8(walk, neighbour) == 0
							-- No cutting corners: a diagonal step needs both sides free.
							if open and di ~= 0 and dj ~= 0 then
								open = buffer.readu8(walk, j * width + ni) == 0
									and buffer.readu8(walk, nj * width + i) == 0
							end
							if open and buffer.readu32(done, neighbour * 4) ~= search then
								local step = if di ~= 0 and dj ~= 0 then DIAGONAL else STRAIGHT
								local total = base + step
								if
									buffer.readu32(seen, neighbour * 4) ~= search
									or total < buffer.readu32(cost, neighbour * 4)
								then
									buffer.writeu32(seen, neighbour * 4, search)
									buffer.writeu32(cost, neighbour * 4, total)
									buffer.writei32(parent, neighbour * 4, current)
									push(neighbour, total + estimate(neighbour))
								end
							end
						end
					end
				end
			end
		end
		if not found then
			return nil
		end

		-- Walk back from the goal, then straighten: keep only the corners.
		local cells: { Point } = {}
		local cursor = goal
		while cursor ~= -1 do
			table.insert(cells, 1, centre(cursor))
			cursor = buffer.readi32(parent, cursor * 4)
		end

		local path: { Point } = {}
		local anchor = origin
		local index = 2
		while index <= #cells do
			local furthest = index
			for _, stride in SMOOTH_STRIDES do
				local candidate = math.min(#cells, index + stride)
				if
					candidate > furthest
					and lineClear(walk, anchor.x, anchor.z, cells[candidate].x, cells[candidate].z)
				then
					furthest = candidate
					break
				end
			end
			if
				furthest == index and not lineClear(walk, anchor.x, anchor.z, cells[index].x, cells[index].z)
			then
				-- The walker is off-centre in its cell and the next step clips a corner:
				-- go through the centre of the current cell first.
				anchor = cells[index - 1]
				table.insert(path, anchor)
			end
			anchor = cells[furthest]
			table.insert(path, anchor)
			index = furthest + 1
		end
		return path
	end

	return (grid :: any) :: NavGrid
end

return NavGrid
