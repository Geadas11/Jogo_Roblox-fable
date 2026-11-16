-- Colours and materials used by the map generator. One place to restyle the greybox.

local Kit = require("./Kit")
local S, decor = Kit.style, Kit.decor

local P = {}

-- Structure
P.facade = S(190, 184, 172, "Concrete")
P.wall = S(214, 212, 204, "Plaster")
P.wallBack = S(150, 152, 150, "Concrete")
P.wallCold = S(206, 216, 220, "Metal")
P.roof = S(52, 52, 56, "Concrete")
P.ceiling = S(226, 226, 220, "Plaster")
P.ceilingBack = S(84, 86, 88, "Metal")

-- Floors
P.floorShop = S(204, 202, 194, "CeramicTiles")
P.floorBath = S(160, 180, 186, "CeramicTiles")
P.floorStaff = S(150, 146, 136, "SmoothPlastic")
P.floorOffice = S(66, 72, 88, "Carpet")
P.floorBack = S(116, 116, 114, "Concrete")
P.floorCold = S(138, 144, 150, "DiamondPlate")

-- Generic
P.steel = S(168, 172, 176, "Metal")
P.darkSteel = S(62, 66, 72, "Metal")
P.white = S(236, 236, 232, "SmoothPlastic")
P.offWhite = S(214, 212, 204, "SmoothPlastic")
P.black = S(22, 22, 24, "SmoothPlastic")
P.grey = S(120, 122, 126, "SmoothPlastic")
P.wood = S(134, 100, 68, "WoodPlanks")
P.woodDark = S(86, 62, 44, "Wood")
P.cardboard = S(164, 126, 84, "Cardboard")
P.rubber = S(28, 28, 30, "Rubber")
P.fabric = S(70, 84, 104, "Fabric")
P.red = S(170, 44, 40, "SmoothPlastic")
P.green = S(52, 110, 70, "SmoothPlastic")
P.yellow = S(214, 176, 48, "SmoothPlastic")
P.blue = S(48, 86, 150, "SmoothPlastic")
P.door = S(120, 124, 130, "Metal")
P.doorWood = S(112, 84, 58, "Wood")
P.shelf = S(220, 220, 214, "Metal")
P.plinth = S(58, 60, 66, "SmoothPlastic")
P.frost = S(210, 228, 236, "Ice")

-- Glass: blocks movement, lets light and sight through.
P.glass = S(168, 204, 214, "Glass", { alpha = 0.7, shadow = false })
P.glassDecor = S(168, 204, 214, "Glass", { alpha = 0.7, collide = false })
P.mirror = S(196, 206, 210, "Glass", { reflect = 0.35, collide = false })

-- Exterior
P.asphalt = S(36, 36, 40, "Asphalt")
P.concrete = S(126, 126, 124, "Concrete")
P.line = S(206, 206, 196, "SmoothPlastic", { collide = false })
P.lineYellow = S(200, 164, 40, "SmoothPlastic", { collide = false })
P.fence = S(40, 44, 46, "Metal")
P.distant = S(18, 20, 26, "Concrete", { collide = false })
P.hedge = S(34, 58, 40, "Grass")

-- Invisible collider that stands in for a group of detailed, non-colliding parts.
P.collider = S(255, 255, 255, "SmoothPlastic", { alpha = 1, shadow = false })
-- Invisible barrier around the playable area.
P.barrier = S(255, 255, 255, "SmoothPlastic", { alpha = 1, shadow = false })

-- Decorative (non-colliding) variants
P.dSteel = decor(P.steel)
P.dDarkSteel = decor(P.darkSteel)
P.dWhite = decor(P.white)
P.dBlack = decor(P.black)
P.dGrey = decor(P.grey)
P.dWood = decor(P.wood)
P.dCardboard = decor(P.cardboard)
P.dRed = decor(P.red)
P.dGreen = decor(P.green)
P.dYellow = decor(P.yellow)
P.dBlue = decor(P.blue)
P.dShelf = decor(P.shelf)
P.dRubber = decor(P.rubber)

-- Glowing parts
function P.neon(r, g, b)
	return S(r, g, b, "Neon", { collide = false })
end

return P
