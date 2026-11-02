--!strict
-- Sends this machine's script errors to the server's telltale (server/Telemetry, Net.Report), a few per minute at
-- most, with the device and the language, so that what goes wrong on players' screens can be read and fixed.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptContext = game:GetService("ScriptContext")
local UserInputService = game:GetService("UserInputService")

local Report = ReplicatedStorage:WaitForChild("Net"):WaitForChild("Report") :: RemoteEvent
local device = if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then "touch"
	elseif UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then "gamepad" else "computer"

local seen: { [string]: boolean } = {}
ScriptContext.Error:Connect(function(message: string, trace: string, script: Instance?)
	local key = string.sub(message, 1, 120)
	if seen[key] then return end -- the same error once per session
	seen[key] = true
	Report:FireServer("error", { msg = message, trace = trace, script = if script then script.Name else "?", device = device })
end)
