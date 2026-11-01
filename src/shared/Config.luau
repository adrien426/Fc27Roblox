-- Shared settings. The match is simulated in metres on a 105 x 68 pitch (x along the length, y across,
-- z up), exactly like the web version; Config.toWorld turns that into Roblox studs.
local Config = {}

Config.M = 3 -- studs per metre: a 1.8 m footballer is about the size of a Roblox avatar
Config.L = 105
Config.W = 68
Config.GOAL_HALF = 3.66 -- half the goal width
Config.BAR = 2.44 -- crossbar height
Config.GOAL_DEPTH = 2.2
Config.G = 9.8
Config.BALL_R = 0.11
Config.GROUND_Y = 0 -- world Y of the grass

-- Web game's player model: height in metres, turn so it faces where the R15 body faces (Mixamo models face +Z,
-- Roblox characters face -Z)
Config.PLAYER_HEIGHT = 1.8
Config.BODY_YAW = math.pi

-- Ball of balls.glb used in the match: classique, etoiles, jabu, brazu or euro
Config.BALL_MODEL = "classique"

Config.MATCH_MINUTES = 6 -- real minutes for the full 90'
Config.TEAM_SIZE = 11
Config.SNAPSHOT_HZ = 20

-- Movement speeds in studs per second (Roblox's default walk speed is 16)
Config.WALK = 16
Config.SPRINT = 25
Config.STUN_SPEED = 6

Config.TEAMS = {
	{ name = "Rouges", abbr = "ROU", color = Color3.fromRGB(215, 38, 61), shorts = Color3.fromRGB(244, 244, 244), brick = "Bright red" },
	{ name = "Bleus", abbr = "BLE", color = Color3.fromRGB(43, 111, 214), shorts = Color3.fromRGB(15, 31, 69), brick = "Bright blue" },
}

-- 4-4-2 for a team attacking towards x = 105 (same layout as the web game): x, y, role, shirt number
Config.FORMATION = {
	{ 3, 34, "GK", 1 },
	{ 18, 9, "DF", 2 }, { 15, 26, "DF", 4 }, { 15, 42, "DF", 5 }, { 18, 59, "DF", 3 },
	{ 32, 11, "MF", 7 }, { 29, 28, "MF", 6 }, { 29, 40, "MF", 8 }, { 32, 57, "MF", 11 },
	{ 46, 28, "FW", 9 }, { 46, 40, "FW", 10 },
}

Config.NAMES = {
	"Martin", "Bernard", "Dubois", "Thomas", "Robert", "Petit", "Durand", "Leroy", "Moreau", "Simon", "Laurent",
	"Michel", "Garcia", "David", "Roux", "Vincent", "Fournier", "Morel", "Girard", "Mercier", "Dupont", "Lambert",
	"Bonnet", "Weber", "Muller", "Klein", "Da Silva", "Pereira", "Diallo", "Traoré", "Koné", "Mendy", "Rossi", "Costa",
}

function Config.toWorld(x: number, y: number, z: number?): Vector3
	return Vector3.new((x - Config.L / 2) * Config.M, Config.GROUND_Y + (z or 0) * Config.M, (y - Config.W / 2) * Config.M)
end

-- World position to pitch metres: returns x, y, z
function Config.toPitch(v: Vector3): (number, number, number)
	return v.X / Config.M + Config.L / 2, v.Z / Config.M + Config.W / 2, (v.Y - Config.GROUND_Y) / Config.M
end

return Config
