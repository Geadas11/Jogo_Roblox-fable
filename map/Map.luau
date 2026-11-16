-- Entry point of the map generator. Builds the whole supermarket under `parent`
-- (normally Workspace) inside one root folder named "Map", so it can be replaced whole.

local Kit = require("./Kit")

local SECTIONS = { "Structure", "Shop", "Rooms", "Exterior", "Markers" }

local Map = {}

-- Returns the kit, which carries the record of every part created (for verification).
function Map.build(parent)
	local kit = Kit.new(20260611)
	local root = kit:folder(parent, "Map")
	for _, name in SECTIONS do
		local section = require("./" .. name)
		section(kit, root)
	end
	return kit, root
end

return Map
