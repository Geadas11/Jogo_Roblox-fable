--!strict
-- The local player's settings, as the rest of the client sees them.
--
--   Settings.Get("MusicVolume")        current value (0..1)
--   Settings.Set("MusicVolume", 0.4)   changes it now and asks the server to save it
--   Settings.Changed:Connect(fn)       fn(key, value) on every change
--
-- The server owns the saved copy (SettingsService) and replicates it as attributes; a
-- change made here is applied at once, without waiting for the round trip.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared.Config.SettingsConfig)
local Signal = require(Shared.Util.Signal)
local Net = require(script.Parent.Net)

local Settings = {}

Settings.Changed = Signal.new() :: Signal.Signal<string, number>

local values: { [string]: number } = {}
local started = false

function Settings.Get(key: string): number
	local value = values[key]
	if value ~= nil then
		return value
	end
	return SettingsConfig.Defaults[key] or 0
end

function Settings.Set(key: string, value: number)
	value = math.clamp(value, 0, 1)
	if values[key] == value then
		return
	end
	values[key] = value
	Settings.Changed:Fire(key, value)
	Net.FireServer("SetSetting", key, value)
end

-- Follows the values the server sends (loaded from the save). Called once at boot.
function Settings.Start()
	if started then
		return
	end
	started = true
	local player = Players.LocalPlayer
	for _, key in SettingsConfig.Keys do
		local attribute = SettingsConfig.AttributePrefix .. key
		local function pull()
			local value = player:GetAttribute(attribute)
			if type(value) == "number" and values[key] ~= value then
				values[key] = value
				Settings.Changed:Fire(key, value)
			end
		end
		player:GetAttributeChangedSignal(attribute):Connect(pull)
		pull()
	end
end

return Settings
