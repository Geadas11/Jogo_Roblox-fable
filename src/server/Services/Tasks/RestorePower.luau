--!strict
-- Restore the power: issued by TaskManager when PowerManager reports a failure.
-- Done when every circuit and the generator are back on, whoever does it.

local Services = script.Parent.Parent
local PowerManager = require(Services.PowerManager)

local RestorePower = {}

function RestorePower.Begin(task: any, _units: number, context: any): number
	if PowerManager.AllOn() then
		return 0
	end
	if PowerManager.IsGeneratorOn() then
		task.Detail = "Reset the breakers in the electrical room: "
			.. table.concat(PowerManager.GetOff(), ", ")
			.. "."
	else
		task.Detail = "Restart the generator in the electrical room, then reset the breakers."
	end
	task.State = {
		Connection = PowerManager.Changed:Connect(function()
			if PowerManager.AllOn() then
				context.Progress(1)
			end
		end),
	}
	return 1
end

function RestorePower.Cleanup(task: any)
	if task.State then
		task.State.Connection:Disconnect()
		task.State = nil
	end
end

return RestorePower
