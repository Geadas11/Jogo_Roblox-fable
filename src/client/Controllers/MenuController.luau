--!strict
-- What a player sees before playing, and the settings screen.
--
--   1. Warning       content warning (horror, flashing lights, sudden loud sounds).
--   2. Main menu     the store at night behind the title, the camera drifting slowly
--                    through it. SINGLE PLAYER / MULTIPLAYER / HOW TO PLAY / SETTINGS.
--   3. Settings      audio volumes, camera sensitivity, camera shake, reduced flashing.
--                    Also reachable during the game from the gear button (top right).
--
-- Single player asks the server for a private server of your own (MatchService); a
-- player who arrives in one (teleport data Mode = "Solo") goes straight into the game.
-- While the menu is up the HUD is hidden and the camera belongs to the menu.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.SettingsConfig)
local Signal = require(Shared.Util.Signal)
local Net = require(script.Parent.Parent.Net)
local Settings = require(script.Parent.Parent.Settings)
local Theme = require(script.Parent.Parent.UI.Theme)
local AudioConfig = require(Shared.Config.AudioConfig)
local AudioController = require(script.Parent.AudioController)
local HudController = require(script.Parent.HudController)
local WakeUpController = require(script.Parent.WakeUpController)

-- The menu's music: fades in under the warning, out when the night starts.
local menuMusic: Sound? = nil

local function musicTo(level: number, seconds: number)
	local music = menuMusic
	if not music then
		return
	end
	if level > 0 and not music.IsPlaying then
		music:Play()
	end
	local tween = TweenService:Create(music, TweenInfo.new(seconds), {
		Volume = AudioConfig.Sounds.MenuMusic.Volume * level,
	})
	tween:Play()
	if level <= 0 then
		tween.Completed:Once(function()
			music:Stop()
		end)
	end
end

local MenuController = {}

-- Fired once the player has chosen how to play and the menu is gone.
MenuController.Closed = Signal.new() :: Signal.Signal<()>

local gui: ScreenGui
local warningPage: Frame
local menuPage: Frame
local helpPage: Frame
local settingsPage: Frame
local fade: Frame
-- The SETTINGS button in the corner during play.
local gearButton: TextButton
local inMenu = false
local cameraThread: thread? = nil
-- The background camera move currently playing.
local menuTween: Tween? = nil

-- Slow camera moves through the store for the menu background: from, to, look at.
local SHOTS = {
	{ Vector3.new(20, 9, 72), Vector3.new(20, 7.5, 56), Vector3.new(20, 4, 0) },
	{ Vector3.new(-23, 5.6, 44), Vector3.new(-23, 5.6, 12), Vector3.new(-23, 4, -30) },
	{ Vector3.new(60, 6.5, -22), Vector3.new(30, 6.5, -22), Vector3.new(-20, 4, -22) },
	{ Vector3.new(-82, 8, -42), Vector3.new(-50, 8, -46), Vector3.new(-10, 3, -62) },
}
local SHOT_SECONDS = 14

-- Building blocks -------------------------------------------------------------------------------

local function page(name: string): Frame
	return Theme.create("Frame", {
		Name = name,
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundTransparency = 1,
		Visible = false,
		-- Above the fade, which only darkens the 3D view between camera shots.
		ZIndex = 2,
		Parent = gui,
	}) :: Frame
end

local function menuButton(text: string, order: number, parent: Instance, onClick: () -> ()): TextButton
	local button = Theme.create("TextButton", {
		Name = string.gsub(text, "%s", ""),
		Size = UDim2.new(1, 0, 0, 46),
		BackgroundColor3 = Theme.Colors.Text,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		FontFace = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.TextDim,
		TextSize = 22,
		TextXAlignment = Enum.TextXAlignment.Left,
		Text = text,
		LayoutOrder = order,
		-- Frees the mouse from the first-person lock while the menu is up.
		Modal = true,
		Parent = parent,
	}, {
		Theme.create("UIPadding", { PaddingLeft = UDim.new(0, 14) }),
	}) :: TextButton
	-- Hover: the line lights up and slides a little, like a selected menu entry.
	local function highlight(on: boolean)
		TweenService:Create(button, TweenInfo.new(0.15), {
			TextColor3 = if on then Theme.Colors.Text else Theme.Colors.TextDim,
			BackgroundTransparency = if on then 0.9 else 1,
		}):Play()
	end
	button.MouseEnter:Connect(function()
		highlight(true)
	end)
	button.MouseLeave:Connect(function()
		highlight(false)
	end)
	button.Activated:Connect(onClick)
	return button
end

local function smallButton(text: string, properties: { [string]: any }, onClick: () -> ()): TextButton
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Text,
		TextSize = 16,
		Text = text,
		-- Frees the mouse from the first-person lock while this button is on screen.
		Modal = true,
	}
	for key, value in properties do
		defaults[key] = value
	end
	local button = Theme.create("TextButton", defaults, {
		Theme.create("UICorner", { CornerRadius = UDim.new(0, 6) }),
	}) :: TextButton
	button.Activated:Connect(onClick)
	return button
end

local function show(target: Frame?)
	for _, frame in { warningPage, menuPage, helpPage, settingsPage } do
		frame.Visible = frame == target
	end
end

local fadeTween: Tween? = nil

local function fadeTo(transparency: number, seconds: number)
	local tween = TweenService:Create(fade, TweenInfo.new(seconds), { BackgroundTransparency = transparency })
	fadeTween = tween
	tween:Play()
	task.wait(seconds)
end

-- Background camera -----------------------------------------------------------------------------

local function startCamera()
	local camera = Workspace.CurrentCamera
	if not camera or cameraThread then
		return
	end
	-- Other controllers hand the camera back to the player when their character spawns;
	-- while the menu is up it stays ours.
	local hold: RBXScriptConnection
	hold = RunService.RenderStepped:Connect(function()
		if not inMenu then
			hold:Disconnect()
		elseif camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
	end)
	cameraThread = task.spawn(function()
		local index = 1
		while inMenu do
			local shot = SHOTS[index]
			camera.CameraType = Enum.CameraType.Scriptable
			camera.CFrame = CFrame.lookAt(shot[1], shot[3])
			local tween = TweenService:Create(
				camera,
				TweenInfo.new(SHOT_SECONDS, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CFrame = CFrame.lookAt(shot[2], shot[3]) }
			)
			menuTween = tween
			tween:Play()
			fadeTo(1, 1.2)
			task.wait(SHOT_SECONDS - 2.4)
			if not inMenu then
				break
			end
			fadeTo(0, 1.2)
			index = index % #SHOTS + 1
		end
		cameraThread = nil
	end)
end

-- Settings ----------------------------------------------------------------------------------------

local function slider(setting: SettingsConfig.Setting, parent: Instance, order: number)
	local row = Theme.create("Frame", {
		Name = setting.Key,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}) :: Frame
	Theme.label({
		Name = "Label",
		Size = UDim2.new(0.42, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		Text = setting.Label,
		Parent = row,
	})
	local valueLabel = Theme.label({
		Name = "Value",
		AnchorPoint = Vector2.new(1, 0),
		-- Clear of the list's scroll bar.
		Position = UDim2.new(1, -14, 0, 0),
		Size = UDim2.new(0, 48, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Theme.Fonts.Clock,
		TextSize = 15,
		TextColor3 = Theme.Colors.TextDim,
		Text = "",
		Parent = row,
	})
	local fill = Theme.create("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = Theme.Colors.Text,
		BorderSizePixel = 0,
	}, { Theme.create("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame
	local knob = Theme.create("Frame", {
		Name = "Knob",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(0, 16, 0, 16),
		BackgroundColor3 = Theme.Colors.Text,
		BorderSizePixel = 0,
		ZIndex = 2,
	}, { Theme.create("UICorner", { CornerRadius = UDim.new(1, 0) }) }) :: Frame
	-- The visible bar is thin; the button around it is tall, so it is easy to grab with a
	-- mouse or a finger.
	local bar = Theme.create("Frame", {
		Name = "Bar",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
		Size = UDim2.new(1, 0, 0, 6),
		BackgroundColor3 = Theme.Colors.Background,
		BackgroundTransparency = 0.1,
		BorderSizePixel = 0,
	}, { Theme.create("UICorner", { CornerRadius = UDim.new(1, 0) }), fill }) :: Frame
	local track = Theme.create("TextButton", {
		Name = "Track",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.44, 0, 0.5, 0),
		Size = UDim2.new(0.56, -76, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		Parent = row,
	}, { bar, knob }) :: TextButton

	local function draw(value: number)
		fill.Size = UDim2.new(value, 0, 1, 0)
		knob.Position = UDim2.new(value, 0, 0.5, 0)
		valueLabel.Text = string.format("%d%%", math.round(value * 100))
	end
	local function setFromX(x: number)
		local width = track.AbsoluteSize.X
		if width <= 0 then
			return
		end
		local value = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		-- Steps of 5%, so it is easy to land on a value.
		value = math.round(value * 20) / 20
		Settings.Set(setting.Key, value)
		draw(value)
	end

	local dragging = false
	track.InputBegan:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input: InputObject)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)
	Settings.Changed:Connect(function(key: string, value: number)
		if key == setting.Key then
			draw(value)
		end
	end)
	draw(Settings.Get(setting.Key))
end

local function toggle(setting: SettingsConfig.Setting, parent: Instance, order: number)
	local row = Theme.create("Frame", {
		Name = setting.Key,
		Size = UDim2.new(1, 0, 0, 44),
		BackgroundTransparency = 1,
		LayoutOrder = order,
		Parent = parent,
	}) :: Frame
	Theme.label({
		Name = "Label",
		Size = UDim2.new(0.7, 0, 1, 0),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextSize = 16,
		Text = setting.Label,
		Parent = row,
	})
	local button: TextButton
	local function draw(value: number)
		local on = value >= 0.5
		button.Text = if on then "ON" else "OFF"
		button.BackgroundColor3 = if on then Theme.Colors.Text else Theme.Colors.Background
		button.TextColor3 = if on then Theme.Colors.Background else Theme.Colors.TextDim
	end
	button = smallButton("", {
		Name = "Toggle",
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
		Size = UDim2.new(0, 70, 0, 30),
		TextSize = 14,
		Parent = row,
	}, function()
		local value = if Settings.Get(setting.Key) >= 0.5 then 0 else 1
		Settings.Set(setting.Key, value)
		draw(value)
	end)
	Settings.Changed:Connect(function(key: string, value: number)
		if key == setting.Key then
			draw(value)
		end
	end)
	draw(Settings.Get(setting.Key))
end

local closeSettings: () -> () = function() end

local function buildSettings()
	settingsPage = page("Settings")
	settingsPage.ZIndex = 5
	local panel = Theme.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 520, 0.82, 0),
		BackgroundTransparency = 0.06,
		Parent = settingsPage,
	}, {
		Theme.create(
			"UISizeConstraint",
			{ MaxSize = Vector2.new(560, 640), MinSize = Vector2.new(300, 260) }
		),
	})
	Theme.label({
		Name = "Title",
		Position = UDim2.new(0, 24, 0, 16),
		Size = UDim2.new(1, -48, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Fonts.Title,
		TextSize = 26,
		Text = "SETTINGS",
		Parent = panel,
	})
	local list = Theme.create("ScrollingFrame", {
		Name = "List",
		Position = UDim2.new(0, 24, 0, 60),
		Size = UDim2.new(1, -48, 1, -126),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		Parent = panel,
	}, {
		Theme.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }),
	})
	local order = 0
	local section = ""
	for _, setting in SettingsConfig.List do
		if setting.Section ~= section then
			section = setting.Section
			order += 1
			Theme.label({
				Name = "Section",
				Size = UDim2.new(1, 0, 0, 32),
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Bottom,
				FontFace = Theme.Fonts.Title,
				TextSize = 13,
				TextColor3 = Theme.Colors.Accent,
				Text = section,
				LayoutOrder = order,
				Parent = list,
			})
		end
		order += 1
		if setting.Kind == "Slider" then
			slider(setting, list, order)
		else
			toggle(setting, list, order)
		end
	end
	smallButton("DONE", {
		Name = "Done",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0, 160, 0, 40),
		Parent = panel,
	}, function()
		closeSettings()
	end)
end

-- Pages -------------------------------------------------------------------------------------------

local function buildWarning(onContinue: () -> ())
	warningPage = page("Warning")
	Theme.create("Frame", {
		Name = "Back",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = warningPage,
	})
	local box = Theme.create("Frame", {
		Name = "Box",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.9, 0, 0, 330),
		BackgroundTransparency = 1,
		Parent = warningPage,
	}, {
		Theme.create("UISizeConstraint", { MaxSize = Vector2.new(620, 400) }),
		Theme.create("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			HorizontalAlignment = Enum.HorizontalAlignment.Center,
			Padding = UDim.new(0, 14),
		}),
	})
	Theme.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 40),
		FontFace = Theme.Fonts.Title,
		TextSize = 30,
		TextColor3 = Theme.Colors.Accent,
		Text = "WARNING",
		LayoutOrder = 1,
		Parent = box,
	})
	Theme.label({
		Name = "Body",
		Size = UDim2.new(1, 0, 0, 150),
		TextSize = 18,
		TextColor3 = Theme.Colors.Text,
		Text = "This game contains horror themes, dark environments, sudden loud sounds and "
			.. "flashing lights that may not be suitable for players with photosensitive "
			.. "epilepsy.\n\nFlashing can be reduced in Settings.\nHeadphones are recommended.",
		LayoutOrder = 2,
		Parent = box,
	})
	smallButton("I UNDERSTAND", {
		Name = "Continue",
		Size = UDim2.new(0, 220, 0, 46),
		LayoutOrder = 3,
		Parent = box,
	}, onContinue)
end

local function buildMenu(onSolo: () -> (), onMulti: () -> (), onHelp: () -> (), onSettings: () -> ())
	menuPage = page("Menu")
	-- Darkens the left side so the title reads over the store.
	Theme.create("Frame", {
		Name = "Shade",
		Size = UDim2.new(0.6, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BorderSizePixel = 0,
		Parent = menuPage,
	}, {
		Theme.create("UIGradient", {
			Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.15),
				NumberSequenceKeypoint.new(1, 1),
			}),
		}),
	})
	local column = Theme.create("Frame", {
		Name = "Column",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 70, 0.5, 0),
		Size = UDim2.new(0, 360, 0, 460),
		BackgroundTransparency = 1,
		Parent = menuPage,
	}, {
		Theme.create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }),
		Theme.create("UISizeConstraint", { MaxSize = Vector2.new(360, 460) }),
	})
	Theme.label({
		Name = "Title",
		Size = UDim2.new(1, 0, 0, 58),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Fonts.Title,
		TextSize = 52,
		TextWrapped = false,
		Text = "NIGHT SHIFT",
		LayoutOrder = 1,
		Parent = column,
	})
	Theme.label({
		Name = "Subtitle",
		Size = UDim2.new(1, 0, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Fonts.Clock,
		TextSize = 22,
		TextColor3 = Theme.Colors.Accent,
		Text = "S U P E R M A R K E T",
		LayoutOrder = 2,
		Parent = column,
	})
	Theme.create("Frame", {
		Name = "Gap",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = column,
	})
	menuButton("SINGLE PLAYER", 4, column, onSolo)
	menuButton("MULTIPLAYER", 5, column, onMulti)
	menuButton("HOW TO PLAY", 6, column, onHelp)
	menuButton("SETTINGS", 7, column, onSettings)
	Theme.label({
		Name = "Note",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -24, 1, -18),
		Size = UDim2.new(0, 420, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Right,
		TextSize = 12,
		TextColor3 = Theme.Colors.TextDim,
		Text = "Multiplayer: up to 6 employees per store",
		Parent = menuPage,
	})
end

local function buildHelp(onBack: () -> ())
	helpPage = page("Help")
	local panel = Theme.panel({
		Name = "Panel",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0.9, 0, 0, 440),
		BackgroundTransparency = 0.06,
		Parent = helpPage,
	}, {
		Theme.create("UISizeConstraint", { MaxSize = Vector2.new(620, 460) }),
	})
	Theme.label({
		Name = "Title",
		Position = UDim2.new(0, 24, 0, 16),
		Size = UDim2.new(1, -48, 0, 34),
		TextXAlignment = Enum.TextXAlignment.Left,
		FontFace = Theme.Fonts.Title,
		TextSize = 26,
		Text = "HOW TO PLAY",
		Parent = panel,
	})
	Theme.label({
		Name = "Body",
		Position = UDim2.new(0, 24, 0, 60),
		Size = UDim2.new(1, -48, 1, -130),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextSize = 16,
		LineHeight = 1.25,
		Text = "You work the night shift, from 12 AM to 6 AM. Clock in at the time clock in "
			.. "the employee room to begin.\n\n"
			.. "Do the jobs on your list: restock, mop, take out the trash, check the "
			.. "coolers. Keep the power on.\n\n"
			.. "Something else is in the store after 3 AM. Walk - running is loud. Hide in "
			.. "lockers, but not for too long.\n\n"
			.. "E  interact      G  drop      F  flashlight      SHIFT  run      SPACE  leave a hiding spot",
		Parent = panel,
	})
	smallButton("BACK", {
		Name = "Back",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.new(0, 160, 0, 40),
		Parent = panel,
	}, onBack)
end

-- Flow ---------------------------------------------------------------------------------------------

local function closeMenu()
	if not inMenu then
		return
	end
	inMenu = false
	if menuTween then
		menuTween:Cancel()
		menuTween = nil
	end
	if cameraThread then
		pcall(task.cancel, cameraThread)
		cameraThread = nil
	end
	if fadeTween then
		fadeTween:Cancel()
		fadeTween = nil
	end
	musicTo(0, 2.5)
	task.spawn(function()
		-- Straight to black, then wake up at the table (WakeUpController draws its own
		-- eyelids over the view).
		fade.BackgroundTransparency = 0
		show(nil)
		task.wait(0.15)
		fade.BackgroundTransparency = 1
		WakeUpController.Play()
		HudController.GetScreen().Enabled = true
		gearButton.Visible = true
		MenuController.Closed:Fire()
	end)
end

local function arrivedSolo(): boolean
	local ok, data = pcall(function()
		return TeleportService:GetLocalPlayerTeleportData()
	end)
	return ok and type(data) == "table" and data.Mode == "Solo"
end

function MenuController.IsOpen(): boolean
	return inMenu
end

-- The same as pressing SINGLE PLAYER or MULTIPLAYER (from any page). For tests and
-- debugging.
function MenuController.Choose(mode: "Solo" | "Multiplayer")
	if not inMenu then
		return
	end
	if mode == "Solo" then
		Net.FireServer("RequestSolo")
	end
	closeMenu()
end

function MenuController.Init()
	gui = Theme.create("ScreenGui", {
		Name = "Menu",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		DisplayOrder = 50,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}) :: ScreenGui

	buildWarning(function()
		show(menuPage)
	end)
	buildMenu(
		function()
			Net.FireServer("RequestSolo")
			closeMenu()
		end,
		closeMenu,
		function()
			show(helpPage)
		end,
		function()
			show(settingsPage)
		end
	)
	buildHelp(function()
		show(menuPage)
	end)
	buildSettings()

	fade = Theme.create("Frame", {
		Name = "Fade",
		Size = UDim2.new(1, 0, 1, 0),
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 1,
		Active = false,
		Parent = gui,
	}) :: Frame

	local function toggleSettings()
		if not inMenu then
			show(if settingsPage.Visible then nil else settingsPage)
		end
	end
	gearButton = smallButton(if UserInputService.TouchEnabled then "SETTINGS" else "SETTINGS  [P]", {
		Name = "Gear",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 70),
		Size = UDim2.new(0, 120, 0, 30),
		TextSize = 12,
		BackgroundTransparency = 0.35,
		Visible = false,
		-- Must not free the mouse during play: on a keyboard it is opened with P.
		Modal = false,
		Parent = gui,
	}, toggleSettings)
	UserInputService.InputBegan:Connect(function(input: InputObject)
		local typing = UserInputService:GetFocusedTextBox() ~= nil
		if not typing and input.KeyCode == Enum.KeyCode.P and gearButton.Visible then
			toggleSettings()
		end
	end)

	closeSettings = function()
		show(if inMenu then menuPage else nil)
	end

	-- Camera sensitivity: the slider's middle (0.5) is Roblox's normal speed.
	local function applySensitivity()
		UserInputService.MouseDeltaSensitivity = 0.2 + Settings.Get("Sensitivity") * 1.6
	end
	Settings.Changed:Connect(function(key: string)
		if key == "Sensitivity" then
			applySensitivity()
		end
	end)
	applySensitivity()

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
end

function MenuController.Start()
	-- While playing, Roblox's mouse cursor is hidden: the dot in the middle of the screen
	-- is all you aim with. It comes back whenever a menu needs clicking.
	RunService.RenderStepped:Connect(function()
		local needsCursor = inMenu or settingsPage.Visible or helpPage.Visible
		if UserInputService.MouseIconEnabled ~= needsCursor then
			UserInputService.MouseIconEnabled = needsCursor
		end
	end)
	if arrivedSolo() then
		-- Chose single player in another server: straight to waking up.
		HudController.GetScreen().Enabled = false
		task.spawn(function()
			WakeUpController.Play()
			HudController.GetScreen().Enabled = true
			gearButton.Visible = true
		end)
		return
	end
	inMenu = true
	HudController.GetScreen().Enabled = false
	fade.BackgroundTransparency = 0
	show(warningPage)
	startCamera()
	menuMusic = AudioController.Loop("MenuMusic")
	musicTo(1, 4)

	-- The title stutters now and then, like a sign with a bad contact.
	local title = menuPage:FindFirstChild("Column") and (menuPage :: any).Column:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		task.spawn(function()
			while inMenu do
				task.wait(2 + math.random() * 5)
				for _ = 1, math.random(2, 5) do
					if not inMenu then
						break
					end
					title.TextTransparency = 0.55 + math.random() * 0.4
					task.wait(0.03 + math.random() * 0.07)
					title.TextTransparency = 0
					task.wait(0.04 + math.random() * 0.12)
				end
			end
		end)
	end
end

return MenuController
