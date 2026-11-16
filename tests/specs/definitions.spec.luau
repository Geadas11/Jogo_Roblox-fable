-- Shared.Net.Definitions: the real remote catalog must be well-formed. This guards
-- every remote added in later phases.

local side = Engine.new().side("server")
local Definitions = side.load("ReplicatedStorage.Shared.Net.Definitions")
local Gate = side.load("ServerScriptService.Server.Net.Gate")

test("the catalog is accepted by the gate", function()
	Gate.new(Definitions)
end)

test("every remote declares one validator function per argument", function()
	for name, definition in Definitions do
		expect.equal(type(definition.args), "table", name .. ".args")
		for index, validator in definition.args do
			expect.equal(type(validator), "function", string.format("%s.args[%d]", name, index))
		end
	end
end)

test("every client remote has a sane rate", function()
	for name, definition in Definitions do
		if definition.from == "Client" then
			expect.truthy(definition.rate, name .. ".rate")
			expect.truthy(definition.rate.burst >= 1, name .. ".rate.burst")
			expect.truthy(definition.rate.perSecond > 0, name .. ".rate.perSecond")
		end
	end
end)

test("the catalog cannot be modified at runtime", function()
	expect.throws(function()
		Definitions.Injected = { kind = "Event", from = "Client", args = {} }
	end)
end)
