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
local Theme = require(script.Parent.Parent.UI.Theme)
local HudController = require(script.Parent.HudController)

type Fixture = {
	Tube: BasePart,
	Light: Light?,
	Circuit: string,
	Color: Color3,
	Faulty: boolean,
	Flickering: boolean,
}

local LightingController = {}

local fixtures: { Fixture } = {}
local nextFlickerIn = math.huge
local powerGrade: ColorCorrectionEffect? = nil
local lightButton: TextButton? = nil

local OFF_COLOR = Color3.fromRGB(70, 72, 74)

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
	local light = fixture.Light
	if light then
		light.Enabled = lit
	end
	fixture.Tube.Material = if lit then Enum.Material.Neon else Enum.Material.SmoothPlastic
	fixture.Tube.Color = if lit then fixture.Color else OFF_COLOR
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
	}
	table.insert(fixtures, fixture)
	setLit(fixture, circuitOn(fixture.Circuit))
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

	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.F then
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

	RunService.Heartbeat:Connect(function(dt: number)
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
