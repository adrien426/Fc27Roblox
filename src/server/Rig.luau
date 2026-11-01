-- Footballer bodies. Every footballer (computer or human) moves as a standard R15 Humanoid; when the web game's
-- player model (player.glb, the Ch38 footballer) is loaded, it is welded on as the visible "Body" in the team kit
-- and the R15 body is hidden. Each player's machine then plays the web game's clips on it (client/Bodies).
-- Without the model, the R15 avatar shows the kit and plays Roblox's default run and idle animations.
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Skeleton = require(Shared.Skeleton)
local Assets = require(script.Parent.Assets)

local Rig = {}

local ANIM = { run = "rbxassetid://913376220", walk = "rbxassetid://913402848", idle = "rbxassetid://507766388" }
local SKIN = { Color3.fromRGB(241, 199, 163), Color3.fromRGB(217, 167, 124), Color3.fromRGB(168, 113, 74), Color3.fromRGB(110, 68, 40) }
local HAIR = { Color3.fromRGB(43, 26, 16), Color3.fromRGB(20, 16, 14), Color3.fromRGB(110, 70, 35), Color3.fromRGB(200, 160, 90), Color3.fromRGB(150, 60, 30) }
local BOOTS = { Color3.fromRGB(21, 21, 21), Color3.fromRGB(244, 244, 244), Color3.fromRGB(240, 120, 20), Color3.fromRGB(30, 200, 230), Color3.fromRGB(230, 40, 120) }
-- Colours of the Ch38 textures, so a tint lands on the wanted colour (same ratios as the web game)
local TEX_SKIN = Color3.fromRGB(217, 167, 124)

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
	Rig.addBody(model, teamIdx, num, rng)
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

-- Tints a part of the Ch38 model. Its kit textures are plain white cloth: the texture keeps the folds and the colour
-- multiplies it (SurfaceAppearance.Color); a part with only a TextureID loses the texture and takes the colour.
local function tint(p: BasePart, c: Color3, keepTexture: boolean)
	local sa = p:FindFirstChildOfClass("SurfaceAppearance")
	if sa and pcall(function() (sa :: any).Color = c end) then return end
	if keepTexture then return end
	if sa then sa:Destroy() end
	if p:IsA("MeshPart") then p.TextureID = "" end
	p.Color = c
end

local function ratio(c: Color3, ref: Color3): Color3
	return Color3.new(math.min(1, c.R / ref.R), math.min(1, c.G / ref.G), math.min(1, c.B / ref.B))
end

-- Hides the R15 body (it still walks, jumps and collides) and whatever the avatar wears
local function hideAvatar(model: Model, body: Model)
	local function hide(d: Instance)
		if d:IsDescendantOf(body) then return end
		if d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			task.defer(function() d:Destroy() end)
		elseif d:IsA("BasePart") then
			d.Transparency = 1
		elseif d:IsA("Decal") or d:IsA("SurfaceGui") then
			task.defer(function() d:Destroy() end)
		end
	end
	for _, d in model:GetDescendants() do hide(d) end
	model.DescendantAdded:Connect(hide)
end

-- Where the footballer faces, read from its hip bones (its left is LeftUpLeg's side): it does not depend on how
-- Roblox's importer turned the model. nil if the bones are missing.
local function facing(body: Model): Vector3?
	local l: Bone?, r: Bone? = nil, nil
	for _, d in body:GetDescendants() do
		if d:IsA("Bone") then
			local k = Skeleton.boneKey(d.Name)
			if k == "LeftUpLeg" then l = d elseif k == "RightUpLeg" then r = d end
		end
	end
	if not l or not r then return nil end
	local f = ((l :: Bone).WorldPosition - (r :: Bone).WorldPosition):Cross(Vector3.yAxis)
	return if f.Magnitude > 1e-3 then f.Unit else nil
end

-- Welds the web game's footballer on this body, in the team kit. Returns false when the model is not loaded.
local function addBody(model: Model, teamIdx: number, num: number, rng: Random): boolean
	local tpl = Assets.player
	local root = model:FindFirstChild("HumanoidRootPart")
	if not tpl or not root or not root:IsA("BasePart") then return false end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local old = model:FindFirstChild("Body")
	if old then old:Destroy() end
	local team = Config.TEAMS[teamIdx]
	local body = tpl:Clone()
	body.Name = "Body"

	-- Height: the model's own (in the bind pose, the model's box is its height)
	local _, size0 = body:GetBoundingBox()
	body:ScaleTo(body:GetScale() * Config.PLAYER_HEIGHT * Config.M / math.max(0.1, size0.Y))

	-- Kit and looks: shirt and socks in the team colour, shorts, boots, skin tone, hair colour or a shaved head
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local hair = HAIR[rng:NextInteger(1, #HAIR)]
	local boot = BOOTS[rng:NextInteger(1, #BOOTS)]
	local shaved = rng:NextNumber() < 0.2
	for _, p in body:GetDescendants() do
		if not p:IsA("BasePart") then continue end
		local n = p.Name
		if n:find("Shirt") then tint(p, team.color, false)
		elseif n:find("Shorts") then tint(p, team.shorts, false)
		elseif n:find("Socks") then tint(p, team.color, false)
		elseif n:find("Shoes") then tint(p, boot, false)
		elseif n:find("Hair") then
			if shaved then p.Transparency = 1 else tint(p, hair, true) end
		elseif n:find("Body") then tint(p, ratio(skin, TEX_SKIN), true) end
	end

	-- Feet on the ground: an R15 root floats HipHeight + half its height above it, an R6 root stands on 2-stud legs.
	-- Facing where the character faces (from the hip bones; without them, a Mixamo model faces +Z).
	local cf, size = body:GetBoundingBox()
	local hip = if hum and hum.RigType == Enum.HumanoidRigType.R15 then hum.HipHeight else 2
	local base = cf * CFrame.new(0, -size.Y / 2, 0)
	local turn = CFrame.Angles(0, math.pi, 0)
	local fwd = facing(body)
	if fwd then
		local fl = base:VectorToObjectSpace(fwd)
		fl = Vector3.new(fl.X, 0, fl.Z)
		if fl.Magnitude > 0.1 then turn = CFrame.lookAt(Vector3.zero, fl.Unit):Inverse() end
	end
	local feet = root.CFrame * CFrame.new(0, -(hip + root.Size.Y / 2), 0) * CFrame.Angles(0, Config.BODY_YAW, 0) * turn
	body:PivotTo(feet * base:ToObjectSpace(body:GetPivot()))
	for _, p in body:GetDescendants() do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.Massless = true
			p.CastShadow = true
			local w = Instance.new("WeldConstraint")
			w.Part0 = root
			w.Part1 = p
			w.Parent = p
		end
	end
	body.Parent = model
	model:SetAttribute("Team", teamIdx)
	model:SetAttribute("Num", num)
	hideAvatar(model, body)
	CollectionService:AddTag(body, "FC27Body")
	return true
end

-- Never throws: if the footballer cannot be put on, the player keeps the standard avatar
function Rig.addBody(model: Model, teamIdx: number, num: number, rng: Random): boolean
	local ok, res = pcall(addBody, model, teamIdx, num, rng)
	if ok then return res end
	warn(`[FC27] Could not put the footballer model on {model.Name}: {res}`)
	local body = model:FindFirstChild("Body")
	if body then body:Destroy() end
	return false
end

-- Animation tracks per body, loaded on first use
local tracksOf: { [Model]: { [string]: AnimationTrack } } = setmetatable({}, { __mode = "k" }) :: any

-- Run / walk / idle from the body's speed (R15 stand-in only: the web game's body is animated by client/Bodies)
function Rig.animate(model: Model, speed: number)
	if model:FindFirstChild("Body") then return end
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
