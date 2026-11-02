--!strict
-- The web game's recorded sounds (sounds/*.mp3, uploaded to Roblox: ids in Shared.AssetIds): crowd bed all match
-- long, louder for a moment on a shot, a save, a skill move or a card (Net attribute Crowd), the referee's whistle
-- at kick-offs, restarts after a foul, half time and full time, a roar and the fans' chant after a goal.
-- No footsteps: Roblox's default character sounds are replaced by an empty script (src/stubs).
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

local bed = sound("bed", 0.5, true)
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

-- The crowd rises for a moment (shot, save, dribble, card…), then settles back
local BED = 0.5
local swellTween: Tween? = nil
Net:GetAttributeChangedSignal("CrowdAt"):Connect(function()
	if not bed then return end
	local b = bed :: Sound
	local a = Net:GetAttribute("Crowd")
	local amount = if type(a) == "number" then math.clamp(a, 0, 1) else 0.3
	if swellTween then (swellTween :: Tween):Cancel() end
	b.Volume = BED + amount * 0.55
	swellTween = TweenService:Create(b, TweenInfo.new(2.2 + amount * 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Volume = BED })
	;(swellTween :: Tween):Play()
end)

-- A whistle for fouls (free kicks and penalties)
Net:GetAttributeChangedSignal("SetKind"):Connect(function()
	local k = Net:GetAttribute("SetKind")
	if k == "freekick" or k == "penalty" then blow(1) end
end)

-- ---------- Commentator's voice ----------
-- Roblox's text-to-speech reads the commentary out loud, in the player's language: the server sends a coded message
-- (shared/Lang), translated here, and read by the voice of that language (Lang.VOICE). Roblox's own translation of
-- the spoken text is switched off: the text is already in the right language. If text-to-speech is not available,
-- the commentary stays on screen only.
local Players = game:GetService("Players")
local Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))
local tts: any = nil
pcall(function()
	local t: any = (Instance.new :: any)("AudioTextToSpeech") -- newer than the type definitions
	t.VoiceId = Lang.VOICE[Lang.current()] or "1"
	pcall(function() t.AutoLocalize = false end)
	t.Volume = 1.6
	t.Speed = 1.08
	t.Parent = SoundService
	local out = Instance.new("AudioDeviceOutput")
	out.Parent = SoundService
	local w = Instance.new("Wire")
	w.SourceInstance = t
	w.TargetInstance = out
	w.Parent = t
	tts = t
end)
local speaking = 0
Net:GetAttributeChangedSignal("CommentAt"):Connect(function()
	if not tts or Net:GetAttribute("CommentSpeak") ~= true then return end
	local text = Net:GetAttribute("Comment")
	if type(text) ~= "string" then return end
	speaking += 1
	local mine = speaking
	task.spawn(function()
		local ok = pcall(function()
			tts:Pause()
			tts.Text = Lang.show(text)
			tts:LoadAsync()
			if speaking == mine then tts:Play() end
		end)
		Players.LocalPlayer:SetAttribute("Voice", if ok then "ok" else "indisponible")
	end)
end)

-- What is playing, shown in the on-screen state line (client/Hud): to understand a silent crowd
task.spawn(function()
	while true do
		local b = bed
		local state = if not b then "foule : pas de son"
			elseif b.IsPlaying and b.IsLoaded then string.format("foule : %.0f%%", b.Volume * 100)
			elseif b.IsLoaded then "foule : arrêtée"
			else "foule : chargement"
		local v = Players.LocalPlayer:GetAttribute("Voice")
		Players.LocalPlayer:SetAttribute("Audio", state .. (if tts then " · voix " .. tostring(v or "prête") else " · voix absente"))
		if b and b.IsLoaded and not b.IsPlaying then b:Play() end
		task.wait(2)
	end
end)
