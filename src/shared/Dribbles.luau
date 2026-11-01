--!strict
-- The web game's 31 skill moves, ported as they are. Each move lasts `dur` seconds; k goes from 0 to 1 over it.
-- - v(k): the player's speed during the move, in metres per second, along his direction (forward) and to the
--   chosen side (side > 0 = towards the side picked when the move starts)
-- - ball(k): where the ball is, in metres from the player: forward, side, height (moves without it keep the
--   usual dribble)
-- - knock: the ball is released at k = at with a velocity [forward, side, up] ("through" = between the nearest
--   defender's legs), and the dribbler gets first claim on it for a moment
-- - at: when the outcome is decided (default: the knock, or the middle of the move)
-- - anim(k, A): the move's body animation, layered on top of the running clip (client/Bodies)
-- - reverse: the player ends the move facing back (drag-backs); fake: "pass" or "shot" (a shot fake can send the
--   keeper the wrong way); needDef: only with a defender close; airborne: the ball is in the air
-- stars: difficulty, 1 to 5.
local Dribbles = {}

export type Anim = {
	spin: (a: number) -> (),
	lean: (a: number) -> (),
	bend: (a: number) -> (),
	hop: (y: number) -> (),
	crouch: (c: number) -> (),
	leg: (which: string, side: number, fwd: number, knee: number) -> (),
	arms: (out: number, fwd: number?) -> (),
}

export type Move = {
	key: string,
	name: string,
	stars: number,
	dur: number,
	at: number?,
	reverse: boolean?,
	fake: string?,
	needDef: boolean?,
	airborne: boolean?,
	knock: { at: number, v: { number } | string }?,
	v: (k: number) -> (number, number),
	ball: ((k: number) -> (number, number, number))?,
	anim: (k: number, A: Anim) -> (),
}

local function clamp(x: number, a: number, b: number): number return math.clamp(x, a, b) end
local function kSm(q: number): number return q * q * (3 - 2 * q) end
local function kSeg(k: number, a: number, b: number): number return clamp((k - a) / (b - a), 0, 1) end
local function kBump(k: number, a: number, b: number): number return math.sin(kSeg(k, a, b) * math.pi) end
local function kLerp(a: number, b: number, t: number): number return a + (b - a) * t end
local PI, TAU = math.pi, math.pi * 2

local MOVES: { Move } = {
	{ key = "crochet", name = "Crochet", stars = 1, dur = 0.45,
		v = function(k) return 2.5, 7.6 * (1 - k * 0.5) end,
		ball = function(k) return 0.6, 0.3 * kSm(kSeg(k, 0, 0.45)), 0 end,
		anim = function(k, A) A.lean(0.35 * kBump(k, 0, 1)); A.leg("O", -0.35 * kBump(k, 0, 0.45), 0.5 * kBump(k, 0, 0.45), 0.3) end },
	{ key = "corps", name = "Feinte de corps", stars = 1, dur = 0.5,
		v = function(k) if k < 0.4 then return 2, -3.5 end; return 5, 6.8 end,
		anim = function(k, A) A.lean(if k < 0.4 then -0.5 * kBump(k, 0, 0.45) else 0.4 * kBump(k, 0.4, 1)); A.bend(0.3); A.arms(1.2, 0.2) end },
	{ key = "rateau", name = "Râteau", stars = 1, dur = 0.55, reverse = true,
		v = function(k) if k < 0.25 then return 1, 0 end; return -4.5, 0.8 end,
		ball = function(k) return 0.6 - 1.2 * kSm(kSeg(k, 0.2, 0.55)), 0, 0 end,
		anim = function(k, A) A.spin(PI * kSm(kSeg(k, 0.35, 0.8))); A.leg("L", 0, 0.6 * kBump(k, 0, 0.3) - 0.5 * kBump(k, 0.25, 0.55), 0.3) end },
	{ key = "stopgo", name = "Arrêt-départ", stars = 1, dur = 0.6,
		v = function(k) if k < 0.4 then return 0.3, 0 end; return 8.5, 0.5 end,
		ball = function(k) return if k < 0.4 then 0.42 else 0.42 + 0.35 * kSeg(k, 0.4, 0.6), 0, 0 end,
		anim = function(k, A) A.leg("L", 0, 0.5 * kBump(k, 0, 0.45), 0.2); A.bend(if k < 0.4 then -0.1 else 0.45) end },
	{ key = "fpasse", name = "Feinte de passe", stars = 1, dur = 0.55, fake = "pass",
		v = function(k) if k < 0.35 then return 0.8, 0 end; return 4, 6 end,
		anim = function(k, A) A.leg("L", 0.3, kLerp(-0.6, 0.3, kSeg(k, 0.1, 0.33)) * kBump(k, 0, 0.36), 0.6 * kBump(k, 0, 0.3)); A.arms(0.9) end },
	{ key = "passement", name = "Passement de jambes", stars = 2, dur = 0.62,
		v = function(k) if k < 0.45 then return 1.5, -2.2 end; return 4, 7.8 end,
		ball = function(k) return 0.6, if k < 0.45 then -0.1 * kBump(k, 0, 0.45) else 0.35 * kSm(kSeg(k, 0.45, 0.75)), 0 end,
		anim = function(k, A)
			local b = kBump(k, 0.05, 0.42)
			A.leg("O", 0.7 * b, 0.6 * b, 0.6 * b)
			A.lean(if k < 0.45 then -0.35 * kBump(k, 0, 0.45) else 0.4 * kBump(k, 0.45, 1))
			A.arms(1.2)
		end },
	{ key = "passinv", name = "Passement inversé", stars = 2, dur = 0.6,
		v = function(k) if k < 0.45 then return 1.5, -2 end; return 4, 7.6 end,
		ball = function(k) return 0.6, if k < 0.45 then -0.1 * kBump(k, 0, 0.45) else 0.35 * kSm(kSeg(k, 0.45, 0.75)), 0 end,
		anim = function(k, A)
			local b = kBump(k, 0.05, 0.42)
			A.leg("L", -0.5 * kBump(k, 0.05, 0.25) + 0.6 * kBump(k, 0.2, 0.42), 0.6 * b, 0.5 * b)
			A.lean(if k < 0.45 then -0.3 else 0.4 * kBump(k, 0.45, 1))
			A.arms(1.2)
		end },
	{ key = "croqueta", name = "La croqueta", stars = 2, dur = 0.42,
		v = function(k) if k < 0.55 then return 2, 9.5 end; return 5.5, 1.5 end,
		ball = function(k) return 0.55, -0.25 + 0.6 * kSm(kSeg(k, 0.1, 0.45)), 0 end,
		anim = function(k, A)
			A.leg("O", -0.3 * kBump(k, 0.05, 0.3), 0.3 * kBump(k, 0.05, 0.3), 0.2)
			A.leg("L", 0.3 * kBump(k, 0.3, 0.55), 0.3 * kBump(k, 0.3, 0.55), 0.2)
			A.hop(0.08 * kBump(k, 0.1, 0.5))
		end },
	{ key = "semelle", name = "Roulé de semelle", stars = 2, dur = 0.5,
		v = function() return 1.5, 6.5 end,
		ball = function(k) return 0.5, -0.2 + 0.7 * kSm(kSeg(k, 0.05, 0.6)), 0 end,
		anim = function(k, A) A.leg("O", -0.6 * kBump(k, 0, 0.6), 0.4 * kBump(k, 0, 0.6), 0.2); A.hop(0.06 * kBump(k, 0.3, 0.8)); A.lean(0.25) end },
	{ key = "cruyff", name = "Crochet Cruyff", stars = 2, dur = 0.6, reverse = true,
		v = function(k) if k < 0.3 then return 0.8, 0 end; return -5.5, 2.4 end,
		ball = function(k) return 0.6 - 1.2 * kSm(kSeg(k, 0.3, 0.65)), 0.25 * kBump(k, 0.3, 0.65), 0 end,
		anim = function(k, A)
			A.spin(PI * kSm(kSeg(k, 0.3, 0.85)))
			A.leg("L", -0.4 * kBump(k, 0.3, 0.6), if k < 0.3 then kLerp(-0.8, 0.4, kSeg(k, 0.1, 0.3)) * kBump(k, 0, 0.32) else -0.3 * kBump(k, 0.3, 0.6), 0.6)
			A.arms(1.1)
		end },
	{ key = "chop", name = "Chop (Ronaldo)", stars = 2, dur = 0.5,
		v = function(k) if k < 0.3 then return 3, 0 end; return -1.5, 7.5 end,
		ball = function(k) return 0.6 - 0.4 * kSm(kSeg(k, 0.25, 0.5)), 0.3 * kSm(kSeg(k, 0.25, 0.5)), 0 end,
		anim = function(k, A) A.spin(0.5 * PI * kBump(k, 0.3, 1)); A.leg("L", -0.6 * kBump(k, 0.15, 0.5), -0.4 * kBump(k, 0.15, 0.5), 0.5); A.lean(0.3 * kBump(k, 0.3, 1)) end },
	{ key = "frappe", name = "Feinte de frappe", stars = 2, dur = 0.62, fake = "shot",
		v = function(k) if k < 0.38 then return 0.4, 0 end; return 3.5, 7.2 end,
		ball = function(k) return 0.65, 0.3 * kSm(kSeg(k, 0.4, 0.7)), 0 end,
		anim = function(k, A) A.leg("L", 0, kLerp(-1.1, 0.5, kSeg(k, 0.1, 0.38)) * kBump(k, 0, 0.42), 1.2 * kBump(k, 0, 0.3)); A.arms(1.4); A.lean(0.35 * kBump(k, 0.4, 1)) end },
	{ key = "grandpont", name = "Grand pont", stars = 2, dur = 0.7, knock = { at = 0.15, v = { 9, 3.5, 0.3 } },
		v = function(k) if k < 0.5 then return 5.5, -6 end; return 8, 3.5 end,
		anim = function(k, A) A.leg("L", 0.2, 0.8 * kBump(k, 0, 0.2), 0.2); A.arms(1.1) end },
	{ key = "roulette", name = "Roulette marseillaise", stars = 3, dur = 0.62,
		v = function() return 3.2, 5.6 end,
		ball = function(k) return 0.45, 0.3 * math.sin(TAU * kSm(k)), 0 end,
		anim = function(k, A)
			A.spin(TAU * kSm(k))
			A.leg("L", 0.1, 0.5 * kBump(k, 0.05, 0.5), 0.3)
			A.leg("O", 0.1, 0.5 * kBump(k, 0.5, 0.95), 0.3)
			A.crouch(0.06)
			A.arms(1.3)
		end },
	{ key = "doublepass", name = "Double passement", stars = 3, dur = 0.85,
		v = function(k) if k < 0.33 then return 1.5, -2.2 elseif k < 0.62 then return 1.5, 2.4 end; return 4.5, 7.5 end,
		anim = function(k, A)
			local a, b = kBump(k, 0.03, 0.3), kBump(k, 0.33, 0.6)
			A.leg("O", 0.7 * a, 0.6 * a, 0.6 * a)
			A.leg("L", 0.7 * b, 0.6 * b, 0.6 * b)
			A.lean(if k < 0.33 then -0.35 elseif k < 0.62 then 0.35 else 0.4)
			A.arms(1.2)
		end },
	{ key = "berbatov", name = "Pirouette Berbatov", stars = 3, dur = 0.65,
		v = function() return 2.2, 4 end,
		ball = function(k) return 0.4, 0.2 * math.sin(TAU * kSm(kSeg(k, 0.15, 0.75))), 0 end,
		anim = function(k, A) A.spin(TAU * kSm(kSeg(k, 0.15, 0.75))); A.leg("L", 0.1, 0.6, 0.4); A.arms(1.4) end },
	{ key = "talon", name = "Talonnade", stars = 3, dur = 0.6, knock = { at = 0.35, v = { 4.5, 4.2, 0.6 } },
		v = function(k) if k < 0.35 then return 1, 0 end; return 3.8, 4.5 end,
		ball = function(k) return 0.6 - 0.5 * kSeg(k, 0, 0.3), 0, 0 end,
		anim = function(k, A) A.leg("L", -0.3, -0.7 * kBump(k, 0.1, 0.4), 1.6 * kBump(k, 0.1, 0.4)); A.spin(TAU * kSm(kSeg(k, 0.35, 1))) end },
	{ key = "talontalon", name = "Talon-talon", stars = 3, dur = 0.55,
		v = function() return 4, 4 end,
		ball = function(k) return 0.4 + 0.3 * kSm(kSeg(k, 0.4, 0.8)), -0.2 + 0.6 * kSm(kSeg(k, 0.1, 0.5)), 0.1 * kBump(k, 0.1, 0.5) end,
		anim = function(k, A) A.leg("L", 0, -0.6 * kBump(k, 0, 0.45), 1.4 * kBump(k, 0, 0.45)); A.leg("O", 0, -0.5 * kBump(k, 0.4, 0.8), 1.2 * kBump(k, 0.4, 0.8)) end },
	{ key = "petitpont", name = "Petit pont", stars = 3, dur = 0.6, knock = { at = 0.2, v = "through" }, needDef = true,
		v = function(k) if k < 0.45 then return 4.5, 5.5 end; return 7.5, -4 end,
		anim = function(k, A) A.leg("L", -0.2, 0.7 * kBump(k, 0, 0.25), 0.2); A.lean(0.3 * kBump(k, 0.2, 1)) end },
	{ key = "elastico", name = "Elastico (Ronaldinho)", stars = 4, dur = 0.55,
		v = function(k) if k < 0.3 then return 1.5, -4 end; return 3, 8.6 end,
		ball = function(k) return 0.6, -0.4 * kBump(k, 0, 0.4) + 0.4 * kSm(kSeg(k, 0.35, 0.6)), 0 end,
		anim = function(k, A) A.leg("O", 0.6 * kBump(k, 0, 0.3) - 0.6 * kBump(k, 0.28, 0.55), 0.3, 0.3); A.lean(if k < 0.3 then -0.3 else 0.4); A.arms(1.3) end },
	{ key = "elainv", name = "Elastico inversé", stars = 4, dur = 0.55,
		v = function(k) if k < 0.3 then return 1.5, -3 end; return 3, 8.4 end,
		ball = function(k) return 0.6, -0.3 * kBump(k, 0, 0.35) + 0.45 * kSm(kSeg(k, 0.35, 0.6)), 0 end,
		anim = function(k, A) A.leg("L", -0.5 * kBump(k, 0, 0.3) + 0.6 * kBump(k, 0.28, 0.55), 0.3, 0.3); A.lean(if k < 0.3 then -0.25 else 0.4); A.arms(1.3) end },
	{ key = "rabona", name = "Feinte de rabona", stars = 4, dur = 0.6, fake = "shot",
		v = function(k) if k < 0.4 then return 0.6, 0 end; return 3.5, 7 end,
		anim = function(k, A) A.leg("O", -0.7 * kBump(k, 0.05, 0.4), kLerp(-1.0, 0.6, kSeg(k, 0.1, 0.38)) * kBump(k, 0, 0.42), kBump(k, 0, 0.3)); A.arms(1.4); A.lean(0.35 * kBump(k, 0.4, 1)) end },
	{ key = "mcgeady", name = "Spin McGeady", stars = 4, dur = 0.6,
		v = function(k) if k < 0.4 then return 1, 0 end; return 2, 7.5 end,
		ball = function(k) return 0.6 - 0.8 * kBump(k, 0.1, 0.6), 0.2 * kBump(k, 0.3, 0.8), 0 end,
		anim = function(k, A) A.spin(TAU * kSm(k)); A.leg("L", 0, 0.5 * kBump(k, 0, 0.5) - 0.4 * kBump(k, 0.3, 0.6), 0.4); A.crouch(0.1) end },
	{ key = "okocha", name = "Coup d’Okocha", stars = 4, dur = 0.6,
		v = function(k) if k < 0.25 then return 1.5, -1.5 end; return 3, 6.5 end,
		ball = function(k) return 0.55, -0.3 + 0.7 * kSm(kSeg(k, 0.2, 0.55)), 0.45 * kBump(k, 0.2, 0.55) end,
		anim = function(k, A)
			A.leg("O", 0.6 * kBump(k, 0, 0.25), 0.5 * kBump(k, 0, 0.25), 0.5)
			A.leg("L", -0.3 * kBump(k, 0.2, 0.5), 0.5 * kBump(k, 0.2, 0.5), kBump(k, 0.2, 0.5))
			A.arms(1.3)
		end },
	{ key = "bolasie", name = "Flick Bolasie", stars = 4, dur = 0.55,
		v = function(k) if k < 0.35 then return 1.5, 2 end; return 5, 3 end,
		ball = function(k) return 0.4 + 0.4 * kSm(kSeg(k, 0.35, 0.7)), 0.3 * kBump(k, 0, 0.4), 0.2 * kBump(k, 0.35, 0.7) end,
		anim = function(k, A) A.leg("O", 0.6 * kBump(k, 0, 0.35), 0.5 * kBump(k, 0, 0.35), 0.5); A.leg("L", 0, -0.5 * kBump(k, 0.35, 0.7), 1.4 * kBump(k, 0.35, 0.7)) end },
	{ key = "sombrero", name = "Sombrero", stars = 4, dur = 0.62, knock = { at = 0.32, v = { 6.2, 0, 5.2 } },
		v = function(k) if k < 0.32 then return 1.5, 0 end; return 6.2, 0 end,
		ball = function(k) return 0.5, 0, 0.35 * kSeg(k, 0, 0.3) end,
		anim = function(k, A) A.leg("L", 0, 0.4 + 0.6 * kBump(k, 0.15, 0.4), 0.6 * (1 - kSeg(k, 0.2, 0.4))); A.hop(0.05) end },
	{ key = "arcenciel", name = "Arc-en-ciel (Neymar)", stars = 5, dur = 0.75, knock = { at = 0.45, v = { 7, 0, 6.6 } },
		v = function(k) if k < 0.45 then return 2, 0 end; return 6.6, 0 end,
		ball = function(k) return 0.3 - 0.6 * kSm(kSeg(k, 0, 0.3)), 0, 0.5 * kSm(kSeg(k, 0.1, 0.42)) end,
		anim = function(k, A)
			A.leg("L", 0, -0.3 * kBump(k, 0, 0.3) - 0.6 * kBump(k, 0.25, 0.5), 0.6 + 1.6 * kBump(k, 0.25, 0.5))
			A.hop(0.25 * kBump(k, 0.3, 0.55))
			A.arms(1.4)
		end },
	{ key = "hocus", name = "Hocus-pocus", stars = 5, dur = 0.7,
		v = function(k) if k < 0.35 then return 1, -1 end; return 3, 7 end,
		ball = function(k) return 0.5 - 0.65 * kBump(k, 0.15, 0.55), -0.2 + 0.65 * kSm(kSeg(k, 0.2, 0.6)), 0 end,
		anim = function(k, A) A.leg("L", -0.7 * kBump(k, 0.1, 0.5), -0.6 * kBump(k, 0.1, 0.5), 1.4 * kBump(k, 0.1, 0.5)); A.lean(if k < 0.35 then -0.2 else 0.4); A.arms(1.3) end },
	{ key = "cuauhtemina", name = "Cuauhtemiña", stars = 5, dur = 0.75, airborne = true,
		v = function() return 3.5, 0.4 end,
		ball = function(k) return 0.08, 0, 0.12 + 0.6 * kBump(k, 0.15, 0.85) end,
		anim = function(k, A)
			local b = kBump(k, 0.1, 0.9)
			A.hop(0.6 * kBump(k, 0.15, 0.85))
			A.leg("L", -0.15, 0.3, 0.9 * b)
			A.leg("O", -0.15, 0.3, 0.9 * b)
			A.arms(1.5)
		end },
	{ key = "tornade", name = "Tornade", stars = 5, dur = 0.75, airborne = true,
		v = function() return 3.5, 4 end,
		ball = function(k) return 0.45, 0.2 * math.sin(TAU * kSm(kSeg(k, 0.15, 0.85))), 0.35 * kBump(k, 0.15, 0.85) end,
		anim = function(k, A) A.spin(TAU * kSm(kSeg(k, 0.15, 0.85))); A.hop(0.4 * kBump(k, 0.15, 0.85)); A.arms(1.6); A.leg("L", 0, 0.4, 0.6) end },
	{ key = "otarie", name = "Dribble de l’otarie (Kerlon)", stars = 5, dur = 1.3, at = 0.55, airborne = true,
		v = function() return 5.2, 0 end,
		ball = function(k)
			local z = if k < 0.08 then kLerp(0.2, 1.9, k / 0.08)
				elseif k > 0.9 then kLerp(1.9, 0.1, (k - 0.9) / 0.1)
				else 1.85 + 0.3 * math.abs(math.sin(k * PI * 9))
			return 0.12, 0, z
		end,
		anim = function(k, A) A.bend(-0.18); A.hop(0.06 * math.abs(math.sin(k * PI * 9))); A.arms(0.9) end },
}

Dribbles.list = MOVES
Dribbles.byKey = {} :: { [string]: Move }
for _, m in MOVES do Dribbles.byKey[m.key] = m end

-- When the outcome is decided (fraction of the move)
function Dribbles.decideAt(m: Move): number
	if m.knock then return m.knock.at end
	return m.at or 0.5
end

-- Chance of success, 0 to 1 (web game's formula without the players' ratings): harder moves and a defender close
-- by make it less likely. `oppDist` in metres (nil: nobody near)
function Dribbles.chance(m: Move, oppDist: number?, stamina: number?): number
	local pressure = if oppDist then math.clamp((5 - oppDist) / 5, 0, 1) else 0
	local c = 0.97 - (m.stars - 1) * 0.08 - pressure * 0.32 - pressure * 0.21 - (1 - (stamina or 1)) * 0.3
	return math.clamp(c, 0, 1)
end

-- Result from the chance and a roll: 0 missed, 1 half (keeps the ball, defender not beaten), 2 success, 3 perfect
function Dribbles.quality(c: number, r: number): number
	if r < c then return if (c - r) / math.max(c, 1e-3) > 0.55 then 3 else 2 end
	return if (r - c) / math.max(1 - c, 1e-3) < 0.4 then 1 else 0
end

Dribbles.RESULT = { [0] = "Raté", [1] = "À moitié", [2] = "Réussi", [3] = "Parfait" }

-- Picks a move: all of them with a defender close, otherwise those that do not need one; easy moves more often
function Dribbles.pick(rng: Random, defenderNear: boolean): Move
	local pool, weights, total = {}, {}, 0
	for _, m in MOVES do
		if m.needDef and not defenderNear then continue end
		local w = if m.stars <= 2 then 3 elseif m.stars == 3 then 2 elseif m.stars == 4 then 1 else 0.6
		table.insert(pool, m)
		table.insert(weights, w)
		total += w
	end
	local pick = rng:NextNumber() * total
	for i, m in pool do
		pick -= weights[i]
		if pick <= 0 then return m end
	end
	return pool[1]
end

-- The move's body animation at k, collected: spin (radians), lean, bend, hop and crouch (metres), legs, arms
export type Pose = { spin: number, lean: number, bend: number, hop: number, crouch: number, legs: { { any } }, arms: { number }? }
function Dribbles.pose(m: Move, k: number): Pose
	local o: Pose = { spin = 0, lean = 0, bend = 0, hop = 0, crouch = 0, legs = {}, arms = nil }
	local A: Anim = {
		spin = function(a) o.spin = a end,
		lean = function(a) o.lean = a end,
		bend = function(a) o.bend = a end,
		hop = function(y) o.hop = y end,
		crouch = function(c) o.crouch = c end,
		leg = function(w, side, fwd, knee) table.insert(o.legs, ({ w, side, fwd, knee } :: { any })) end,
		arms = function(out, fwd) o.arms = { out, fwd or 0 } end,
	}
	m.anim(k, A)
	return o
end

return Dribbles
