-- FC27 on Roblox: the server referees the match. It owns the ball (ported physics), the score and the clock,
-- runs the computer players and applies what each human asks for (pass, shot, lob, through ball, tackle).
-- Every human player is one footballer of his team; computer players fill both sides up to eleven.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Teams = game:GetService("Teams")
local PhysicsService = game:GetService("PhysicsService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local BallPhysics = require(Shared.BallPhysics)
local Assets = require(script.Parent.Assets)
local Pitch = require(script.Parent.Pitch)
local Rig = require(script.Parent.Rig)
local Dribbles = require(Shared.Dribbles)
-- Texts are sent as coded messages (Lang.L), shown in each player's language on his machine
local Lang = require(Shared.Lang)
local T = Lang.L
local TEAM, ABBR = Lang.team, Lang.abbr

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
local Economy = require(script.Parent.Economy)
local Shop = require(Shared.Shop)

Pitch.build(Assets.stadium)
Pitch.buildLobby()
-- Characters only appear once the pitch is there (Players.CharacterAutoLoads is off in the place file): the
-- server first loads the models, which takes a few seconds, and a character spawned before would fall
Players.CharacterAutoLoads = true
local botFolder = Instance.new("Folder")
botFolder.Name = "Bots"
botFolder.Parent = workspace

-- ---------- Match state ----------
local score = { 0, 0 }
-- Every goal with what led to it (read by the test hook at the bottom, for scripts/inspect/match.luau)
local goalLog: { { [string]: any } } = {}
local stats = { fouls = 0, penalties = 0, cards = 0, shots = 0 }
-- This match's statistics, per team and per player (end-of-match screen, client/Stats)
type TeamStats = { shots: number, passes: number, tackles: number, fouls: number, cards: number, offsides: number, poss: number }
local function freshStats(): { teams: { TeamStats }, players: { [string]: any }, scorers: { any } }
	local function t(): TeamStats return { shots = 0, passes = 0, tackles = 0, fouls = 0, cards = 0, offsides = 0, poss = 0 } end
	return { teams = { t(), t() }, players = {}, scorers = {} }
end
local ms = freshStats()
local function pstat(a: any, key: string)
	local p = ms.players[a.name]
	if not p then
		p = { name = a.name, team = a.team, num = a.num, human = a.player ~= nil, goals = 0, passes = 0, tackles = 0, shots = 0 }
		ms.players[a.name] = p
	end
	p[key] += 1
end
local boundsHow = "free" -- "free": ball in flight / rolling, "carried": at someone's feet
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

-- A line of commentary at the bottom of the screen (client/Hud), and the crowd getting louder for a moment
-- (client/Sounds): swell 0..1
-- speak: the commentator also says it out loud (client/Sounds, text-to-speech in each player's language)
local function comment(text: string, swell: number?, speak: boolean?)
	Net:SetAttribute("CommentSpeak", speak == true)
	Net:SetAttribute("Comment", text)
	Net:SetAttribute("CommentAt", workspace:GetServerTimeNow())
	if swell and swell > 0 then
		Net:SetAttribute("Crowd", swell)
		Net:SetAttribute("CrowdAt", workspace:GetServerTimeNow())
	end
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
	drib: any?, skillCD: number?, lastActive: number?, warned: boolean?,
	yellow: number?, sentOff: boolean?, kicked: boolean?, charConn: RBXScriptConnection?,
}
local actors: { Actor } = {}

local function homeOf(a: Actor): (number, number)
	local f = Config.FORMATION[a.slot]
	if dir[a.team] > 0 then return f[1], f[2] end
	return L - f[1], W - f[2]
end

local function posOf(a: Actor): (number, number)
	local r = a.root
	if not r then return homeOf(a) end
	local x, y = toPitch(r.Position)
	return x, y
end

local function velOf(a: Actor): (number, number)
	local r = a.root
	if not r then return 0, 0 end
	local v = r.AssemblyLinearVelocity
	return v.X / M, v.Z / M
end

local function facingOf(a: Actor): (number, number)
	local r = a.root
	if not r then return dir[a.team], 0 end
	local lv = r.CFrame.LookVector
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

-- Tells every player's machine which of the web game's clips this body plays now (client/Bodies picks the
-- part of the clip and its length); dur 0 = the clip's usual length
local function act(a: Actor, clip: string, dur: number?)
	local m = a.model
	if not m then return end
	m:SetAttribute("Act", clip)
	m:SetAttribute("ActDur", dur or 0)
	m:SetAttribute("ActAt", workspace:GetServerTimeNow())
end

-- Footballers do not collide with each other (walking into one would climb on top of him): like the web game,
-- they are pushed apart instead (separate() in the main loop)
local GROUP = "Footballers"
pcall(function() PhysicsService:RegisterCollisionGroup(GROUP) end)
PhysicsService:CollisionGroupSetCollidable(GROUP, GROUP, false)
local grouped: { [Model]: boolean } = setmetatable({}, { __mode = "k" }) :: any
local function setGroup(d: Instance)
	if d:IsA("BasePart") then d.CollisionGroup = GROUP end
end

local function attach(a: Actor, model: Model)
	if not grouped[model] then
		grouped[model] = true
		for _, d in model:GetDescendants() do setGroup(d) end
		model.DescendantAdded:Connect(setGroup)
	end
	a.model = model
	a.hum = model:FindFirstChildOfClass("Humanoid")
	local r = model:FindFirstChild("HumanoidRootPart")
	a.root = if r and r:IsA("BasePart") then r else nil
end

local function spawnBot(a: Actor)
	local model = Rig.createBot(a.name, a.team, a.num, rng)
	model.Parent = botFolder
	attach(a, model)
	model:SetAttribute("Role", a.role)
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


-- ---------- Ball ----------
local ball: BallPhysics.Ball = { x = L / 2, y = W / 2, z = 0, vx = 0, vy = 0, vz = 0, spin = 0, tspin = 0 }
local owner: Actor? = nil
local lastOwner: Actor? = nil -- to tell a human when he loses the ball
local held = false -- a goalkeeper has it in his hands
local lastTouch: Actor? = nil
local shotBy: number? = nil -- team of the last shot, while it flies
local target: Actor? = nil -- intended receiver of the last pass

local function resetBall(x: number, y: number)
	if owner then (owner :: Actor).kicked = true end -- a restart, not a lost ball
	ball.x, ball.y, ball.z, ball.vx, ball.vy, ball.vz, ball.spin, ball.tspin = x, y, 0, 0, 0, 0, 0, 0
	owner, held, shotBy, target = nil, false, nil, nil
end

local function gauss(): number
	return math.sqrt(-2 * math.log(math.max(1e-9, rng:NextNumber()))) * math.cos(2 * math.pi * rng:NextNumber())
end

-- Offside, as in the web game: when a player plays the ball forward, any team-mate standing in the opponents' half,
-- ahead of the ball and beyond the second-last opponent is marked; if one of them is the next to touch it, offside
-- (a free kick for the defenders). Not on throw-ins, corners and goal kicks.
local offsideSet: { [Actor]: boolean }? = nil
local function markOffside(a: Actor)
	offsideSet = nil
	local d = dir[a.team]
	local ax = posOf(a)
	local line: { number } = {}
	for _, o in actors do
		if o.team ~= a.team and o.root then table.insert(line, (posOf(o)) * d) end
	end
	table.sort(line, function(p, q) return p > q end)
	local second = line[2] or L * d
	for _, m in actors do
		if m.team ~= a.team or m == a or not m.root then continue end
		local mx = posOf(m)
		if (mx - L / 2) * d > 0 and (mx - ax) * d > 0.5 and mx * d > second + 0.3 then
			offsideSet = offsideSet or {}
			;(offsideSet :: any)[m] = true
		end
	end
end

local function kickBall(a: Actor, vx: number, vy: number, vz: number, spin: number?, clip: string?)
	local restart = phase == "set" and (setKindNow == "throw" or setKindNow == "corner" or setKindNow == "goalkick")
	if restart then offsideSet = nil else markOffside(a) end
	a.kicked = true -- his own shot or pass: not a lost ball
	local pl = a.player
	if pl and math.sqrt(vx * vx + vy * vy) > 14 and Economy.owns(pl, "trail") then
		local tr = Economy.equipOf(pl).trail
		if tr then
			Net:SetAttribute("Trail", tr)
			Net:SetAttribute("TrailAt", workspace:GetServerTimeNow())
		end
	end
	act(a, clip or (if phase == "set" and setKindNow == "throw" then "throwIn" else "kick"))
	if phase == "set" then phase = "play" end
	owner, held = nil, false
	local fx, fy = facingOf(a)
	local x, y = posOf(a)
	-- Struck from in front of him, but never from behind a line (a keeper clearing while facing his own goal)
	ball.x, ball.y = math.clamp(x + fx * 0.7, 0.15, L - 0.15), math.clamp(y + fy * 0.7, 0.15, W - 0.15)
	ball.z = math.max(ball.z, 0.11)
	ball.vx, ball.vy, ball.vz, ball.spin, ball.tspin = vx, vy, vz, spin or 0, 0
	a.cool = 0.35
	lastTouch = a
	shotBy, target = nil, nil
end

local function giveBall(a: Actor)
	offsideSet = nil
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
		-- Computer players look for the humans first (a free human is worth a longer or less obvious pass)
		if m.player and not a.player and open >= 1.3 then s += 6 end
		if s > bestS then best, bestS = m, s end
	end
	return best
end

-- Ground pass into the receiver's run, weighted so it reaches him at a comfortable speed
local function passTo(a: Actor, m: Actor)
	if m.player then comment(T("c.seeks", { a = a.name, b = m.name }), nil, true) elseif rng:NextNumber() < 0.3 then comment(T("c.pass", { a = a.name, b = m.name })) end
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
	kickBall(a, math.cos(ang) * v, math.sin(ang) * v, 0, nil, if phase == "set" and setKindNow == "throw" then "throwIn" else "pass")
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
	if m then passTo(a, m) else kickBall(a, dx * 14, dy * 14, 0, nil, if phase == "set" and setKindNow == "throw" then "throwIn" else "pass") end
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
	if not best then doPass(a, dx, dy); return end
	local mx, my = posOf(best)
	local mvx, mvy = velOf(best)
	local tx = math.clamp(mx + dir[a.team] * rng:NextNumber(7, 11) + mvx * 0.4, 2, L - 2)
	local ty = math.clamp(my + (W / 2 - my) * 0.15 + mvy * 0.4, 2, W - 2)
	local d = dist2(px, py, tx, ty)
	local v = math.clamp(d * 0.78 + 5, 9, 24)
	local ang = math.atan2(ty - py, tx - px) + gauss() * 0.03
	kickBall(a, math.cos(ang) * v, math.sin(ang) * v, 0, nil, "pass")
	target = best
end

local function doShoot(a: Actor, dx: number, dy: number, power: number)
	ms.teams[a.team].shots += 1
	pstat(a, "shots")
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
	say(T("say.shot"), a.name, 0.8)
	comment(T("c.shot", { a = a.name }), 0.3, a.player ~= nil)
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

-- A short text above a footballer's head, like the web game's labels
local function label(a: Actor, text: string, color: Color3, dur: number)
	local m = a.model
	local head = m and (m:FindFirstChild("Head") or a.root)
	if not head then return end
	local old = head:FindFirstChild("FC27Label")
	if old then old:Destroy() end
	local g = Instance.new("BillboardGui")
	g.Name = "FC27Label"
	g.Size = UDim2.fromOffset(260, 26)
	g.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	g.AlwaysOnTop = true
	g.MaxDistance = 90
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.4
	t.Parent = g
	g.Parent = head
	task.delay(dur, function() if g.Parent then g:Destroy() end end)
end

-- A foul (defined with the restarts below): free kick, or a penalty in the box, with a card now and then
local foul: (f: Actor, v: Actor, behind: boolean) -> ()

-- Tackled from behind: the tackler comes from the side the victim turns his back to
local function fromBehind(tackler: Actor, victim: Actor): boolean
	local px, py = posOf(tackler)
	local ox, oy = posOf(victim)
	local fx, fy = facingOf(victim)
	local d = math.max(dist2(px, py, ox, oy), 1e-3)
	return ((px - ox) * fx + (py - oy) * fy) / d < -0.3
end

local function doTackle(a: Actor)
	local victim = owner
	local px, py = posOf(a)
	-- A loose ball close by: the tackle wins it
	if not victim and phase == "play" and ball.z < 1 and dist2(px, py, ball.x, ball.y) < 2.6 then
		act(a, "tackle", 0.45)
		giveBall(a)
		label(a, T("lab.won"), Color3.fromRGB(120, 230, 120), 1)
		return
	end
	if not victim or victim.team == a.team or held then
		if a.player then label(a, T("lab.noone"), Color3.fromRGB(220, 220, 220), 0.8) end
		return
	end
	-- No tackling the taker of a restart
	if phase == "set" then return end
	act(a, "tackle", 0.45)
	local ox, oy = posOf(victim)
	-- 2.6 m: the server sees a human's position a little late
	if dist2(px, py, ox, oy) > (if a.player then 2.6 else 2.3) then
		if a.player then label(a, T("lab.far"), Color3.fromRGB(255, 220, 160), 0.8) end
		stunActor(a, 0.25)
		return
	end
	local behind = fromBehind(a, victim)
	if rng:NextNumber() < 0.55 then
		stunActor(victim, 0.7)
		act(victim, "trip", 0.7)
		victim.cool = 0.6
		local fx, fy = facingOf(a)
		owner = nil
		ball.x, ball.y = math.clamp(ox, 0.15, L - 0.15), math.clamp(oy, 0.15, W - 0.15)
		ball.vx, ball.vy, ball.vz = fx * 4, fy * 4, 0
		lastTouch = a
		a.cool = 0.1
		say(T("say.tackle"), a.name, 0.9)
		if a.player then Economy.earn(a.player, "tackle") end
		ms.teams[a.team].tackles += 1
		pstat(a, "tackles")
		comment(T("c.tackle", { a = a.name }), 0.2)
		if behind and rng:NextNumber() < 0.2 then foul(a, victim, true) end
	else
		label(a, T("lab.tacklemiss"), Color3.fromRGB(255, 120, 100), 1)
		stunActor(a, if a.player then 0.35 else 0.6)
		if rng:NextNumber() < (if behind then 0.6 else 0.06) then foul(a, victim, behind) end
	end
end

-- ---------- Skill moves (the web game's 31 dribbles, Shared.Dribbles) ----------
-- The move is picked here with its chance of success and its result rolled at once; the model's attributes
-- (Drib, DribAt, DribF/DribS = forward and side directions, DribV0) tell every machine to play it: the body's
-- animation (client/Bodies), the ball at the feet (client/BallView) and, for a human, his own movement
-- (client/Controls). The server moves the computer players and applies the outcome when the move reaches it.
local dribbler: Actor? = nil -- after a knock or a flick, he gets first claim on the ball until dribblerT
local dribblerT = 0

local function now(): number return workspace:GetServerTimeNow() end

local function nearestOpp(a: Actor): (Actor?, number)
	local x, y = posOf(a)
	local best, bd = nil, math.huge
	for _, o in actors do
		if o.team == a.team or not o.root then continue end
		local ox, oy = posOf(o)
		local d = dist2(x, y, ox, oy)
		if d < bd then best, bd = o, d end
	end
	return best, bd
end

local TIER_COLOR = {
	[0] = Color3.fromRGB(255, 90, 80), [1] = Color3.fromRGB(255, 190, 70),
	[2] = Color3.fromRGB(120, 230, 120), [3] = Color3.fromRGB(80, 220, 255),
}

-- Opponents close by are left behind (stunned for a moment); in front only unless the move was perfect
local function beatDefenders(a: Actor, range: number, stunT: number, coolT: number, frontOnly: boolean): Actor?
	local d = a.drib
	local x, y = posOf(a)
	local victim = nil
	for _, o in actors do
		if o.team == a.team or o.role == "GK" or not o.root then continue end
		local ox, oy = posOf(o)
		local dd = dist2(x, y, ox, oy)
		if dd > range then continue end
		local front = ((ox - x) * d.fx + (oy - y) * d.fy) / math.max(dd, 1e-3)
		if frontOnly and front < -0.25 then continue end
		stunActor(o, math.max(o.stun, stunT))
		o.cool = math.max(o.cool, coolT)
		victim = victim or o
	end
	return victim
end

local function endDribble(a: Actor)
	local d = a.drib
	if not d then return end
	a.drib = nil
	local m = a.model
	if m then
		for _, k in { "Drib", "DribAt", "DribF", "DribS", "DribV0" } do m:SetAttribute(k, nil) end
	end
	local hum, root = a.hum, a.root
	if hum then hum.AutoRotate = true end
	-- Drag-backs end facing back (computer players; a human's machine turns him)
	if d.m.reverse and root and not a.player then
		local p = root.Position
		root.CFrame = CFrame.lookAt(p, p - Vector3.new(d.fx, 0, d.fy))
	end
end

local function dribbleOutcome(a: Actor)
	local d = a.drib
	d.done = true
	local m: Dribbles.Move = d.m
	local q: number = d.q
	label(a, T("lab.drib", { move = "§drib." .. m.key, pct = math.floor(d.c * 100 + 0.5), res = "§res." .. q }), TIER_COLOR[q], 1.6)
	local opp, od = nearestOpp(a)
	local knock = m.knock
	if knock then
		local bvx, bvy, bvz
		if knock.v == "through" then
			local tx, ty = d.fx, d.fy
			if opp then
				local ox, oy = posOf(opp)
				tx, ty = ox - ball.x, oy - ball.y
			end
			local n = math.max(math.sqrt(tx * tx + ty * ty), 1e-3)
			bvx, bvy, bvz = tx / n * 9.5, ty / n * 9.5, 0.1
		else
			local v = knock.v :: { number }
			bvx, bvy, bvz = d.fx * v[1] + d.sx * v[2], d.fy * v[1] + d.sy * v[2], v[3]
		end
		if q == 0 then
			if opp and od < 4 then
				-- Straight to the defender
				local ox, oy = posOf(opp)
				local dx, dy = ox - ball.x, oy - ball.y
				local n = math.max(math.sqrt(dx * dx + dy * dy), 1e-3)
				bvx, bvy, bvz = dx / n * 6, dy / n * 6, 0.1
				opp.stun, opp.cool = 0, 0
			else
				local ang = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(0.5, 0.9)
				local c, sn = math.cos(ang), math.sin(ang)
				bvx, bvy = (bvx * c - bvy * sn) * 1.4, (bvx * sn + bvy * c) * 1.4
			end
		elseif q == 1 then
			bvx, bvy, bvz = bvx * 0.8, bvy * 0.8, bvz * 0.85
		end
		if owner == a then
			owner, held = nil, false
			ball.vx, ball.vy, ball.vz = bvx, bvy, bvz
			ball.z = math.max(ball.z, 0.05)
			ball.spin, ball.tspin = 0, 0
			lastTouch = a
			shotBy, target = nil, nil
			a.cool = 0.28
			if q >= 1 then dribbler, dribblerT = a, now() + 1.8 end
		end
		if q >= 2 and knock.v == "through" and opp then
			stunActor(opp, math.max(opp.stun, 0.9))
			opp.cool = 1
		end
		if q >= 2 then beatDefenders(a, 3.6, if q == 3 then 1.2 else 0.8, 1, true) end
	elseif q == 0 then
		-- Missed: the ball goes to the defender, or rolls away
		if owner == a then
			if opp and od < 2.6 then
				giveBall(opp)
			else
				owner = nil
				ball.vx, ball.vy, ball.vz = d.fx * 4.5 + gauss() * 0.8, d.fy * 4.5 + gauss() * 0.8, 0.1
				lastTouch = a
				a.cool = 0.25
				dribbler, dribblerT = a, now() + 1.2
			end
		end
		stunActor(a, math.max(a.stun, 0.25))
	elseif q == 1 then
		d.v0 *= 0.5 -- keeps the ball, but slowed down and the defender is not beaten
	end
	if q <= 1 then
		if a.player and q == 0 then say(T("say.dribfail", { move = "§drib." .. m.key }), a.name, 1.2) end
		if not knock then endDribble(a) end
		return
	end
	if not knock then
		if q == 3 then beatDefenders(a, 4.5, 1.2, 0.8, false) else beatDefenders(a, 3.6, 0.8, 0.4, true) end
	end
	-- A shot fake near the goal can send the keeper the wrong way
	if m.fake == "shot" then
		for _, gk in actors do
			if gk.team ~= a.team and gk.role == "GK" and gk.root then
				local x, y = posOf(a)
				if dist2(x, y, oppGoalX(a.team), W / 2) < 25 and rng:NextNumber() < 0.55 then
					act(gk, if rng:NextNumber() < 0.5 then "diveL" else "diveR", 0.9)
					stunActor(gk, 0.9)
				end
			end
		end
	end
	if q == 3 and a.player then say(T("say.dribperfect", { move = "§drib." .. m.key }), a.name, 1.4) end
	if q == 3 then comment(T("c.dribperfect", { move = "§drib." .. m.key, a = a.name }), 0.4, true) elseif q == 2 and rng:NextNumber() < 0.5 then comment(T("c.dribnice", { a = a.name, move = "§drib." .. m.key }), 0.15) end
end

-- Starts a skill move for the player who has the ball. (ix, iy): where his stick points, to choose the side
local function doSkill(a: Actor, ix: number?, iy: number?)
	local t = now()
	if a.drib or (a.skillCD or 0) > t or owner ~= a or held or not a.model then return end
	local opp, od = nearestOpp(a)
	local m = Dribbles.pick(rng, opp ~= nil and od < 4.5)
	local fx, fy = facingOf(a)
	local sx, sy = -fy, fx -- the player's right (pitch x/y)
	local function flip() sx, sy = -sx, -sy end
	local lateral = if ix and iy then ix * sx + iy * sy else 0
	if math.abs(lateral) > 0.3 then
		if lateral < 0 then flip() end
	elseif opp and od < 6 then
		local ox, oy = posOf(opp)
		local x, y = posOf(a)
		if (ox - x) * sx + (oy - y) * sy > 0 then flip() end
	elseif rng:NextNumber() < 0.5 then
		flip()
	end
	local stamina = if a.player then (a.player:GetAttribute("Stamina") :: number?) else nil
	local c = Dribbles.chance(m, if od < 10 then od else nil, stamina)
	-- Like the web game, the human's moves are much more likely to work than the computer's
	if a.player then c = math.max(c + 0.3, 0.88) end
	local vx, vy = velOf(a)
	local d = {
		m = m, t0 = t, fx = fx, fy = fy, sx = sx, sy = sy, c = c, q = Dribbles.quality(c, rng:NextNumber()),
		done = false, v0 = math.sqrt(vx * vx + vy * vy),
	}
	a.drib = d
	a.skillCD = t + m.dur + 0.55
	local model = a.model :: Model
	model:SetAttribute("DribF", Vector3.new(fx, 0, fy))
	model:SetAttribute("DribS", Vector3.new(sx, 0, sy))
	model:SetAttribute("DribV0", d.v0)
	model:SetAttribute("DribAt", t)
	model:SetAttribute("Drib", m.key)
	label(a, T("lab.dribstart", { move = "§drib." .. m.key, stars = string.rep("★", m.stars), pct = math.floor(c * 100 + 0.5) }), Color3.fromRGB(201, 182, 255), m.dur + 0.2)
end

-- Every frame for a player in a move: outcome when it is time, and the computer players' movement
local function dribbleStep(a: Actor)
	local d = a.drib
	if not d then return end
	local m: Dribbles.Move = d.m
	local k = (now() - d.t0) / m.dur
	if k >= 1 or a.stun > 0.3 then
		if not d.done and a.stun <= 0.3 then dribbleOutcome(a) end
		endDribble(a)
		return
	end
	if not d.done and k >= Dribbles.decideAt(m) then
		dribbleOutcome(a)
		if not a.drib then return end
	end
	local hum, root = a.hum, a.root
	if a.player or not hum or not root then return end
	local fv, sv = m.v(k)
	if not m.reverse then fv = math.max(fv, d.v0 * 0.75) end
	local vx, vy = d.fx * fv + d.sx * sv, d.fy * fv + d.sy * sv
	local sp = math.sqrt(vx * vx + vy * vy)
	hum.AutoRotate = false
	local p = root.Position
	root.CFrame = CFrame.lookAt(p, p + Vector3.new(d.fx, 0, d.fy))
	hum.WalkSpeed = sp * M
	if sp > 0.05 then hum:Move(Vector3.new(vx / sp, 0, vy / sp)) else hum:Move(Vector3.zero) end
end

-- ---------- Restarts ----------
local function nearestOf(t: number, x: number, y: number, preferHuman: boolean?): Actor?
	local best, bd = nil, math.huge
	for _, a in actors do
		if a.team ~= t or a.role == "GK" or not a.root then continue end
		local ax, ay = posOf(a)
		local d = dist2(ax, ay, x, y)
		-- A human takes the restart when he is close enough to walk to it (he is not moved there)
		if preferHuman and a.player and d < 12 then d -= 12 end
		if d < bd then best, bd = a, d end
	end
	return best
end

local function setPiece(kind: string, t: number, x: number, y: number, taker: Actor?)
	if kind == "penalty" then
		-- On the spot, 11 m out; the keeper on his line, everybody else out of the box
		local gx = oppGoalX(t)
		x, y = gx - dir[t] * 11, W / 2
		for _, a in actors do
			if not a.root or a == taker then continue end
			if a.role == "GK" and a.team ~= t then
				place(a, gx - dir[t] * 0.3, W / 2)
			elseif a.role ~= "GK" and math.abs(posOf(a) - gx) < 21 then
				local _, ay = posOf(a)
				place(a, gx - dir[t] * rng:NextNumber(21, 25), math.clamp(ay, 12, W - 12))
			end
		end
		if not taker then
			-- A human of that side takes it, otherwise the nearest computer player
			for _, a in actors do
				if a.team == t and a.player and a.root then taker = a; break end
			end
		end
	end
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
	Net:SetAttribute("SetKind", kind)
	publish()
	if tk.player then
		-- Everybody waits for him (8 s at most, then it is played for him)
		local how = if kind == "penalty" then T("how.penalty") elseif kind == "throw" then T("how.throw") else T("how.other")
		Message:FireClient(tk.player, T("msg.yourturn", { kind = "§set." .. kind }), how, 3)
	end
	if kind == "corner" or kind == "freekick" or kind == "penalty" then comment(T("c.setpiece", { kind = "§set." .. kind, team = TEAM(t), a = tk.name }), 0.15) end
end

local function inBoxOf(t: number, x: number, y: number): boolean
	return math.abs(x - ownGoalX(t)) < 16.5 and y > 13.84 and y < 54.16
end

-- The web game's fouls: a card now and then (more often from behind; a second yellow is a red), advantage when the
-- fouled side attacks and keeps the ball, otherwise a free kick, or a penalty when it happens in the box
foul = function(f: Actor, v: Actor, behind: boolean)
	if phase ~= "play" then return end
	stats.fouls += 1
	local card: string? = nil
	if rng:NextNumber() < (if behind then 0.3 else 0.06) then
		f.yellow = (f.yellow or 0) + 1
		card = if (f.yellow :: number) >= 2 and f.role ~= "GK" then "red" else "yellow"
	end
	local vx, vy = posOf(v)
	local inBox = inBoxOf(f.team, vx, vy)
	local sub = if card == "red" then T("sub.red", { a = f.name, n = f.num })
		elseif card == "yellow" then T("sub.yellow", { a = f.name, n = f.num })
		else T("sub.foul", { a = f.name, b = v.name })
	label(f, if card == "red" then T("lab.red") elseif card == "yellow" then T("lab.yellow") else T("lab.foul"),
		if card == "red" then Color3.fromRGB(227, 34, 47) elseif card == "yellow" then Color3.fromRGB(246, 211, 45) else Color3.fromRGB(255, 173, 71), 2.2)
	if card == "red" then
		f.sentOff = true
		if f.player then
			-- A human is not taken off: ten seconds on the spot instead
			stunActor(f, 10)
		else
			if owner == f then owner = nil end
			if f.model then f.model:Destroy() end
			f.model, f.hum, f.root = nil, nil, nil
		end
	end
	local o = owner
	local attacking = (vx - L / 2) * dir[v.team] > 0
	if not inBox and attacking and o and o.team == v.team and (o ~= v or (v.stun <= 0 and rng:NextNumber() < 0.6)) then
		label(o, T("lab.advantage"), Color3.fromRGB(79, 224, 138), 1.5)
		say(T("say.advantage"), sub, 1.5)
		return
	end
	if card then stats.cards += 1; ms.teams[f.team].cards += 1 end
	ms.teams[f.team].fouls += 1
	comment(if card == "red" then T("c.red", { a = f.name }) elseif card == "yellow" then T("c.yellow", { a = f.name })
		else T("c.foul", { a = f.name, b = v.name }), if card then 0.4 else 0.15, card ~= nil or inBox)
	if inBox then
		stats.penalties += 1
		say(T("say.penalty"), sub, 2.2)
		setPiece("penalty", v.team, 0, 0, if v.player then v else nil)
	else
		say(T("set.freekick"), sub, 1.8)
		setPiece("freekick", v.team, math.clamp(vx, 1, L - 1), math.clamp(vy, 1, W - 1), v)
	end
end

-- The match ball (one of balls.glb's, shown by client/BallView) and the line-ups (client/Intro)
local BALLS = { "classique", "etoiles", "jabu", "brazu", "euro" }
Net:SetAttribute("MatchBall", BALLS[rng:NextInteger(1, #BALLS)])
local function publishLineups()
	local teams = { {}, {} }
	for _, a in actors do
		if not a.sentOff then
			table.insert(teams[a.team], { num = a.num, name = a.name, role = a.role, human = a.player ~= nil, slot = a.slot,
				vip = a.player ~= nil and Economy.owns(a.player, "vip") })
		end
	end
	for t = 1, 2 do table.sort(teams[t], function(p, q) return p.num < q.num end) end
	Net:SetAttribute("Lineups", game:GetService("HttpService"):JSONEncode(teams))
end
-- Right away: the locker room's picker shows the places before any match has started
publishLineups()

local function kickoff(t: number)
	publishLineups()
	for _, a in actors do
		local hx, hy = homeOf(a)
		-- Everybody in his own half for the kick-off
		hx = if dir[a.team] > 0 then math.min(hx, L / 2 - 1.5) else math.max(hx, L / 2 + 1.5)
		place(a, hx, hy)
		a.stun, a.cool, a.diveT = 0, 0, 0
	end
	-- A computer player kicks off, so that nobody waits for a human who does not know it is his turn
	local tk: Actor? = nil
	local bd = math.huge
	for _, a in actors do
		if a.team == t and not a.player and a.role ~= "GK" and a.root then
			local hx, hy = homeOf(a)
			local d = dist2(hx, hy, L / 2, W / 2)
			if d < bd then tk, bd = a, d end
		end
	end
	if tk then place(tk, L / 2 - dir[t] * 0.8, W / 2) end
	setPiece("kickoff", t, L / 2, W / 2, tk)
	say(T("set.kickoff"), TEAM(t), 1.5)
	comment(T("c.kickoff", { team = TEAM(t) }), 0.2, true)
end

local function goalFor(t: number)
	if owner then (owner :: Actor).kicked = true end
	local lt = lastTouch
	if lt and lt.team == t then
		pstat(lt, "goals")
		table.insert(ms.scorers, { name = lt.name, team = t, minute = math.max(1, math.floor(clock + 0.5)) })
	else
		table.insert(ms.scorers, { name = "csc", team = t, minute = math.max(1, math.floor(clock + 0.5)) })
	end
	table.insert(goalLog, {
		team = t, clock = math.floor(clock), how = boundsHow, phase = phase,
		x = math.floor(ball.x * 100) / 100, y = math.floor(ball.y * 100) / 100, z = math.floor(ball.z * 100) / 100,
		vx = math.floor(ball.vx * 10) / 10, vy = math.floor(ball.vy * 10) / 10,
		last = if lt then `{lt.name} ({lt.team}{if lt.player then ", human" else ""}{if lt.role == "GK" then ", GK" else ""})` else "nobody",
		owner = if owner then (owner :: Actor).name else "none", shot = shotBy or 0, held = held,
	})
	score[t] += 1
	local own = not (lastTouch and lastTouch.team == t)
	local scorer = if lastTouch and not own then lastTouch.name else T("sub.og")
	phase, phaseT = "goal", 0
	owner, held, shotBy = nil, false, nil
	publish()
	say(T("say.goal"), T("sub.goal", { team = TEAM(t), who = scorer }), 3.5)
	comment(if own then T("c.og", { team = TEAM(t) }) else T("c.goal", { a = scorer, team = TEAM(t) }), 1, true)
	Net:SetAttribute("LastGoalTeam", t)
	Net:SetAttribute("GoalAt", workspace:GetServerTimeNow())
	if lastTouch and lastTouch.team == t then
		local sc = lastTouch :: Actor
		local pl = sc.player
		if pl then
			Economy.earn(pl, "goal")
			Economy.stat(pl, "goals")
			-- All-time scorers board in the locker room
			task.spawn(function()
				pcall(function()
					game:GetService("DataStoreService"):GetOrderedDataStore("FC27Goals_v1"):IncrementAsync(tostring(pl.UserId), 1)
				end)
			end)
			-- His own celebration if he bought them (shop), otherwise none: the team celebrates anyway
			local cel = Economy.owns(pl, "celebrations") and Economy.equipOf(pl).celebration
			if cel then act(sc, cel) end
		else
			act(sc, "siuu")
		end
	end
end

-- Ball over a line: goal, corner, goal kick or throw-in
local function checkBounds(prevX: number)
	local crossed = (ball.x < 0 and prevX >= 0) or (ball.x > L and prevX <= L)
	local off = math.abs(ball.y - W / 2)
	-- Posts and crossbar
	if crossed and ball.z < BAR + 0.15 and math.abs(off - GH) < 0.15 then
		ball.vx = -ball.vx * 0.6
		ball.x = if ball.x < 0 then 0.05 else L - 0.05
		say(T("say.post"), nil, 1)
		return
	end
	if crossed and off < GH and math.abs(ball.z - BAR) < 0.15 then
		ball.vx, ball.vz = -ball.vx * 0.5, math.abs(ball.vz) * 0.3
		ball.x = if ball.x < 0 then 0.05 else L - 0.05
		say(T("say.bar"), nil, 1)
		return
	end
	if ball.x < -0.17 or ball.x > L + 0.17 then
		local gx = if ball.x < 0 then 0 else L
		local defT = if ownGoalX(1) == gx then 1 else 2
		local attT = 3 - defT
		if off < GH and ball.z < BAR then
			goalFor(attT)
		elseif lastTouch and lastTouch.team == defT then
			say(T("set.corner"), TEAM(attT), 1.2)
			setPiece("corner", attT, if gx == 0 then 0.6 else L - 0.6, if ball.y < W / 2 then 0.6 else W - 0.6)
		else
			say(T("set.goalkick"), TEAM(defT), 1.2)
			local gk = nil
			for _, a in actors do if a.team == defT and a.role == "GK" then gk = a end end
			setPiece("goalkick", defT, if gx == 0 then 5.5 else L - 5.5, W / 2 + (if ball.y < W / 2 then -6 else 6), gk)
		end
	elseif ball.y < -0.17 or ball.y > W + 0.17 then
		local t = if lastTouch and lastTouch.team == 1 then 2 else 1
		say(T("set.throw"), TEAM(t), 1)
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
local function callOffside(m: Actor)
	offsideSet = nil
	ms.teams[m.team].offsides += 1
	local x, y = posOf(m)
	say(T("say.offside"), T("sub.offside", { a = m.name }), 1.8)
	comment(T("c.offside", { a = m.name }), 0.15, true)
	label(m, T("lab.offside"), Color3.fromRGB(255, 220, 90), 1.6)
	setPiece("freekick", 3 - m.team, math.clamp(x, 1, L - 1), math.clamp(y, 1, W - 1))
end

local function tryControl()
	if owner then return end
	local db = dribbler
	if db and now() < dribblerT and db.cool <= 0 and db.stun <= 0 and ball.z < 1.6 and db.root then
		local x, y = posOf(db)
		if dist2(x, y, ball.x, ball.y) < (if db.player then 2.6 else 1.8) then
			dribbler = nil
			giveBall(db)
			return
		end
	end
	local bsp = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
	local best, bd = nil, math.huge
	for _, a in actors do
		if a.cool > 0 or a.stun > 0 or not a.root then continue end
		local x, y = posOf(a)
		local d = dist2(x, y, ball.x, ball.y)
		if a.role == "GK" then
			local inBox = math.abs(x - ownGoalX(a.team)) < 16.5 and math.abs(y - W / 2) < 20.16
			local reach = if a.diveT > 0 then 2.2 else 1.3
			if inBox and d < reach and ball.z < 2.6 then
				-- A hard shot, or one placed away from him, beats him more often (a human's shot a little more)
				local chance = 1
				if shotBy and shotBy ~= a.team then
					local shooter = lastTouch
					chance = math.clamp(0.88 - math.max(0, bsp - 12) * 0.035 - d * 0.18
						- (if shooter and shooter.player then 0.1 else 0), 0.15, 0.9)
				end
				if rng:NextNumber() < chance then
					giveBall(a)
					held = true
					a.holdT = 1.3
					act(a, "gkCatch", 0.5)
					if shotBy then say(T("say.save"), a.name, 1); comment(T("c.save", { a = a.name }), 0.35, true) end
				else
					-- Beaten: he only grazes it, the ball goes on (it used to bounce back out, so shots almost never
					-- went in)
					ball.vx *= 0.85
					ball.vy = ball.vy * 0.85 + gauss() * 1.2
					a.cool = 0.8
					label(a, T("lab.beaten"), Color3.fromRGB(255, 120, 100), 1)
				end
				return
			end
		end
		local reach = 1.3
		if ball.z < 0.9 and d < reach and d < bd then best, bd = a, d end
		-- Header for a ball at head height coming at him
		if ball.z >= 0.9 and ball.z < 2.4 and d < 0.9 and bsp > 4 then
			if offsideSet and (offsideSet :: any)[a] then callOffside(a); return end
			local gx = oppGoalX(a.team)
			local gdx, gdy = gx - x, W / 2 + gauss() * 2 - y
			local gd = math.sqrt(gdx * gdx + gdy * gdy)
			local hx, hy
			if gd < 22 then hx, hy = gdx / gd, gdy / gd else hx, hy = facingOf(a) end
			local v = if gd < 22 then 13 else 10
			kickBall(a, hx * v, hy * v, if gd < 22 then 0.5 else 3, nil, "head")
			if gd < 22 then shotBy = a.team end
			return
		end
	end
	if best then
		if offsideSet and (offsideSet :: any)[best] then callOffside(best :: Actor); return end
		local passer = lastTouch
		if passer and passer ~= best and passer.team == (best :: Actor).team then
			ms.teams[passer.team].passes += 1
			pstat(passer, "passes")
			if passer.player then Economy.earn(passer.player :: Player, "pass") end
		end
		giveBall(best)
	end
end

-- ---------- Computer players ----------
-- precise: follow a moving target closely (going for the ball); otherwise only a target that moved 1.5 m or more,
-- or once a second, is sent again
local function moveBot(a: Actor, x: number, y: number, speed: number, precise: boolean?)
	local hum = a.hum
	if not hum or not a.root then return end
	local p = toWorld(math.clamp(x, -2, L + 2), math.clamp(y, -2, W + 2), 0)
	if a.player then return end -- a human moves himself
	hum.WalkSpeed = speed
	if not a.lastTarget or (a.lastTarget - p).Magnitude > (if precise then 0.3 * M else 1.5) or a.moveT <= 0 then
		hum:MoveTo(p)
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
	if best and best.player then
		-- The human goes for it himself when he is close; otherwise the nearest computer player of his side goes
		if bd < 6 then return nil end
		local bot, bb = nil, math.huge
		for _, a in actors do
			if a.team ~= t or a.role == "GK" or not a.root or a.stun > 0 or a.player then continue end
			local x, y = posOf(a)
			local d = dist2(x, y, ball.x, ball.y)
			if d < bb then bot, bb = a, d end
		end
		return bot
	end
	return best
end

local function botWithBall(a: Actor, dt: number)
	if a.drib then return end -- dribbleStep moves him
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
		if gd < 24 and (gx - x) * d > 0.5 then
			local gdx, gdy = (gx - x) / gd, (W / 2 + gauss() * 2.5 - y) / gd
			doShoot(a, gdx, gdy, rng:NextNumber(0.55, 0.85))
			return
		end
		-- A defender right in front: sometimes a skill move instead of a pass
		if pressure < 3 and rng:NextNumber() < 0.3 then
			local o = nearestOpp(a)
			if o then
				local ox, oy = posOf(o)
				local fx, fy = facingOf(a)
				if (ox - x) * fx + (oy - y) * fy > 0 then doSkill(a); return end
			end
		end
		if pressure < 3.5 or rng:NextNumber() < 0.15 then
			local m = bestPass(a, d, 0, -0.1) or bestPass(a, nil, nil)
			if m then passTo(a, m); return end
		end
		if rng:NextNumber() < 0.06 then doThrough(a, d, 0); return end
	end
	moveBot(a, math.clamp(x + d * 8, 1.5, L - 1.5), y + (W / 2 - y) * 0.15, 19)
end

local function keeper(a: Actor, dt: number)
	local gx = ownGoalX(a.team)
	local d = dir[a.team]
	local _, y = posOf(a)
	a.diveT = math.max(0, a.diveT - dt)
	-- Shot coming: go for the point where it crosses the line
	if shotBy and shotBy ~= a.team and (gx - ball.x) * ball.vx > 0 and math.abs(ball.vx) > 3 then
		local t = (gx + d * 0.6 - ball.x) / ball.vx
		local yc = ball.y + ball.vy * t
		if t > 0 and t < 1.2 and math.abs(yc - W / 2) < GH + 1.5 then
			if t < 0.55 and a.diveT <= 0 and math.abs(yc - y) > 0.8 then
				a.diveT = 0.6
				-- Same rule as the web game: the side of the dive seen from the keeper (he faces the pitch, +x or -x)
				local lat = -(yc - y) * d
				act(a, if lat > 0 then "diveL" else "diveR", 0.6)
			end
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
	if a.stun > 0 then moveBot(a, x, y, 0); return end
	if owner == a then botWithBall(a, dt); return end
	if a.role == "GK" then keeper(a, dt); return end
	local t = a.team
	local d = dir[t]
	local hx, hy = homeOf(a)
	local attacking = owner ~= nil and (owner :: Actor).team == t
	-- At a restart everybody waits for the taker: his team-mates hold their places, opponents keep their distance
	if phase == "set" and setTaker and setTaker.team == t and setTaker ~= a then
		moveBot(a, x, y, 0)
		return
	end
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
		-- Where the ball will be, and half a metre past it so that he runs into it instead of stopping short
		local px, py = ball.x + ball.vx * 0.35, ball.y + ball.vy * 0.35
		local ddx, ddy = px - x, py - y
		local dd = math.sqrt(ddx * ddx + ddy * ddy)
		if dd > 0.1 then px, py = px + ddx / dd * 0.5, py + ddy / dd * 0.5 end
		moveBot(a, px, py, 21, true)
		-- Tackle when close to an opponent with the ball
		if owner and (owner :: Actor).team ~= t and a.cool <= 0 and not held and not (owner :: Actor).drib then
			local ox, oy = posOf(owner :: Actor)
			if dist2(x, y, ox, oy) < 1.5 and rng:NextNumber() < 1.2 * dt then
				local succ = if (owner :: Actor).player then 0.42 else 0.5
				act(a, "tackle", 0.45)
				local victim = owner :: Actor
				local behind = fromBehind(a, victim)
				if rng:NextNumber() < succ then
					stunActor(victim, 0.6)
					victim.cool = 0.6
					act(victim, "trip", 0.6)
					label(a, T("lab.tackle"), Color3.fromRGB(255, 120, 100), 1.2)
					if victim.player then say(T("say.lost"), T("sub.tackledby", { a = a.name }), 1.2) end
					giveBall(a)
					ms.teams[a.team].tackles += 1
					pstat(a, "tackles")
					if behind and rng:NextNumber() < 0.2 then foul(a, victim, true) end
				else
					label(a, T("lab.tacklemiss"), Color3.fromRGB(255, 220, 160), 1)
					a.cool = 0.8
					if rng:NextNumber() < (if behind then 0.6 else 0.06) then foul(a, victim, behind) end
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
-- What he bought and chose in the shop, put on his character for Rig.addBody: boots colour, special shirt, VIP
local function dressFromShop(pl: Player, char: Model)
	local eq = Economy.equipOf(pl)
	local boots = Economy.owns(pl, "style") and Shop.choice("boots", eq.boots)
	local kit = Economy.owns(pl, "style") and Shop.choice("kit", eq.kit)
	char:SetAttribute("BootsColor", if boots then boots.color else nil)
	char:SetAttribute("KitTint", if kit then kit.color else nil)
	char:SetAttribute("VIP", Economy.owns(pl, "vip"))
end

-- A choice made in the shop during the match shows at once: the body is dressed again
Players.PlayerAdded:Connect(function(pl)
	pl:GetAttributeChangedSignal("Equip"):Connect(function()
		local a = actorOfPlayer(pl)
		local char = a and a.model
		if not a or not char then return end
		dressFromShop(pl, char)
		Rig.addBody(char, a.team, a.num, rng)
	end)
end)

-- A player in the locker room takes a place: team t, formation slot (client/Lobby). The computer player there steps
-- aside; the human is dressed in the team's kit and sent onto the pitch at that place.
local function joinMatch(pl: Player, t: number, slot: number): (boolean, string)
	if actorOfPlayer(pl) then return false, T("join.already") end
	local pick: Actor? = nil
	for _, a in actors do
		if a.team == t and a.slot == slot then pick = a end
	end
	if not pick then return false, T("join.noslot") end
	local p = pick :: Actor
	if p.player then return false, T("join.taken") end
	if owner == p then owner = nil end
	if setTaker == p and phase == "set" then phase = "play" end
	if p.model then p.model:Destroy() end
	p.model, p.hum, p.root = nil, nil, nil
	p.drib = nil
	p.player = pl
	p.name = pl.DisplayName
	p.lastActive = os.clock()
	p.warned = false
	pl.Team = Teams:FindFirstChild(Config.TEAMS[t].name) :: Team
	pl.Neutral = false
	pl:SetAttribute("InMatch", true)
	local function onChar(char: Model)
		task.wait(0.3)
		if p.player ~= pl then return end
		attach(p, char)
		dressFromShop(pl, char)
		Rig.dress(char, t, p.num)
		Rig.addBody(char, t, p.num, rng)
		char:SetAttribute("Team", t)
		char:SetAttribute("Role", p.role)
		local hum = p.hum
		if hum then
			hum.WalkSpeed = Config.WALK
			hum.UseJumpPower = false
			hum.JumpHeight = 0 -- no jumping in a football match (Roblox also hides the jump button)
		end
		local hx, hy = homeOf(p)
		place(p, hx, hy)
	end
	p.charConn = pl.CharacterAdded:Connect(onChar)
	if pl.Character then task.spawn(onChar, pl.Character) end
	publishLineups()
	comment(T("c.enters", { a = pl.DisplayName, team = TEAM(t) }), 0.3, true)
	if phase == "waiting" then
		task.delay(2, function() if phase == "waiting" then kickoff(1) end end)
	end
	return true, T("join.ok")
end

-- Back to the locker room: a computer player takes the place again
local function leaveMatch(pl: Player)
	local a = actorOfPlayer(pl)
	if not a then return end
	if a.charConn then a.charConn:Disconnect(); a.charConn = nil end
	if owner == a then owner = nil end
	a.player = nil
	a.drib = nil
	a.name = Config.NAMES[rng:NextInteger(1, #Config.NAMES)]
	pl:SetAttribute("InMatch", false)
	;(pl :: any).Team = nil
	pl.Neutral = true
	spawnBot(a)
	publishLineups()
	local anyone = false
	for _, b in actors do if b.player then anyone = true end end
	if not anyone then phase = "waiting"; publish() end
end

-- The VIP corner of the locker room: anybody else standing on its carpet is walked back out
task.spawn(function()
	local lobby = workspace:WaitForChild("Lobby")
	local zone = lobby:WaitForChild("VipZone") :: BasePart
	while true do
		task.wait(0.5)
		for _, pl in Players:GetPlayers() do
			local char = pl.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			if not root or not root:IsA("BasePart") or Economy.owns(pl, "vip") then continue end
			local rel = zone.CFrame:PointToObjectSpace(root.Position)
			if math.abs(rel.X) < zone.Size.X / 2 and math.abs(rel.Z) < zone.Size.Z / 2 and math.abs(rel.Y) < 8 then
				root.CFrame = CFrame.new(root.Position - Vector3.new(zone.Size.X / 2 + 3 + rel.X, 0, 0)) * root.CFrame.Rotation
				Message:FireClient(pl, T("vip.title"), T("vip.sub"), 2)
			end
		end
	end
end)

-- The all-time scorers board in the locker room (OrderedDataStore FC27Goals_v1, filled at each human goal)
task.spawn(function()
	local names: { [number]: string } = {}
	local rows = workspace:WaitForChild("Lobby"):WaitForChild("ScorersBoard"):WaitForChild("Board"):WaitForChild("Rows") :: TextLabel
	while true do
		pcall(function()
			local pages = game:GetService("DataStoreService"):GetOrderedDataStore("FC27Goals_v1"):GetSortedAsync(false, 10)
			local lines = {}
			for i, e in pages:GetCurrentPage() do
				local id = tonumber(e.key) or 0
				if not names[id] then
					local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(id) end)
					names[id] = if ok then n else "?"
				end
				table.insert(lines, T(if e.value > 1 then "board.row" else "board.row1", { i = i, a = names[id], n = e.value }))
			end
			rows.Text = if #lines > 0 then table.concat(lines, "\n") else T("board.none")
		end)
		task.wait(60)
	end
end)

-- Players arrive in the locker room (Pitch.buildLobby) and pick their place there
local Join = Instance.new("RemoteFunction")
Join.Name = "Join"
Join.OnServerInvoke = function(pl: Player, t: any, slot: any): (boolean, string)
	if type(t) ~= "number" or type(slot) ~= "number" or (t ~= 1 and t ~= 2) then return false, T("join.invalid") end
	return joinMatch(pl, t, slot)
end
Join.Parent = Net
local Leave = Instance.new("RemoteEvent")
Leave.Name = "Leave"
Leave.OnServerEvent:Connect(function(pl: Player)
	if not actorOfPlayer(pl) then return end
	leaveMatch(pl)
	pl:LoadCharacter() -- back in the locker room
end)
Leave.Parent = Net
Players.PlayerAdded:Connect(function(pl) pl:SetAttribute("InMatch", false) end)
for _, pl in Players:GetPlayers() do pl:SetAttribute("InMatch", false) end
-- Those who arrived while the pitch was being built get their character now
for _, pl in Players:GetPlayers() do
	if not pl.Character then task.spawn(function() pl:LoadCharacter() end) end
end

Players.PlayerRemoving:Connect(function(pl)
	leaveMatch(pl)
end)

-- A human keeper's dive (the Tacle button, labelled Plonger): towards the side he pushes, or the ball's; for a
-- moment he reaches 2.2 m instead of 1.3 m (tryControl)
local function gkDive(a: Actor, ix: number, iy: number)
	if a.diveT > 0 or held then return end
	local _, y = posOf(a)
	local lat = (ball.y - y) * dir[a.team]
	if math.abs(iy) > 0.3 then lat = iy * dir[a.team] end
	a.diveT = 0.7
	act(a, if lat > 0 then "diveR" else "diveL", 0.7)
end

Action.OnServerEvent:Connect(function(pl: Player, kind: any, dx: any, dz: any, power: any)
	local a = actorOfPlayer(pl)
	if not a or type(kind) ~= "string" then return end
	-- Any input keeps him in the match ("active" is sent by his machine while he moves)
	a.lastActive = os.clock()
	a.warned = false
	if kind == "active" then return end
	if phase ~= "play" and phase ~= "set" then return end
	if a.stun > 0 then
		if kind == "tackle" then label(a, T("lab.notyet"), Color3.fromRGB(220, 220, 220), 0.6) end
		return
	end
	dx = if type(dx) == "number" and dx == dx then dx else 0
	dz = if type(dz) == "number" and dz == dz then dz else 0
	power = if type(power) == "number" and power == power then math.clamp(power, 0, 1) else 0.5
	local n = math.sqrt(dx * dx + dz * dz)
	local fx, fy
	if n > 0.1 then fx, fy = dx / n, dz / n else fx, fy = facingOf(a) end
	if kind == "tackle" then
		if owner == a and held and a.role == "GK" then doLob(a, dir[a.team], fy * 0.4, 0.85) -- keeper's clearance (Dégager)
		elseif owner == a and not held then doSkill(a, fx, fy)
		elseif a.role == "GK" then gkDive(a, fx, fy)
		else doTackle(a) end
		return
	end
	-- A keeper with the ball in his hands plays it with Passe, Lob or Tir
	if owner ~= a or (held and a.role ~= "GK") then return end
	if kind == "pass" then doPass(a, fx, fy)
	elseif kind == "through" then doThrough(a, fx, fy)
	elseif kind == "shoot" then doShoot(a, fx, fy, power)
	elseif kind == "lob" then doLob(a, fx, fy, power)
	end
end)

-- Two footballers closer than 0.9 m are pushed apart (the web game's 1.1 m kept a computer player off a ball lying
-- next to a fallen player). Only computer players are moved: a human
-- player's character is moved by his own machine, so a computer player steps aside by the whole overlap.
local function separate()
	for i = 1, #actors do
		local a = actors[i]
		local ra = a.root
		if not ra then continue end
		for j = i + 1, #actors do
			local b = actors[j]
			local rb = b.root
			if not rb or (a.player and b.player) then continue end
			local d = Vector3.new(rb.Position.X - ra.Position.X, 0, rb.Position.Z - ra.Position.Z)
			local dm = d.Magnitude / M
			if dm >= 0.9 or dm < 1e-3 then continue end
			local push = d.Unit * (0.9 - dm) * M
			if a.player then
				rb.CFrame += push
			elseif b.player then
				ra.CFrame -= push
			else
				ra.CFrame -= push / 2
				rb.CFrame += push / 2
			end
		end
	end
end

-- A player who does not touch the controls for Config.IDLE_KICK seconds leaves the match: a computer player takes
-- his place (PlayerRemoving). He is warned 20 seconds before.
local function checkIdle()
	local t = os.clock()
	for _, a in actors do
		local pl = a.player
		if not pl then continue end
		if not a.lastActive then a.lastActive = t end
		local idle = t - (a.lastActive :: number)
		if idle > Config.IDLE_KICK then
			pl:Kick(Lang.t("idle.kick", nil, Lang.code(pl.LocaleId)))
		elseif idle > Config.IDLE_KICK - 20 and not a.warned then
			a.warned = true
			Message:FireClient(pl, T("idle.title"), T("idle.sub"), 3)
		end
	end
end
local idleT = 0

-- ---------- Main loop ----------
local sendT, aiT = 0, 0
local AI_DT = 0.1

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1)
	phaseT += dt
	for _, a in actors do
		a.cool = math.max(0, a.cool - dt)
		a.stun = math.max(0, a.stun - dt)
		if a.player then a.diveT = math.max(0, a.diveT - dt) end
	end
	separate()
	-- Possession, and a human keeper holding the ball more than 6 s plays it out
	if owner and phase == "play" then
		local o = owner :: Actor
		ms.teams[o.team].poss += dt
		if held and o.player then
			o.holdT -= dt
			if o.holdT < -4.7 then doLob(o, dir[o.team], gauss() * 0.3, 0.8) end
		end
	end
	idleT += dt
	if idleT >= 1 then idleT = 0; checkIdle() end
	for _, a in actors do
		if a.drib then dribbleStep(a) end
	end

	if phase == "play" or phase == "set" then
		clock += dt * 90 / (Config.MATCH_MINUTES * 60)
		if half == 1 and clock >= 45 then
			phase, phaseT = "break", 0
			resetBall(L / 2, W / 2)
			say(T("say.half"), T("sub.score", { a1 = ABBR(1), s1 = score[1], s2 = score[2], a2 = ABBR(2) }), 5)
		elseif half == 2 and clock >= 90 then
			phase, phaseT = "done", 0
			resetBall(L / 2, W / 2)
			-- End-of-match screen (client/Stats): score, scorers, team statistics, man of the match
			local players = {}
			for _, p in ms.players do table.insert(players, p) end
			table.sort(players, function(p, q) return p.goals * 10 + p.passes + p.tackles * 2 > q.goals * 10 + q.passes + q.tackles * 2 end)
			local total = math.max(0.001, ms.teams[1].poss + ms.teams[2].poss)
			Net:SetAttribute("MatchStats", game:GetService("HttpService"):JSONEncode({
				score = score, scorers = ms.scorers, teams = ms.teams,
				poss = { math.floor(ms.teams[1].poss / total * 100 + 0.5), math.floor(ms.teams[2].poss / total * 100 + 0.5) },
				best = players[1], at = workspace:GetServerTimeNow(),
			}))
			for _, a in actors do
				local pl = a.player
				if pl then
					Economy.stat(pl, "matches")
					if score[a.team] > score[3 - a.team] then Economy.earn(pl, "win"); Economy.stat(pl, "wins")
					elseif score[1] == score[2] then Economy.earn(pl, "draw") end
				end
			end
			local res = if score[1] == score[2] then T("say.draw") else T("say.wins", { team = TEAM(if score[1] > score[2] then 1 else 2) })
			say(T("say.end"), T("sub.result", { res = res, s1 = score[1], s2 = score[2] }), 8)
		end
	elseif phase == "goal" and phaseT > Config.GOAL_PAUSE then
		local conceded = if Net:GetAttribute("LastGoalTeam") == 1 then 2 else 1
		kickoff(conceded)
	elseif phase == "break" and phaseT > 6 then
		dir[1], dir[2] = -dir[1], -dir[2]
		half, clock = 2, 45
		kickoff(2)
	elseif phase == "done" and phaseT > 12 then
		score, half, clock, dir = { 0, 0 }, 1, 0, { 1, -1 }
		ms = freshStats()
		Net:SetAttribute("MatchBall", BALLS[rng:NextInteger(1, #BALLS)])
		for _, a in actors do
			a.yellow = 0
			if a.sentOff and not a.player then spawnBot(a) end
			a.sentOff = false
		end
		kickoff(1)
	end

	-- A restart whose ball nobody has any more (the taker dribbled or was tackled): play goes on, so that everybody
	-- goes for it again (in "set", nobody chases the ball)
	if phase == "set" and not owner and phaseT > 0.5 then phase = "play"; publish() end

	-- A computer player takes the restart after a short pause; a human has 10 s before it is played for him
	if phase == "set" and setTaker and owner == setTaker then
		local tk = setTaker :: Actor
		if (not tk.player and phaseT > (if setKindNow == "penalty" then 2.2 elseif setKindNow == "freekick" then 1.8 else 1.2)) or (tk.player and phaseT > 8) then
			if setKindNow == "corner" then
				doLob(tk, (oppGoalX(tk.team) - ball.x) / 12, (W / 2 - ball.y) / 34, 0.55)
			elseif setKindNow == "goalkick" then
				doLob(tk, dir[tk.team], gauss() * 0.4, 0.8)
			elseif setKindNow == "penalty" or (setKindNow == "freekick" and dist2(ball.x, ball.y, oppGoalX(tk.team), W / 2) < 30
				and rng:NextNumber() < 0.7) then
				-- At goal, towards one side (or straight down the middle now and then for a penalty)
				local gx = oppGoalX(tk.team)
				local side = if setKindNow == "penalty" and rng:NextNumber() < 0.15 then 0
					else (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(0.55, 0.95)
				local tx, ty = gx - ball.x, W / 2 + side * GH - ball.y
				local n = math.sqrt(tx * tx + ty * ty)
				doShoot(tk, tx / n, ty / n, rng:NextNumber(0.6, 0.9))
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
				local d = a.drib
				local bf = d and d.m.ball
				if held then
					ball.x, ball.y, ball.z = x + fx * 0.4, y + fy * 0.4, 1.0
				elseif bf then
					local f, sd, z = bf(math.clamp((now() - d.t0) / d.m.dur, 0, 1))
					ball.x, ball.y, ball.z = x + d.fx * f + d.sx * sd, y + d.fy * f + d.sy * sd, math.max(0, z)
				else
					ball.x, ball.y, ball.z = x + fx * 0.75, y + fy * 0.75, 0
				end
				ball.vx, ball.vy, ball.vz = vx, vy, 0
				-- A ball at someone's feet always stays on the pitch: only a shot can score. Carrying it over a line
				-- scored without a shot: an attacker pushed back by a player standing in front of the goal
				-- (separate) went over the line with the ball, again and again.
				if not held then
					-- A human may walk the ball into the opponent's goal between the posts (a goal); computer players
					-- must shoot (they could be pushed over the line by a human standing in front of the goal)
					ball.y = math.clamp(ball.y, 0.15, W - 0.15)
					local walkIn = a.player ~= nil and math.abs(ball.y - W / 2) < GH and phase == "play"
					if not (walkIn and dir[a.team] > 0) then ball.x = math.min(ball.x, L - 0.15) end
					if not (walkIn and dir[a.team] < 0) then ball.x = math.max(ball.x, 0.15) end
					if walkIn and (ball.x < 0 or ball.x > L) then
						boundsHow = "carried"
						checkBounds(if ball.x < 0 then 0.1 else L - 0.1)
						boundsHow = "free"
					end
				end
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
		-- What the server sees, shown small on screen next to the version (to understand a stuck ball)
		local c1, c2 = chaserOf(1), chaserOf(2)
		local humans = {}
		for _, a in actors do
			if a.player then table.insert(humans, `{a.name} ({Config.TEAMS[a.team].abbr} {a.num})`) end
		end
		Net:SetAttribute("Debug", string.format("%s%s · ballon : %s · chasseurs : %s / %s · cible : %s · humains : %s",
			phase, if phase == "set" then " " .. tostring(setKindNow) else "",
			if owner then (owner :: Actor).name .. (if held then " (mains)" else "") else "libre",
			if c1 then c1.name else "—", if c2 then c2.name else "—", if target then (target :: Actor).name else "—",
			if #humans > 0 then table.concat(humans, ", ") else "—"))
	end
	-- A human who loses the ball is told how (a shot or pass of his own is not a loss)
	if owner ~= lastOwner then
		local was = lastOwner
		if was and was.player and not was.kicked then
			local why = if owner then T("sub.tookball", { a = (owner :: Actor).name }) elseif phase == "goal" then T("sub.goalnow") else T("sub.loose")
			Message:FireClient(was.player, T("say.lost"), why, 1.3)
		end
		if was then was.kicked = false end
		lastOwner = owner
	end
end)

publish()

-- ---------- Test hook ----------
-- For scripts/inspect/match.luau (run on a server with Open Cloud): start a match between computer players and read
-- the score and every goal with its context. Not reachable from players' machines (ServerStorage).
local hook = Instance.new("BindableFunction")
hook.Name = "FC27Test"
hook.OnInvoke = function(cmd: string): any
	if cmd == "start" then
		if phase == "waiting" then kickoff(1) end
		return true
	end
	return { score1 = score[1], score2 = score[2], phase = phase, clock = clock, half = half, goals = goalLog,
		stats = stats, ball = { math.floor(ball.x), math.floor(ball.y) }, owner = if owner then (owner :: Actor).name else "-" }
end
hook.Parent = game:GetService("ServerStorage")

return {}
