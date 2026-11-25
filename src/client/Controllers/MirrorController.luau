--!strict
-- Mirrors (tag: Mirror, attribute Normal = the way the glass faces). Roblox cannot render
-- real reflections, so each mirror shows a ViewportFrame on its glass: a mirror-image copy
-- of the room in front of it (built once, the first time you come near), and mirror-image
-- copies of your character and the monster, moved every frame. The view is taken from
-- your camera through the glass, so the reflection shifts as you move.
--
-- It is an approximation: lit by a flat dim light (no lamps or flashlight), and slightly
-- off when the mirror is seen at a steep angle. Only mirrors within reach update.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MirrorController = {}

-- Only mirrors this close to the camera are drawn.
local RANGE = 32
-- The room copied: everything in front of the glass, this far out and to the sides.
-- (Just the room: a restroom is 20 deep and 40 wide, the mirror in the middle of a side.)
local DEPTH = 20.2
local SIDE = 21

type Mirror = {
	Part: BasePart,
	Normal: Vector3,
	Gui: SurfaceGui?,
	View: ViewportFrame?,
	Camera: Camera?,
	World: WorldModel?,
	Actors: { [Model]: { Clone: Model, Pairs: { { BasePart } } } },
	Warned: boolean?,
}

local mirrors: { Mirror } = {}

-- The front face of the glass: its centre, the normal, and its width and height.
local function glass(mirror: Mirror): (Vector3, Vector3, number, number)
	local part = mirror.Part
	local n = mirror.Normal
	local centre = part.Position + n * (part.Size.Z / 2)
	return centre, n, part.Size.X, part.Size.Y
end

-- The mirror image of a CFrame across the plane through `p0` with normal `n`.
local function reflect(cf: CFrame, p0: Vector3, n: Vector3): CFrame
	local function v(x: Vector3): Vector3
		return x - 2 * x:Dot(n) * n
	end
	local position = cf.Position - 2 * (cf.Position - p0):Dot(n) * n
	-- Reflecting flips handedness; turning the right axis back keeps a proper rotation
	-- (shapes are symmetric left to right, so they look right).
	return CFrame.fromMatrix(position, -v(cf.RightVector), v(cf.UpVector), -v(cf.LookVector))
end

local function faceOf(n: Vector3): Enum.NormalId
	if n.Z > 0.5 then
		return Enum.NormalId.Back
	elseif n.Z < -0.5 then
		return Enum.NormalId.Front
	elseif n.X > 0.5 then
		return Enum.NormalId.Right
	end
	return Enum.NormalId.Left
end

local function stripped(part: BasePart): BasePart
	local copy = part:Clone()
	for _, child in copy:GetChildren() do
		if not child:IsA("SurfaceAppearance") and not child:IsA("SpecialMesh") and not child:IsA("Decal") then
			child:Destroy()
		end
	end
	copy.Anchored = true
	return copy
end

-- Builds the glass's view and the mirrored copy of the room in front of it.
local function build(mirror: Mirror)
	local centre, n, width, height = glass(mirror)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Reflection"
	gui.Face = faceOf(n)
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	-- Kept in the player's GUI and shown on the glass through Adornee: a ViewportFrame
	-- in a SurfaceGui parented straight to the part did not draw.
	gui.Adornee = mirror.Part
	gui.ResetOnSpawn = false
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	local view = Instance.new("ViewportFrame")
	view.Size = UDim2.new(1, 0, 1, 0)
	view.BackgroundColor3 = Color3.fromRGB(10, 10, 9)
	view.BorderSizePixel = 0
	-- Dim, a little green: an old, dirty mirror at night.
	view.Ambient = Color3.fromRGB(150, 144, 124)
	view.LightColor = Color3.fromRGB(190, 180, 150)
	view.LightDirection = Vector3.new(0, -1, 0)
	view.ImageColor3 = Color3.fromRGB(210, 212, 196)
	view.Parent = gui
	local camera = Instance.new("Camera")
	camera.Parent = view
	view.CurrentCamera = camera
	local world = Instance.new("WorldModel")
	world.Parent = view

	-- The room in front of the glass: every visible part of the map whose middle is in
	-- front of it and within reach (walked through the map, not a spatial query - that
	-- would miss the decorative parts, which cannot be queried).
	local across = n:Cross(Vector3.new(0, 1, 0)).Unit
	local map = Workspace:FindFirstChild("Map")
	for _, part in if map then map:GetDescendants() else {} do
		if not part:IsA("BasePart") or part == mirror.Part then
			continue
		end
		local offset = part.Position - centre
		local inFront = offset:Dot(n)
		if
			inFront > 0.05
			and inFront < DEPTH
			and math.abs(offset:Dot(across)) < SIDE
			and math.abs(offset.Y) < 9
			and part.Transparency < 0.95
			and part.Name ~= "BloodLayer"
			and not part:IsDescendantOf(Players.LocalPlayer.Character or Instance.new("Folder"))
			and not CollectionService:HasTag(part, "Monster")
		then
			local copy = stripped(part)
			copy.CFrame = reflect(part.CFrame, centre, n)
			copy.Parent = world
		end
	end
	mirror.Gui, mirror.View, mirror.Camera, mirror.World = gui, view, camera, world
	local _ = width + height
end

-- A copy of a character, kept as the mirror image of it.
local function actor(mirror: Mirror, model: Model)
	local entry = mirror.Actors[model]
	if entry then
		return entry
	end
	local archivable = model.Archivable
	model.Archivable = true
	local clone = model:Clone()
	model.Archivable = archivable
	if not clone then
		return nil
	end
	-- Pair every part with its copy first (the clone keeps the original's order), then
	-- strip what the copy must not run or play.
	local originals = model:GetDescendants()
	local copies = clone:GetDescendants()
	local pairsList = {}
	for index, original in originals do
		local copy = copies[index]
		if original:IsA("BasePart") and copy and copy:IsA("BasePart") and copy.Name == original.Name then
			copy.Anchored = true
			table.insert(pairsList, { original, copy })
		end
	end
	for _, d in copies do
		if
			d:IsA("LuaSourceContainer")
			or d:IsA("Sound")
			or d:IsA("Light")
			or d:IsA("Constraint")
			or d:IsA("JointInstance")
		then
			d:Destroy()
		end
	end
	clone.Parent = mirror.World
	entry = { Clone = clone, Pairs = pairsList }
	mirror.Actors[model] = entry
	return entry
end

local function update(mirror: Mirror, camera: Camera)
	local centre, n, width, height = glass(mirror)
	local eye = camera.CFrame.Position
	local distance = (eye - centre):Dot(n)
	if distance < 0.3 or (eye - centre).Magnitude > RANGE then
		if mirror.Gui then
			mirror.Gui.Enabled = false
		end
		return
	end
	if not mirror.Gui then
		build(mirror)
	end
	local gui = mirror.Gui :: SurfaceGui
	gui.Enabled = true
	-- Looking from the eye through the middle of the glass, the frustum just covering it.
	local view = mirror.Camera :: Camera
	view.CFrame = CFrame.lookAt(eye, centre - n * 0.01)
	view.FieldOfView = math.clamp(math.deg(2 * math.atan(height / 2 / distance)), 5, 110)
	local _ = width

	-- The people in front of it.
	local characters: { Model } = {}
	local own = Players.LocalPlayer.Character
	if own then
		table.insert(characters, own)
	end
	local monster = Workspace:FindFirstChild("TheCustomerBody")
	if monster and monster:IsA("Model") then
		table.insert(characters, monster)
	end
	local present: { [Model]: boolean } = {}
	for _, model in characters do
		present[model] = true
		local entry = actor(mirror, model)
		if entry then
			for _, pair in entry.Pairs do
				local original, copy = pair[1], pair[2]
				copy.CFrame = reflect(original.CFrame, centre, n)
				-- First person hides your own head; the reflection shows it.
				copy.Transparency = original.Transparency
				copy.LocalTransparencyModifier = 0
			end
		end
	end
	for model, entry in mirror.Actors do
		if not present[model] or not model.Parent then
			entry.Clone:Destroy()
			mirror.Actors[model] = nil
		end
	end
end

local function add(part: Instance)
	if not part:IsA("BasePart") then
		return
	end
	local normal = part:GetAttribute("Normal")
	table.insert(mirrors, {
		Part = part,
		Normal = if typeof(normal) == "Vector3" then normal.Unit else part.CFrame.LookVector,
		Actors = {},
	})
end

function MirrorController.Start()
	CollectionService:GetInstanceAddedSignal("Mirror"):Connect(add)
	for _, part in CollectionService:GetTagged("Mirror") do
		add(part)
	end
	RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		for _, mirror in mirrors do
			local ok, message = pcall(update, mirror, camera)
			if not ok then
				if not mirror.Warned then
					mirror.Warned = true
					warn("[Mirror] " .. tostring(message))
				end
				if mirror.Gui then
					mirror.Gui.Enabled = false
				end
			end
		end
	end)
end

return MirrorController
