--!strict
-- Every employee carries a flashlight (F, or the LIGHT button). The light itself is a
-- SpotLight on the character's head, so every player sees everyone's beam. A lit
-- flashlight lets you see in the dark, and lets the monster see you.

local Net = require(script.Parent.Parent.Net)
local PlayerManager = require(script.Parent.PlayerManager)

local FlashlightService = {}

local function lightFor(player: Player): SpotLight?
	local character = player.Character
	if not character then
		return nil
	end
	local holder = character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart")
	if not holder or not holder:IsA("BasePart") then
		return nil
	end
	local existing = holder:FindFirstChild("Flashlight")
	if existing and existing:IsA("SpotLight") then
		return existing
	end
	local light = Instance.new("SpotLight")
	light.Name = "Flashlight"
	light.Face = Enum.NormalId.Front
	light.Angle = 55
	light.Range = 45
	light.Brightness = 2.2
	light.Color = Color3.fromRGB(255, 244, 222)
	light.Shadows = true
	light.Enabled = false
	light.Parent = holder
	return light
end

function FlashlightService.IsOn(player: Player): boolean
	return player:GetAttribute("FlashlightOn") == true
end

function FlashlightService.Set(player: Player, on: boolean)
	local status = player:GetAttribute("Status")
	-- No light while hiding or caught.
	if on and status ~= "Working" then
		on = false
	end
	if not PlayerManager.GetRoot(player) then
		on = false
	end
	local light = lightFor(player)
	if light then
		light.Enabled = on
	end
	player:SetAttribute("FlashlightOn", on)
end

function FlashlightService.Init()
	Net.On("Flashlight", function(player: Player, on: boolean)
		FlashlightService.Set(player, on)
	end)
end

function FlashlightService.Start()
	PlayerManager.PlayerReady:Connect(function(player: Player)
		player:SetAttribute("FlashlightOn", false)
		player.CharacterAdded:Connect(function()
			player:SetAttribute("FlashlightOn", false)
		end)
		player:GetAttributeChangedSignal("Status"):Connect(function()
			if player:GetAttribute("Status") ~= "Working" and FlashlightService.IsOn(player) then
				FlashlightService.Set(player, false)
			end
		end)
	end)
end

return FlashlightService
