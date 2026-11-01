--!strict
-- Animates every footballer that wears the web game's body (tag "FC27Body", added by server/Rig) with the web
-- game's clips, on this player's machine. Like the web version, each frame picks one clip and a time in it:
-- an action sent by the server (kick, pass, tackle, dive...), a keeper holding the ball, a throw-in, goal and
-- full-time celebrations, otherwise idle / walk / jog / run / backwards / sideways from the body's speed.
-- Changing clip blends from the last pose. Also draws the shirt number on the back.
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Skeleton = require(Shared:WaitForChild("Skeleton"))
local Net = ReplicatedStorage:WaitForChild("Net")
local BallState = Net:WaitForChild("BallState") :: any

local M = Config.M
local FADE = 0.18 -- seconds to blend into a new clip
local FAR = 160 -- studs: bodies further away are updated 15 times a second

-- Timed actions: clip, part of it to play (seconds), and for dives the landing played after it at normal speed.
-- Windows measured on the clips in the web game.
type Window = { clip: string, from: number, to: number, rest: number? }
local ACTS: { [string]: Window } = {
	kick = { clip = "kick", from = 0.37, to = 1.0 },
	pass = { clip = "pass", from = 0.4, to = 1.1 },
	throwIn = { clip = "throwIn", from = 1.25, to = 2.2 },
	head = { clip = "head", from = 0.45, to = 1.45 },
	tackle = { clip = "tackle", from = 0.1, to = 1.3 },
	trip = { clip = "trip", from = 0, to = 1.2 },
	gkCatch = { clip = "gkCatch", from = 0.12, to = 0.8 },
	diveL = { clip = "diveL", from = 0.93, to = 2.1, rest = 2.9 },
	diveR = { clip = "diveR", from = 0.93, to = 1.43, rest = 2.3 },
	siuu = { clip = "siuu", from = 0, to = 2.95 },
}

-- Locomotion: speeds in metres per second at which each clip plays at its normal pace
local WALK_PACE, JOG_PACE, RUN_PACE, SIDE_PACE, BACK_PACE = 1.4, 3.4, 6.8, 2.6, 2.2

type Body = {
	model: Model,
	body: Model,
	root: BasePart?,
	rig: Skeleton.Rig,
	seed: number,
	cur: string,
	last: Skeleton.Pose?,
	from: Skeleton.Pose?,
	fade: number,
	phase: { [string]: number },
	acc: number,
	plate: Part?,
	spine: Bone?,
	plateOff: CFrame?,
}

local bodies: { [Model]: Body } = {}
local ownerModel: Model? = nil
local held = false

BallState.OnClientEvent:Connect(function(s: any, o: any)
	if type(s) ~= "table" then return end
	held = s[9] == 1
	ownerModel = if typeof(o) == "Instance" and o:IsA("Model") then o else nil
end)

-- Shirt number: a small plate that follows the upper back
local function makePlate(st: Body)
	local num = st.model:GetAttribute("Num")
	local team = Config.TEAMS[st.model:GetAttribute("Team") :: number or 1]
	if typeof(num) ~= "number" or not team then return end
	for _, list in st.rig.bones do
		for _, b in list do
			if string.find(b.Name, "Spine2$") then st.spine = b end
		end
	end
	if not st.spine then return end
	local p = Instance.new("Part")
	p.Name = "FC27Number"
	p.Size = Vector3.new(0.55, 0.6, 0.02)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 80
	gui.LightInfluence = 1
	gui.Parent = p
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = tostring(num)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	local c = team.color
	t.TextColor3 = if c.R + c.G + c.B > 2.2 then Color3.new(0.1, 0.1, 0.1) else Color3.new(1, 1, 1)
	t.Parent = gui
	p.Parent = st.body
	st.plate = p
	-- Where it sits, measured once in the bind pose (the body faces where its root faces): on the shirt's back,
	-- 12 cm behind the Spine2 bone and 3 cm below it in player.glb, its front face (the number) turned backwards.
	-- Kept relative to the bone, so it follows the back whatever axes the importer gave the bone.
	local root = st.root
	local spine = st.spine :: Bone
	if root then
		local look = root.CFrame.LookVector
		local fwd = Vector3.new(look.X, 0, look.Z).Unit
		local pos = spine.TransformedWorldCFrame.Position - fwd * (0.125 * M) - Vector3.new(0, 0.03 * M, 0)
		st.plateOff = spine.TransformedWorldCFrame:ToObjectSpace(CFrame.lookAt(pos, pos - fwd))
	end
end

-- Reported once in the console (F9) when the footballer cannot be animated, to know why
local reported = false
local function report(msg: string)
	if reported then return end
	reported = true
	warn("[FC27] " .. msg)
end

local function add(inst: Instance, tries: number?)
	if not inst:IsA("Model") then return end
	local body = inst :: Model
	local parent = body.Parent
	if not parent or not parent:IsA("Model") then return end
	if not CollectionService:HasTag(body, "FC27Body") then return end
	local model = parent :: Model
	local cur = bodies[model]
	if cur and cur.body == body then return end
	local rig = Skeleton.bind(body)
	if not rig then
		-- Its bones may still be arriving from the server: try again for a few seconds
		local n = (tries or 0) + 1
		if n < 20 then
			task.delay(0.5, add, body, n)
		else
			local parts = 0
			for _, d in body:GetDescendants() do
				if d:IsA("BasePart") then parts += 1 end
			end
			report(`The footballer model has no bones ({parts} parts): it was imported without its skeleton, so it cannot be animated`)
		end
		return
	end
	if not reported then
		local walk = Skeleton.clip("walk")
		local matched, names = 0, {}
		for k in (rig :: Skeleton.Rig).bones do
			if walk and walk.bones[k] then matched += 1 end
			if #names < 6 then table.insert(names, k) end
		end
		if matched == 0 then
			report(`The footballer's bones do not match the clips (bones: {table.concat(names, ", ")}): no animation`)
		end
	end
	local r = model:FindFirstChild("HumanoidRootPart")
	local root: BasePart? = if r and r:IsA("BasePart") then r :: BasePart else nil
	local st: Body = {
		model = model, body = body, root = root, rig = rig :: Skeleton.Rig,
		seed = math.random(0, 1000), cur = "", fade = 1, phase = {}, acc = 0,
	}
	bodies[model] = st
	makePlate(st)
end

local function remove(body: Instance)
	for m, st in bodies do
		if st.body == body then
			if st.plate then st.plate:Destroy() end
			bodies[m] = nil
		end
	end
end

CollectionService:GetInstanceAddedSignal("FC27Body"):Connect(add)
CollectionService:GetInstanceRemovedSignal("FC27Body"):Connect(remove)
for _, b in CollectionService:GetTagged("FC27Body") do task.spawn(add, b) end

-- Looping clip with its own running time (so a jog keeps its stride when the pace changes)
local function loop(st: Body, clip: string, dt: number, rate: number): (string, number)
	local t = st.phase[clip] or (st.seed % 97) / 13
	t += dt * rate
	st.phase[clip] = t
	return clip, t
end

local function choose(st: Body, now: number, dt: number): (string, number)
	local m = st.model
	-- 1. An action from the server
	local act = m:GetAttribute("Act")
	local at = m:GetAttribute("ActAt")
	if typeof(act) == "string" and typeof(at) == "number" then
		local w = ACTS[act]
		if w then
			local el = now - at
			local d = m:GetAttribute("ActDur")
			local dur = if typeof(d) == "number" and d > 0 then d else w.to - w.from
			if el >= 0 and el < dur then
				return w.clip, w.from + (w.to - w.from) * el / dur
			end
			local rest = w.rest
			if rest and el >= dur and el < dur + (rest - w.to) then
				return w.clip, w.to + (el - dur)
			end
		end
	end
	-- 2. Keeper holding the ball against his chest; taker holding it overhead for a throw-in
	if ownerModel == m then
		if held then return "catch", 0.95 end
		if Net:GetAttribute("Phase") == "set" and Net:GetAttribute("SetKind") == "throw" then return "throwIn", 1.0 end
	end
	-- 3. Goal and full time
	local phase = Net:GetAttribute("Phase")
	local team = m:GetAttribute("Team")
	if phase == "goal" and typeof(team) == "number" then
		local g = Net:GetAttribute("LastGoalTeam")
		local ga = Net:GetAttribute("GoalAt")
		local el = if typeof(ga) == "number" then now - ga else 0
		if team == g then
			if st.seed % 2 == 1 then return "victory", math.min(el, 4.4) end
			return loop(st, "win", dt, 0.9)
		end
		return "defeat", math.min(el + (st.seed % 3) * 0.3, 4.6)
	end
	if phase == "done" and typeof(team) == "number" then
		local s1, s2 = Net:GetAttribute("Score1") :: number?, Net:GetAttribute("Score2") :: number?
		if s1 and s2 and s1 ~= s2 then
			local won = (if s1 > s2 then 1 else 2) == team
			if won then return loop(st, "dance", dt, 1) end
			return "defeat", 4.6
		end
	end
	-- 4. Moving
	local isGK = m:GetAttribute("Role") == "GK"
	if not st.root then return loop(st, "idleN", dt, 1) end
	local root = st.root :: BasePart
	local v = root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local speed = flat.Magnitude / M
	if speed < 0.4 then
		if isGK then return loop(st, "gkIdle", dt, 1) end
		return loop(st, "idleN", dt, 1)
	end
	local cf = root.CFrame
	local fwd = flat:Dot(cf.LookVector) / (speed * M)
	local side = flat:Dot(cf.RightVector) / (speed * M)
	if fwd < -0.5 then return loop(st, "back", dt, math.clamp(speed / BACK_PACE, 0.6, 1.8)) end
	if math.abs(side) > 0.75 then
		if isGK then return loop(st, if side < 0 then "gkSide" else "gkSideR", dt, math.clamp(speed / SIDE_PACE, 0.6, 1.8)) end
		return loop(st, if side < 0 then "strL" else "strR", dt, math.clamp(speed / SIDE_PACE, 0.6, 1.8))
	end
	if speed < 2.2 then return loop(st, "walk", dt, math.clamp(speed / WALK_PACE, 0.5, 1.6)) end
	if speed < 4.5 then return loop(st, "jog", dt, math.clamp(speed / JOG_PACE, 0.6, 1.6)) end
	return loop(st, "run", dt, math.clamp(speed / RUN_PACE, 0.6, 1.6))
end

local function update(st: Body, now: number, dt: number)
	local name, t = choose(st, now, dt)
	local clip = Skeleton.clip(name) or Skeleton.clip("idle")
	if not clip then return end
	local pose = Skeleton.sample(st.rig, clip :: Skeleton.Clip, t)
	if name ~= st.cur then
		st.from = st.last
		st.fade = 0
		st.cur = name
	end
	if st.from and st.fade < FADE then
		st.fade += dt
		pose = Skeleton.blend(st.from :: Skeleton.Pose, pose, math.min(1, st.fade / FADE))
	end
	Skeleton.apply(st.rig, pose)
	st.last = pose
end

RunService.RenderStepped:Connect(function(dt)
	local now = workspace:GetServerTimeNow()
	local cam = workspace.CurrentCamera
	local eye = if cam then cam.CFrame.Position else Vector3.zero
	for model, st in bodies do
		if not st.body.Parent or not model.Parent then
			if st.plate then st.plate:Destroy() end
			bodies[model] = nil
			continue
		end
		st.acc += dt
		local far = st.root ~= nil and ((st.root :: BasePart).Position - eye).Magnitude > FAR
		if far and st.acc < 1 / 15 then continue end
		update(st, now, st.acc)
		st.acc = 0
		local plate, spine, off = st.plate, st.spine, st.plateOff
		if plate and spine and off then
			plate.CFrame = spine.TransformedWorldCFrame * off
		end
	end
end)
