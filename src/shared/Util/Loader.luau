--!strict
-- Boots a set of singleton modules (server "services" or client "controllers") in a
-- fixed, explicit order.
--
-- Lifecycle of each module:
--   Init()   optional. Runs first for every module, in order, and must not yield.
--            Set up own state and bind remotes here. Do NOT call other modules yet:
--            they may not have run their own Init.
--   Start()  optional. Runs after every Init has finished, each in its own thread.
--            Other modules are safe to use from here on.
--
-- A failing require or Init aborts the boot with a clear error: running half a game
-- is worse than not running. A failing Start is reported and the others keep going.

export type Logger = {
	Info: (self: any, message: string, ...any) -> (),
	Warn: (self: any, message: string, ...any) -> (),
}

export type Lifecycle = {
	Init: (() -> ())?,
	Start: (() -> ())?,
	[string]: any,
}

local Loader = {}

function Loader.Run(container: Instance, order: { string }, log: Logger): { [string]: Lifecycle }
	local modules: { [string]: Lifecycle } = {}

	-- 1. Require, in order.
	for _, name in order do
		if modules[name] then
			error(string.format("Loader: %q is listed twice", name), 0)
		end

		local child = container:FindFirstChild(name)
		if not child or not child:IsA("ModuleScript") then
			error(string.format("Loader: %s has no ModuleScript named %q", container:GetFullName(), name), 0)
		end

		-- `require` is cast because its argument is only known at runtime.
		local ok, result = pcall(require :: any, child)
		if not ok then
			error(string.format("Loader: could not require %q: %s", name, tostring(result)), 0)
		end
		if type(result) ~= "table" then
			error(string.format("Loader: %q must return a table, got %s", name, typeof(result)), 0)
		end
		modules[name] = result
	end

	-- A module that exists but is not listed would silently never run. Say so.
	for _, child in container:GetChildren() do
		if child:IsA("ModuleScript") and not modules[child.Name] then
			log:Warn(
				"%s exists in %s but is not in the boot order; it will not run",
				child.Name,
				container.Name
			)
		end
	end

	-- 2. Init, in order.
	for _, name in order do
		local init = modules[name].Init
		if init then
			local ok, message = xpcall(init, debug.traceback)
			if not ok then
				error(string.format("Loader: %s.Init failed: %s", name, tostring(message)), 0)
			end
		end
	end

	-- 3. Start, each isolated in its own thread.
	for _, name in order do
		local start = modules[name].Start
		if start then
			task.spawn(function()
				local ok, message = xpcall(start, debug.traceback)
				if not ok then
					log:Warn("%s.Start failed: %s", name, tostring(message))
				end
			end)
		end
	end

	return modules
end

return Loader
