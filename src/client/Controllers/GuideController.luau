--!strict
-- Draws the trail GuideService sends: a line of soft glowing dots on the floor from the
-- player towards their next step (the broom, a spill, a bag, the dumpsters), with a
-- pulse running along it in the direction to go. Only this player sees their trail.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Parent.Net)

local GuideController = {}

-- A dot every this many studs, starting this far ahead, for at most this far.
local SPACING = 2.2
local START = 2.5
local MAX_LENGTH = 70
local COLOR = Color3.fromRGB(255, 214, 120)

local folder: Folder? = nil
local dots: { BasePart } = {}
local shown = 0
local ray: RaycastParams? = nil

local function getFolder(): Folder
	local current = folder
	if current and current.Parent then
		return current
	end
	local created = Instance.new("Folder")
	created.Name = "GuideTrail"
	created.Parent = Workspace
	folder = created
	return created
end

local function dot(index: number): BasePart
	local existing = dots[index]
	if existing then
		return existing
	end
	local part = Instance.new("Part")
	part.Name = "GuideDot"
	part.Shape = Enum.PartType.Cylinder
	-- A flat disc: a cylinder's axis is its X axis, turned upright below.
	part.Size = Vector3.new(0.05, 0.45, 0.45)
	part.Color = COLOR
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Parent = getFolder()
	dots[index] = part
	return part
end

-- The floor under (x, z), near height `y`.
local function floorAt(x: number, z: number, y: number): number
	local params = ray
	if not params and typeof(RaycastParams) ~= "table" and not RaycastParams then
		-- (No physics to ask: keep the guess.)
		return y
	end
	if not params then
		params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		ray = params
	end
	local exclude: { Instance } = { getFolder() }
	local character = Players.LocalPlayer.Character
	if character then
		table.insert(exclude, character)
	end
	params.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(Vector3.new(x, y + 3, z), Vector3.new(0, -9, 0), params)
	return if hit then hit.Position.Y else y
end

local function hideFrom(index: number)
	for i = index, #dots do
		dots[i].Transparency = 1
	end
end

-- Lays the dots along the route.
function GuideController.Show(route: { number })
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if #route < 4 or not root or not root:IsA("BasePart") then
		shown = 0
		hideFrom(1)
		return
	end
	local floorGuess = root.Position.Y - 3
	local count = 0
	local walked = 0
	local nextAt = START
	for i = 1, #route - 3, 2 do
		local ax, az, bx, bz = route[i], route[i + 1], route[i + 2], route[i + 3]
		local length = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		while length > 0 and nextAt <= walked + length and nextAt <= MAX_LENGTH do
			local t = (nextAt - walked) / length
			local x, z = ax + (bx - ax) * t, az + (bz - az) * t
			count += 1
			local part = dot(count)
			local y = floorAt(x, z, floorGuess)
			floorGuess = y
			part.CFrame = CFrame.new(x, y + 0.06, z) * CFrame.Angles(0, 0, math.pi / 2)
			part:SetAttribute("Along", nextAt)
			nextAt += SPACING
		end
		walked += length
		if nextAt > MAX_LENGTH then
			break
		end
	end
	shown = count
	hideFrom(count + 1)
end

-- The pulse running along the trail, and a fade towards its far end.
local function animate()
	if shown == 0 then
		return
	end
	local now = os.clock()
	for index = 1, shown do
		local part = dots[index]
		local along = part:GetAttribute("Along") :: number? or 0
		local wave = (math.sin(along * 0.35 - now * 4) + 1) / 2
		local fade = math.clamp(along / MAX_LENGTH, 0, 1)
		part.Transparency = 0.25 + 0.5 * (1 - wave) * 0.7 + 0.35 * fade
	end
end

function GuideController.Start()
	Net.On("Guide", function(route: any)
		if type(route) == "table" then
			GuideController.Show(route)
		end
	end)
	RunService.RenderStepped:Connect(animate)
end

return GuideController
