-- Controls, same keys as the web game: J pass, K shoot (hold for power), I lob (hold: further and higher),
-- L through ball, E tackle (with the ball: a skill move), Shift sprint, C TV camera. Gamepad and touch buttons
-- do the same.
-- Running is Roblox's own movement (ZQSD / WASD, stick or thumbstick).
-- Not touching anything for Config.IDLE_KICK seconds takes you out of the match (a computer player takes over):
-- this script tells the server, every few seconds, that you are still playing.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Dribbles = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Dribbles"))
local Net = ReplicatedStorage:WaitForChild("Net")
local Action = Net:WaitForChild("Action") :: RemoteEvent
local BallState = Net:WaitForChild("BallState") :: any

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FULL = { shoot = 0.85, lob = 0.9 } -- seconds of holding for full power
local charging: { kind: string, t0: number }? = nil
local sprintHeld = false
local stamina = 1
local tvCam = false
local haveBall = false

-- Roblox's own movement controls, switched off while a skill move moves the player
local controls: any = nil
pcall(function()
	controls = (require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")) :: any):GetControls()
end)
local inMove = false
local moveRev: Vector3? = nil

local lastPing = 0

local function body(): (Humanoid?, BasePart?)
	local char = player.Character
	if not char then return nil, nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart")
	return hum, if root and root:IsA("BasePart") then root else nil
end

-- Direction pushed on the stick or keys, else where the player faces (world X/Z = pitch x/y)
local function aim(): (number, number)
	local hum, root = body()
	if hum and hum.MoveDirection.Magnitude > 0.1 then return hum.MoveDirection.X, hum.MoveDirection.Z end
	if root then return root.CFrame.LookVector.X, root.CFrame.LookVector.Z end
	return 1, 0
end

local function fire(kind: string, power: number?)
	local dx, dz = aim()
	Action:FireServer(kind, dx, dz, power or 0.5)
end

local function press(kind: string)
	if FULL[kind] then
		charging = { kind = kind, t0 = os.clock() }
	elseif kind == "sprint" then
		sprintHeld = true
	elseif kind == "camera" then
		if player:GetAttribute("InMatch") ~= true then return end -- not in the locker room
		tvCam = not tvCam
		if not tvCam then
			camera.CameraType = Enum.CameraType.Custom
			local hum = body()
			if hum then camera.CameraSubject = hum end
		end
	else
		fire(kind)
	end
end

local function release(kind: string)
	if kind == "sprint" then sprintHeld = false; return end
	local c = charging
	if c and c.kind == kind then
		charging = nil
		fire(kind, math.clamp((os.clock() - c.t0) / FULL[kind], 0, 1))
	end
end

local BINDS = {
	{ "pass", Enum.KeyCode.J, Enum.KeyCode.ButtonA },
	{ "shoot", Enum.KeyCode.K, Enum.KeyCode.ButtonB },
	{ "lob", Enum.KeyCode.I, Enum.KeyCode.ButtonY },
	{ "through", Enum.KeyCode.L, Enum.KeyCode.ButtonL1 },
	{ "tackle", Enum.KeyCode.E, Enum.KeyCode.ButtonX },
	{ "sprint", Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonR1 },
	{ "camera", Enum.KeyCode.C, Enum.KeyCode.ButtonSelect },
}
for _, b in BINDS do
	local kind = b[1]
	ContextActionService:BindActionAtPriority("FC27_" .. kind, function(_, state)
		if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		if state == Enum.UserInputState.Begin then press(kind)
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then release(kind) end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, b[2], b[3])
end

-- Skill move: the move sets the speed and direction and the body keeps facing where it was going. This runs right
-- after Roblox's own controls each frame and overrides their movement while the move lasts; the controls are never
-- switched off, so a stick still held at the end of the move carries straight on.
RunService:BindToRenderStep("FC27SkillMove", Enum.RenderPriority.Input.Value + 1, function()
	local hum, root = body()
	if not hum or not root then return end
	local char = player.Character :: Model
	local key = char:GetAttribute("Drib")
	local at = char:GetAttribute("DribAt")
	local m = if type(key) == "string" then Dribbles.byKey[key] else nil
	local k = if m and type(at) == "number" then (workspace:GetServerTimeNow() - at) / m.dur else 2
	if m and k >= 0 and k < 1 then
		local F = char:GetAttribute("DribF") :: Vector3
		local S = char:GetAttribute("DribS") :: Vector3
		local v0 = (char:GetAttribute("DribV0") :: number?) or 0
		inMove = true
		local fv, sv = m.v(k)
		if not m.reverse then fv = math.max(fv, v0 * 0.75) end
		local v = F * fv + S * sv
		hum.AutoRotate = false
		local p = root.Position
		root.CFrame = CFrame.lookAt(p, p + F)
		hum.WalkSpeed = v.Magnitude * Config.M
		hum:Move(if v.Magnitude > 0.05 then v.Unit else Vector3.zero)
		moveRev = if m.reverse then -F else nil
	elseif inMove then
		inMove = false
		hum.AutoRotate = true
		if moveRev then
			local p = root.Position
			root.CFrame = CFrame.lookAt(p, p + moveRev)
			moveRev = nil
		end
	end
end)

-- Still playing: moving the stick tells the server (button presses already reach it as actions)
RunService.Heartbeat:Connect(function()
	local hum = body()
	local mv = if controls then (controls:GetMoveVector() :: Vector3) else (if hum then hum.MoveDirection else Vector3.zero)
	if (mv.Magnitude > 0.1 or sprintHeld or charging) and os.clock() - lastPing > 5 then
		lastPing = os.clock()
		Action:FireServer("active", 0, 0, 0)
	end
end)

-- Touch buttons, left of Roblox's jump button
if UserInputService.TouchEnabled then
	local gui = Instance.new("ScreenGui")
	gui.Name = "FC27Touch"
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local function button(kind: string, text: string, size: number, pos: UDim2, color: Color3, textColor: Color3)
		local b = Instance.new("TextButton")
		b.Name = kind
		b.Size = UDim2.fromOffset(size, size)
		b.AnchorPoint = Vector2.new(0.5, 0.5)
		b.Position = pos
		b.BackgroundColor3 = color
		b.BackgroundTransparency = 0.1
		b.Text = text
		b.TextColor3 = textColor
		b.Font = Enum.Font.GothamBold
		b.TextSize = math.floor(size / 4.2)
		b.AutoButtonColor = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0.5, 0)
		corner.Parent = b
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.new(1, 1, 1)
		stroke.Thickness = 2
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = b
		b.InputBegan:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then press(kind) end
		end)
		b.InputEnded:Connect(function(input)
			if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then release(kind) end
		end)
		b.Parent = gui
	end
	local dark = Color3.fromRGB(19, 36, 26)
	-- The match buttons only show on the pitch, not in the locker room
	local function showButtons() gui.Enabled = player:GetAttribute("InMatch") == true end
	player:GetAttributeChangedSignal("InMatch"):Connect(showButtons)
	showButtons()
	-- With the ball, the tackle button does a skill move
	BallState.OnClientEvent:Connect(function(_s: any, o: any)
		haveBall = o ~= nil and o == player.Character
		local b = gui:FindFirstChild("tackle")
		if b and b:IsA("TextButton") then b.Text = if haveBall then "Dribble" else "Tacle" end
	end)
	button("shoot", "Tir", 70, UDim2.new(), Color3.fromRGB(242, 194, 48), dark)
	button("pass", "Passe", 70, UDim2.new(), Color3.fromRGB(244, 247, 240), dark)
	button("lob", "Lob", 70, UDim2.new(), Color3.fromRGB(191, 230, 255), Color3.fromRGB(15, 42, 92))
	button("sprint", "Sprint", 70, UDim2.new(), Color3.fromRGB(20, 38, 28), Color3.new(1, 1, 1))
	button("tackle", "Tacle", 70, UDim2.new(), Color3.fromRGB(255, 107, 87), Color3.new(1, 1, 1))
	button("camera", "🎥", 44, UDim2.new(0.5, 0, 0, 30), Color3.fromRGB(20, 38, 28), Color3.new(1, 1, 1))

	-- Two columns above Roblox's jump button, each button the jump button's size, a little apart:
	--   Sprint  Tacle/Dribble
	--   Passe   Lob
	--   Tir     (jump)
	-- The jump button is read from Roblox's own touch controls (its size changes with the screen)
	local GRID = { shoot = { 0, 0 }, pass = { 0, 1 }, lob = { 1, 1 }, sprint = { 0, 2 }, tackle = { 1, 2 } }
	local function layout()
		local size, right, bottom = 70, 0, 0
		local touchGui = player.PlayerGui:FindFirstChild("TouchGui")
		local jump = touchGui and touchGui:FindFirstChild("JumpButton", true)
		local origin = gui.AbsolutePosition
		if jump and jump:IsA("GuiObject") and jump.AbsoluteSize.X > 0 then
			size = jump.AbsoluteSize.X
			right = jump.AbsolutePosition.X - origin.X -- left edge of the jump button
			bottom = jump.AbsolutePosition.Y - origin.Y -- top edge of the jump button
		else
			local cam = workspace.CurrentCamera
			local vs = if cam then cam.ViewportSize else Vector2.new(800, 400)
			right = vs.X - 95 - origin.X
			bottom = vs.Y - 90 - origin.Y
		end
		local gap = math.max(8, size * 0.15)
		for kind, cell in GRID do
			local b = gui:FindFirstChild(kind)
			if not b or not b:IsA("TextButton") then continue end
			b.Size = UDim2.fromOffset(size, size)
			b.TextSize = math.floor(size / 4.6)
			-- Column 1 sits right above the jump button, column 0 to its left; row 0 is the jump button's row
			local x = right + size / 2 + (cell[1] - 1) * (size + gap)
			local y = bottom + size / 2 - cell[2] * (size + gap)
			b.Position = UDim2.fromOffset(x, y)
		end
	end
	task.spawn(function()
		while true do
			layout()
			task.wait(1)
		end
	end)
end

RunService.RenderStepped:Connect(function(dt)
	local hum, root = body()
	-- Holding too long releases the strike at full power
	local c = charging
	if c then
		local held = os.clock() - c.t0
		player:SetAttribute("ChargeKind", c.kind)
		player:SetAttribute("Charge", math.clamp(held / FULL[c.kind], 0, 1))
		if held > FULL[c.kind] + 0.3 then release(c.kind) end
	else
		player:SetAttribute("Charge", 0)
	end
	-- Sprint with stamina, slowed down after a missed tackle or when tackled
	if hum then
		local moving = hum.MoveDirection.Magnitude > 0.1
		local stunUntil = player.Character and player.Character:GetAttribute("StunUntil")
		local stunned = type(stunUntil) == "number" and workspace:GetServerTimeNow() < stunUntil
		local sprinting = sprintHeld and moving and stamina > 0.05 and not stunned
		if sprinting then
			stamina = math.max(0, stamina - dt * 0.12)
		else
			stamina = math.min(1, stamina + dt * (if moving then 0.135 else 0.18))
		end
		if not inMove then
			hum.WalkSpeed = if stunned then Config.STUN_SPEED elseif sprinting then Config.SPRINT else Config.WALK
		end
		player:SetAttribute("Stamina", stamina)
		player:SetAttribute("Sprinting", sprinting)
	end
	-- Back in the locker room: the TV camera is switched off
	if tvCam and player:GetAttribute("InMatch") ~= true then
		tvCam = false
		camera.CameraType = Enum.CameraType.Custom
		if hum then camera.CameraSubject = hum end
	end
	-- TV camera: high on the main stand side, following the ball
	if tvCam then
		local ball = workspace:FindFirstChild("FC27Ball")
		local focus = if ball and ball:IsA("BasePart") then ball.Position elseif root then root.Position else Vector3.zero
		camera.CameraType = Enum.CameraType.Scriptable
		local x = math.clamp(focus.X, -40 * Config.M, 40 * Config.M)
		local want = CFrame.lookAt(Vector3.new(x, 26 * Config.M, (Config.W / 2 + 30) * Config.M), focus)
		camera.CFrame = camera.CFrame:Lerp(want, 1 - math.exp(-dt * 4))
	end
end)
