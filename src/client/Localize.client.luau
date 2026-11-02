--!strict
-- Shows every text of the game in this player's language (shared/Lang): any text label whose text is a coded message
-- from the server ("§key|args": the locker-room signs, the scorers board, the labels over the footballers' heads...)
-- is turned into this player's language, here and whenever it changes. Roblox's own automatic translation is switched
-- off on the game's screens and signs: the texts are already translated, and players' names must stay as they are.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))

local function handle(d: Instance)
	if d:IsA("LayerCollector") then
		pcall(function() (d :: any).AutoLocalize = false end)
	elseif d:IsA("TextLabel") or d:IsA("TextButton") then
		local t = d :: any
		local function fix()
			local s = t.Text
			if type(s) == "string" and string.sub(s, 1, 2) == "§" then t.Text = Lang.show(s) end
		end
		fix()
		t:GetPropertyChangedSignal("Text"):Connect(fix)
	end
end

local function watch(root: Instance)
	for _, d in root:GetDescendants() do handle(d) end
	root.DescendantAdded:Connect(handle)
end
watch(workspace)
watch(Players.LocalPlayer:WaitForChild("PlayerGui"))
