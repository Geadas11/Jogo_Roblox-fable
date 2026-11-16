--!strict
-- Hands out the night's work and keeps score.
--
-- At the start of every hour a few task types are drawn from Config.TaskDefinitions.
-- Each type lives in its own module under Tasks/ with two functions:
--   Begin(task, units, context) -> goal   set the work up in the world; return how many
--                                         units were actually created
--   Cleanup(task)                         remove whatever is left
-- A type reports progress through context.Progress; it never touches scores itself.
--
-- The objectives list is sent to clients whole on every change, and on request.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage.Shared
local TaskDefinitions = require(Shared.Config.TaskDefinitions)
local Log = require(Shared.Util.Log)
local Rng = require(Shared.Util.Rng)
local Signal = require(Shared.Util.Signal)
local Net = require(script.Parent.Parent.Net)
local GameManager = require(script.Parent.GameManager)
local PlayerManager = require(script.Parent.PlayerManager)
local ShiftManager = require(script.Parent.ShiftManager)

local log = Log.new("Tasks")

type Task = {
	Id: number,
	Type: string,
	Title: string,
	Detail: string,
	Progress: number,
	Goal: number,
	Reward: number,
	Completed: boolean,
	-- Private to the task type's module.
	State: any,
}

-- What clients are told about a task.
export type PublicTask = {
	Id: number,
	Title: string,
	Detail: string,
	Progress: number,
	Goal: number,
	Completed: boolean,
}

local TaskManager = {}

-- Fired when a task is finished: (public task, reward).
TaskManager.TaskCompleted = Signal.new() :: Signal.Signal<PublicTask, number>

local modules: { [string]: any } = {}
local tasks: { Task } = {}
local nextId = 1
local earnings = 0
local rng = Rng.new(os.time())

local function publicTask(task: Task): PublicTask
	return {
		Id = task.Id,
		Title = task.Title,
		Detail = task.Detail,
		Progress = task.Progress,
		Goal = task.Goal,
		Completed = task.Completed,
	}
end

-- The objectives list as clients see it.
function TaskManager.GetSnapshot(): { PublicTask }
	local snapshot = {}
	for _, task in tasks do
		table.insert(snapshot, publicTask(task))
	end
	return snapshot
end

-- Tasks finished, tasks handed out, and money earned this shift.
function TaskManager.GetStats(): (number, number, number)
	local completed = 0
	for _, task in tasks do
		if task.Completed then
			completed += 1
		end
	end
	return completed, #tasks, earnings
end

local function broadcast()
	Net.FireAllClients("TasksChanged", TaskManager.GetSnapshot())
end

local function isActive(typeName: string): boolean
	for _, task in tasks do
		if task.Type == typeName and not task.Completed then
			return true
		end
	end
	return false
end

local function progress(task: Task, amount: number)
	if task.Completed or amount <= 0 then
		return
	end
	task.Progress = math.min(task.Goal, task.Progress + amount)
	if task.Progress >= task.Goal then
		-- Completed is set before anything else so a reward can never be paid twice.
		task.Completed = true
		earnings += task.Reward
		log:Info("Completed %s (+$%d)", task.Title, task.Reward)
		Net.FireAllClients(
			"Notify",
			string.format("Task complete: %s  +$%d", task.Title, task.Reward),
			"Info"
		)
		TaskManager.TaskCompleted:Fire(publicTask(task), task.Reward)
	end
	broadcast()
end

-- Creates one task of the given type. Returns false when the type has nothing to do
-- right now (for example every shelf is already being restocked).
function TaskManager.Issue(typeName: string, units: number): boolean
	local definition = TaskDefinitions.Types[typeName]
	local module = modules[typeName]
	if not definition or not module then
		log:Warn("Unknown task type %s", typeName)
		return false
	end

	local task: Task = {
		Id = nextId,
		Type = typeName,
		Title = definition.Title,
		Detail = "",
		Progress = 0,
		Goal = 0,
		Reward = 0,
		Completed = false,
		State = nil,
	}
	local context = {
		Rng = rng,
		Progress = function(amount: number, _player: Player?)
			progress(task, amount)
		end,
		Notify = function(player: Player, text: string, kind: string?)
			Net.FireClient(player, "Notify", text, kind or "Info")
		end,
	}

	local ok, goal = xpcall(module.Begin, debug.traceback, task, units, context)
	if not ok then
		log:Warn("%s.Begin failed: %s", typeName, tostring(goal))
		pcall(module.Cleanup, task)
		return false
	end
	if type(goal) ~= "number" or goal <= 0 then
		return false
	end

	nextId += 1
	task.Goal = goal
	task.Reward = goal * definition.RewardPerUnit
	table.insert(tasks, task)
	return true
end

-- Draws this hour's tasks from the pool.
local function issueForHour()
	local candidates = {}
	for typeName in TaskDefinitions.Types do
		if modules[typeName] and not isActive(typeName) then
			table.insert(candidates, typeName)
		end
	end
	-- Sorted so a given seed always produces the same night.
	table.sort(candidates)

	local extra =
		math.floor(TaskDefinitions.ExtraUnitsPerPlayer * math.max(0, #PlayerManager.GetReadyPlayers() - 1))
	local issued = {}
	for _ = 1, TaskDefinitions.TasksPerHour do
		if #candidates == 0 then
			break
		end
		local typeName = rng:PickWeighted(candidates, function(name: string)
			return TaskDefinitions.Types[name].Weight
		end) :: string
		table.remove(candidates, table.find(candidates, typeName))

		local definition = TaskDefinitions.Types[typeName]
		if TaskManager.Issue(typeName, rng:Int(definition.Min, definition.Max) + extra) then
			table.insert(issued, definition.Title)
		end
	end

	if #issued > 0 then
		Net.FireAllClients("Notify", "New tasks: " .. table.concat(issued, ", "), "Info")
		broadcast()
	end
end

-- Removes every unfinished task from the world. Scores are kept for the results screen.
local function cleanupWorld()
	for _, task in tasks do
		if task.State ~= nil then
			local module = modules[task.Type]
			local ok, message = xpcall(module.Cleanup, debug.traceback, task)
			if not ok then
				log:Warn("%s.Cleanup failed: %s", task.Type, tostring(message))
			end
		end
	end
end

function TaskManager.Init()
	for _, child in script.Parent.Tasks:GetChildren() do
		if child:IsA("ModuleScript") then
			modules[child.Name] = (require :: any)(child)
		end
	end
	for typeName in TaskDefinitions.Types do
		if not modules[typeName] then
			error(
				string.format(
					"Task type %q is defined in TaskDefinitions but has no module in Tasks/",
					typeName
				),
				0
			)
		end
	end

	Net.Handle("GetTasks", function()
		return TaskManager.GetSnapshot()
	end)

	GameManager.AddResultsContributor(function(results)
		local completed, total, earned = TaskManager.GetStats()
		results.TasksCompleted = completed
		results.TasksTotal = total
		results.Earnings = earned
	end)
end

function TaskManager.Start()
	ShiftManager.HourChanged:Connect(function(hour: number)
		if hour == 0 then
			-- A new night: forget the previous one.
			tasks = {}
			earnings = 0
		end
		issueForHour()
	end)

	GameManager.PhaseChanged:Connect(function(phase: string)
		if phase ~= "Shift" then
			cleanupWorld()
			if phase == "Lobby" then
				tasks = {}
				broadcast()
			end
		end
	end)
end

return TaskManager
