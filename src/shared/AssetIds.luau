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
		celebrations = 126690707640780,
		style = 138281138776883,
		vip = 81669267564792,
		trail = 79077480470837,
		coins500 = 77591651434819,
		coins1500 = 125450251810823,
		coins5000 = 129387775565413,
	},
}
