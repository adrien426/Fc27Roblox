-- Draws the ball. The server sends its state 20 times a second; in between, this player's machine runs the
-- same ball physics so the flight stays smooth. A ball at someone's feet is drawn in front of that player.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local BallPhysics = require(Shared:WaitForChild("BallPhysics"))
local Net = ReplicatedStorage:WaitForChild("Net")
local BallState = Net:WaitForChild("BallState") :: any

local M = Config.M
local SIZE = 0.9 -- studs: a little bigger than life so it reads well on a phone
local R = SIZE / 2

local ball = Instance.new("Part")
ball.Name = "FC27Ball"
ball.Shape = Enum.PartType.Ball
ball.Size = Vector3.new(SIZE, SIZE, SIZE)
ball.Anchored = true
ball.CanCollide = false
ball.CanQuery = false
ball.CanTouch = false
ball.Material = Enum.Material.SmoothPlastic
ball.Color = Color3.fromRGB(248, 248, 248)
ball.Parent = workspace
-- Black patches, like a classic ball
for _, f in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right, Enum.NormalId.Top, Enum.NormalId.Bottom } do
	local gui = Instance.new("SurfaceGui")
	gui.Face = f
	gui.CanvasSize = Vector2.new(64, 64)
	gui.Parent = ball
	local spot = Instance.new("Frame")
	spot.Size = UDim2.fromScale(0.42, 0.42)
	spot.Position = UDim2.fromScale(0.29, 0.29)
	spot.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
	spot.BorderSizePixel = 0
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.3, 0)
	c.Parent = spot
	spot.Parent = gui
end

-- The web game's ball model (balls.glb, loaded by the server into ReplicatedStorage.FC27Assets) replaces the plain
-- sphere when it is there: its parts are scaled to the ball, centred on it and welded, the sphere becomes invisible.
task.spawn(function()
	local assets = ReplicatedStorage:WaitForChild("FC27Assets", 15)
	local balls = assets and assets:WaitForChild("Balls", 15)
	if not balls then return end
	local src = balls:FindFirstChild(Config.BALL_MODEL, true) or balls
	local parts: { BasePart } = {}
	if src:IsA("BasePart") then table.insert(parts, src) end
	for _, d in src:GetDescendants() do
		if d:IsA("BasePart") then table.insert(parts, d) end
	end
	if #parts == 0 then return end
	local m = Instance.new("Model")
	m.Name = "BallModel"
	for _, p in parts do
		local c = p:Clone()
		c:ClearAllChildren()
		for _, k in p:GetChildren() do
			if k:IsA("SurfaceAppearance") then k:Clone().Parent = c end
		end
		c.Parent = m
	end
	local cf, size = m:GetBoundingBox()
	m:ScaleTo(SIZE / math.max(size.X, size.Y, size.Z, 1e-3))
	cf = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() + (ball.Position - cf.Position))
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanQuery = false
			p.CanTouch = false
			p.Massless = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = ball
			w.Part1 = p
			w.Parent = p
		end
	end
	for _, g in ball:GetChildren() do
		if g:IsA("SurfaceGui") then g:Destroy() end
	end
	ball.Transparency = 1
	m.Parent = ball
end)

local shadow = Instance.new("Part")
shadow.Name = "FC27BallShadow"
shadow.Shape = Enum.PartType.Cylinder
shadow.Size = Vector3.new(0.05, SIZE * 1.1, SIZE * 1.1)
shadow.Anchored = true
shadow.CanCollide = false
shadow.CanQuery = false
shadow.CanTouch = false
shadow.CastShadow = false
shadow.Color = Color3.new(0, 0, 0)
shadow.Transparency = 0.55
shadow.Material = Enum.Material.SmoothPlastic
shadow.Parent = workspace

local state: BallPhysics.Ball = { x = Config.L / 2, y = Config.W / 2, z = 0, vx = 0, vy = 0, vz = 0, spin = 0, tspin = 0 }
local ownerModel: Model? = nil
local held = false
local shown = Config.toWorld(state.x, state.y, 0) + Vector3.new(0, R, 0)
local spin = CFrame.identity

BallState.OnClientEvent:Connect(function(s: any, o: any)
	if type(s) ~= "table" then return end
	state.x, state.y, state.z, state.vx, state.vy, state.vz, state.spin, state.tspin = s[1], s[2], s[3], s[4], s[5], s[6], s[7], s[8]
	held = s[9] == 1
	ownerModel = if typeof(o) == "Instance" and o:IsA("Model") then o else nil
end)

RunService.RenderStepped:Connect(function(dt)
	local want: Vector3
	local root = ownerModel and ownerModel.Parent and ownerModel:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local lv = root.CFrame.LookVector
		local flat = Vector3.new(lv.X, 0, lv.Z)
		flat = if flat.Magnitude > 1e-3 then flat.Unit else Vector3.xAxis
		local groundY = Config.GROUND_Y
		if held then
			want = Vector3.new(root.Position.X, groundY + 1.0 * M, root.Position.Z) + flat * 0.4 * M
		else
			want = Vector3.new(root.Position.X, groundY + R, root.Position.Z) + flat * 0.75 * M
		end
	else
		BallPhysics.advance(state, dt)
		want = Config.toWorld(state.x, state.y, state.z) + Vector3.new(0, R, 0)
	end
	-- Smooth out the small jumps when a new snapshot corrects the local flight; a big jump is a restart: snap
	local gap = (want - shown).Magnitude
	shown = if gap > 10 then want else shown:Lerp(want, 1 - math.exp(-dt * 30))
	local moved = Vector3.new(want.X - ball.Position.X, 0, want.Z - ball.Position.Z)
	if moved.Magnitude > 1e-3 and moved.Magnitude < 5 then
		spin = CFrame.fromAxisAngle(moved.Unit:Cross(Vector3.yAxis), -moved.Magnitude / R) * spin
	end
	ball.CFrame = CFrame.new(shown) * spin
	shadow.CFrame = CFrame.new(Vector3.new(shown.X, Config.GROUND_Y + 0.13, shown.Z)) * CFrame.Angles(0, 0, math.pi / 2)
	local h = math.max(0, shown.Y - Config.GROUND_Y)
	shadow.Transparency = math.clamp(0.5 + h / 40, 0.5, 0.92)
end)
