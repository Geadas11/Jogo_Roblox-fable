--!strict
-- The in-game HUD: the shift clock, a one-line status, short notifications and the
-- end-of-shift summary. Deliberately sparse - the screen should stay clear.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared.Config.GameConfig)
local SessionState = require(Shared.SessionState)
local ShiftClock = require(Shared.ShiftClock)
local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Parent.UI.Theme)

local MAX_NOTIFICATIONS = 4
local NOTIFICATION_SECONDS = 5

local STATUS = {
	Lobby = "CLOCK IN AT THE EMPLOYEE ROOM TO START YOUR SHIFT",
	Shift = "NIGHT SHIFT",
	Results = "SHIFT OVER",
}

local HudController = {}

local clockLabel: TextLabel
local statusLabel: TextLabel
local notifications: Frame
local resultsPanel: Frame
local resultsTitle: TextLabel
local resultsBody: TextLabel

local function build(): ScreenGui
	clockLabel = Theme.label({
		Name = "Clock",
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = Theme.Fonts.Clock,
		TextSize = 34,
		Text = "",
		LayoutOrder = 1,
	})
	statusLabel = Theme.label({
		Name = "Status",
		Size = UDim2.new(1, 0, 0, 18),
		TextSize = 13,
		TextColor3 = Theme.Colors.TextDim,
		Text = "",
		LayoutOrder = 2,
	})
	local top = Theme.create("Frame", {
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 10),
		Size = UDim2.new(0, 420, 0, 64),
		BackgroundTransparency = 1,
	}, {
		Theme.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 2),
		}),
		clockLabel,
		statusLabel,
	})

	notifications = Theme.create("Frame", {
		Name = "Notifications",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.new(0, 460, 0, 160),
		BackgroundTransparency = 1,
	}, {
		Theme.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Bottom,
			Padding = UDim.new(0, 6),
		}),
	}) :: Frame

	resultsTitle = Theme.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 44),
		FontFace = Theme.Fonts.Title,
		TextSize = 30,
		Text = "",
		LayoutOrder = 1,
	})
	resultsBody = Theme.label({
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 120),
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		Text = "",
		LayoutOrder = 2,
	})
	resultsPanel = Theme.panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.45, 0),
		Size = UDim2.new(0, 440, 0, 210),
		Visible = false,
	}, {
		Theme.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			VerticalAlignment = Enum.VerticalAlignment.Center,
			Padding = UDim.new(0, 8),
		}),
		resultsTitle,
		resultsBody,
	})

	return Theme.create("ScreenGui", {
		Name = "HUD",
		ResetOnSpawn = false,
		DisplayOrder = 10,
	}, { top, notifications, resultsPanel }) :: ScreenGui
end

-- Redraws the clock and status from the replicated session state.
function HudController.Refresh()
	local phase = SessionState.Get("Phase")
	statusLabel.Text = STATUS[phase] or ""

	if phase == "Shift" then
		local elapsed = Workspace:GetServerTimeNow() - SessionState.Get("ShiftStartTime")
		clockLabel.Text = ShiftClock.format(elapsed, SessionState.Get("HourDuration"), GameConfig.Shift.Hours)
		clockLabel.TextColor3 = Theme.Colors.Text
	elseif phase == "Results" then
		clockLabel.Text = ShiftClock.format(math.huge, 1, GameConfig.Shift.Hours)
		clockLabel.TextColor3 = Theme.Colors.Good
	else
		clockLabel.Text = "OFF SHIFT"
		clockLabel.TextColor3 = Theme.Colors.TextDim
	end
end

-- Shows a short message at the bottom of the screen for a few seconds.
function HudController.Notify(text: string, kind: string?)
	local existing = notifications:GetChildren()
	local shown = 0
	for _, child in existing do
		if child:IsA("TextLabel") then
			shown += 1
		end
	end
	if shown >= MAX_NOTIFICATIONS then
		for _, child in existing do
			if child:IsA("TextLabel") then
				child:Destroy()
				break
			end
		end
	end

	local label = Theme.label({
		Name = "Notification",
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 0.3,
		BackgroundColor3 = Theme.Colors.Panel,
		TextColor3 = if kind == "Warning" then Theme.Colors.Warning else Theme.Colors.Text,
		TextSize = 16,
		Text = text,
		LayoutOrder = os.clock() * 1000,
	})
	Theme.create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = label })
	label.Parent = notifications
	task.delay(NOTIFICATION_SECONDS, function()
		label:Destroy()
	end)
end

local function showResults(results: any)
	if type(results) ~= "table" then
		return
	end
	local seconds = tonumber(results.DurationSeconds) or 0
	resultsTitle.Text = if results.Completed then "SHIFT COMPLETE" else "SHIFT ENDED"
	resultsTitle.TextColor3 = if results.Completed then Theme.Colors.Good else Theme.Colors.Accent
	resultsBody.Text = string.format(
		"Clocked out at %s\nHours worked: %d\nTime on shift: %d:%02d\n\nReturning to the employee room...",
		ShiftClock.format(math.huge, 1, GameConfig.Shift.Hours),
		tonumber(results.HoursWorked) or 0,
		seconds // 60,
		seconds % 60
	)
	resultsPanel.Visible = true
end

function HudController.Init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
	build().Parent = playerGui

	Net.On("Notify", HudController.Notify)
	Net.On("ShiftEnded", showResults)
end

function HudController.Start()
	SessionState.Observe("Phase", function(phase: string)
		if phase ~= "Results" then
			resultsPanel.Visible = false
		end
		HudController.Refresh()
	end)

	while true do
		HudController.Refresh()
		task.wait(0.25)
	end
end

return HudController
