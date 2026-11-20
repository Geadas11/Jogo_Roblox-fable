--!strict
-- The night's presentation on screen.
--
--   Hour cards   every hour of the shift: letterbox bars close in, the time appears big
--                in the middle with one quiet line, then everything fades. From 3 AM a
--                low stinger goes with it.
--   Task cards   a new task or a finished one slides in from the right as a small card
--                (instead of a line of text at the bottom), one after another.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SessionState = require(Shared.SessionState)
local Net = require(script.Parent.Parent.Net)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioController = require(script.Parent.AudioController)
local HudController = require(script.Parent.HudController)

local CinematicController = {}

local HOUR_LINES = {
	[0] = "Your shift begins. The store is closed.",
	[1] = "Something moved in aisle four.",
	[2] = "The store does not feel empty.",
	[3] = "It is in the building.",
	[4] = "The power will not hold.",
	[5] = "Last hour. Stay alive.",
}

local topBar: Frame
local bottomBar: Frame
local hourText: TextLabel
local hourLine: TextLabel
local cards: Frame
local hourSerial = 0
-- Tasks already seen, and whether each was finished, to tell what changed.
local known: { [number]: boolean } = {}

local function tween(instance: Instance, seconds: number, goal: { [string]: any }, style: Enum.EasingStyle?)
	TweenService
		:Create(
			instance,
			TweenInfo.new(seconds, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			goal
		)
		:Play()
end

local function build(screen: ScreenGui)
	local function bar(name: string, top: boolean): Frame
		return Theme.create("Frame", {
			Name = name,
			AnchorPoint = Vector2.new(0, if top then 1 else 0),
			Position = UDim2.new(0, 0, if top then 0 else 1, 0),
			Size = UDim2.new(1, 0, 0.11, 0),
			BackgroundColor3 = Color3.new(0, 0, 0),
			BorderSizePixel = 0,
			ZIndex = 20,
			Parent = screen,
		}) :: Frame
	end
	topBar = bar("LetterboxTop", true)
	bottomBar = bar("LetterboxBottom", false)

	hourText = Theme.label({
		Name = "HourCard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0.8, 0, 0, 80),
		FontFace = Theme.Fonts.Clock,
		TextSize = 72,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		Text = "",
		ZIndex = 21,
		Parent = screen,
	})
	hourLine = Theme.label({
		Name = "HourLine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.42, 58),
		Size = UDim2.new(0.8, 0, 0, 26),
		TextSize = 18,
		TextColor3 = Theme.Colors.TextDim,
		TextTransparency = 1,
		Text = "",
		ZIndex = 21,
		Parent = screen,
	})

	cards = Theme.create("Frame", {
		Name = "TaskCards",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 112),
		Size = UDim2.new(0, 320, 0, 300),
		BackgroundTransparency = 1,
		Parent = screen,
	}, {
		Theme.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Right,
			Padding = UDim.new(0, 8),
		}),
	}) :: Frame
end

-- Hour cards --------------------------------------------------------------------------------------

function CinematicController.ShowHour(hour: number)
	hourSerial += 1
	local serial = hourSerial
	local clock = string.format("%d:00 AM", if hour == 0 then 12 else hour)
	hourText.Text = clock
	hourLine.Text = HOUR_LINES[hour] or ""
	if hour >= 3 then
		AudioController.Play("Stinger", 0.35)
	end
	task.spawn(function()
		tween(topBar, 0.9, { Position = UDim2.new(0, 0, 0.11, 0) })
		tween(bottomBar, 0.9, { Position = UDim2.new(0, 0, 0.89, 0) })
		task.wait(0.4)
		tween(hourText, 1.2, { TextTransparency = 0, TextStrokeTransparency = 0.6 }, Enum.EasingStyle.Sine)
		task.wait(0.5)
		tween(hourLine, 1.2, { TextTransparency = 0.1 }, Enum.EasingStyle.Sine)
		task.wait(2.6)
		if serial ~= hourSerial then
			return
		end
		tween(hourText, 1, { TextTransparency = 1, TextStrokeTransparency = 1 }, Enum.EasingStyle.Sine)
		tween(hourLine, 1, { TextTransparency = 1 }, Enum.EasingStyle.Sine)
		task.wait(0.6)
		tween(topBar, 1, { Position = UDim2.new(0, 0, 0, 0) })
		tween(bottomBar, 1, { Position = UDim2.new(0, 0, 1, 0) })
	end)
end

-- Task cards --------------------------------------------------------------------------------------

function CinematicController.TaskCard(kind: "New" | "Done", title: string, detail: string)
	local accent = if kind == "Done" then Theme.Colors.Good else Theme.Colors.Warning
	local heading = Theme.label({
		Name = "Heading",
		Position = UDim2.new(0, 16, 0, 7),
		Size = UDim2.new(1, -24, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Fonts.Title,
		TextSize = 11,
		TextColor3 = accent,
		Text = if kind == "Done" then "TASK COMPLETE" else "NEW TASK",
	})
	local name = Theme.label({
		Name = "Title",
		Position = UDim2.new(0, 16, 0, 22),
		Size = UDim2.new(1, -24, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Fonts.Title,
		TextSize = 17,
		Text = title,
	})
	local hint = Theme.label({
		Name = "Detail",
		Position = UDim2.new(0, 16, 0, 43),
		Size = UDim2.new(1, -24, 0, 14),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 12,
		TextColor3 = Theme.Colors.TextDim,
		TextTruncate = Enum.TextTruncate.AtEnd,
		TextWrapped = false,
		Text = detail,
	})
	local stripe = Theme.create("Frame", {
		Name = "Stripe",
		Size = UDim2.new(0, 4, 1, 0),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
	})
	-- A thin line that sweeps across the bottom while the card is up.
	local sweep = Theme.create("Frame", {
		Name = "Sweep",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, 0),
		Size = UDim2.new(0, 0, 0, 2),
		BackgroundColor3 = accent,
		BorderSizePixel = 0,
	})
	local inner = Theme.panel({
		Name = "Inner",
		Position = UDim2.new(1, 20, 0, 0),
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 0.12,
		ClipsDescendants = true,
	}, { stripe, heading, name, hint, sweep })
	local holder = Theme.create("Frame", {
		Name = "Card",
		Size = UDim2.new(1, 0, 0, if detail ~= "" then 64 else 50),
		BackgroundTransparency = 1,
		LayoutOrder = math.floor(os.clock() * 100),
		Parent = cards,
	}, { inner }) :: Frame

	task.spawn(function()
		tween(inner, 0.45, { Position = UDim2.new(0, 0, 0, 0) })
		tween(sweep, 3.6, { Size = UDim2.new(1, 0, 0, 2) }, Enum.EasingStyle.Linear)
		task.wait(3.8)
		tween(inner, 0.4, { Position = UDim2.new(1, 20, 0, 0) }, Enum.EasingStyle.Quad)
		task.wait(0.45)
		holder:Destroy()
	end)
end

local function onTasks(snapshot: any)
	if type(snapshot) ~= "table" then
		return
	end
	if #snapshot == 0 then
		known = {}
		return
	end
	for _, item in snapshot do
		if type(item) == "table" and type(item.Id) == "number" then
			local before = known[item.Id]
			local done = item.Completed == true
			if before == nil and not done then
				CinematicController.TaskCard("New", tostring(item.Title), tostring(item.Detail or ""))
			elseif before == false and done then
				CinematicController.TaskCard("Done", tostring(item.Title), "")
			end
			known[item.Id] = done
		end
	end
end

function CinematicController.Init()
	build(HudController.GetScreen())
	Net.On("TasksChanged", onTasks)
end

function CinematicController.Start()
	local lastHour = -1
	local function check()
		if SessionState.Get("Phase") ~= "Shift" then
			lastHour = -1
			return
		end
		local hour = SessionState.Get("Hour")
		if hour ~= lastHour and hour < 6 then
			lastHour = hour
			CinematicController.ShowHour(hour)
		end
	end
	SessionState.Observe("Hour", check)
	SessionState.Observe("Phase", check)
end

return CinematicController
