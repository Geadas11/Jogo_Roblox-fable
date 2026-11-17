--!strict
-- The Customer's mind: a state machine that decides where to go and whom to chase.
--
-- It knows nothing about Roblox objects. Everything it needs comes through `World`
-- (where the players are, whether a spot is occupied) and it reports what it does
-- through callbacks. MonsterManager connects it to the game; the tests drive it
-- directly, step by step, on the real map grid.
--
-- States
--   Patrol       walks between patrol points, sometimes pausing to look around
--   Observe      stands still and stares at someone it has half-noticed
--   Investigate  walks to a noise
--   Search       looks around an area: a few nearby points, maybe a hiding spot
--   Chase        pursues one player
--   Catch        has caught someone; stands still for the catch sequence
--   Vanished     gone for a while after a catch, then reappears elsewhere

local NavGrid = require(script.Parent.NavGrid)

export type Target = {
	Id: number,
	X: number,
	Z: number,
	-- Moving fast enough to be heard and to be noticed more easily.
	Running: boolean,
	-- Inside a hiding spot (and therefore invisible to normal sight).
	Hidden: boolean,
	-- The hiding spot they are in, if any.
	Spot: number?,
	-- Standing somewhere with the lights on (or holding a lit flashlight).
	Lit: boolean?,
	-- Holding a lit flashlight: noticed more easily.
	Flashlight: boolean?,
}

export type Spot = { Id: number, X: number, Z: number }

export type World = {
	-- Players who can currently be hunted.
	Targets: () -> { Target },
	PatrolPoints: { NavGrid.Point },
	HidingSpots: { Spot },
	-- Who is in a hiding spot, or nil.
	OccupantOf: (spot: number) -> number?,
	OnCatch: (id: number) -> (),
	-- The monster moved somewhere new (for opening doors on the way, etc.).
	OnStateChanged: ((state: string, target: number?) -> ())?,
	-- Picks where to reappear; nil to stay hidden a little longer.
	ChooseSpawn: () -> NavGrid.Point?,
	Random: () -> number,
}

export type Config = {
	Speed: { Patrol: number, Investigate: number, Search: number, Chase: number },
	Senses: { [string]: number },
	Behaviour: { [string]: number },
	CatchDistance: number,
	CatchSequenceSeconds: number,
}

local Brain = {}
Brain.__index = Brain

export type Brain = typeof(setmetatable(
	{} :: {
		Grid: NavGrid.NavGrid,
		World: World,
		Config: Config,
		X: number,
		Z: number,
		-- Unit vector of where it is facing.
		FaceX: number,
		FaceZ: number,
		State: string,
		-- Player being chased, stared at or caught.
		TargetId: number?,
		SpeedMultiplier: number,
		Present: boolean,

		_time: number,
		_stateTime: number,
		_path: { NavGrid.Point }?,
		_pathGoal: NavGrid.Point?,
		_lastRepath: number,
		_awareness: { [number]: number },
		_lastSeen: { x: number, z: number, at: number }?,
		_searchPoints: { NavGrid.Point },
		_searchSpot: Spot?,
		_pauseUntil: number,
		_patrolGoal: NavGrid.Point?,
		_observeRolled: { [number]: boolean },
		_vanishUntil: number,
		_noise: { x: number, z: number }?,
	},
	Brain
))

local function distance(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = bx - ax, bz - az
	return math.sqrt(dx * dx + dz * dz)
end

function Brain.new(grid: NavGrid.NavGrid, world: World, config: Config): Brain
	local self = setmetatable({
		Grid = grid,
		World = world,
		Config = config,
		X = 0,
		Z = 0,
		FaceX = 0,
		FaceZ = -1,
		State = "Vanished",
		TargetId = nil,
		SpeedMultiplier = 1,
		Present = false,

		_time = 0,
		_stateTime = 0,
		_path = nil,
		_pathGoal = nil,
		_lastRepath = -math.huge,
		_awareness = {},
		_lastSeen = nil,
		_searchPoints = {},
		_searchSpot = nil,
		_pauseUntil = 0,
		_patrolGoal = nil,
		_observeRolled = {},
		_vanishUntil = 0,
		_noise = nil,
	}, Brain)
	return self
end

-- Puts the monster somewhere and starts it patrolling.
function Brain.Appear(self: Brain, x: number, z: number)
	local point = self.Grid:Nearest(x, z, 6)
	if point then
		x, z = point.x, point.z
	end
	self.X, self.Z = x, z
	self.Present = true
	self._awareness = {}
	self._lastSeen = nil
	self:_setState("Patrol", nil)
end

-- Removes the monster until Appear is called again (end of the night).
function Brain.Disappear(self: Brain)
	self.Present = false
	self._vanishUntil = 0
	self._noise = nil
	self._awareness = {}
	self:_setState("Vanished", nil)
end

function Brain._setState(self: Brain, state: string, target: number?)
	local changed = state ~= self.State or target ~= self.TargetId
	self.State = state
	self.TargetId = target
	self._stateTime = self._time
	self._path = nil
	self._pathGoal = nil
	self._patrolGoal = nil
	self._pauseUntil = 0
	if changed and self.World.OnStateChanged then
		self.World.OnStateChanged(state, target)
	end
end

-- Movement -------------------------------------------------------------------------------

-- Walks towards (x, z) along a path. Returns true once there.
function Brain._moveTowards(self: Brain, x: number, z: number, speed: number, dt: number): boolean
	if distance(self.X, self.Z, x, z) < 1 then
		return true
	end

	local goal = self._pathGoal
	local needsPath = self._path == nil or goal == nil or distance(goal.x, goal.z, x, z) > 2
	if needsPath then
		if self.Grid:CanWalkLine(self.X, self.Z, x, z) then
			-- Straight line: no search needed, and always up to date.
			self._path = { { x = x, z = z } }
			self._pathGoal = { x = x, z = z }
		elseif self._time - self._lastRepath >= self.Config.Behaviour.RepathSeconds or self._path == nil then
			self._lastRepath = self._time
			local path = self.Grid:FindPath(self.X, self.Z, x, z)
			if not path then
				return true -- unreachable: treat as arrived so the state moves on
			end
			self._path = path
			self._pathGoal = { x = x, z = z }
		end
	end

	local path = self._path :: { NavGrid.Point }
	local budget = speed * self.SpeedMultiplier * dt
	while budget > 0 and #path > 0 do
		local waypoint = path[1]
		local dx, dz = waypoint.x - self.X, waypoint.z - self.Z
		local length = math.sqrt(dx * dx + dz * dz)
		if length > 0.001 then
			self.FaceX, self.FaceZ = dx / length, dz / length
		end
		if length <= budget then
			self.X, self.Z = waypoint.x, waypoint.z
			budget -= length
			table.remove(path, 1)
		else
			self.X += dx / length * budget
			self.Z += dz / length * budget
			budget = 0
		end
	end
	-- The path ends as close to the goal as the monster can stand.
	return #path == 0
end

function Brain._face(self: Brain, x: number, z: number)
	local dx, dz = x - self.X, z - self.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length > 0.001 then
		self.FaceX, self.FaceZ = dx / length, dz / length
	end
end

-- Turns slowly on the spot (looking around).
function Brain._lookAround(self: Brain, dt: number)
	local angle = math.atan2(self.FaceZ, self.FaceX) + dt * 0.9
	self.FaceX, self.FaceZ = math.cos(angle), math.sin(angle)
end

-- Senses ---------------------------------------------------------------------------------

-- Whether the monster can see this target right now.
function Brain._canSee(self: Brain, target: Target): boolean
	if target.Hidden then
		return false
	end
	local senses = self.Config.Senses
	local d = distance(self.X, self.Z, target.X, target.Z)
	local range = if target.Lit == false
		then senses.VisionRange * (senses.DarkVisionFactor or 1)
		else senses.VisionRange
	if d > range then
		return false
	end
	if d > senses.ProximityRange then
		local dx, dz = (target.X - self.X) / d, (target.Z - self.Z) / d
		local cosine = dx * self.FaceX + dz * self.FaceZ
		if cosine < math.cos(math.rad(senses.FieldOfView / 2)) then
			return false
		end
	end
	return self.Grid:CanSee(self.X, self.Z, target.X, target.Z)
end

-- Raises awareness of whoever it can see. Returns the target it has become sure about
-- (if any) and the target it is most aware of.
function Brain._sense(self: Brain, dt: number, factor: number): (Target?, Target?)
	local senses = self.Config.Senses
	local seen: { [number]: boolean } = {}
	local sure, best = nil, nil
	local bestLevel = 0
	for _, target in self.World.Targets() do
		local d = distance(self.X, self.Z, target.X, target.Z)
		if not target.Hidden and d <= senses.ProximityRange then
			-- Close enough to be sensed without being seen.
			self._awareness[target.Id] = 1
			seen[target.Id] = true
		elseif self:_canSee(target) then
			-- Close is noticed quickly, far slowly; running stands out.
			local closeness = 1 - d / senses.VisionRange
			local rate = (0.35 + 1.3 * closeness) / senses.DetectSeconds * factor
			if target.Running then
				rate *= 1.5
			end
			if target.Flashlight then
				rate *= senses.FlashlightNoticeFactor or 1
			end
			self._awareness[target.Id] = (self._awareness[target.Id] or 0) + rate * dt
			seen[target.Id] = true
		end
		local level = self._awareness[target.Id] or 0
		if
			seen[target.Id]
			and level >= 1
			and (sure == nil or d < distance(self.X, self.Z, sure.X, sure.Z))
		then
			sure = target
		end
		if seen[target.Id] and level > bestLevel then
			best, bestLevel = target, level
		end
	end
	for id, level in self._awareness do
		if not seen[id] then
			local decayed = level - senses.AwarenessDecay * dt
			self._awareness[id] = if decayed > 0 then decayed else nil
			if decayed <= 0 then
				-- Forgotten: a later encounter may make it stop and stare again.
				self._observeRolled[id] = nil
			end
		end
	end
	return sure, best
end

-- Called when a noise happens within earshot.
function Brain.Hear(self: Brain, x: number, z: number)
	if not self.Present or self.State == "Chase" or self.State == "Catch" then
		return
	end
	self._noise = { x = x, z = z }
end

-- Actions --------------------------------------------------------------------------------

function Brain._startChase(self: Brain, target: Target)
	self._lastSeen = { x = target.X, z = target.Z, at = self._time }
	self._noise = nil
	self:_setState("Chase", target.Id)
end

function Brain._startSearch(self: Brain, x: number, z: number)
	local behaviour = self.Config.Behaviour
	self._searchPoints = {}
	for _ = 1, behaviour.SearchPoints do
		local angle = self.World.Random() * math.pi * 2
		local radius = behaviour.SearchRadius * (0.4 + 0.6 * self.World.Random())
		local point = self.Grid:Nearest(x + math.cos(angle) * radius, z + math.sin(angle) * radius, 6)
		if point then
			table.insert(self._searchPoints, point)
		end
	end

	-- Perhaps open a hiding spot near the place it is searching.
	self._searchSpot = nil
	if self.World.Random() < behaviour.CheckHidingSpotChance then
		local nearest, nearestDistance = nil, behaviour.HidingSpotCheckRange
		for _, spot in self.World.HidingSpots do
			local d = distance(x, z, spot.X, spot.Z)
			if d < nearestDistance then
				nearest, nearestDistance = spot, d
			end
		end
		self._searchSpot = nearest
	end
	self:_setState("Search", nil)
end

function Brain._catch(self: Brain, id: number)
	self:_setState("Catch", id)
	self.World.OnCatch(id)
end

function Brain._nextPatrolPoint(self: Brain): NavGrid.Point?
	local points = self.World.PatrolPoints
	if #points == 0 then
		return nil
	end
	-- Prefer somewhere a fair walk away, so it roams the whole store.
	for _ = 1, 8 do
		local point = points[math.floor(self.World.Random() * #points) + 1]
		local d = distance(self.X, self.Z, point.x, point.z)
		if d > 25 and d < 180 then
			return point
		end
	end
	return points[math.floor(self.World.Random() * #points) + 1]
end

-- One tick ---------------------------------------------------------------------------------

function Brain.Step(self: Brain, dt: number)
	self._time += dt
	if not self.Present then
		if self.State == "Vanished" and self._vanishUntil > 0 and self._time >= self._vanishUntil then
			local spawn = self.World.ChooseSpawn()
			if spawn then
				self._vanishUntil = 0
				self:Appear(spawn.x, spawn.z)
			end
		end
		return
	end

	local state = self.State
	local speed = self.Config.Speed
	local behaviour = self.Config.Behaviour

	if state == "Catch" then
		if self._time - self._stateTime >= self.Config.CatchSequenceSeconds then
			self.Present = false
			self._vanishUntil = self._time + behaviour.VanishSeconds
			self:_setState("Vanished", nil)
		end
		return
	end

	if state == "Chase" then
		self:_stepChase(dt)
		return
	end

	-- Every calm state watches for players.
	local factor = if state == "Observe" then 0.5 else 1
	local sure, best = self:_sense(dt, factor)
	if sure then
		self:_startChase(sure)
		return
	end

	-- Someone half-noticed at a distance: sometimes it stops and stares (decided once
	-- per encounter).
	if best and state ~= "Observe" and not self._observeRolled[best.Id] then
		local d = distance(self.X, self.Z, best.X, best.Z)
		if d >= behaviour.ObserveMinDistance then
			self._observeRolled[best.Id] = true
			if self.World.Random() < behaviour.ObserveChance then
				self:_setState("Observe", best.Id)
				return
			end
		end
	end

	-- Otherwise anything glimpsed makes it stop and turn towards it while it makes up
	-- its mind ("what was that?").
	if best and state ~= "Observe" and self._noise == nil then
		self:_face(best.X, best.Z)
		return
	end

	-- A noise interrupts anything calm.
	local noise = self._noise
	if noise then
		self._noise = nil
		self._lastSeen = nil
		self:_setState("Investigate", nil)
		self._searchPoints = { { x = noise.x, z = noise.z } }
		state = "Investigate"
	end

	if state == "Observe" then
		local target = nil
		for _, candidate in self.World.Targets() do
			if candidate.Id == self.TargetId then
				target = candidate
			end
		end
		if target and self:_canSee(target) then
			self:_face(target.X, target.Z)
			self._lastSeen = { x = target.X, z = target.Z, at = self._time }
		elseif self._lastSeen == nil or self._time - self._lastSeen.at > 3 then
			self:_setState("Patrol", nil)
		end
		if self._time - self._stateTime > 12 then
			self:_setState("Patrol", nil)
		end
	elseif state == "Investigate" then
		local point = self._searchPoints[1]
		if not point or self:_moveTowards(point.x, point.z, speed.Investigate, dt) then
			local x, z = if point then point.x else self.X, if point then point.z else self.Z
			self:_startSearch(x, z)
		end
	elseif state == "Search" then
		self:_stepSearch(dt)
	else -- Patrol
		if self._pauseUntil > self._time then
			self:_lookAround(dt)
		else
			if self._patrolGoal == nil then
				self._patrolGoal = self:_nextPatrolPoint()
			end
			local goal = self._patrolGoal
			if goal and self:_moveTowards(goal.x, goal.z, speed.Patrol, dt) then
				self._patrolGoal = nil
				self._path = nil
				self._pathGoal = nil
				if self.World.Random() < behaviour.PauseChance then
					local pause = behaviour.PauseMin
						+ (behaviour.PauseMax - behaviour.PauseMin) * self.World.Random()
					self._pauseUntil = self._time + pause
				end
			end
		end
	end
end

function Brain._stepSearch(self: Brain, dt: number)
	local speed = self.Config.Speed

	-- First the hiding spot, if it chose to check one.
	local spot = self._searchSpot
	if spot then
		if
			self:_moveTowards(spot.X, spot.Z, speed.Search, dt)
			or distance(self.X, self.Z, spot.X, spot.Z) < 3
		then
			self._searchSpot = nil
			self._path = nil
			self._pathGoal = nil
			local occupant = self.World.OccupantOf(spot.Id)
			if occupant then
				self:_catch(occupant)
			end
		end
		return
	end

	local point = self._searchPoints[1]
	if not point then
		self:_setState("Patrol", nil)
		return
	end
	if self._pauseUntil > self._time then
		self:_lookAround(dt)
		return
	end
	if self:_moveTowards(point.x, point.z, speed.Search, dt) then
		table.remove(self._searchPoints, 1)
		self._path = nil
		self._pathGoal = nil
		self._pauseUntil = self._time + 1.5
	end
end

function Brain._stepChase(self: Brain, dt: number)
	local senses = self.Config.Senses
	local target: Target? = nil
	for _, candidate in self.World.Targets() do
		if candidate.Id == self.TargetId then
			target = candidate
		end
	end

	local lastSeen = self._lastSeen
	if not target or not lastSeen then
		-- They left, or were caught by someone else's hand.
		self:_startSearch(self.X, self.Z)
		return
	end

	if target.Hidden then
		-- Seen going in: it goes straight to the spot and pulls them out.
		if self._time - lastSeen.at <= senses.SeenHidingWindow and target.Spot then
			local spotTarget = nil
			for _, spot in self.World.HidingSpots do
				if spot.Id == target.Spot then
					spotTarget = spot
				end
			end
			if spotTarget then
				self._lastSeen = nil
				self:_setState("Search", nil)
				self._searchSpot = spotTarget
				self._searchPoints = {}
				return
			end
		end
		self:_startSearch(lastSeen.x, lastSeen.z)
		return
	end

	local d = distance(self.X, self.Z, target.X, target.Z)
	local visible = d <= senses.ProximityRange or self:_canSee(target)
	if visible then
		self._lastSeen = { x = target.X, z = target.Z, at = self._time }
		if d <= self.Config.CatchDistance then
			self:_catch(target.Id)
			return
		end
	elseif self._time - lastSeen.at > senses.LoseSightSeconds then
		self:_startSearch(lastSeen.x, lastSeen.z)
		return
	end

	local goal = self._lastSeen :: { x: number, z: number, at: number }
	if self:_moveTowards(goal.x, goal.z, self.Config.Speed.Chase, dt) and not visible then
		-- At the last place it saw them, and they are not here: search.
		self:_startSearch(goal.x, goal.z)
	end
end

-- Whether it is currently interested in anyone in particular (for HUD/audio cues).
function Brain.AwarenessOf(self: Brain, id: number): number
	return self._awareness[id] or 0
end

return Brain
