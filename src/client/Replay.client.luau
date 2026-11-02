--!strict
-- Goal replays, like the web game: this machine keeps the last seconds of play (every footballer's position and
-- action, and the ball), and after a goal shows them again at half speed from a TV camera that follows the ball
-- closely, from the side and a little behind the action. All the footballers are shown by doubles (clones, animated by client/Bodies at half speed, "Slow" = 2), the
-- real ones are hidden meanwhile. "Passer" ends it. The server waits Config.GOAL_PAUSE before the kick-off.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))
local Net = ReplicatedStorage:WaitForChild("Net")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local KEEP = 10 -- seconds kept (the replay starts Config.REPLAY_AT seconds after the goal, after the celebration)
local BEFORE, AFTER = 2.6, 0.9 -- replayed: seconds before the ball crosses the line, and after (the ball in the net)
local SLOW = 2 -- half speed
local MAX_DOUBLES = 24 -- everybody: footballers left live would walk about at full speed in the middle of it

type Snap = { cf: CFrame, act: string?, actAt: number?, actDur: number? }
type Frame = { t: number, st: number, ball: CFrame?, models: { [Model]: Snap } }
local frames: { Frame } = {}

-- ---------- Recording ----------
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	if acc < 0.05 then return end
	acc = 0
	local f: Frame = { t = os.clock(), st = workspace:GetServerTimeNow(), models = {} }
	local ball = workspace:FindFirstChild("FC27Ball")
	if ball and ball:IsA("BasePart") then f.ball = ball.CFrame end
	for _, body in CollectionService:GetTagged("FC27Body") do
		local m = body.Parent
		if not m or not m:IsA("Model") or m:GetAttribute("Replay") then continue end
		local root = m:FindFirstChild("HumanoidRootPart")
		if not root or not root:IsA("BasePart") then continue end
		local act = m:GetAttribute("Act")
		f.models[m] = { cf = root.CFrame, act = if type(act) == "string" then act else nil,
			actAt = m:GetAttribute("ActAt") :: number?, actDur = m:GetAttribute("ActDur") :: number? }
	end
	table.insert(frames, f)
	while #frames > 0 and f.t - frames[1].t > KEEP do table.remove(frames, 1) end
end)

-- ---------- Playback ----------
local playing = false
local restoreGuis: (() -> ())? = nil -- puts the screen back if the replay fails half-way
local function sample(t: number): (Frame?, Frame?, number)
	for i = 1, #frames - 1 do
		local a, b = frames[i], frames[i + 1]
		if t >= a.t and t <= b.t then return a, b, (t - a.t) / math.max(b.t - a.t, 1e-3) end
	end
	return frames[#frames], frames[#frames], 0
end

-- Hides a real footballer (or the ball) during the replay; the labels over his head that were showing come back
-- after it, and only those
local shownLabels: { BillboardGui } = {}
local function hide(m: Instance, on: boolean)
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then (d :: any).LocalTransparencyModifier = if on then 1 else 0
		elseif d:IsA("BillboardGui") and on and d.Enabled then d.Enabled = false; table.insert(shownLabels, d) end
	end
end
local function showLabels()
	for _, g in shownLabels do if g.Parent then g.Enabled = true end end
	shownLabels = {}
end

-- What each replay did, sent to the server's telltale (server/Telemetry): to understand a strange replay
local Report = Net:WaitForChild("Report", 10) :: RemoteEvent?
local info: { [string]: any } = {}
local function report()
	if Report then pcall(function() (Report :: RemoteEvent):FireServer("replay", info) end) end
end

local function play(goalT: number)
	info = { frames = #frames, inMatch = player:GetAttribute("InMatch") == true }
	if playing or player:GetAttribute("InMatch") ~= true or #frames < 10 then info.skipped = "not in match / no frames"; report(); return end
	-- The moment the ball crossed the line, found in the recording: the message announcing the goal reaches this
	-- machine a little later, and the ball seen here is a little late too
	local arrived = goalT
	for _, f in frames do
		local b = f.ball
		if b and f.t > arrived - 3 and f.t < arrived + 1.5 then
			local px, py = Config.toPitch(b.Position)
			if (px < 0 or px > Config.L) and math.abs(py - Config.W / 2) < Config.GOAL_HALF + 1 then
				goalT = f.t
				break
			end
		end
	end
	info.crossing = goalT - arrived
	local t0, t1 = goalT - BEFORE, math.min(goalT + AFTER, frames[#frames].t)
	-- Not past the moment the ball is put back for the kick-off (a jump)
	for i = 2, #frames do
		local a, b = frames[i - 1].ball, frames[i].ball
		if a and b and frames[i].t > goalT and (a.Position - b.Position).Magnitude > 12 then
			t1 = math.min(t1, frames[i - 1].t)
			break
		end
	end
	if frames[1].t > t0 then t0 = frames[1].t end
	info.span = t1 - t0
	info.recorded = frames[#frames].t - frames[1].t
	if t1 - t0 < 1 then info.skipped = "too short"; report(); return end
	playing = true
	local goalFrame = select(1, sample(goalT)) :: Frame
	local ballAtGoal = (goalFrame.ball or CFrame.new()).Position
	do
		local n = 0
		for _ in goalFrame.models do n += 1 end
		info.models = n
		info.ballAtGoal = { Config.toPitch(ballAtGoal) }
		info.hasBall = goalFrame.ball ~= nil
	end

	-- Doubles of the footballers nearest the ball when it went in
	local near = {}
	for m, snap in goalFrame.models do
		if m.Parent then table.insert(near, { m = m, d = (snap.cf.Position - ballAtGoal).Magnitude }) end
	end
	table.sort(near, function(a, b) return a.d < b.d end)
	local doubles: { [Model]: Model } = {}
	local folder = Instance.new("Folder")
	folder.Name = "FC27Replay"
	folder.Parent = workspace
	for i = 1, math.min(MAX_DOUBLES, #near) do
		local m = near[i].m :: Model
		m.Archivable = true
		local ok, c = pcall(function() return m:Clone() end)
		if not ok or not c then continue end
		local clone = c :: Model
		for _, d in clone:GetDescendants() do
			if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false; d.CanQuery = false; d.CanTouch = false
			elseif d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Humanoid") or d:IsA("BillboardGui") or d:IsA("Sound") then d:Destroy() end
		end
		clone:SetAttribute("Replay", true)
		clone:SetAttribute("Slow", SLOW)
		clone.Parent = folder
		doubles[m] = clone
	end
	do
		local n = 0
		for _ in doubles do n += 1 end
		info.doubles = n
	end
	-- Hide the real ones and the real ball
	local hidden: { Instance } = {}
	for m in doubles do hide(m, true); table.insert(hidden, m) end
	local realBall = workspace:FindFirstChild("FC27Ball")
	local shadow = workspace:FindFirstChild("FC27BallShadow")
	if realBall then hide(realBall, true); (realBall :: any).LocalTransparencyModifier = 1; table.insert(hidden, realBall) end
	if shadow then (shadow :: any).LocalTransparencyModifier = 1 end
	local ghost: BasePart? = nil
	if realBall and realBall:IsA("BasePart") then
		realBall.Archivable = true
		local g = realBall:Clone()
		for _, d in g:GetDescendants() do
			-- The ball model's pieces stay welded to the ghost (only the ghost itself is anchored)
			if d:IsA("BasePart") then (d :: any).LocalTransparencyModifier = 0
			elseif d:IsA("Trail") then d.Enabled = true end
		end
		g.LocalTransparencyModifier = 0
		g.Anchored = true
		g.Parent = folder
		ghost = g
	end

	-- Nothing else on the screen meanwhile (score, big messages, buttons): only the replay
	local pg = player:WaitForChild("PlayerGui")
	local switched: { ScreenGui } = {}
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled then g.Enabled = false; table.insert(switched, g) end
	end
	local fov = camera.FieldOfView
	restoreGuis = function()
		for _, g in switched do if g.Parent then g.Enabled = true end end
		camera.FieldOfView = fov
	end

	-- Banner and skip button
	local gui = Instance.new("ScreenGui")
	gui.Name = "FC27ReplayGui"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 11
	gui.Parent = player:WaitForChild("PlayerGui")
	for _, top in { true, false } do
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 0.06, 0)
		bar.Position = if top then UDim2.new() else UDim2.new(0, 0, 0.94, 0)
		bar.BackgroundColor3 = Color3.new(0, 0, 0)
		bar.BorderSizePixel = 0
		bar.Parent = gui
	end
	local tag = Instance.new("TextLabel")
	tag.AnchorPoint = Vector2.new(0.5, 0)
	tag.Position = UDim2.new(0.5, 0, 0.07, 0)
	tag.Size = UDim2.fromOffset(200, 30)
	tag.BackgroundColor3 = Color3.fromRGB(200, 30, 40)
	tag.Text = Lang.t("replay.tag")
	tag.TextColor3 = Color3.new(1, 1, 1)
	tag.Font = Enum.Font.GothamBlack
	tag.TextSize = 18
	tag.Parent = gui
	Instance.new("UICorner", tag).CornerRadius = UDim.new(0, 6)
	local skip = Instance.new("TextButton")
	skip.AnchorPoint = Vector2.new(1, 1)
	skip.Position = UDim2.new(1, -20, 0.92, 0)
	skip.Size = UDim2.fromOffset(120, 38)
	skip.BackgroundColor3 = Color3.fromRGB(242, 194, 48)
	skip.Text = Lang.t("btn.skip")
	skip.Font = Enum.Font.GothamBlack
	skip.TextSize = 16
	skip.TextColor3 = Color3.fromRGB(14, 24, 18)
	skip.Parent = gui
	Instance.new("UICorner", skip).CornerRadius = UDim.new(0, 8)

	-- TV camera
	-- Close to the ball (about 15 m), on the side of the main stand and a little behind the play, looking towards
	-- the goal; it never goes past the advertising boards nor into the goal.
	local M = Config.M
	local goalRight = Config.toPitch(ballAtGoal) > Config.L / 2
	local gs = if goalRight then 1 else -1
	local function eyeFor(b: Vector3): Vector3
		local bx, by = Config.toPitch(b)
		local ex = math.clamp(bx - gs * 9, 2, Config.L - 2)
		local ey = math.max(by - 13, -2)
		return Config.toWorld(ex, ey, 6)
	end
	local eye: Vector3? = nil
	local look: Vector3? = nil
	camera.FieldOfView = 50
	local done = false
	skip.Activated:Connect(function() done = true end)
	local start = os.clock()
	local renders = 0
	info.ghost = ghost ~= nil
	local lastPos: { [Model]: Vector3 } = {}
	RunService:BindToRenderStep("FC27Replay", Enum.RenderPriority.Camera.Value + 2, function()
		local tt = t0 + (os.clock() - start) / SLOW
		if tt >= t1 or done then return end
		renders += 1
		local fa, fb, k = sample(tt)
		if not fa or not fb then return end
		local a, b = fa :: Frame, fb :: Frame
		for m, clone in doubles do
			local sa, sb = a.models[m], b.models[m]
			if not sa then continue end
			local cf = if sb then sa.cf:Lerp(sb.cf, k) else sa.cf
			clone:PivotTo(cf)
			local rv = if sb then (sb.cf.Position - sa.cf.Position) / math.max(b.t - a.t, 1e-3) else Vector3.zero
			clone:SetAttribute("ReplayVel", Vector3.new(rv.X, 0, rv.Z))
			lastPos[m] = cf.Position
			-- Its action (kick, tackle...) as recorded, at half speed
			if sa.act and type(sa.actAt) == "number" then
				local serverT = a.st + (b.st - a.st) * k
				clone:SetAttribute("Act", sa.act)
				clone:SetAttribute("ActDur", (sa.actDur or 0) * SLOW)
				clone:SetAttribute("ActAt", workspace:GetServerTimeNow() - (serverT - (sa.actAt :: number)) * SLOW)
			end
		end
		local g = ghost
		if g and a.ball then
			local bc = if b.ball then (a.ball :: CFrame):Lerp(b.ball :: CFrame, k) else a.ball :: CFrame
			g.CFrame = bc
			camera.CameraType = Enum.CameraType.Scriptable
			-- Smoothed, so that a shot does not jerk the camera; it aims a little ahead of the ball, towards the goal
			local target = bc.Position + Vector3.new(gs * 2 * M, 0, 0)
			local e, l = eye, look
			if e and l then
				e = e:Lerp(eyeFor(bc.Position), 0.06)
				l = l:Lerp(target, 0.2)
			else
				e, l = eyeFor(bc.Position), target
			end
			eye, look = e, l
			camera.CFrame = CFrame.lookAt(e :: Vector3, l :: Vector3)
		end
	end)
	while not done and os.clock() - start < (t1 - t0) * SLOW do task.wait() end

	info.played = os.clock() - start
	info.skippedByPlayer = done
	info.fps = renders / math.max(0.1, os.clock() - start)
	-- Back to the match
	RunService:UnbindFromRenderStep("FC27Replay")
	gui:Destroy()
	folder:Destroy()
	for _, h in hidden do
		if h.Parent then hide(h, false) end
		if h:IsA("BasePart") then (h :: any).LocalTransparencyModifier = 0 end
	end
	showLabels()
	if shadow then (shadow :: any).LocalTransparencyModifier = 0 end
	if restoreGuis then restoreGuis(); restoreGuis = nil end
	camera.CameraType = Enum.CameraType.Custom
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then camera.CameraSubject = hum end
	playing = false
	report()
end

Net:GetAttributeChangedSignal("GoalAt"):Connect(function()
	local goalT = os.clock()
	task.delay(Config.REPLAY_AT, function()
		local ok, err = pcall(function() play(goalT) end)
		if not ok then
			warn("[FC27] replay: " .. tostring(err))
			info.error = tostring(err)
			report()
			-- Everything visible again (the footballers and the ball were hidden for the replay)
			for _, body in CollectionService:GetTagged("FC27Body") do
				local m = body.Parent
				if m and not m:GetAttribute("Replay") then hide(m, false) end
			end
			for _, n in { "FC27Ball", "FC27BallShadow" } do
				local b = workspace:FindFirstChild(n)
				if b then hide(b, false); if b:IsA("BasePart") then (b :: any).LocalTransparencyModifier = 0 end end
			end
			showLabels()
			playing = false
			RunService:UnbindFromRenderStep("FC27Replay")
			local r = restoreGuis
			if r then restoreGuis = nil; pcall(r) end
			local f = workspace:FindFirstChild("FC27Replay")
			if f then f:Destroy() end
			local g = player:FindFirstChild("PlayerGui") and (player :: any).PlayerGui:FindFirstChild("FC27ReplayGui")
			if g then g:Destroy() end
			camera.CameraType = Enum.CameraType.Custom
		end
	end)
end)
