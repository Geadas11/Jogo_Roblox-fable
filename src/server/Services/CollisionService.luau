--!strict
-- Registers the collision groups declared in Config.CollisionGroups and offers one
-- helper to put a whole model into a group.

local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local CollisionGroups = require(Shared.Config.CollisionGroups)

local CollisionService = {}

local knownGroups: { [string]: boolean } = {}

function CollisionService.Init()
	for _, groupName in CollisionGroups.Names do
		knownGroups[groupName] = true
		if not PhysicsService:IsCollisionGroupRegistered(groupName) then
			PhysicsService:RegisterCollisionGroup(groupName)
		end
	end

	for _, pair in CollisionGroups.NonColliding do
		PhysicsService:CollisionGroupSetCollidable(pair[1], pair[2], false)
	end
end

-- Puts every BasePart under `root` into `groupName`, including parts added later
-- (accessories, tools, carried items). Disconnect the returned connection when the
-- model no longer needs to be tracked; destroying `root` also ends it.
function CollisionService.Assign(root: Instance, groupName: string): RBXScriptConnection
	if not knownGroups[groupName] then
		error(string.format("CollisionService: %q is not a group from Config.CollisionGroups", groupName), 2)
	end

	local function apply(instance: Instance)
		if instance:IsA("BasePart") then
			instance.CollisionGroup = groupName
		end
	end

	apply(root)
	for _, descendant in root:GetDescendants() do
		apply(descendant)
	end
	return root.DescendantAdded:Connect(apply)
end

return CollisionService
