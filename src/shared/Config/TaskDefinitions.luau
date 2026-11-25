--!strict
-- The pool of ordinary supermarket work. TaskManager hands out a few of these at the
-- start of every hour. Only data lives here; what each type does in the world is in
-- ServerScriptService.Server.Services.Tasks.<Type>.

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

export type TaskType = {
	-- Module under Server.Services.Tasks that sets this work up in the world. Several
	-- types can share one module and differ only in Params.
	Module: string,
	-- Shown in the objectives list.
	Title: string,
	-- Money earned per unit of work (per shelf, per spill...).
	RewardPerUnit: number,
	-- Units of work when playing alone.
	Min: number,
	Max: number,
	-- Relative chance of being picked. 0: never drawn at random; another system issues
	-- it when needed (e.g. restoring the power).
	Weight: number,
	-- Settings read by the module.
	Params: { [string]: any }?,
}

local Types: { [string]: TaskType } = {
	RestorePower = {
		Module = "RestorePower",
		Title = "Restore the power",
		RewardPerUnit = 60,
		Min = 1,
		Max = 1,
		Weight = 0,
	},
	Restock = {
		Module = "Restock",
		Title = "Restock shelves",
		RewardPerUnit = 30,
		Min = 2,
		Max = 4,
		Weight = 3,
	},
	CleanSpills = {
		Module = "CleanSpills",
		Title = "Clean up spills",
		RewardPerUnit = 20,
		Min = 2,
		Max = 3,
		Weight = 3,
	},
	CollectTrash = {
		Module = "CollectTrash",
		Title = "Take out the trash",
		RewardPerUnit = 25,
		Min = 2,
		Max = 4,
		Weight = 2,
	},
	InspectCoolers = {
		Module = "Inspect",
		Title = "Check the coolers",
		RewardPerUnit = 15,
		Min = 3,
		Max = 5,
		Weight = 2,
		Params = {
			Tag = "FridgeUnit",
			Action = "Inspect",
			Object = "Cooler",
			Hold = 1.5,
			Detail = "Look for the amber warning lights.",
		},
	},
	RefillToiletPaper = {
		Module = "Inspect",
		Title = "Refill the toilet paper",
		RewardPerUnit = 15,
		Min = 2,
		Max = 4,
		Weight = 2,
		Params = {
			Tag = "PaperHolder",
			Action = "Refill",
			Object = "Toilet paper",
			Hold = 2,
			Detail = "Some stalls in the restrooms are out of paper.",
		},
	},
	CloseRegisters = {
		Module = "Inspect",
		Title = "Cash up the registers",
		RewardPerUnit = 20,
		Min = 2,
		Max = 4,
		Weight = 2,
		Params = {
			Tag = "CheckoutRegister",
			Action = "Cash up",
			Object = "Register",
			Hold = 3,
			Detail = "Count the tills at the checkout.",
		},
	},
}

return deepFreeze({
	-- New tasks handed out at the start of each hour.
	TasksPerHour = 2,
	-- Extra units of work for every player beyond the first (rounded down).
	ExtraUnitsPerPlayer = 0.5,
	Types = Types,
})
