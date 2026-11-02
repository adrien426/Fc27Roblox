-- Roblox ids of the web game's models and sounds, written by scripts/upload-assets.mjs after it uploads
-- assets/build/*.glb and assets/source/sounds/*.mp3 with the Open Cloud key. 0 = not uploaded yet: the game then
-- uses its built-in stand-ins (stadium built from code, standard avatars, plain ball, no recorded sounds).
return {
	player = 73631537493084,
	stadium = 81120181062508,
	balls = 98156148120151,
	sounds = {
		whistle = 136259723407282,
		bed = 111053005158227,
		chant = 138515484233725,
		roar = 116598049171507,
	},
	-- The shop's pictures (decals), shown as rbxthumb://type=Asset&id=...
	art = {
		celebrations = 0,
		style = 0,
		vip = 0,
		trail = 0,
		coins500 = 0,
		coins1500 = 0,
		coins5000 = 0,
	},
}
