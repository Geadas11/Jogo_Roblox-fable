--!strict
-- The player's settings: what they are, their defaults, and how they are shown in the
-- settings menu. Every value is a number from 0 to 1 (toggles are 0 = off, 1 = on), so
-- one validator covers them all on the server.
--
-- Settings are saved per player by the server (SettingsService, DataStore) and
-- replicated as player attributes named "Setting_<Key>".

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

export type Setting = {
	Key: string,
	Label: string,
	Kind: "Slider" | "Toggle",
	Default: number,
	Section: string,
}

local List: { Setting } = {
	{ Key = "MasterVolume", Label = "Master volume", Kind = "Slider", Default = 1, Section = "AUDIO" },
	{ Key = "MusicVolume", Label = "Music", Kind = "Slider", Default = 0.8, Section = "AUDIO" },
	{ Key = "AmbientVolume", Label = "Ambience", Kind = "Slider", Default = 1, Section = "AUDIO" },
	{ Key = "EffectsVolume", Label = "Effects", Kind = "Slider", Default = 1, Section = "AUDIO" },
	{
		Key = "Sensitivity",
		Label = "Camera sensitivity",
		Kind = "Slider",
		Default = 0.5,
		Section = "GAMEPLAY",
	},
	{ Key = "CameraShake", Label = "Camera shake", Kind = "Toggle", Default = 1, Section = "GAMEPLAY" },
	{
		Key = "ReducedFlashing",
		Label = "Reduce flashing lights",
		Kind = "Toggle",
		Default = 0,
		Section = "ACCESSIBILITY",
	},
}

local Keys: { string } = {}
local Defaults: { [string]: number } = {}
for _, setting in List do
	table.insert(Keys, setting.Key)
	Defaults[setting.Key] = setting.Default
end

return deepFreeze({
	List = List,
	Keys = Keys,
	Defaults = Defaults,
	AttributePrefix = "Setting_",
	-- DataStore holding everyone's settings. Bump the version to start over.
	StoreName = "PlayerSettings_v1",
	-- Seconds between saves of changed settings (and always when the player leaves).
	SaveInterval = 60,
})
