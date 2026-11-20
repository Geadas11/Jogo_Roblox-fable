--!strict
-- Plays the night's strange events on this client (the server's EventManager decides
-- them and anything physical has already happened in the world):
--
--   Sound          a sound at a point (knocking, footsteps, a cart rolling...)
--   Flicker        the lights around a point stutter
--   Blackout       the lights around a point go out for a few seconds
--   Announcement   the intercom speaks: a chime of feedback, then a line of text that
--                  types itself out and glitches
--   Silhouette     a tall dark figure at the end of an aisle. It does not like being
--                  looked at: look straight at it, or walk towards it, and it is gone.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)
local HudController = require(script.Parent.HudController)
local LightingController = require(script.Parent.LightingController)

local EventController = {}

local announcement: Frame
local announcementText: TextLabel
local announcementSerial = 0

-- Announcements ------------------------------------------------------------------------------

local GLITCH = "#%&@$?!/\\|"

local function glitched(text: string, amount: number): string
	local characters = {}
	for index = 1, #text do
		local character = string.sub(text, index, index)
		if character ~= " " and math.random() < amount then
			local pick = math.random(1, #GLITCH)
			character = string.sub(GLITCH, pick, pick)
		end
		characters[index] = character
	end
	return table.concat(characters)
end

local function buildAnnouncement(screen: ScreenGui)
	announcementText = Theme.label({
		Name = "Text",
		Position = UDim2.new(0, 14, 0, 26),
		Size = UDim2.new(1, -28, 1, -34),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		FontFace = Theme.Fonts.Clock,
		TextSize = 17,
		Text = "",
	})
	local header = Theme.label({
		Name = "Header",
		Position = UDim2.new(0, 14, 0, 6),
		Size = UDim2.new(1, -28, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Fonts.Title,
		TextSize = 12,
		TextColor3 = Theme.Colors.Accent,
		Text = "INTERCOM",
	})
	announcement = Theme.panel({
		Name = "Announcement",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.new(0, 520, 0, 78),
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = screen,
	}, { header, announcementText })
end

function EventController.Announce(text: string)
	announcementSerial += 1
	local serial = announcementSerial
	AudioController.Play("Intercom")
	announcement.Visible = true
	task.spawn(function()
		-- Feedback first, then the voice "types" in, a little broken.
		task.wait(0.6)
		for count = 1, #text do
			if serial ~= announcementSerial then
				return
			end
			announcementText.Text = glitched(string.sub(text, 1, count), 0.08)
			task.wait(0.035)
		end
		for _ = 1, 12 do
			if serial ~= announcementSerial then
				return
			end
			announcementText.Text = glitched(text, 0.04)
			task.wait(0.25)
		end
		announcementText.Text = text
		task.wait(3)
		if serial == announcementSerial then
			announcement.Visible = false
		end
	end)
end

-- The silhouette -------------------------------------------------------------------------------

local function buildFigure(position: Vector3, lookAt: Vector3): Model
	local model = Instance.new("Model")
	model.Name = "Silhouette"
	local base = CFrame.lookAt(position, Vector3.new(lookAt.X, position.Y, lookAt.Z))
	local function piece(size: Vector3, offset: CFrame)
		local part = Instance.new("Part")
		part.Size = size
		part.Color = Color3.fromRGB(6, 6, 7)
		part.Material = Enum.Material.SmoothPlastic
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.CastShadow = false
		part.CFrame = base * offset
		part.Parent = model
	end
	-- Too tall, too thin, arms too long. Feet on the floor (position is floor level).
	piece(Vector3.new(0.5, 3.9, 0.5), CFrame.new(-0.35, 1.95, 0))
	piece(Vector3.new(0.5, 3.9, 0.5), CFrame.new(0.35, 1.95, 0))
	piece(Vector3.new(1.6, 3.1, 0.8), CFrame.new(0, 5.4, 0))
	piece(Vector3.new(0.38, 3.8, 0.38), CFrame.new(-1.0, 5.0, 0) * CFrame.Angles(0, 0, 0.05))
	piece(Vector3.new(0.38, 3.8, 0.38), CFrame.new(1.0, 5.0, 0) * CFrame.Angles(0, 0, -0.05))
	piece(Vector3.new(0.9, 1.25, 0.9), CFrame.new(0, 7.75, 0) * CFrame.Angles(0, 0, 0.25))
	return model
end

function EventController.ShowSilhouette(x: number, z: number, lookX: number, lookZ: number, seconds: number)
	local figure = buildFigure(Vector3.new(x, 0.2, z), Vector3.new(lookX, 0, lookZ))
	figure.Parent = Workspace
	local shownAt = os.clock()
	local connection: RBXScriptConnection
	local function vanish()
		if connection then
			connection:Disconnect()
		end
		figure:Destroy()
	end
	connection = RunService.RenderStepped:Connect(function()
		local camera = Workspace.CurrentCamera
		if not camera or os.clock() - shownAt > seconds then
			vanish()
			return
		end
		local offset = Vector3.new(x, camera.CFrame.Position.Y, z) - camera.CFrame.Position
		local distance = offset.Magnitude
		local direct = distance > 0.01 and offset.Unit:Dot(camera.CFrame.LookVector) > 0.985
		-- Looked at squarely (after it had a moment to be noticed), or approached: gone.
		if distance < 18 or (direct and os.clock() - shownAt > 1.2) then
			vanish()
		end
	end)
end

-- Dispatch -------------------------------------------------------------------------------------

local function onEvent(kind: any, data: any)
	if type(data) ~= "table" then
		return
	end
	if kind == "Sound" then
		AudioController.PlayAt(
			tostring(data.Name),
			Vector3.new(tonumber(data.X) or 0, tonumber(data.Y) or 0, tonumber(data.Z) or 0)
		)
	elseif kind == "Flicker" then
		LightingController.FlickerNear(
			tonumber(data.X) or 0,
			tonumber(data.Z) or 0,
			tonumber(data.Radius) or 30
		)
	elseif kind == "Blackout" then
		LightingController.BlackoutNear(
			tonumber(data.X) or 0,
			tonumber(data.Z) or 0,
			tonumber(data.Radius) or 40,
			tonumber(data.Seconds) or 3
		)
	elseif kind == "Announcement" then
		EventController.Announce(tostring(data.Text))
	elseif kind == "Silhouette" then
		-- Everyone gets the figure; only the one it appeared for hears it arrive.
		if data.For == Players.LocalPlayer.UserId then
			AudioController.PlayAt(
				"Presence",
				Vector3.new(tonumber(data.X) or 0, 3, tonumber(data.Z) or 0),
				0.6
			)
		end
		EventController.ShowSilhouette(
			tonumber(data.X) or 0,
			tonumber(data.Z) or 0,
			tonumber(data.LookX) or 0,
			tonumber(data.LookZ) or 0,
			tonumber(data.Seconds) or 4
		)
	end
end

function EventController.Init()
	buildAnnouncement(HudController.GetScreen())
	Net.On("HorrorEvent", onEvent)
end

return EventController
