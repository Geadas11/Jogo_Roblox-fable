--!strict
-- The game's visual identity for 2D interface: one palette, one set of fonts, and small
-- helpers so every screen is built the same way. Interfaces are created from code
-- (no hand-made ScreenGuis) so they stay consistent and live in the repository.

local Theme = {}

-- A horror palette: almost no colour. Bone-white text, dried-blood red, a moss green
-- and an old amber that read as signals without looking like a cheerful game.
Theme.Colors = {
	Background = Color3.fromRGB(8, 8, 9),
	Panel = Color3.fromRGB(13, 12, 12),
	Text = Color3.fromRGB(214, 206, 192),
	TextDim = Color3.fromRGB(128, 122, 114),
	Accent = Color3.fromRGB(150, 32, 30),
	Good = Color3.fromRGB(132, 150, 120),
	Warning = Color3.fromRGB(186, 160, 110),
	Edge = Color3.fromRGB(70, 22, 20),
}

-- Typewriter type everywhere: an incident report, not a game menu.
Theme.Fonts = {
	Title = Font.fromEnum(Enum.Font.SpecialElite),
	Body = Font.fromEnum(Enum.Font.SpecialElite),
	Clock = Font.fromEnum(Enum.Font.SpecialElite),
}

-- Creates an instance, sets its properties and parents its children to it.
function Theme.create(className: string, properties: { [string]: any }, children: { Instance }?): Instance
	local instance = Instance.new(className)
	for name, value in properties do
		(instance :: any)[name] = value
	end
	for _, child in children or {} do
		child.Parent = instance
	end
	return instance
end

-- Text with the theme's defaults; pass any property to override.
function Theme.label(properties: { [string]: any }): TextLabel
	local defaults: { [string]: any } = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		FontFace = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		TextSize = 18,
		TextWrapped = true,
	}
	for name, value in properties do
		defaults[name] = value
	end
	return Theme.create("TextLabel", defaults) :: TextLabel
end

-- Dark translucent panel with rounded corners.
function Theme.panel(properties: { [string]: any }, children: { Instance }?): Frame
	local defaults: { [string]: any } = {
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.25,
		BorderSizePixel = 0,
	}
	for name, value in properties do
		defaults[name] = value
	end
	local frame = Theme.create("Frame", defaults, children) :: Frame
	-- Hard corners and a thin dark-red edge.
	Theme.create("UICorner", { CornerRadius = UDim.new(0, 2), Parent = frame })
	Theme.create("UIStroke", {
		Color = Theme.Colors.Edge,
		Thickness = 1,
		Transparency = 0.35,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = frame,
	})
	return frame
end

return Theme
