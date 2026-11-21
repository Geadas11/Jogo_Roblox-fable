--!strict
-- Owns the local player's camera.
--
-- First person, always. Other controllers take the camera over for a moment (the catch
-- sequence, watching a teammate); whenever the player is back at work it is handed back
-- to the normal first-person camera here.
-- Also turns off the reset button (resetting would be a free escape from the monster)
-- and starts the chat window closed.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local CameraController = {}

local function restore()
	local camera = Workspace.CurrentCamera
	if camera then
		camera.CameraType = Enum.CameraType.Custom
	end
end

-- The core scripts may not be ready to accept these yet; try for a while.
local function setCore(name: string, value: any)
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCore(name, value)
		end)
		if ok then
			return
		end
		task.wait(0.5)
	end
end

local function disableReset()
	setCore("ResetButtonCallback", false)
end

-- The chat starts closed (still one click away on the chat button): an open chat
-- window sits over a dark, quiet scene.
local function closeChat()
	setCore("ChatActive", false)
end

function CameraController.Start()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.LockFirstPerson
	player.CameraMinZoomDistance = 0.5
	player.CameraMaxZoomDistance = 0.5

	-- Hold the first-person mouse lock ourselves, every frame, whenever the player is in
	-- control of the normal camera and no menu needs the cursor (MenuController shows the
	-- cursor exactly then). Without this, anything that frees the mouse for a moment (a
	-- menu button, a borrowed camera, the window losing focus) could leave it free, and
	-- the view would only turn while the right mouse button is held.
	RunService:BindToRenderStep("NSSFirstPersonLock", Enum.RenderPriority.Camera.Value + 1, function()
		local camera = Workspace.CurrentCamera
		if
			camera
			and camera.CameraType == Enum.CameraType.Custom
			and not UserInputService.MouseIconEnabled
			and UserInputService.MouseBehavior ~= Enum.MouseBehavior.LockCenter
		then
			UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
		end
	end)

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
	task.spawn(closeChat)
end

return CameraController
