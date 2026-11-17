--!strict
-- Loads the navigation and sight grids that tools/build.luau bakes into ServerStorage
-- (StringValues "NavGrid" and "SightGrid"). Returns nil when the place has none, for
-- example a place synced with Rojo before the map was built.

local ServerStorage = game:GetService("ServerStorage")

local NavGrid = require(script.Parent.NavGrid)

local MapGrid = {}

local loaded: NavGrid.NavGrid? = nil
local attempted = false

function MapGrid.Get(): NavGrid.NavGrid?
	if attempted then
		return loaded
	end
	attempted = true
	local walk = ServerStorage:FindFirstChild("NavGrid")
	local sight = ServerStorage:FindFirstChild("SightGrid")
	if not walk or not sight or not walk:IsA("StringValue") or not sight:IsA("StringValue") then
		return nil
	end
	loaded = NavGrid.new({
		OriginX = walk:GetAttribute("OriginX") :: number,
		OriginZ = walk:GetAttribute("OriginZ") :: number,
		Width = walk:GetAttribute("Width") :: number,
		Depth = walk:GetAttribute("Depth") :: number,
		Walk = walk.Value,
		Sight = sight.Value,
	})
	return loaded
end

return MapGrid
