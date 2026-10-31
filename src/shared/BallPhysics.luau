-- Ball flight and roll, ported from the web game's ballPhysics: gravity, quadratic drag with the drag crisis,
-- Magnus curl (side spin) and dip (top spin), bounces, then turf drag plus rolling resistance on the ground.
-- Shared so the server runs the real ball and each client can carry it on smoothly between snapshots.
local Config = require(script.Parent.Config)

local G = Config.G
local BOUNCE = 0.5
local FRIC = 0.95 -- turf drag factor (dry grass)
local ROLL = 0.95 -- rolling resistance, m/s²

local BallPhysics = {}

local function magK(v: number): number
	return math.clamp(v / 18, 0.3, 1.7) * (0.45 + math.clamp((27 - v) / 11, 0, 1))
end

export type Ball = { x: number, y: number, z: number, vx: number, vy: number, vz: number, spin: number, tspin: number }

function BallPhysics.step(b: Ball, dt: number)
	b.vz -= G * dt
	b.z += b.vz * dt
	local airborne = b.z > 0.05
	if airborne and b.tspin ~= 0 then
		b.vz -= b.tspin * 4.5 * magK(math.sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)) * dt
	end
	if b.z <= 0 then
		b.z = 0
		if b.vz < -1.8 then
			b.vz = -b.vz * BOUNCE * (1 - math.max(0, b.tspin) * 0.15)
			local sk = 0.72 * math.clamp(1 + b.tspin * 0.22, 0.6, 1.25)
			b.vx *= sk
			b.vy *= sk
			b.tspin *= 0.5
		else
			b.vz = 0
		end
	end
	local sp = math.sqrt(b.vx * b.vx + b.vy * b.vy)
	if b.spin ~= 0 and sp > 2 then
		local mk = if airborne then magK(math.sqrt(sp * sp + b.vz * b.vz)) else 1
		local ax, ay = -b.vy / sp * b.spin * mk * dt, b.vx / sp * b.spin * mk * dt
		b.vx += ax
		b.vy += ay
	end
	if airborne then
		-- F = ½·ρ·Cd·A·|v|²; Cd drops from 0.45 to 0.22 above about 15 m/s
		local vr = math.sqrt(b.vx * b.vx + b.vy * b.vy + b.vz * b.vz)
		local cd = 0.22 + 0.23 * math.clamp((18 - vr) / 8, 0, 1)
		local kd = 0.0271 * cd * vr * dt
		b.vx -= b.vx * kd
		b.vy -= b.vy * kd
		b.vz -= b.vz * kd
	end
	b.spin *= math.exp(-dt * (if airborne then 0.3 else 3))
	if not airborne then
		b.tspin *= math.exp(-dt * 1.2)
		local tsp = math.clamp(b.tspin, -1, 1)
		local f = math.exp(-FRIC * 0.58 * (1 - tsp * 0.35) * dt)
		b.vx *= f
		b.vy *= f
		local sp0 = math.sqrt(b.vx * b.vx + b.vy * b.vy)
		local cr = ROLL * (1 - tsp * 0.3) * dt
		if sp0 > cr then
			b.vx -= b.vx / sp0 * cr
			b.vy -= b.vy / sp0 * cr
		else
			b.vx, b.vy = 0, 0
		end
	end
	if b.z == 0 and math.sqrt(b.vx * b.vx + b.vy * b.vy) < 0.3 then
		b.vx, b.vy = 0, 0
	end
	b.x += b.vx * dt
	b.y += b.vy * dt
end

-- Steps in small slices so fast shots behave the same at any frame rate
function BallPhysics.advance(b: Ball, dt: number)
	local n = math.max(1, math.ceil(dt / (1 / 120)))
	local h = dt / n
	for _ = 1, n do
		BallPhysics.step(b, h)
	end
end

-- Ground pass: kick speed that brings the ball to distance d still rolling at va, and the travel time
-- (rolling model dv/dt = -k v - c, as above)
function BallPhysics.groundPass(d: number, va: number): (number, number)
	local k, c = FRIC * 0.58, ROLL
	local ck = c / k
	local function at(v0: number): (number, number)
		local t = math.log((v0 + ck) / (va + ck)) / k
		return (v0 - va) / k - ck * t, t
	end
	local lo, hi = va, 40
	for _ = 1, 30 do
		local mid = (lo + hi) / 2
		if at(mid) < d then lo = mid else hi = mid end
	end
	local _, t = at(hi)
	return math.min(hi, 28), t
end

-- Speed a pass should arrive at: soft when short, firmer over distance
function BallPhysics.passArrive(d: number): number
	return math.clamp(5 + d * 0.12, 5.5, 9)
end

-- Height at the goal line for a shot of this power (0..1)
function BallPhysics.shotHeight(power: number): number
	return 0.15 + math.clamp(power, 0, 1) ^ 1.5 * 1.75
end

return BallPhysics
