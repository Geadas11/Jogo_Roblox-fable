--!strict
-- The pool of ordinary supermarket work. TaskManager hands out a few of these at the
-- start of every hour. Only data lives here; what each type does in the world is in
-- ServerScriptService.Server.Services.Tasks.<Type>.

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

export type TaskType = {
	-- Shown in the objectives list.
	Title: string,
	-- Money earned per unit of work (per shelf, per spill...).
	RewardPerUnit: number,
	-- Units of work when playing alone.
	Min: number,
	Max: number,
	-- Relative chance of being picked.
	Weight: number,
}

local Types: { [string]: TaskType } = {
	Restock = { Title = "Restock shelves", RewardPerUnit = 30, Min = 2, Max = 4, Weight = 3 },
	CleanSpills = { Title = "Clean up spills", RewardPerUnit = 20, Min = 2, Max = 3, Weight = 3 },
	InspectCoolers = { Title = "Check the coolers", RewardPerUnit = 15, Min = 3, Max = 5, Weight = 2 },
}

return deepFreeze({
	-- New tasks handed out at the start of each hour.
	TasksPerHour = 2,
	-- Extra units of work for every player beyond the first (rounded down).
	ExtraUnitsPerPlayer = 0.5,
	Types = Types,
})
