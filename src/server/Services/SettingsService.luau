--!strict
-- Keeps each player's settings (Config.SettingsConfig) and saves them between visits.
--
-- Roblox has no local storage on the player's device, so settings are saved on the
-- server in a DataStore. The current values travel to the client as player attributes
-- ("Setting_MusicVolume" = 0.8 ...).
--
-- Safety rules for the DataStore:
--   * a failed load never leads to a save: we would overwrite the player's real
--     settings with defaults. The player keeps defaults for the session instead.
--   * reads and writes are retried a few times with a pause, then given up quietly.
--   * changes are saved at most once per SaveInterval, when the player leaves, and when
--     the server shuts down - not on every slider movement.
--   * DataStores do not work in Studio unless "Enable Studio Access to API Services" is
--     on (Game Settings > Security). Without it settings simply last for the session.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local SettingsConfig = require(Shared.Config.SettingsConfig)
local Log = require(Shared.Util.Log)
local Net = require(script.Parent.Parent.Net)

local log = Log.new("Settings")

local RETRIES = 3

type Record = {
	-- Loaded from the store (or confirmed new); only then may we save.
	Loaded: boolean,
	Dirty: boolean,
}

local SettingsService = {}

local records: { [Player]: Record } = {}
local store: DataStore? = nil

local function key(player: Player): string
	return "u" .. tostring(player.UserId)
end

local function withRetries<T>(action: () -> T): (boolean, T?)
	for attempt = 1, RETRIES do
		local ok, result = pcall(action)
		if ok then
			return true, result
		end
		if attempt < RETRIES then
			task.wait(attempt * 2)
		end
	end
	return false, nil
end

local function apply(player: Player, values: { [string]: any }?)
	for _, settingKey in SettingsConfig.Keys do
		local value = if values then values[settingKey] else nil
		if type(value) ~= "number" or value ~= value or value < 0 or value > 1 then
			value = SettingsConfig.Defaults[settingKey]
		end
		player:SetAttribute(SettingsConfig.AttributePrefix .. settingKey, value)
	end
end

local function snapshot(player: Player): { [string]: number }
	local values = {}
	for _, settingKey in SettingsConfig.Keys do
		local value = player:GetAttribute(SettingsConfig.AttributePrefix .. settingKey)
		if type(value) == "number" then
			values[settingKey] = value
		end
	end
	return values
end

local function save(player: Player)
	local record = records[player]
	local current = store
	if not record or not record.Loaded or not record.Dirty or not current then
		return
	end
	local values = snapshot(player)
	record.Dirty = false
	local ok = withRetries(function()
		return (current :: DataStore):SetAsync(key(player), values, { player.UserId })
	end)
	if not ok then
		record.Dirty = true
		log:Info("Could not save settings for %s; will try again later", player.Name)
	end
end

local function load(player: Player)
	local record: Record = { Loaded = false, Dirty = false }
	records[player] = record
	apply(player, nil)
	local current = store
	if not current then
		return
	end
	local ok, values = withRetries(function()
		return (current :: DataStore):GetAsync(key(player))
	end)
	if not player.Parent then
		return
	end
	if ok then
		record.Loaded = true
		if type(values) == "table" then
			apply(player, values)
		end
	else
		log:Info("Could not load settings for %s; using defaults, not saving this session", player.Name)
	end
end

function SettingsService.Init()
	Net.On("SetSetting", function(player: Player, settingKey: string, value: number)
		local record = records[player]
		if not record then
			return
		end
		player:SetAttribute(SettingsConfig.AttributePrefix .. settingKey, value)
		record.Dirty = true
	end)
end

function SettingsService.Start()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(SettingsConfig.StoreName)
	end)
	if ok then
		store = result
	else
		log:Info("DataStore unavailable (%s): settings will last for this session only", tostring(result))
	end

	Players.PlayerAdded:Connect(load)
	for _, player in Players:GetPlayers() do
		if not records[player] then
			task.spawn(load, player)
		end
	end
	Players.PlayerRemoving:Connect(function(player: Player)
		save(player)
		records[player] = nil
	end)
	pcall(function()
		game:BindToClose(function()
			for _, player in Players:GetPlayers() do
				save(player)
			end
		end)
	end)

	while true do
		task.wait(SettingsConfig.SaveInterval)
		for player in records do
			task.spawn(save, player)
		end
	end
end

return SettingsService
