-- Controls, same keys as the web game: J pass, K shoot (hold for power), I lob (hold: further and higher),
-- L through ball, E tackle, Shift sprint, C TV camera. Gamepad and touch buttons do the same.
-- Running is Roblox's own movement (ZQSD / WASD, stick or thumbstick).
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = ReplicatedStorage:WaitForChild("Net")
local Action = Net:WaitForChild("Action") :: RemoteEvent

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local FULL = { shoot = 0.85, lob = 0.9 } -- seconds of holding for full power
local charging: { kind: string, t0: number }? = nil
local sprintHeld = false
local stamina = 1
local tvCam = false

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
	button("shoot", "Tir", 92, UDim2.new(1, -150, 1, -175), Color3.fromRGB(242, 194, 48), dark)
	button("pass", "Passe", 76, UDim2.new(1, -250, 1, -110), Color3.fromRGB(244, 247, 240), dark)
	button("lob", "Lob", 64, UDim2.new(1, -262, 1, -205), Color3.fromRGB(191, 230, 255), Color3.fromRGB(15, 42, 92))
	button("tackle", "Tacle", 64, UDim2.new(1, -165, 1, -275), Color3.fromRGB(255, 107, 87), Color3.new(1, 1, 1))
	button("sprint", "Sprint", 58, UDim2.new(1, -60, 1, -260), Color3.fromRGB(20, 38, 28), Color3.new(1, 1, 1))
	button("camera", "🎥", 44, UDim2.new(1, -40, 0, 90), Color3.fromRGB(20, 38, 28), Color3.new(1, 1, 1))
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
		hum.WalkSpeed = if stunned then Config.STUN_SPEED elseif sprinting then Config.SPRINT else Config.WALK
		player:SetAttribute("Stamina", stamina)
		player:SetAttribute("Sprinting", sprinting)
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
