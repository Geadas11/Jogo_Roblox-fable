--!strict
-- Restore the power: issued by TaskManager when PowerManager reports a failure.
-- Done when every circuit and the generator are back on, whoever does it.
-- The hint follows the electrical room as it changes: a second failure while the task
-- is open (a trip, then the 4 AM blackout) updates it instead of leaving it stale.

local Services = script.Parent.Parent
local PowerManager = require(Services.PowerManager)
local SessionState = require(game:GetService("ReplicatedStorage").Shared.SessionState)

local RestorePower = {}

local function describe(): string
	if not PowerManager.IsGeneratorOn() then
		return "Restart the generator in the electrical room, then reset the breakers."
	end
	return "Reset the breakers in the electrical room: " .. table.concat(PowerManager.GetOff(), ", ") .. "."
end

function RestorePower.Begin(task: any, _units: number, context: any): number
	if PowerManager.AllOn() then
		return 0
	end
	task.Detail = describe()
	task.State = {
		Connection = PowerManager.Changed:Connect(function()
			-- When the shift ends the power is put back automatically: that is not the
			-- team's work, so it must not pay out.
			if SessionState.Get("Phase") ~= "Shift" then
				return
			end
			if PowerManager.AllOn() then
				context.Progress(1)
			elseif context.SetDetail then
				context.SetDetail(describe())
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
