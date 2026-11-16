--!strict
-- Baseline look of the world at the start of a shift (midnight, everything working).
-- The server applies this once at boot. Per-hour and per-zone changes are layered on
-- top of it later by the client LightingController.
--
-- These are starting values chosen on paper. They have NOT been tuned against the real
-- map yet (the map does not exist until Phase 3) and are expected to change.
--
-- Lighting technology: Roblox replaced `Lighting.Technology` with two properties.
-- The old "Future" setting corresponds to LightingStyle = Realistic with
-- PrioritizeLightingQuality = true, which is what we ask for here.

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

export type ChildSpec = {
	ClassName: string,
	Name: string,
	Properties: { [string]: any },
}

export type Profile = {
	Lighting: { [string]: any },
	Children: { ChildSpec },
}

local Base: Profile = {
	Lighting = {
		LightingStyle = Enum.LightingStyle.Realistic,
		PrioritizeLightingQuality = true,

		ClockTime = 0, -- midnight; the moon is the only outdoor light
		Brightness = 1,
		GlobalShadows = true,
		ShadowSoftness = 0.25,

		-- Indoor floor level. Low enough that unlit corners read as dark, high enough
		-- that a phone screen in daylight still shows shapes.
		Ambient = Color3.fromRGB(10, 11, 14),
		-- Cool blue night for the parking lot.
		OutdoorAmbient = Color3.fromRGB(28, 32, 44),

		EnvironmentDiffuseScale = 0.25,
		EnvironmentSpecularScale = 0.35,
		ExposureCompensation = 0,
	},

	Children = {
		{
			ClassName = "Atmosphere",
			Name = "Atmosphere",
			Properties = {
				Density = 0.38,
				Offset = 0.1,
				Color = Color3.fromRGB(42, 46, 58),
				Decay = Color3.fromRGB(18, 20, 28),
				Glare = 0,
				Haze = 2.2,
			},
		},
		{
			ClassName = "ColorCorrectionEffect",
			Name = "Grade",
			Properties = {
				Enabled = true,
				Brightness = -0.02,
				Contrast = 0.12,
				Saturation = -0.18,
				TintColor = Color3.fromRGB(238, 244, 255),
			},
		},
		{
			ClassName = "BloomEffect",
			Name = "Bloom",
			Properties = {
				Enabled = true,
				Intensity = 0.4,
				Size = 24,
				Threshold = 1.8,
			},
		},
	},
}

return deepFreeze({
	Base = Base,
})
