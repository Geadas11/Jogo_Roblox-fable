--!strict
-- The strange things that happen during the night (EventManager).
--
-- Nothing supernatural happens at midnight. From 1 AM the store starts to misbehave,
-- a little more every hour. Silence matters as much as the events: a share of the
-- chances are deliberately skipped, and nothing extra happens while the monster is
-- chasing someone.

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

export type EventSpec = {
	-- First hour it can happen (1 = 1 AM).
	MinHour: number,
	-- Relative chance among the events allowed this hour.
	Weight: number,
	-- Seconds before the same event can happen again.
	Cooldown: number,
}

local Events: { [string]: EventSpec } = {
	-- A few lights near someone stutter.
	Flicker = { MinHour = 1, Weight = 3, Cooldown = 25 },
	-- A shopping cart rolls a few feet on its own, out of everyone's sight.
	CartRoll = { MinHour = 1, Weight = 2, Cooldown = 70 },
	-- Something falls off a shelf in a nearby aisle.
	ItemFall = { MinHour = 1, Weight = 2, Cooldown = 50 },
	-- Knocking on a door somewhere close.
	Knock = { MinHour = 1, Weight = 2, Cooldown = 60 },
	-- Footsteps behind someone, where nobody is.
	Footsteps = { MinHour = 2, Weight = 2, Cooldown = 55 },
	-- A door bangs shut - or one you closed is found open.
	DoorSlam = { MinHour = 2, Weight = 2, Cooldown = 70 },
	-- The intercom speaks.
	Announcement = { MinHour = 2, Weight = 1, Cooldown = 150 },
	-- A figure at the end of an aisle, gone when you look properly.
	Silhouette = { MinHour = 2, Weight = 1, Cooldown = 100 },
	-- The lights around someone go out for a few seconds.
	Blackout = { MinHour = 3, Weight = 1, Cooldown = 90 },
}

return deepFreeze({
	Events = Events,

	-- Average seconds between events, by hour (index 1 = 12 AM ... 6 = 5 AM). 0 = none.
	IntervalByHour = { 0, 70, 50, 40, 34, 26 },
	-- Each extra player shortens the interval by this share (more people, more to see).
	PerPlayerSpeedup = 0.12,
	-- Chance that a due event is skipped on purpose: silence.
	SilenceChance = 0.25,

	-- What the intercom says, by hour (index 3 = 2 AM ... 6 = 5 AM).
	Announcements = {
		[3] = {
			"Attention customers: the store is now closed. Please make your way to the exit.",
			"Clean-up on aisle... clean-up on aisle... clean-up on aisle.",
			"Would the employee in the storage room please stop moving.",
		},
		[4] = {
			"Attention employees: there is a customer in the store. Please assist them.",
			"We are aware of the problem with the lights. Please do not look at it.",
			"Thank you for shopping with us. Thank you for shopping with us.",
		},
		[5] = {
			"Attention employees. Please remain where you are.",
			"All staff: do not open the lockers. It is listening.",
			"The customer would like to speak to the manager.",
		},
		[6] = {
			"Attention employees. Please remain where you are. Your shift is not over.",
			"We know where you are standing.",
			"Thank you for working the night shift. You will be missed.",
		},
	},
})
