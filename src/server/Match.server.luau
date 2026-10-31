-- FC27 on Roblox: the server referees the match. It owns the ball (ported physics), the score and the clock,
-- runs the computer players and applies what each human asks for (pass, shot, lob, through ball, tackle).
-- Every human player is one footballer of his team; computer players fill both sides up to eleven.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BallPhysics = require(Shared.BallPhysics)
local Pitch = require(script.Parent.Pitch)
local Rig = require(script.Parent.Rig)

local M, L, W, G = Config.M, Config.L, Config.W, Config.G
local GH, BAR = Config.GOAL_HALF, Config.BAR
local toWorld, toPitch = Config.toWorld, Config.toPitch
local rng = Random.new()

-- ---------- Teams, network objects, stadium ----------
for _, t in Config.TEAMS do
	if not Teams:FindFirstChild(t.name) then
		local team = Instance.new("Team")
		team.Name = t.name
		team.TeamColor = BrickColor.new(t.brick)
		team.AutoAssignable = false
		team.Parent = Teams
	end
end

local Net = Instance.new("Folder")
Net.Name = "Net"
local function remote(name: string, unreliable: boolean?): Instance
	local r: Instance
	if unreliable then
		local ok, u = pcall(Instance.new, "UnreliableRemoteEvent")
		r = if ok then u else Instance.new("RemoteEvent")
	else
		r = Instance.new("RemoteEvent")
	end
	r.Name = name
	r.Parent = Net
	return r
end
local Action = remote("Action") :: RemoteEvent
local BallState = remote("BallState", true) :: any
local Message = remote("Message") :: RemoteEvent
Net.Parent = ReplicatedStorage

Pitch.build()
local botFolder = Instance.new("Folder")
botFolder.Name = "Bots"
botFolder.Parent = workspace

-- ---------- Match state ----------
local score = { 0, 0 }
local dir = { 1, -1 } -- team 1 attacks towards x = 105 in the first half
local clock, half = 0, 1
local phase = "waiting" -- waiting, set, play, goal, break, done
local phaseT = 0
local setTaker = nil
local setKindNow = nil

local function publish()
	Net:SetAttribute("Score1", score[1])
	Net:SetAttribute("Score2", score[2])
	Net:SetAttribute("Clock", math.floor(clock))
	Net:SetAttribute("Half", half)
	Net:SetAttribute("Phase", phase)
	Net:SetAttribute("Dir1", dir[1])
end

local function say(text: string, sub: string?, dur: number?)
	Message:FireAllClients(text, sub or "", dur or 2)
end

local function oppGoalX(t: number): number return if dir[t] > 0 then L else 0 end
local function ownGoalX(t: number): number return if dir[t] > 0 then 0 else L end

-- ---------- Footballers (humans and computer players) ----------
type Actor = {
	team: number, slot: number, role: string, num: number, name: string,
	player: Player?, model: Model?, hum: Humanoid?, root: BasePart?,
	cool: number, stun: number, decT: number, holdT: number, diveT: number, moveT: number, lastTarget: Vector3?,
}
local actors: { Actor } = {}

local function homeOf(a: Actor): (number, number)
	local f = Config.FORMATION[a.slot]
	if dir[a.team] > 0 then return f[1], f[2] end
	return L - f[1], W - f[2]
end

local function posOf(a: Actor): (number, number)
	if not a.root then return homeOf(a) end
	local x, y = toPitch(a.root.Position)
	return x, y
end

local function velOf(a: Actor): (number, number)
	if not a.root then return 0, 0 end
	local v = a.root.AssemblyLinearVelocity
	return v.X / M, v.Z / M
end

local function facingOf(a: Actor): (number, number)
	if not a.root then return dir[a.team], 0 end
	local lv = a.root.CFrame.LookVector
	local n = math.sqrt(lv.X * lv.X + lv.Z * lv.Z)
	if n < 1e-3 then return dir[a.team], 0 end
	return lv.X / n, lv.Z / n
end

local function place(a: Actor, x: number, y: number)
	if a.model and a.root then
		local p = toWorld(x, y, 0) + Vector3.new(0, 3, 0)
		local fx = dir[a.team]
		a.model:PivotTo(CFrame.lookAt(p, p + Vector3.new(fx, 0, 0)))
		a.root.AssemblyLinearVelocity = Vector3.zero
		if a.hum and not a.player then a.hum:MoveTo(p) end
	end
end

local function attach(a: Actor, model: Model)
	a.model = model
	a.hum = model:FindFirstChildOfClass("Humanoid")
	local r = model:FindFirstChild("HumanoidRootPart")
	a.root = if r and r:IsA("BasePart") then r else nil
end

local function spawnBot(a: Actor)
	local model = Rig.createBot(a.name, a.team, a.num, rng)
	model.Parent = botFolder
	attach(a, model)
	local hx, hy = homeOf(a)
	place(a, hx, hy)
	if a.root then pcall(function() (a.root :: BasePart):SetNetworkOwner(nil) end) end
	if a.hum then a.hum.WalkSpeed = Config.WALK end
end

local nameBag = table.clone(Config.NAMES)
for t = 1, 2 do
	for slot, f in Config.FORMATION do
		local name = table.remove(nameBag, rng:NextInteger(1, #nameBag)) or ("Joueur " .. f[4])
		local a: Actor = { team = t, slot = slot, role = f[3], num = f[4], name = name, cool = 0, stun = 0, decT = 0, holdT = 0, diveT = 0, moveT = 0 }
		table.insert(actors, a)
		spawnBot(a)
	end
end

local function actorOfPlayer(pl: Player): Actor?
	for _, a in actors do if a.player == pl then return a end end
	return nil
end

local function humansIn(t: number): number
	local n = 0
	for _, a in actors do if a.team == t and a.player then n += 1 end end
	return n
end

-- ---------- Ball ----------
local ball: BallPhysics.Ball = { x = L / 2, y = W / 2, z = 0, vx = 0, vy = 0, vz = 0, spin = 0, tspin = 0 }
local owner: Actor? = nil
local held = false -- a goalkeeper has it in his hands
local lastTouch: Actor? = nil
local shotBy: number? = nil -- team of the last shot, while it flies
local target: Actor? = nil -- intended receiver of the last pass

local function resetBall(x: number, y: number)
	ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz, ball.spin, ball.tspin = x, y, 0, 0, 0, 0, 0, 0
	owner, held, shotBy, target = nil, false, nil, nil
end

local function gauss(): number
	return math.sqrt(-2 * math.log(math.max(1e-9, rng:NextNumber()))) * math.cos(2 * math.pi * rng:NextNumber())
end

local function kickBall(a: Actor, vx: number, vy: number, vz: number, spin: number?)
	if phase == "set" then phase = "play" end
	owner, held = nil, false
	local fx, fy = facingOf(a)
	local x, y = posOf(a)
	ball.x, ball.y = x + fx * 0.7, y + fy * 0.7
	ball.z = math.max(ball.z, 0.11)
	ball.vx, ball.vy, ball.vz, ball.spin, ball.tspin = vx, vy, vz, spin or 0, 0
	a.cool = 0.35
	lastTouch = a
	shotBy, target = nil, nil
end

local function giveBall(a: Actor)
	owner = a
	held = false
	lastTouch = a
	shotBy, target = nil, nil
	ball.vx, ball.vy, ball.vz, ball.z = 0, 0, 0, 0
end

local function dist2(ax: number, ay: number, bx: number, by: number): number
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

local function segDist(ox: number, oy: number, ax: number, ay: number, bx: number, by: number): number
	local abx, aby = bx - ax, by - ay
	local l2 = abx * abx + aby * aby
	if l2 == 0 then l2 = 1 end
	local t = math.clamp(((ox - ax) * abx + (oy - ay) * aby) / l2, 0, 1)
	return dist2(ax + abx * t, ay + aby * t, ox, oy)
end

-- Best team-mate for a pass, in a direction (dx, dy) or anywhere (nil): aligned, open, not too far
local function bestPass(a: Actor, dx: number?, dy: number?, minAlign: number?): Actor?
	local px, py = posOf(a)
	local best, bestS = nil, -math.huge
	for _, m in actors do
		if m.team ~= a.team or m == a or not m.root then continue end
		local mx, my = posOf(m)
		local ox, oy = mx - px, my - py
		local d = math.sqrt(ox * ox + oy * oy)
		if d < 4 or d > 48 then continue end
		local align = 0
		if dx and dy then
			align = (ox * dx + oy * dy) / d
			if align < (minAlign or 0.4) then continue end
		elseif m.role == "GK" then
			continue
		end
		local open = 6
		for _, o in actors do
			if o.team == a.team or not o.root then continue end
			local qx, qy = posOf(o)
			open = math.min(open, segDist(qx, qy, px, py, mx, my) * 1.2, dist2(qx, qy, mx, my))
		end
		local s
		if dx then
			s = align * 20 + open * 1.0 - math.max(0, d - 25) * 0.15
		else
			s = ox * dir[a.team] * 0.35 + open * 1.6 - d * 0.12 + (if m.role == "FW" then 1 else 0)
			if open < 1.3 then s -= 8 end
		end
		if s > bestS then best, bestS = m, s end
	end
	return best
end

-- Ground pass into the receiver's run, weighted so it reaches him at a comfortable speed
local function passTo(a: Actor, m: Actor)
	local px, py = posOf(a)
	local mx, my = posOf(m)
	local mvx, mvy = velOf(m)
	local lead = 0.6
	local tx, ty, d, v = mx, my, 0, 0
	for _ = 1, 2 do
		tx, ty = math.clamp(mx + mvx * lead, 1, L - 1), math.clamp(my + mvy * lead, 1, W - 1)
		d = dist2(px, py, tx, ty)
		local t
		v, t = BallPhysics.groundPass(d, BallPhysics.passArrive(d))
		lead = math.min(1.6, t)
	end
	local ang = math.atan2(ty - py, tx - px) + gauss() * 0.02
	kickBall(a, math.cos(ang) * v, math.sin(ang) * v, 0)
	target = m
end

-- Launch speed so a lofted ball covering d metres lands there despite the drag (vz fixed)
local function lobSpeed(d: number, vz: number): number
	local vh = d / (2 * vz / G)
	for _ = 1, 5 do
		local b = { x = 0, y = 0, z = 0.11, vx = vh, vy = 0, vz = vz, spin = 0, tspin = 0 }
		local t = 0
		repeat
			BallPhysics.step(b, 1 / 60)
			t += 1 / 60
		until (b.z <= 0 and t > 0.1) or t > 6
		if b.x > 0.5 then vh *= d / b.x end
	end
	return vh
end

local function lobTo(a: Actor, tx: number, ty: number, d: number, vz: number)
	local px, py = posOf(a)
	local vh = lobSpeed(d, vz)
	local ang = math.atan2(ty - py, tx - px) + gauss() * 0.03
	kickBall(a, math.cos(ang) * vh, math.sin(ang) * vh, vz)
end

local function doPass(a: Actor, dx: number, dy: number)
	local m = bestPass(a, dx, dy) or bestPass(a, dx, dy, -0.2) or bestPass(a, nil, nil)
	if m then passTo(a, m) else kickBall(a, dx * 14, dy * 14, 0) end
end

local function doThrough(a: Actor, dx: number, dy: number)
	local px, py = posOf(a)
	local best, bs = nil, -math.huge
	for _, m in actors do
		if m.team ~= a.team or m == a or m.role == "GK" or m.role == "DF" or not m.root then continue end
		local mx, my = posOf(m)
		local ox, oy = mx - px, my - py
		local d = math.sqrt(ox * ox + oy * oy)
		if d < 5 or d > 40 then continue end
		local align = (ox * dx + oy * dy) / d
		local fwd = ox * dir[a.team]
		local s = align * 10 + fwd * 0.3
		if align > 0.2 and s > bs then best, bs = m, s end
	end
	if not best then doPass(a, dx, dy) return end
	local mx, my = posOf(best)
	local mvx, mvy = velOf(best)
	local tx = math.clamp(mx + dir[a.team] * rng:NextNumber(7, 11) + mvx * 0.4, 2, L - 2)
	local ty = math.clamp(my + (W / 2 - my) * 0.15 + mvy * 0.4, 2, W - 2)
	local d = dist2(px, py, tx, ty)
	local v = math.clamp(d * 0.78 + 5, 9, 24)
	local ang = math.atan2(ty - py, tx - px) + gauss() * 0.03
	kickBall(a, math.cos(ang) * v, math.sin(ang) * v, 0)
	target = best
end

local function doShoot(a: Actor, dx: number, dy: number, power: number)
	local px, py = posOf(a)
	local gx = oppGoalX(a.team)
	local gd = dist2(px, py, gx, W / 2)
	-- Facing away from goal or far out: just a big kick where he faces
	if (dx * (gx - px) + dy * (W / 2 - py)) / gd < -0.2 or gd > 45 then
		local v = 15 + power * 19
		kickBall(a, dx * v, dy * v, 0.8 + power * power * 5)
		return
	end
	-- Pushing left or right picks the corner, otherwise a little random
	local side = if math.abs(dy) > 0.3 then math.clamp(dy * 1.15, -1, 1) else gauss() * 0.25
	local ty = W / 2 + side * (GH - 0.55)
	local tz = BallPhysics.shotHeight(power)
	local v = (13 + power * 23) * (0.94 + rng:NextNumber() * 0.08)
	local D = dist2(px, py, gx, ty)
	local T = D / (v * 0.9)
	local vz = math.clamp((tz - 0.11) / T + G * T / 2, -2, v * 0.8) + gauss() * power * power * 1.2
	local vh = math.sqrt(math.max(1, v * v - vz * vz))
	local err = (0.012 + power * power * 0.04) * (1 + math.max(0, gd - 20) * 0.03)
	local ang = math.atan2(ty - py, gx - px) + gauss() * err
	kickBall(a, math.cos(ang) * vh, math.sin(ang) * vh, vz)
	shotBy = a.team
	say("Tir !", a.name, 0.8)
end

-- Lob: the longer it was held, the further and higher. A team-mate running into the landing spot gets it
local function doLob(a: Actor, dx: number, dy: number, power: number)
	local px, py = posOf(a)
	local far = 12 + power * 40
	local lx, ly = px + dx * far, py + dy * far
	local tgt, bestE = nil, math.max(7, far * 0.25)
	for _, m in actors do
		if m.team ~= a.team or m == a or m.role == "GK" or not m.root then continue end
		local mx, my = posOf(m)
		local mvx, mvy = velOf(m)
		local ahead = (mx - px) * dx + (my - py) * dy
		local e = dist2(mx + mvx * 1.2, my + mvy * 1.2, lx, ly)
		if ahead > 4 and e < bestE then tgt, bestE = m, e end
	end
	if tgt then
		local mx, my = posOf(tgt)
		local mvx, mvy = velOf(tgt)
		local tx, ty = mx + mvx * 1.3, my + mvy * 1.3
		local d = dist2(px, py, tx, ty) * 0.9
		lobTo(a, tx, ty, d, math.clamp(5 + d * 0.17, 6, 13))
		target = tgt
	else
		lobTo(a, lx, ly, far, 6 + power * 8)
	end
end

local function stunActor(a: Actor, t: number)
	a.stun = t
	if a.model then a.model:SetAttribute("StunUntil", workspace:GetServerTimeNow() + t) end
end

local function doTackle(a: Actor)
	if not owner or owner.team == a.team or held then return end
	local px, py = posOf(a)
	local ox, oy = posOf(owner)
	if dist2(px, py, ox, oy) > 2.3 then
		stunActor(a, 0.4)
		return
	end
	if rng:NextNumber() < 0.55 then
		local victim = owner :: Actor
		stunActor(victim, 0.7)
		victim.cool = 0.6
		local fx, fy = facingOf(a)
		owner = nil
		ball.x, ball.y = ox, oy
		ball.vx, ball.vy, ball.vz = fx * 4, fy * 4, 0
		lastTouch = a
		a.cool = 0.1
		say("Tacle réussi !", a.name, 0.9)
	else
		stunActor(a, 0.6)
	end
end

-- ---------- Restarts ----------
local function nearestOf(t: number, x: number, y: number, preferHuman: boolean?): Actor?
	local best, bd = nil, math.huge
	for _, a in actors do
		if a.team ~= t or a.role == "GK" or not a.root then continue end
		local ax, ay = posOf(a)
		local d = dist2(ax, ay, x, y) - (if preferHuman and a.player then 12 else 0)
		if d < bd then best, bd = a, d end
	end
	return best
end

local function setPiece(kind: string, t: number, x: number, y: number, taker: Actor?)
	resetBall(x, y)
	local tk = taker or nearestOf(t, x, y, true)
	if not tk then return end
	-- Behind the ball, facing the pitch
	local ax, ay = x - dir[t] * 0.8, y
	if kind == "throw" then ay = if y < W / 2 then y - 0.6 else y + 0.6 end
	place(tk, ax, ay)
	giveBall(tk)
	ball.x, ball.y = x, y
	phase, phaseT, setTaker, setKindNow = "set", 0, tk, kind
	publish()
end

local function kickoff(t: number)
	for _, a in actors do
		local hx, hy = homeOf(a)
		-- Everybody in his own half for the kick-off
		hx = if dir[a.team] > 0 then math.min(hx, L / 2 - 1.5) else math.max(hx, L / 2 + 1.5)
		place(a, hx, hy)
		a.stun, a.cool, a.diveT = 0, 0, 0
	end
	local tk = nearestOf(t, L / 2, W / 2, true)
	if tk then place(tk, L / 2 - dir[t] * 0.8, W / 2) end
	setPiece("kickoff", t, L / 2, W / 2, tk)
	say("Coup d’envoi", Config.TEAMS[t].name, 1.5)
end

local function goalFor(t: number)
	score[t] += 1
	local scorer = if lastTouch and lastTouch.team == t then lastTouch.name else "contre son camp"
	phase, phaseT = "goal", 0
	owner, held, shotBy = nil, false, nil
	publish()
	say("BUT !", Config.TEAMS[t].name .. " · " .. scorer, 3.5)
	Net:SetAttribute("LastGoalTeam", t)
end

-- Ball over a line: goal, corner, goal kick or throw-in
local function checkBounds(prevX: number)
	local crossed = (ball.x < 0 and prevX >= 0) or (ball.x > L and prevX <= L)
	local off = math.abs(ball.y - W / 2)
	-- Posts and crossbar
	if crossed and ball.z < BAR + 0.15 and math.abs(off - GH) < 0.15 then
		ball.vx = -ball.vx * 0.6
		ball.x = if ball.x < 0 then 0.05 else L - 0.05
		say("Poteau !", nil, 1)
		return
	end
	if crossed and off < GH and math.abs(ball.z - BAR) < 0.15 then
		ball.vx, ball.vz = -ball.vx * 0.5, math.abs(ball.vz) * 0.3
		ball.x = if ball.x < 0 then 0.05 else L - 0.05
		say("Transversale !", nil, 1)
		return
	end
	if ball.x < -0.17 or ball.x > L + 0.17 then
		local gx = if ball.x < 0 then 0 else L
		local defT = if ownGoalX(1) == gx then 1 else 2
		local attT = 3 - defT
		if off < GH and ball.z < BAR then
			goalFor(attT)
		elseif lastTouch and lastTouch.team == defT then
			say("Corner", Config.TEAMS[attT].name, 1.2)
			setPiece("corner", attT, if gx == 0 then 0.6 else L - 0.6, if ball.y < W / 2 then 0.6 else W - 0.6)
		else
			say("Six mètres", Config.TEAMS[defT].name, 1.2)
			local gk = nil
			for _, a in actors do if a.team == defT and a.role == "GK" then gk = a end end
			setPiece("goalkick", defT, if gx == 0 then 5.5 else L - 5.5, W / 2 + (if ball.y < W / 2 then -6 else 6), gk)
		end
	elseif ball.y < -0.17 or ball.y > W + 0.17 then
		local t = if lastTouch and lastTouch.team == 1 then 2 else 1
		say("Touche", Config.TEAMS[t].name, 1)
		setPiece("throw", t, math.clamp(ball.x, 1, L - 1), if ball.y < 0 then 0 else W)
	end
end

-- Inside the net after a goal: the ball dies against the netting
local function netContain()
	local inGoal = (ball.x < 0 or ball.x > L) and math.abs(ball.y - W / 2) < GH + 0.3
	if not inGoal then return end
	local back = if ball.x < 0 then -Config.GOAL_DEPTH else L + Config.GOAL_DEPTH
	if (ball.x < 0 and ball.x < back) or (ball.x > L and ball.x > back) then
		ball.x, ball.vx = back, -ball.vx * 0.15
	end
	if math.abs(ball.y - W / 2) > GH - 0.1 then ball.vy = -ball.vy * 0.3 end
	if ball.z > BAR - 0.1 then ball.z, ball.vz = BAR - 0.1, 0 end
end

-- ---------- Possession and keepers ----------
local function tryControl()
	if owner then return end
	local bsp = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
	local best, bd = nil, math.huge
	for _, a in actors do
		if a.cool > 0 or a.stun > 0 or not a.root then continue end
		local x, y = posOf(a)
		local d = dist2(x, y, ball.x, ball.y)
		if a.role == "GK" then
			local inBox = math.abs(x - ownGoalX(a.team)) < 16.5 and math.abs(y - W / 2) < 20.16
			local reach = if a.diveT > 0 then 2.6 else 1.7
			if inBox and d < reach and ball.z < 2.6 then
				-- A hard, well placed shot can beat him
				local chance = if shotBy and shotBy ~= a.team then math.clamp(0.95 - math.max(0, bsp - 14) * 0.03 - d * 0.08, 0.3, 0.95) else 1
				if rng:NextNumber() < chance then
					giveBall(a)
					held = true
					a.holdT = 1.3
					if shotBy then say("Arrêt !", a.name, 1) end
				else
					ball.vx = -ball.vx * 0.35 + gauss() * 2
					ball.vy = ball.vy * 0.5 + gauss() * 4
					ball.vz = math.abs(ball.vz) * 0.4 + 2
					a.cool = 0.6
					lastTouch = a
					shotBy = nil
				end
				return
			end
		end
		local reach = if a.player then 1.3 else 1.0
		if ball.z < 0.9 and d < reach and d < bd then best, bd = a, d end
		-- Header for a ball at head height coming at him
		if ball.z >= 0.9 and ball.z < 2.4 and d < 0.9 and bsp > 4 then
			local gx = oppGoalX(a.team)
			local gdx, gdy = gx - x, W / 2 + gauss() * 2 - y
			local gd = math.sqrt(gdx * gdx + gdy * gdy)
			local hx, hy
			if gd < 22 then hx, hy = gdx / gd, gdy / gd else hx, hy = facingOf(a) end
			local v = if gd < 22 then 13 else 10
			kickBall(a, hx * v, hy * v, if gd < 22 then 0.5 else 3)
			if gd < 22 then shotBy = a.team end
			return
		end
	end
	if best then giveBall(best) end
end

-- ---------- Computer players ----------
local function moveBot(a: Actor, x: number, y: number, speed: number)
	if not a.hum or not a.root then return end
	local p = toWorld(math.clamp(x, -2, L + 2), math.clamp(y, -2, W + 2), 0)
	a.hum.WalkSpeed = speed
	if not a.lastTarget or (a.lastTarget - p).Magnitude > 1.5 or a.moveT <= 0 then
		a.hum:MoveTo(p)
		a.lastTarget = p
		a.moveT = 1
	end
end

local function chaserOf(t: number): Actor?
	-- The computer player nearest the ball goes for it, unless a human team-mate is closer
	local best, bd = nil, math.huge
	for _, a in actors do
		if a.team ~= t or a.role == "GK" or not a.root or a.stun > 0 then continue end
		local x, y = posOf(a)
		local d = dist2(x, y, ball.x + ball.vx * 0.3, ball.y + ball.vy * 0.3)
		if d < bd then best, bd = a, d end
	end
	if best and best.player then return nil end
	return best
end

local function botWithBall(a: Actor, dt: number)
	local x, y = posOf(a)
	local d = dir[a.team]
	if held then
		a.holdT -= dt
		if a.holdT <= 0 then
			local m = bestPass(a, nil, nil)
			if m and rng:NextNumber() < 0.6 then passTo(a, m) else doLob(a, d, gauss() * 0.3, 0.75) end
		end
		moveBot(a, x, y, 0)
		return
	end
	if phase == "set" then
		moveBot(a, x, y, 0) -- the restart is taken after a short pause, in the main loop
		return
	end
	a.decT -= dt
	if a.decT <= 0 then
		a.decT = rng:NextNumber(0.3, 0.6)
		local gx = oppGoalX(a.team)
		local gd = dist2(x, y, gx, W / 2)
		local pressure = math.huge
		for _, o in actors do
			if o.team ~= a.team and o.root then
				local ox, oy = posOf(o)
				pressure = math.min(pressure, dist2(x, y, ox, oy))
			end
		end
		if gd < 24 and (gx - x) * d > 4 then
			local gdx, gdy = (gx - x) / gd, (W / 2 + gauss() * 2.5 - y) / gd
			doShoot(a, gdx, gdy, rng:NextNumber(0.55, 0.85))
			return
		end
		if pressure < 3.5 or rng:NextNumber() < 0.15 then
			local m = bestPass(a, d, 0, -0.1) or bestPass(a, nil, nil)
			if m then passTo(a, m) return end
		end
		if rng:NextNumber() < 0.06 then doThrough(a, d, 0) return end
	end
	moveBot(a, x + d * 8, y + (W / 2 - y) * 0.15, 19)
end

local function keeper(a: Actor, dt: number)
	local gx = ownGoalX(a.team)
	local d = dir[a.team]
	local x, y = posOf(a)
	a.diveT = math.max(0, a.diveT - dt)
	-- Shot coming: go for the point where it crosses the line
	if shotBy and shotBy ~= a.team and (gx - ball.x) * ball.vx > 0 and math.abs(ball.vx) > 3 then
		local t = (gx + d * 0.6 - ball.x) / ball.vx
		local yc = ball.y + ball.vy * t
		if t > 0 and t < 1.2 and math.abs(yc - W / 2) < GH + 1.5 then
			if t < 0.55 and a.diveT <= 0 and math.abs(yc - y) > 0.8 then a.diveT = 0.6 end
			moveBot(a, gx + d * 0.6, math.clamp(yc, W / 2 - GH - 0.5, W / 2 + GH + 0.5), if a.diveT > 0 then 34 else 24)
			if a.diveT > 0 and a.root then
				-- The dive: a quick lunge sideways
				local step = math.clamp(yc - y, -9 * dt, 9 * dt)
				a.root.CFrame += Vector3.new(0, 0, step * M)
			end
			return
		end
	end
	local ballClose = dist2(ball.x, ball.y, gx, W / 2) < 18
	if not owner and ballClose and math.abs(ball.vx) + math.abs(ball.vy) < 8 then
		moveBot(a, ball.x, ball.y, 22)
		return
	end
	local ty = math.clamp(W / 2 + (ball.y - W / 2) * 0.25, W / 2 - GH + 0.8, W / 2 + GH - 0.8)
	moveBot(a, gx + d * (1.5 + (if ballClose then 1.5 else 0)), ty, 16)
end

local function botThink(a: Actor, dt: number)
	if not a.root or not a.hum then return end
	a.moveT -= dt
	local x, y = posOf(a)
	if a.stun > 0 then moveBot(a, x, y, 0) return end
	if owner == a then botWithBall(a, dt) return end
	if a.role == "GK" then keeper(a, dt) return end
	local t = a.team
	local d = dir[t]
	local hx, hy = homeOf(a)
	local attacking = owner ~= nil and (owner :: Actor).team == t
	-- Opponents keep their distance at a restart
	if phase == "set" and setTaker and setTaker.team ~= t then
		local tx = hx + (ball.x - L / 2) * 0.5
		local ty = hy + (ball.y - W / 2) * 0.3
		local dd = dist2(tx, ty, ball.x, ball.y)
		if dd < 9.5 then
			tx = ball.x + (tx - ball.x) / math.max(dd, 0.1) * 9.5
			ty = ball.y + (ty - ball.y) / math.max(dd, 0.1) * 9.5
		end
		moveBot(a, tx, ty, Config.WALK)
		return
	end
	if phase == "play" and (not owner or (owner :: Actor).team ~= t) and (chaserOf(t) == a or target == a) then
		local px, py = ball.x + ball.vx * 0.35, ball.y + ball.vy * 0.35
		moveBot(a, px, py, 21)
		-- Tackle when close to an opponent with the ball
		if owner and (owner :: Actor).team ~= t and a.cool <= 0 and not held then
			local ox, oy = posOf(owner :: Actor)
			if dist2(x, y, ox, oy) < 1.5 and rng:NextNumber() < 1.2 * dt then
				local succ = if (owner :: Actor).player then 0.42 else 0.5
				if rng:NextNumber() < succ then
					local victim = owner :: Actor
					stunActor(victim, 0.6)
					victim.cool = 0.6
					giveBall(a)
				else
					a.cool = 0.8
				end
			end
		end
		return
	end
	-- Shape: follow the ball across the pitch, push up when the team has it
	local tx = math.clamp(hx + (ball.x - L / 2) * 0.55 + (if attacking then d * 7 else 0), 3, L - 3)
	local ty = math.clamp(hy + (ball.y - W / 2) * 0.3, 2, W - 2)
	local far = dist2(x, y, tx, ty)
	moveBot(a, tx, ty, if far > 8 then 19 else Config.WALK)
end

-- ---------- Humans ----------
local function assignPlayer(pl: Player)
	local t = if humansIn(1) <= humansIn(2) then 1 else 2
	if humansIn(t) >= Config.TEAM_SIZE - 1 then t = 3 - t end
	if humansIn(t) >= Config.TEAM_SIZE - 1 then return end -- both sides full: spectator
	-- Take over a computer player of that team (forwards first, never the keeper)
	local pick = nil
	for i = #actors, 1, -1 do
		local a = actors[i]
		if a.team == t and not a.player and a.role ~= "GK" then pick = a break end
	end
	if not pick then return end
	if pick.model then pick.model:Destroy() end
	pick.model, pick.hum, pick.root = nil, nil, nil
	pick.player = pl
	pick.name = pl.DisplayName
	pl.Team = Teams:FindFirstChild(Config.TEAMS[t].name) :: Team
	pl.Neutral = false
	local function onChar(char: Model)
		task.wait(0.3)
		if pick.player ~= pl then return end
		attach(pick, char)
		Rig.dress(char, t, pick.num)
		char:SetAttribute("Team", t)
		if pick.hum then pick.hum.WalkSpeed = Config.WALK end
		local hx, hy = homeOf(pick)
		place(pick, hx, hy)
	end
	pl.CharacterAdded:Connect(onChar)
	if pl.Character then task.spawn(onChar, pl.Character) end
	if phase == "waiting" then
		task.delay(2, function() if phase == "waiting" then kickoff(1) end end)
	end
end

Players.PlayerAdded:Connect(assignPlayer)
for _, pl in Players:GetPlayers() do task.spawn(assignPlayer, pl) end

Players.PlayerRemoving:Connect(function(pl)
	local a = actorOfPlayer(pl)
	if not a then return end
	if owner == a then owner = nil end
	a.player = nil
	a.name = Config.NAMES[rng:NextInteger(1, #Config.NAMES)]
	spawnBot(a)
	if #Players:GetPlayers() <= 1 then phase = "waiting" publish() end
end)

Action.OnServerEvent:Connect(function(pl: Player, kind: any, dx: any, dz: any, power: any)
	local a = actorOfPlayer(pl)
	if not a or type(kind) ~= "string" then return end
	if phase ~= "play" and phase ~= "set" then return end
	if a.stun > 0 then return end
	dx = if type(dx) == "number" and dx == dx then dx else 0
	dz = if type(dz) == "number" and dz == dz then dz else 0
	power = if type(power) == "number" and power == power then math.clamp(power, 0, 1) else 0.5
	local n = math.sqrt(dx * dx + dz * dz)
	local fx, fy
	if n > 0.1 then fx, fy = dx / n, dz / n else fx, fy = facingOf(a) end
	if kind == "tackle" then doTackle(a) return end
	if owner ~= a or held then return end
	if kind == "pass" then doPass(a, fx, fy)
	elseif kind == "through" then doThrough(a, fx, fy)
	elseif kind == "shoot" then doShoot(a, fx, fy, power)
	elseif kind == "lob" then doLob(a, fx, fy, power)
	end
end)

-- ---------- Main loop ----------
local sendT, aiT = 0, 0
local AI_DT = 0.1

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
	phaseT += dt
	for _, a in actors do
		a.cool = math.max(0, a.cool - dt)
		a.stun = math.max(0, a.stun - dt)
	end

	if phase == "play" or phase == "set" then
		clock += dt * 90 / (Config.MATCH_MINUTES * 60)
		if half == 1 and clock >= 45 then
			phase, phaseT = "break", 0
			resetBall(L / 2, W / 2)
			say("Mi-temps", Config.TEAMS[1].abbr .. " " .. score[1] .. " – " .. score[2] .. " " .. Config.TEAMS[2].abbr, 5)
		elseif half == 2 and clock >= 90 then
			phase, phaseT = "done", 0
			resetBall(L / 2, W / 2)
			local res = if score[1] == score[2] then "Match nul" elseif score[1] > score[2] then Config.TEAMS[1].name .. " gagnent" else Config.TEAMS[2].name .. " gagnent"
			say("Fin du match", res .. " · " .. score[1] .. " – " .. score[2], 8)
		end
	elseif phase == "goal" and phaseT > 4 then
		local conceded = if Net:GetAttribute("LastGoalTeam") == 1 then 2 else 1
		kickoff(conceded)
	elseif phase == "break" and phaseT > 6 then
		dir[1], dir[2] = -dir[1], -dir[2]
		half, clock = 2, 45
		kickoff(2)
	elseif phase == "done" and phaseT > 12 then
		score, half, clock, dir = { 0, 0 }, 1, 0, { 1, -1 }
		kickoff(1)
	end

	-- A computer player takes the restart after a short pause; a human has 10 s before it is played for him
	if phase == "set" and setTaker and owner == setTaker then
		local tk = setTaker :: Actor
		if (not tk.player and phaseT > 1.2) or (tk.player and phaseT > 10) then
			if setKindNow == "corner" then
				doLob(tk, (oppGoalX(tk.team) - ball.x) / 12, (W / 2 - ball.y) / 34, 0.55)
			elseif setKindNow == "goalkick" then
				doLob(tk, dir[tk.team], gauss() * 0.4, 0.8)
			else
				local m = bestPass(tk, nil, nil)
				if m then passTo(tk, m) else doPass(tk, dir[tk.team], 0) end
			end
		end
	end

	-- Ball
	if phase == "play" or phase == "set" or phase == "goal" then
		if owner then
			local a = owner :: Actor
			if not a.root then
				owner = nil
			else
				local x, y = posOf(a)
				local fx, fy = facingOf(a)
				local vx, vy = velOf(a)
				if held then
					ball.x, ball.y, ball.z = x + fx * 0.4, y + fy * 0.4, 1.0
				else
					ball.x, ball.y, ball.z = x + fx * 0.75, y + fy * 0.75, 0
				end
				ball.vx, ball.vy, ball.vz = vx, vy, 0
			end
		else
			local px = ball.x
			BallPhysics.advance(ball, dt)
			if phase == "play" then checkBounds(px) else netContain() end
			if target and math.sqrt(ball.vx ^ 2 + ball.vy ^ 2) < 1.2 then target = nil end
			if shotBy and math.sqrt(ball.vx ^ 2 + ball.vy ^ 2) < 6 then shotBy = nil end
		end
		if phase == "play" then tryControl() end
	end

	-- Computer players
	aiT += dt
	if aiT >= AI_DT then
		for _, a in actors do
			if a.player then continue end
			if phase == "play" or phase == "set" then
				botThink(a, aiT)
			elseif a.hum and a.root then
				local hx, hy = homeOf(a)
				moveBot(a, hx, hy, Config.WALK)
			end
			if a.model and a.root then
				local v = a.root.AssemblyLinearVelocity
				Rig.animate(a.model, Vector3.new(v.X, 0, v.Z).Magnitude)
			end
		end
		aiT = 0
	end

	-- Snapshot for the clients
	sendT += dt
	if sendT >= 1 / Config.SNAPSHOT_HZ then
		sendT = 0
		local o = owner and (owner :: Actor).model
		BallState:FireAllClients({ ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz, ball.spin, ball.tspin, if held then 1 else 0 }, o)
		Net:SetAttribute("Clock", math.floor(clock))
		Net:SetAttribute("Phase", phase)
	end
end)

publish()
