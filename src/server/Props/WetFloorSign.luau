--!strict
-- A yellow "Caution: wet floor" A-frame sign, put up by every spill (CleanSpills) and
-- taken away once it is mopped up. Two panels leaning against each other: together at
-- the top, apart at the feet, the warning printed on the outside of each.

local Workspace = game:GetService("Workspace")

local WetFloorSign = {}

local YELLOW = Color3.fromRGB(236, 196, 40)
local INK = Color3.fromRGB(30, 26, 20)

local PANEL = Vector3.new(1.2, 2.6, 0.06)
-- Each panel leans this far (radians) from upright.
local LEAN = 0.2

-- Stands a sign on the floor at `position` (the floor point), turned by `yaw`.
function WetFloorSign.Create(position: Vector3, yaw: number): Model
	local sign = Instance.new("Model")
	sign.Name = "WetFloorSign"
	local base = CFrame.new(position + Vector3.new(0, PANEL.Y / 2 * math.cos(LEAN), 0))
		* CFrame.Angles(0, yaw, 0)
	for _, side in { 1, -1 } do
		local panel = Instance.new("Part")
		panel.Name = "Panel"
		panel.Size = PANEL
		panel.Color = YELLOW
		panel.Material = Enum.Material.SmoothPlastic
		panel.Anchored = true
		panel.CanCollide = false
		panel.CanQuery = false
		panel.CanTouch = false
		-- Leaning in: the top of each panel comes to the middle, the feet spread apart.
		local half = PANEL.Y / 2 * math.sin(LEAN)
		panel.CFrame = base * CFrame.new(0, 0, side * half) * CFrame.Angles(-side * LEAN, 0, 0)
		panel.Parent = sign

		local gui = Instance.new("SurfaceGui")
		gui.Name = "Print"
		gui.Face = if side > 0 then Enum.NormalId.Back else Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 60
		gui.LightInfluence = 1
		gui.Parent = panel
		local text = Instance.new("TextLabel")
		text.BackgroundTransparency = 1
		text.Size = UDim2.new(0.86, 0, 0.62, 0)
		text.Position = UDim2.new(0.07, 0, 0.2, 0)
		text.Text = "⚠\nCAUTION\nWET\nFLOOR"
		text.TextScaled = true
		text.TextColor3 = INK
		text.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
		text.Parent = gui
	end
	sign.Parent = Workspace
	return sign
end

return WetFloorSign
