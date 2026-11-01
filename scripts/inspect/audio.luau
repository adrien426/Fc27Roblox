-- Checks the game's audio on a real server: do the uploaded sounds load (crowd, whistle, chant, roar), and which
-- text-to-speech voices (AudioTextToSpeech) exist, with a French and an English sentence. Run with
-- scripts/run-luau.mjs.
local ContentProvider = game:GetService("ContentProvider")
local SoundService = game:GetService("SoundService")
local AssetIds = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("AssetIds"))

for name, id in AssetIds.sounds do
	local s = Instance.new("Sound")
	s.SoundId = "rbxassetid://" .. id
	s.Parent = SoundService
	local status = "?"
	ContentProvider:PreloadAsync({ s }, function(_, st) status = tostring(st) end)
	local t0 = os.clock()
	while not s.IsLoaded and os.clock() - t0 < 8 do task.wait(0.2) end
	print(string.format("SOUND %-8s id %d  loaded %s  length %.1f s  preload %s", name, id, tostring(s.IsLoaded), s.TimeLength, status))
	s:Destroy()
end

local function tts(voice: string, text: string): string
	local ok, res = pcall(function()
		local t = Instance.new("AudioTextToSpeech")
		t.Text = text
		t.VoiceId = voice
		t.Parent = SoundService
		local st = t:LoadAsync()
		local out = string.format("%s, %.2f s", tostring(st), t.TimeLength)
		t:Destroy()
		return out
	end)
	return if ok then res else "ERROR " .. tostring(res)
end

local FR = "Frappe de Martin, arrêt du gardien !"
local EN = "Shot by Martin, saved by the keeper!"
for _, v in { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "101", "201", "301", "401", "402", "403", "501", "1001" } do
	print(string.format("VOICE %-5s  fr: %s   en: %s", v, tts(v, FR), tts(v, EN)))
end
return "done" -- audio
