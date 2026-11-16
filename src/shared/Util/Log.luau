--!strict
-- Prefixed logging so every Output line says which side and which system wrote it:
--   [NSS/Server/Net] Rejected ClientReady from ...

local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.Parent.Config.GameConfig)

local SIDE = if RunService:IsServer() then "Server" else "Client"

export type Logger = {
	Debug: (self: Logger, message: string, ...any) -> (),
	Info: (self: Logger, message: string, ...any) -> (),
	Warn: (self: Logger, message: string, ...any) -> (),
}

local function render(prefix: string, message: string, ...: any): string
	if select("#", ...) == 0 then
		return prefix .. message
	end
	return prefix .. string.format(message, ...)
end

local Log = {}

function Log.new(scope: string): Logger
	local prefix = string.format("[NSS/%s/%s] ", SIDE, scope)
	local logger = {}

	function logger.Debug(_self: Logger, message: string, ...: any)
		if GameConfig.Debug.VerboseLogging then
			print(render(prefix, message, ...))
		end
	end

	function logger.Info(_self: Logger, message: string, ...: any)
		print(render(prefix, message, ...))
	end

	function logger.Warn(_self: Logger, message: string, ...: any)
		warn(render(prefix, message, ...))
	end

	return logger
end

return Log
