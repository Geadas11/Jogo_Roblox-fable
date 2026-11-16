--!strict
-- Collision groups and which pairs must NOT collide.
-- Everything still collides with the map ("Default" group).
--
-- Why these pairs are off:
--   Player  x Player       players cannot body-block or trap each other in an aisle
--   Player  x Monster      a catch is decided by the server (distance + line of sight),
--                          never by physics pushing characters around
--   Player  x Npc          a customer can never wall a player in during a chase
--   Npc / Monster pairs    AI agents do not jam each other's pathfinding
--   CarriedItem x agents   a carried box never shoves the character holding it

local deepFreeze = require(script.Parent.Parent.Util.DeepFreeze)

local Names = {
	Player = "Player",
	Monster = "Monster",
	Npc = "Npc",
	CarriedItem = "CarriedItem",
}

return deepFreeze({
	Names = Names,

	NonColliding = {
		{ Names.Player, Names.Player },
		{ Names.Player, Names.Monster },
		{ Names.Player, Names.Npc },
		{ Names.Npc, Names.Npc },
		{ Names.Npc, Names.Monster },
		{ Names.CarriedItem, Names.Player },
		{ Names.CarriedItem, Names.Monster },
		{ Names.CarriedItem, Names.Npc },
		{ Names.CarriedItem, Names.CarriedItem },
	},
})
