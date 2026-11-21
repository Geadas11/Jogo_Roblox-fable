--!strict
-- The store's lights as this client sees them.
--
--   * every ceiling light follows its circuit: off when the circuit is down
--   * the whole store dims a little each hour (Config.PowerConfig.Hours)
--   * lights flicker, more often as the night goes on, and more at fixtures the map
--     marks as faulty
--   * a faint red cast while any circuit is down
--   * the flashlight: F, or the LIGHT button on touch screens
--
-- Flickers are cosmetic and decided by each client on its own; which lights are on or
-- off comes from the server and is the same for everyone.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local LightingConfig = require(Shared.Config.LightingConfig)
local PowerConfig = require(Shared.Config.PowerConfig)
local SessionState = require(Shared.SessionState)
local Net = require(script.Parent.Parent.Net)
local Settings = require(script.Parent.Parent.Settings)
local Theme = require(script.Parent.Parent.UI.Theme)
local HudController = require(script.Parent.HudController)

type Fixture = {
	Tube: BasePart,
	Light: Light?,
	Circuit: string,
	Color: Color3,
	Faulty: boolean,
	Flickering: boolean,
	-- os.clock() until which a blackout event keeps it dark.
	DarkUntil: number,
}

type Zone = { X1: number, X2: number, Z1: number, Z2: number, Area: number, Circuit: string }

local LightingController = {}

local fixtures: { Fixture } = {}
local zones: { Zone } = {}
local nextFlickerIn = math.huge
local powerGrade: ColorCorrectionEffect? = nil
local lightButton: TextButton? = nil
-- 0 = normal air, 1 = the thick dark haze of a room without power.
local fog = 0
local blackoutUntil = 0
local blackoutAt: Vector3? = nil
local blackoutRadius = 0

local OFF_COLOR = Color3.fromRGB(70, 72, 74)

-- The air when the lights are out: denser, darker, closer.
local FOG_DARK = {
	Density = 0.62,
	Offset = 0.55,
	Haze = 5,
	Color = Color3.fromRGB(14, 15, 18),
	Decay = Color3.fromRGB(6, 6, 8),
}

local function circuitOn(circuit: string): boolean
	if circuit == "Emergency" or not table.find(PowerConfig.Circuits, circuit) then
		return true
	end
	return SessionState.Get("Power" .. circuit) == true
end

local function hourProfile(): { Ambient: number, Flicker: number }
	local hour = if SessionState.Get("Phase") == "Shift" then SessionState.Get("Hour") else 0
	return PowerConfig.Hours[math.clamp(hour + 1, 1, #PowerConfig.Hours)]
end

local function setLit(fixture: Fixture, lit: boolean)
	if lit and fixture.DarkUntil > os.clock() then
		lit = false
	end
	local light = fixture.Light
	if light then
		light.Enabled = lit
	end
	fixture.Tube.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	fixture.Tube.Color = if lit then fixture.Color else OFF_COLOR
	-- Lit signs (the checkout lane numbers) carry glowing text: it goes out too.
	for _, child in fixture.Tube:GetChildren() do
		if child:IsA("SurfaceGui") then
			child.Enabled = lit
		end
	end
end

-- Puts every light and the ambient level in line with the power and the hour.
function LightingController.Apply()
	local anyOff = false
	for _, fixture in fixtures do
		local on = circuitOn(fixture.Circuit)
		if not on then
			anyOff = true
		end
		if not fixture.Flickering then
			setLit(fixture, on)
		end
	end

	local profile = hourProfile()
	local base = LightingConfig.Base.Lighting
	local function scaled(color: Color3, factor: number): Color3
		return Color3.new(color.R * factor, color.G * factor, color.B * factor)
	end
	Lighting.Ambient = scaled(base.Ambient, profile.Ambient * (if anyOff then 0.7 else 1))
	Lighting.OutdoorAmbient = scaled(base.OutdoorAmbient, profile.Ambient)

	local camera = Workspace.CurrentCamera
	if camera and not powerGrade then
		local effect = Instance.new("ColorCorrectionEffect")
		effect.Name = "PowerGrade"
		effect.Parent = camera
		powerGrade = effect
	end
	if powerGrade then
		powerGrade.TintColor = if anyOff then Color3.fromRGB(255, 228, 224) else Color3.new(1, 1, 1)
	end

	nextFlickerIn = if profile.Flicker > 0 then math.min(nextFlickerIn, profile.Flicker) else math.huge
end

-- Makes one light stutter for a moment.
function LightingController.Flicker(fixture: Fixture)
	if fixture.Flickering or not circuitOn(fixture.Circuit) then
		return
	end
	fixture.Flickering = true
	if Settings.Get("ReducedFlashing") >= 0.5 then
		-- Reduced flashing: one slow dip instead of a strobe.
		task.spawn(function()
			setLit(fixture, false)
			task.wait(0.8)
			fixture.Flickering = false
			setLit(fixture, circuitOn(fixture.Circuit))
		end)
		return
	end
	task.spawn(function()
		for _ = 1, math.random(3, 7) do
			setLit(fixture, false)
			task.wait(math.random() * 0.12 + 0.03)
			setLit(fixture, circuitOn(fixture.Circuit))
			task.wait(math.random() * 0.25 + 0.03)
		end
		fixture.Flickering = false
		setLit(fixture, circuitOn(fixture.Circuit))
	end)
end

local function fixturesNear(x: number, z: number, radius: number): { Fixture }
	local near = {}
	for _, fixture in fixtures do
		local position = fixture.Tube.Position
		local dx, dz = position.X - x, position.Z - z
		if dx * dx + dz * dz <= radius * radius then
			table.insert(near, fixture)
		end
	end
	return near
end

-- A horror event: the lights around a point stutter together.
function LightingController.FlickerNear(x: number, z: number, radius: number)
	for _, fixture in fixturesNear(x, z, radius) do
		LightingController.Flicker(fixture)
	end
end

-- A horror event: the lights around a point go out for a few seconds, then come back.
function LightingController.BlackoutNear(x: number, z: number, radius: number, seconds: number)
	local untilTime = os.clock() + seconds
	local affected = fixturesNear(x, z, radius)
	for _, fixture in affected do
		fixture.DarkUntil = untilTime
		setLit(fixture, false)
	end
	blackoutUntil = untilTime
	blackoutAt = Vector3.new(x, 0, z)
	blackoutRadius = radius
	task.delay(seconds, function()
		for _, fixture in affected do
			if not fixture.Flickering then
				setLit(fixture, circuitOn(fixture.Circuit))
			end
		end
	end)
end

-- The circuit lighting a point (the smallest zone containing it), like PowerManager.
local function circuitAt(x: number, z: number): string?
	local best: Zone? = nil
	for _, zone in zones do
		if x >= zone.X1 and x <= zone.X2 and z >= zone.Z1 and z <= zone.Z2 then
			if best == nil or zone.Area < best.Area then
				best = zone
			end
		end
	end
	return if best then best.Circuit else nil
end

-- Thickens the air where the player stands has no light; thins it again when it returns.
local function updateFog(dt: number)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		return
	end
	local character = Players.LocalPlayer.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local target = 0
	if root and root:IsA("BasePart") then
		local position = root.Position
		local circuit = circuitAt(position.X, position.Z)
		if circuit and not circuitOn(circuit) then
			target = 1
		end
		local at = blackoutAt
		if at and os.clock() < blackoutUntil then
			local dx, dz = position.X - at.X, position.Z - at.Z
			if dx * dx + dz * dz <= blackoutRadius * blackoutRadius then
				target = 1
			end
		end
	end
	if math.abs(target - fog) < 0.001 then
		return
	end
	-- In quickly when the lights die, out slowly when they come back.
	local speed = if target > fog then 1.2 else 0.35
	fog = if target > fog then math.min(target, fog + dt * speed) else math.max(target, fog - dt * speed)

	local base = (LightingConfig.Base.Children[1] :: any).Properties
	atmosphere.Density = base.Density + (FOG_DARK.Density - base.Density) * fog
	atmosphere.Offset = base.Offset + (FOG_DARK.Offset - base.Offset) * fog
	atmosphere.Haze = base.Haze + (FOG_DARK.Haze - base.Haze) * fog
	atmosphere.Color = (base.Color :: Color3):Lerp(FOG_DARK.Color, fog)
	atmosphere.Decay = (base.Decay :: Color3):Lerp(FOG_DARK.Decay, fog)
end

local function flickerSomewhere()
	if #fixtures == 0 then
		return
	end
	-- Fixtures the map marks as faulty are three times as likely.
	local total = 0
	for _, fixture in fixtures do
		total += if fixture.Faulty then 3 else 1
	end
	local roll = math.random() * total
	for _, fixture in fixtures do
		roll -= if fixture.Faulty then 3 else 1
		if roll <= 0 then
			LightingController.Flicker(fixture)
			return
		end
	end
end

local function register(instance: Instance)
	if not instance:IsA("BasePart") then
		return
	end
	for _, existing in fixtures do
		if existing.Tube == instance then
			return
		end
	end
	local light = instance:FindFirstChild("Light")
	local fixture: Fixture = {
		Tube = instance,
		Light = if light and light:IsA("Light") then light else nil,
		Circuit = tostring(instance:GetAttribute("Circuit") or "Emergency"),
		Color = instance.Color,
		Faulty = instance:GetAttribute("Flicker") == true,
		Flickering = false,
		DarkUntil = 0,
	}
	table.insert(fixtures, fixture)
	setLit(fixture, circuitOn(fixture.Circuit))
end

-- The local player's own beam. The server's flashlight sits on the character's head,
-- which does not tilt up and down with the first-person camera; so this client draws
-- its own beam from the camera (exactly where you look) and hides its head light
-- locally. Everyone else still sees the server's beam.
local beam: Part? = nil

local function updateBeam()
	local player = Players.LocalPlayer
	local on = player:GetAttribute("FlashlightOn") == true
	local camera = Workspace.CurrentCamera
	local character = player.Character
	local head = if character then character:FindFirstChild("Head") else nil
	local headLight = if head then head:FindFirstChild("Flashlight") else nil
	if headLight and headLight:IsA("SpotLight") and on then
		-- Local only: does not replicate, so others keep seeing it.
		headLight.Enabled = false
	end
	if not on or not camera then
		if beam then
			(beam :: Part).Parent = nil
		end
		return
	end
	if not beam then
		local part = Instance.new("Part")
		part.Name = "FlashlightBeam"
		part.Size = Vector3.new(0.2, 0.2, 0.2)
		part.Transparency = 1
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Angle = 50
		light.Range = 55
		light.Brightness = 2.6
		light.Color = Color3.fromRGB(255, 244, 222)
		light.Shadows = true
		light.Parent = part
		-- A little spill around you, so the floor at your feet is not black.
		local spill = Instance.new("PointLight")
		spill.Range = 9
		spill.Brightness = 0.35
		spill.Color = Color3.fromRGB(255, 240, 215)
		spill.Shadows = false
		spill.Parent = part
		beam = part
	end
	local part = beam :: Part
	-- Held low and to the right, like a torch in your hand.
	part.CFrame = camera.CFrame * CFrame.new(0.7, -0.6, -0.4)
	part.Parent = Workspace
end

local function toggleFlashlight()
	local player = Players.LocalPlayer
	Net.FireServer("Flashlight", player:GetAttribute("FlashlightOn") ~= true)
end

function LightingController.Init()
	if UserInputService.TouchEnabled then
		local button = Theme.create("TextButton", {
			Name = "Light",
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -110, 1, -170),
			Size = UDim2.new(0, 64, 0, 64),
			BackgroundColor3 = Theme.Colors.Panel,
			BackgroundTransparency = 0.2,
			BorderSizePixel = 0,
			FontFace = Theme.Fonts.Title,
			TextColor3 = Theme.Colors.Text,
			TextSize = 14,
			Text = "LIGHT",
			Parent = HudController.GetScreen(),
		}, {
			Theme.create("UICorner", { CornerRadius = UDim.new(0, 6) }),
		}) :: TextButton
		button.Activated:Connect(toggleFlashlight)
		lightButton = button
	end
end

function LightingController.Start()
	CollectionService:GetInstanceAddedSignal("LightFixture"):Connect(function(instance)
		register(instance)
	end)
	for _, instance in CollectionService:GetTagged("LightFixture") do
		register(instance)
	end

	local keys = { "Phase", "Hour" }
	for _, circuit in PowerConfig.Circuits do
		table.insert(keys, "Power" .. circuit)
	end
	for _, key in keys do
		SessionState.Observe(key, function()
			LightingController.Apply()
		end)
	end

	-- F, with or without other keys held. Roblox can flag a plain key press as "processed"
	-- by its own UI even when nothing is typed; the only thing that must block it is
	-- typing (chat, a text box).
	UserInputService.InputBegan:Connect(function(input: InputObject)
		if input.KeyCode == Enum.KeyCode.F and UserInputService:GetFocusedTextBox() == nil then
			toggleFlashlight()
		end
	end)

	local player = Players.LocalPlayer
	player:GetAttributeChangedSignal("FlashlightOn"):Connect(function()
		if lightButton then
			lightButton.BackgroundColor3 = if player:GetAttribute("FlashlightOn")
				then Theme.Colors.Warning
				else Theme.Colors.Panel
		end
	end)

	for _, volume in CollectionService:GetTagged("Zone") do
		if volume:IsA("BasePart") and volume:GetAttribute("Circuit") ~= nil then
			local position, size = volume.Position, volume.Size
			table.insert(zones, {
				X1 = position.X - size.X / 2,
				X2 = position.X + size.X / 2,
				Z1 = position.Z - size.Z / 2,
				Z2 = position.Z + size.Z / 2,
				Area = size.X * size.Z,
				Circuit = tostring(volume:GetAttribute("Circuit")),
			})
		end
	end

	RunService.RenderStepped:Connect(updateBeam)

	RunService.Heartbeat:Connect(function(dt: number)
		updateFog(dt)
		local profile = hourProfile()
		if profile.Flicker <= 0 then
			nextFlickerIn = math.huge
			return
		end
		nextFlickerIn -= dt
		if nextFlickerIn <= 0 then
			flickerSomewhere()
			-- Random intervals averaging the hour's value.
			nextFlickerIn = -math.log(1 - math.random() * 0.95) * profile.Flicker
		end
	end)
end

-- For tests.
LightingController.GetFixtures = function(): { Fixture }
	return fixtures
end

return LightingController
