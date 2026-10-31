-- Footballer bodies: computer-controlled players are standard R15 avatars in the team kit, with the shirt
-- number on the back and Roblox's default run and idle animations. Human players get the same kit.
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Rig = {}

local ANIM = { run = "rbxassetid://913376220", walk = "rbxassetid://913402848", idle = "rbxassetid://507766388" }
local SKIN = { Color3.fromRGB(241, 199, 163), Color3.fromRGB(217, 167, 124), Color3.fromRGB(168, 113, 74), Color3.fromRGB(110, 68, 40) }

local function numberDecal(torso: BasePart, num: number, color: Color3)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Number"
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 50
	gui.Parent = torso
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = tostring(num)
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = if color.R + color.G + color.B > 2.2 then Color3.new(0.1, 0.1, 0.1) else Color3.new(1, 1, 1)
	t.Parent = gui
end

-- Team colours on any R15 body: shirt on torso and arms, shorts on the legs, clothes removed so the kit shows
function Rig.dress(model: Model, teamIdx: number, num: number)
	local team = Config.TEAMS[teamIdx]
	for _, c in model:GetChildren() do
		if c:IsA("Shirt") or c:IsA("Pants") or c:IsA("ShirtGraphic") then c:Destroy() end
	end
	local bc = model:FindFirstChildOfClass("BodyColors")
	if bc then
		bc.TorsoColor3 = team.color
		bc.LeftArmColor3 = team.color
		bc.RightArmColor3 = team.color
		bc.LeftLegColor3 = team.shorts
		bc.RightLegColor3 = team.shorts
	end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") then
			local n = p.Name
			if n:find("Torso") or n:find("Arm") then p.Color = team.color
			elseif n:find("Leg") or n:find("Foot") then p.Color = team.shorts end
		end
	end
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		local old = torso:FindFirstChild("Number")
		if old then old:Destroy() end
		numberDecal(torso, num, team.color)
	end
end

-- Simple block body, used only if Roblox cannot build an avatar (for example offline in Studio)
local function blockBody(name: string): Model
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Transparency = 1
	root.Parent = m
	local function piece(n: string, size: Vector3, offset: Vector3)
		local p = Instance.new("Part")
		p.Name = n
		p.Size = size
		p.CanCollide = false
		p.CFrame = root.CFrame * CFrame.new(offset)
		p.Parent = m
		local w = Instance.new("WeldConstraint")
		w.Part0 = root
		w.Part1 = p
		w.Parent = p
	end
	piece("UpperTorso", Vector3.new(2, 2, 1), Vector3.zero)
	piece("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0))
	piece("LeftLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(-0.5, -2, 0))
	piece("RightLeg", Vector3.new(0.9, 2, 0.9), Vector3.new(0.5, -2, 0))
	local hum = Instance.new("Humanoid")
	hum.RigType = Enum.HumanoidRigType.R15
	hum.HipHeight = 3
	hum.Parent = m
	m.PrimaryPart = root
	return m
end

function Rig.createBot(name: string, teamIdx: number, num: number, rng: Random): Model
	local team = Config.TEAMS[teamIdx]
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local model: Model
	local ok, res = pcall(function()
		local d = Instance.new("HumanoidDescription")
		d.HeadColor = skin
		d.TorsoColor = team.color
		d.LeftArmColor = team.color
		d.RightArmColor = team.color
		d.LeftLegColor = team.shorts
		d.RightLegColor = team.shorts
		return Players:CreateHumanoidModelFromDescription(d, Enum.HumanoidRigType.R15)
	end)
	if ok and res then
		model = res
		model.Name = name
	else
		model = blockBody(name)
	end
	Rig.dress(model, teamIdx, num)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayName = name
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
		hum.NameDisplayDistance = 40
		hum.BreakJointsOnDeath = false
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end
	return model
end

-- Animation tracks per body, loaded on first use
local tracksOf: { [Model]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

-- Run / walk / idle from the body's speed
function Rig.animate(model: Model, speed: number)
	local tracks = tracksOf[model]
	if not tracks then
		local hum = model:FindFirstChildOfClass("Humanoid")
		if not hum then return end
		local animator = hum:FindFirstChildOfClass("Animator")
		if not animator then
			animator = Instance.new("Animator")
			animator.Parent = hum
		end
		tracks = {}
		for k, id in ANIM do
			local a = Instance.new("Animation")
			a.AnimationId = id
			local ok, tr = pcall(function() return (animator :: Animator):LoadAnimation(a) end)
			if ok and tr then tracks[k] = tr end
		end
		tracksOf[model] = tracks
	end
	local want = if speed > 12 then "run" elseif speed > 1 then "walk" else "idle"
	for k, tr in tracks do
		if k == want then
			if not tr.IsPlaying then tr:Play(0.2) end
			tr:AdjustSpeed(if k == "run" then math.clamp(speed / 18, 0.6, 1.5) elseif k == "walk" then math.clamp(speed / 10, 0.6, 1.4) else 1)
		elseif tr.IsPlaying then
			tr:Stop(0.2)
		end
	end
end

return Rig
