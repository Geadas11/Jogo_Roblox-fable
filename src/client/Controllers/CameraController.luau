--!strict
-- Owns the local player's camera.
--
-- Phase 2: locks the camera to first person, the default gameplay view.
-- Later phases extend this module with camera shake, the hiding camera and the
-- hand-over to scripted cameras (intro cinematic, CCTV, death sequence).

local Players = game:GetService("Players")

local CameraController = {}

function CameraController.Start()
	local player = Players.LocalPlayer
	player.CameraMode = Enum.CameraMode.LockFirstPerson
end

return CameraController
