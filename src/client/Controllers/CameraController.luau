--!strict
-- Owns the local player's camera.
--
-- First person, always. Other controllers take the camera over for a moment (the catch
-- sequence, watching a teammate); whenever the player is back at work it is handed back
-- to the normal first-person camera here.
-- Also turns off the reset button: resetting would be a free escape from the monster.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local function restore()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- The core scripts may not be ready to accept this yet; try for a while.
local function disableReset()
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

function CameraController.Start()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.LockFirstPerson

	player:GetAttributeChangedSignal("Status"):Connect(function()
		local status = player:GetAttribute("Status")
		if status == "Working" or status == "Hiding" then
			restore()
		end
	end)
	player.CharacterAdded:Connect(function()
		if player:GetAttribute("Status") == "Working" then
			restore()
		end
	end)

	task.spawn(disableReset)
end

return CameraController
