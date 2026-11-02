--!strict
-- The "telltale": notes what goes wrong in real matches, so that it can be read and fixed afterwards.
-- - server errors (ScriptContext.Error), and the players' machines' errors and goal replays (Net.Report, from
--   client/Report and client/Replay), a few per minute at most;
-- - what MatchCore spots: a phase that does not end, a ball that stays still or leaves the stadium, a player who
--   falls out of the world, and every goal with its context.
-- Kept in the DataStore FC27Log_v1, one key per day ("2026-11-02"), the last 400 entries of each day; read with
-- scripts/inspect/log.luau. Nothing is written from Roblox Studio.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Version = require(Shared:WaitForChild("Version")) :: string
local Env = require(Shared:WaitForChild("Env")) :: string

local Telemetry = {}

local KEEP = 400
local store: DataStore? = nil
if not RunService:IsStudio() then
	pcall(function() store = DataStoreService:GetDataStore("FC27Log_v1") end)
end

local buffer: { any } = {}
local minute, perKind = 0, {} :: { [string]: number }

-- Short and safe: strings cut, tables flattened one level, at most 24 fields
local function clean(v: any, depth: number?): any
	local t = type(v)
	if t == "string" then return string.sub(v, 1, 400) end
	if t == "number" then return if v ~= v then "nan" else math.floor(v * 100 + 0.5) / 100 end
	if t == "boolean" or v == nil then return v end
	if t == "table" and (depth or 0) < 2 then
		local out, n = {}, 0
		for k, x in v do
			n += 1
			if n > 24 then break end
			out[tostring(k)] = clean(x, (depth or 0) + 1)
		end
		return out
	end
	return tostring(v)
end

-- Notes something (kind: "error", "stuck", "goal"...); at most 12 of a kind per minute
function Telemetry.log(kind: string, data: any?, pl: Player?)
	local m = math.floor(os.clock() / 60)
	if m ~= minute then minute, perKind = m, {} end
	perKind[kind] = (perKind[kind] or 0) + 1
	if perKind[kind] > 12 then return end
	local e: { [string]: any } = { t = os.time(), k = kind, v = Version, env = Env, job = string.sub(game.JobId, 1, 8), d = clean(data) }
	if pl then e.u = pl.UserId; e.lang = pl.LocaleId end
	table.insert(buffer, e)
	if RunService:IsStudio() then print("[FC27 log]", kind, data) end
end

local function flush()
	local s = store
	if not s or #buffer == 0 then return end
	local batch = buffer
	buffer = {}
	local key = os.date("!%Y-%m-%d") :: string
	local ok = pcall(function()
		(s :: DataStore):UpdateAsync(key, function(old: any)
			local list = if type(old) == "table" then old else {}
			for _, e in batch do table.insert(list, e) end
			while #list > KEEP do table.remove(list, 1) end
			return list
		end)
	end)
	if not ok then
		-- Try again next time (the oldest are dropped if it keeps failing)
		for i = #batch, 1, -1 do table.insert(buffer, 1, batch[i]) end
		while #buffer > KEEP do table.remove(buffer, 1) end
	end
end

task.spawn(function()
	while true do
		task.wait(60)
		flush()
	end
end)
game:BindToClose(flush)

-- Server errors
ScriptContext.Error:Connect(function(message: string, trace: string, script: Instance?)
	Telemetry.log("error", { msg = message, trace = trace, script = if script then script:GetFullName() else "?" })
end)

-- From the players' machines: their errors, and each goal replay (client/Report, client/Replay)
local Report = Instance.new("RemoteEvent")
Report.Name = "Report"
local perPlayer: { [Player]: { n: number, m: number } } = {}
Report.OnServerEvent:Connect(function(pl: Player, kind: any, data: any)
	if kind ~= "error" and kind ~= "replay" then return end
	local m = math.floor(os.clock() / 60)
	local c = perPlayer[pl]
	if not c or c.m ~= m then c = { n = 0, m = m }; perPlayer[pl] = c end
	c.n += 1
	if c.n > 6 then return end
	Telemetry.log("client." .. kind, data, pl)
end)
Players.PlayerRemoving:Connect(function(pl) perPlayer[pl] = nil end)
Report.Parent = ReplicatedStorage:WaitForChild("Net")

return Telemetry
