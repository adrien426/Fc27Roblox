-- Roblox ids of the web game's models and sounds, written by scripts/upload-assets.mjs after it uploads
-- assets/build/*.glb and assets/source/sounds/*.mp3 with the Open Cloud key. 0 = not uploaded yet: the game then
-- uses its built-in stand-ins (stadium built from code, standard avatars, plain ball, no recorded sounds).
return {
	player = 0,
	stadium = 0,
	balls = 0,
	sounds = {
		whistle = 0,
		bed = 0,
		chant = 0,
		roar = 0,
	},
}
