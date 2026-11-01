--!strict
-- The arrival in the stadium, like the web game's intro: the camera flies round the stadium, the match ball is
-- revealed spinning (Net attribute MatchBall, drawn by the server), then the line-ups of both sides (Net attribute
-- Lineups). A tap, a click or any key skips it. Played once, when the player arrives.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = ReplicatedStorage:WaitForChild("Net")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local M = Config.M

local DURATION = 10
local BALL_NAMES = {
	classique = "Classique", etoiles = "Étoiles", jabu = "Jabulani", brazu = "Brazuca", euro = "Euro",
}
local ROLE = { GK = "Gardien", DF = "Défenseur", MF = "Milieu", FW = "Attaquant" }

local gui = Instance.new("ScreenGui")
gui.Name = "FC27Intro"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10
gui.Parent = player:WaitForChild("PlayerGui")

local DARK = Color3.fromRGB(14, 24, 18)
local GOLD = Color3.fromRGB(242, 194, 48)

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do (t :: any)[k] = v end
	t.Parent = parent
	return t
end

-- Match ball card: the model spinning in a viewport, and its name
local ballCard = Instance.new("Frame")
ballCard.AnchorPoint = Vector2.new(0.5, 0.5)
ballCard.Position = UDim2.fromScale(0.5, 0.45)
ballCard.Size = UDim2.fromOffset(260, 250)
ballCard.BackgroundColor3 = DARK
ballCard.BackgroundTransparency = 0.2
ballCard.Visible = false
ballCard.Parent = gui
Instance.new("UICorner", ballCard).CornerRadius = UDim.new(0, 14)
text(ballCard, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 10), Text = "BALLON DU MATCH", TextSize = 16, TextColor3 = GOLD })
local ballName = text(ballCard, { Size = UDim2.new(1, 0, 0, 30), Position = UDim2.new(0, 0, 1, -42), Text = "", TextSize = 22 })
local view = Instance.new("ViewportFrame")
view.Size = UDim2.fromOffset(170, 160)
view.Position = UDim2.fromOffset(45, 42)
view.BackgroundTransparency = 1
view.Parent = ballCard
local viewCam = Instance.new("Camera")
viewCam.FieldOfView = 30
viewCam.Parent = view
view.CurrentCamera = viewCam
local spinning: Model? = nil

local function showBall()
	local key = Net:GetAttribute("MatchBall")
	ballName.Text = if type(key) == "string" then (BALL_NAMES[key] or key) else "Classique"
	local assets = ReplicatedStorage:FindFirstChild("FC27Assets")
	local balls = assets and assets:FindFirstChild("Balls")
	local src = balls and type(key) == "string" and balls:FindFirstChild(key, true)
	if not src then return end
	local m = Instance.new("Model")
	if src:IsA("BasePart") then src:Clone().Parent = m end
	for _, d in (src :: Instance):GetDescendants() do
		if d:IsA("BasePart") then d:Clone().Parent = m end
	end
	local cf, size = m:GetBoundingBox()
	m:PivotTo(m:GetPivot() - cf.Position)
	m.Parent = view
	local r = math.max(size.X, size.Y, size.Z)
	viewCam.CFrame = CFrame.lookAt(Vector3.new(0, r * 0.4, r * 2.2), Vector3.zero)
	spinning = m
end

-- Line-ups: two columns, number, name and position; humans highlighted
local lineups = Instance.new("Frame")
lineups.AnchorPoint = Vector2.new(0.5, 0.5)
lineups.Position = UDim2.fromScale(0.5, 0.5)
lineups.Size = UDim2.fromOffset(560, 330)
lineups.BackgroundTransparency = 1
lineups.Visible = false
lineups.Parent = gui

local function column(t: number, list: { any })
	local team = Config.TEAMS[t]
	local col = Instance.new("Frame")
	col.Size = UDim2.new(0.5, -8, 1, 0)
	col.Position = UDim2.new(if t == 1 then 0 else 0.5, if t == 1 then 0 else 8, 0, 0)
	col.BackgroundColor3 = DARK
	col.BackgroundTransparency = 0.15
	col.Parent = lineups
	Instance.new("UICorner", col).CornerRadius = UDim.new(0, 10)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 4)
	bar.BackgroundColor3 = team.color
	bar.BorderSizePixel = 0
	bar.Parent = col
	text(col, { Size = UDim2.new(1, 0, 0, 28), Position = UDim2.fromOffset(0, 8), Text = string.upper(team.name), TextSize = 20 })
	for i, p in list do
		local y = 40 + (i - 1) * 25
		local row = text(col, { Size = UDim2.new(1, -24, 0, 22), Position = UDim2.fromOffset(12, y), TextSize = 15, Font = Enum.Font.GothamBold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Text = string.format("%d  %s", p.num, p.name), TextColor3 = if p.human then GOLD else Color3.new(1, 1, 1) })
		text(row, { Size = UDim2.fromScale(1, 1), TextSize = 12, Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Right,
			Text = ROLE[p.role] or "", TextColor3 = Color3.fromRGB(180, 188, 196) })
	end
end

local function showLineups()
	local raw = Net:GetAttribute("Lineups")
	if type(raw) ~= "string" then return end
	local ok, teams = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(teams) ~= "table" then return end
	for t = 1, 2 do column(t, teams[t] or {}) end
end

local hint = text(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18), Size = UDim2.fromOffset(400, 22),
	Text = if UserInputService.TouchEnabled then "Touche l’écran pour passer" else "Appuie sur une touche pour passer",
	TextSize = 14, Font = Enum.Font.GothamBold, TextTransparency = 0.25 })

-- ---------- The flight round the stadium ----------
local t0 = os.clock()
local done = false
local a0 = math.random() * math.pi * 2
local centre = Config.toWorld(Config.L / 2, Config.W / 2, 0)

local function finish()
	if done then return end
	done = true
	RunService:UnbindFromRenderStep("FC27Intro")
	gui:Destroy()
	camera.CameraType = Enum.CameraType.Custom
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then camera.CameraSubject = hum end
end

UserInputService.InputBegan:Connect(function(input)
	if done then return end
	local tt = input.UserInputType
	if tt == Enum.UserInputType.Touch or tt == Enum.UserInputType.MouseButton1 or tt == Enum.UserInputType.Keyboard
		or tt == Enum.UserInputType.Gamepad1 then
		if os.clock() - t0 > 0.6 then finish() end
	end
end)

local shownBall, shownLineups = false, false
RunService:BindToRenderStep("FC27Intro", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
	if done then return end
	local t = os.clock() - t0
	if t > DURATION then finish(); return end
	camera.CameraType = Enum.CameraType.Scriptable
	-- Half a turn round the stadium, high up, slowly coming down towards the pitch
	local k = t / DURATION
	local ang = a0 + k * math.pi
	local radius = (Config.L / 2 + 35 - k * 20) * M
	local height = (38 - k * 22) * M
	local eye = centre + Vector3.new(math.cos(ang) * radius, height, math.sin(ang) * radius * 0.8)
	camera.CFrame = CFrame.lookAt(eye, centre + Vector3.new(0, 2 * M, 0))
	-- The ball first, then the line-ups
	if t > 1 and t < 4.6 then
		if not shownBall then shownBall = true; showBall() end
		ballCard.Visible = true
		local sp = spinning
		if sp then sp:PivotTo(sp:GetPivot() * CFrame.Angles(0, dt * 2.2, 0)) end
	else
		ballCard.Visible = false
	end
	if t >= 4.6 then
		if not shownLineups then shownLineups = true; showLineups() end
		lineups.Visible = true
	end
	hint.Visible = true
end)
