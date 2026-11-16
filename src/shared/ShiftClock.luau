--!strict
-- Pure time maths for the night shift, shared by the server (which decides the hour)
-- and the clients (which draw the clock). The shift starts at 12:00 AM.

local ShiftClock = {}

-- Whole hours completed after `elapsed` real seconds, never more than `hours`.
function ShiftClock.hourAt(elapsed: number, hourDuration: number, hours: number): number
	if elapsed <= 0 then
		return 0
	end
	return math.min(hours, math.floor(elapsed / hourDuration))
end

-- Clock text such as "12:00 AM" or "3:45 AM". Stops at `hours`:00.
function ShiftClock.format(elapsed: number, hourDuration: number, hours: number): string
	local minutes = math.floor(math.max(0, elapsed) / hourDuration * 60)
	minutes = math.min(minutes, hours * 60)
	local hour = minutes // 60
	local displayHour = if hour % 12 == 0 then 12 else hour % 12
	return string.format("%d:%02d AM", displayHour, minutes % 60)
end

return ShiftClock
