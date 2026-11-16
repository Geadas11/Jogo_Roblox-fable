--!strict
-- CollectionService tags placed on the map by the map generator (see /map).
-- Game code finds map objects through these tags, never by name or path, so the map can
-- be rebuilt or re-dressed without touching scripts.
--
-- This module is also loaded by the generator outside Roblox, so it must stay plain
-- data: no requires and no engine globals.

return table.freeze({
	-- Areas and navigation
	Zone = "Zone", -- invisible volume. Attributes: ZoneId, DisplayName, Indoor, Circuit
	PatrolNode = "PatrolNode", -- monster patrol point. Attribute: Zone
	CustomerNode = "CustomerNode", -- NPC point. Attributes: Kind (Browse/Queue/Entry), Zone
	PlayerSpawn = "PlayerSpawn",

	-- Power and light
	LightFixture = "LightFixture", -- part holding a light named "Light". Attributes: Zone, Circuit, BaseBrightness
	ElectricalPanel = "ElectricalPanel",
	Breaker = "Breaker", -- Attribute: Circuit

	-- Doors
	Door = "Door", -- hinged leaf. Attributes: ClosedCFrame, OpenCFrame, Open, Zone
	EntranceDoor = "EntranceDoor", -- sliding glass panel, locked during the shift
	EmergencyExit = "EmergencyExit",

	-- Work
	ShelfBay = "ShelfBay", -- model holding the products of one bay. Attributes: Category, Aisle
	FridgeUnit = "FridgeUnit", -- Attribute: Kind (Dairy/Frozen/Chest/Industrial)
	CheckoutRegister = "CheckoutRegister", -- Attribute: Lane
	SpillPoint = "SpillPoint", -- floor position where a spill may appear
	TrashPoint = "TrashPoint", -- position where litter may appear
	CartPoint = "CartPoint", -- position where an abandoned cart may appear
	CartReturn = "CartReturn",
	DeliveryPoint = "DeliveryPoint",
	Dumpster = "Dumpster",
	ToolPickup = "ToolPickup", -- Attribute: Tool
	RepairPoint = "RepairPoint", -- Attribute: Kind
	TimeClock = "TimeClock",

	-- Security and hiding
	CCTVCamera = "CCTVCamera", -- part whose CFrame is the camera view. Attributes: CameraId, DisplayName, Zone
	OfficeComputer = "OfficeComputer",
	SecurityMonitor = "SecurityMonitor",
	HidingSpot = "HidingSpot", -- Attribute: Kind (Locker/UnderDesk/Stall)
	Mirror = "Mirror",
})
