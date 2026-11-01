--!strict
-- The web game's recorded sounds (sounds/*.mp3, uploaded to Roblox: ids in Shared.AssetIds): crowd bed all match
-- long, the referee's whistle at kick-offs, half time and full time, a roar and the fans' chant after a goal.
-- A sound that is not uploaded (id 0) is skipped.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared:WaitForChild("AssetIds"))
local Net = ReplicatedStorage:WaitForChild("Net")

local function sound(name: string, volume: number, looped: boolean): Sound?
	local id = (AssetIds.sounds :: any)[name]
	if typeof(id) ~= "number" or id <= 0 then return nil end
	local s = Instance.new("Sound")
	s.Name = "FC27_" .. name
	s.SoundId = "rbxassetid://" .. id
	s.Volume = volume
	s.Looped = looped
	s.Parent = SoundService
	return s
end

local bed = sound("bed", 0.35, true)
local chant = sound("chant", 0, true)
local roar = sound("roar", 0.8, false)
local whistle = sound("whistle", 0.6, false)

if bed then bed:Play() end

local function blow(times: number)
	if not whistle then return end
	local w = whistle :: Sound
	task.spawn(function()
		for i = 1, times do
			w.PlaybackSpeed = 0.97 + math.random() * 0.06
			w:Play()
			if i < times then task.wait(0.55) end
		end
	end)
end

-- The fans sing for a while after a goal, then fade out
local chantTween: Tween? = nil
local function sing()
	if not chant then return end
	local c = chant :: Sound
	if chantTween then (chantTween :: Tween):Cancel() end
	if not c.IsPlaying then c:Play() end
	c.Volume = 0.55
	chantTween = TweenService:Create(c, TweenInfo.new(14, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Volume = 0 })
	;(chantTween :: Tween):Play()
end

local lastPhase = Net:GetAttribute("Phase")
Net:GetAttributeChangedSignal("Phase"):Connect(function()
	local p = Net:GetAttribute("Phase")
	if p == lastPhase then return end
	if p == "set" and Net:GetAttribute("SetKind") == "kickoff" then
		blow(1)
	elseif p == "break" then
		blow(2)
	elseif p == "done" then
		blow(3)
	end
	lastPhase = p
end)

Net:GetAttributeChangedSignal("GoalAt"):Connect(function()
	if roar then (roar :: Sound):Play() end
	sing()
end)
