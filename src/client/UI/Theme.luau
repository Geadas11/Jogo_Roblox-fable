--!strict
-- The game's visual identity for 2D interface: one palette, one set of fonts, and small
-- helpers so every screen is built the same way. Interfaces are created from code
-- (no hand-made ScreenGuis) so they stay consistent and live in the repository.

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(10, 11, 14),
	Panel = Color3.fromRGB(18, 20, 24),
	Text = Color3.fromRGB(232, 232, 226),
	TextDim = Color3.fromRGB(150, 152, 150),
	Accent = Color3.fromRGB(196, 54, 48),
	Good = Color3.fromRGB(120, 200, 140),
	Warning = Color3.fromRGB(226, 176, 72),
}

Theme.Fonts = {
	Title = Font.fromEnum(Enum.Font.GothamBold),
	Body = Font.fromEnum(Enum.Font.GothamMedium),
	Clock = Font.fromEnum(Enum.Font.RobotoMono),
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
	Theme.create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = frame })
	return frame
end

return Theme
