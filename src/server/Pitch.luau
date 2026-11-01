-- Builds the stadium: striped pitch with all its markings, goals with nets, team spawns and the lighting, from code.
-- Around it, the web game's stadium model (stadium.glb) when it is loaded, placed like in the web version;
-- otherwise stands full of fans, advertising boards and floodlights built from code.
local Lighting = game:GetService("Lighting")
local Teams = game:GetService("Teams")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local M, L, W = Config.M, Config.L, Config.W
local toWorld = Config.toWorld

local Pitch = {}

local function part(parent: Instance, props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- A white line from (x1, y1) to (x2, y2) in pitch metres
local function line(parent: Instance, x1: number, y1: number, x2: number, y2: number)
	local a, b = toWorld(x1, y1, 0), toWorld(x2, y2, 0)
	local len = (b - a).Magnitude
	part(parent, {
		Name = "Line",
		Size = Vector3.new(0.12 * M, 0.05, len + 0.12 * M),
		CFrame = CFrame.lookAt((a + b) / 2, b) + Vector3.new(0, 0.12, 0),
		Color = Color3.fromRGB(245, 245, 245),
		CanCollide = false,
		CastShadow = false,
	})
end

local function arc(parent: Instance, cx: number, cy: number, r: number, a0: number, a1: number, n: number)
	for i = 0, n - 1 do
		local t0 = a0 + (a1 - a0) * i / n
		local t1 = a0 + (a1 - a0) * (i + 1) / n
		line(parent, cx + math.cos(t0) * r, cy + math.sin(t0) * r, cx + math.cos(t1) * r, cy + math.sin(t1) * r)
	end
end

local function markings(parent: Instance)
	line(parent, 0, 0, L, 0)
	line(parent, 0, W, L, W)
	line(parent, 0, 0, 0, W)
	line(parent, L, 0, L, W)
	line(parent, L / 2, 0, L / 2, W)
	arc(parent, L / 2, W / 2, 9.15, 0, math.pi * 2, 40)
	for _, gx in { 0, L } do
		local d = if gx == 0 then 1 else -1
		-- Penalty area, goal area, spot and the arc outside the box
		line(parent, gx, 13.84, gx + d * 16.5, 13.84)
		line(parent, gx, 54.16, gx + d * 16.5, 54.16)
		line(parent, gx + d * 16.5, 13.84, gx + d * 16.5, 54.16)
		line(parent, gx, 24.84, gx + d * 5.5, 24.84)
		line(parent, gx, 43.16, gx + d * 5.5, 43.16)
		line(parent, gx + d * 5.5, 24.84, gx + d * 5.5, 43.16)
		local spot = gx + d * 11
		arc(parent, spot, W / 2, 0.25, 0, math.pi * 2, 6)
		local a = math.acos(5.5 / 9.15)
		if d > 0 then arc(parent, spot, W / 2, 9.15, -a, a, 12) else arc(parent, spot, W / 2, 9.15, math.pi - a, math.pi + a, 12) end
	end
	-- Corner arcs
	arc(parent, 0, 0, 1, 0, math.pi / 2, 4)
	arc(parent, L, 0, 1, math.pi / 2, math.pi, 4)
	arc(parent, 0, W, 1, -math.pi / 2, 0, 4)
	arc(parent, L, W, 1, math.pi, math.pi * 1.5, 4)
	arc(parent, L / 2, W / 2, 0.25, 0, math.pi * 2, 6)
end

local function goal(parent: Instance, gx: number)
	local d = if gx == 0 then -1 else 1 -- towards the outside
	local g = Instance.new("Model")
	g.Name = if gx == 0 then "GoalWest" else "GoalEast"
	g.Parent = parent
	local white = Color3.fromRGB(250, 250, 250)
	local postR = 0.12 * M
	for _, gy in { W / 2 - Config.GOAL_HALF, W / 2 + Config.GOAL_HALF } do
		part(g, { Name = "Post", Shape = Enum.PartType.Cylinder, Size = Vector3.new(Config.BAR * M, postR, postR),
			CFrame = CFrame.new(toWorld(gx, gy, Config.BAR / 2)) * CFrame.Angles(0, 0, math.pi / 2), Color = white })
	end
	local a, b = toWorld(gx, W / 2 - Config.GOAL_HALF, Config.BAR), toWorld(gx, W / 2 + Config.GOAL_HALF, Config.BAR)
	part(g, { Name = "Crossbar", Shape = Enum.PartType.Cylinder, Size = Vector3.new((b - a).Magnitude, postR, postR),
		CFrame = CFrame.new((a + b) / 2) * CFrame.Angles(0, math.pi / 2, 0), Color = white })
	-- Net: back, sides and roof, see-through
	local depth, h = Config.GOAL_DEPTH, Config.BAR
	local netProps = { Color = white, Transparency = 0.55, Material = Enum.Material.ForceField, CanCollide = false, CastShadow = false }
	local function net(name: string, size: Vector3, pos: Vector3)
		local props = table.clone(netProps)
		props.Name = name
		props.Size = size
		props.CFrame = CFrame.new(pos)
		part(g, props)
	end
	net("NetBack", Vector3.new(0.05, h * M, Config.GOAL_HALF * 2 * M), toWorld(gx + d * depth, W / 2, h / 2))
	net("NetRoof", Vector3.new(depth * M, 0.05, Config.GOAL_HALF * 2 * M), toWorld(gx + d * depth / 2, W / 2, h))
	for _, s in { -1, 1 } do
		net("NetSide", Vector3.new(depth * M, h * M, 0.05), toWorld(gx + d * depth / 2, W / 2 + s * Config.GOAL_HALF, h / 2))
	end
end

local FAN_COLORS = {
	Config.TEAMS[1].color, Config.TEAMS[2].color, Color3.fromRGB(245, 245, 245), Color3.fromRGB(30, 30, 30),
	Color3.fromRGB(242, 194, 48), Color3.fromRGB(60, 60, 70),
}

-- One stand along a side of the pitch: concrete steps with rows of fans
local function stand(parent: Instance, center: Vector3, length: number, facing: Vector3, rows: number)
	local right = facing:Cross(Vector3.yAxis).Unit
	local rng = Random.new(math.floor(center.X + center.Z))
	for r = 0, rows - 1 do
		local step = center - facing * (r * 2.4) + Vector3.new(0, 1.2 + r * 1.8, 0)
		part(parent, { Name = "Step", Size = Vector3.new(length, 1.8, 2.4), CFrame = CFrame.fromMatrix(step, right, Vector3.yAxis),
			Color = Color3.fromRGB(70, 74, 82), Material = Enum.Material.Concrete })
		if r % 2 == 0 then
			local n = math.floor(length / 3.2)
			for i = 0, n - 1 do
				if rng:NextNumber() < 0.85 then
					local p = step + right * ((i + 0.5) * 3.2 - length / 2) + Vector3.new(0, 2.1, 0)
					part(parent, { Name = "Fan", Size = Vector3.new(1.4, 2.4, 1.0), CFrame = CFrame.lookAt(p, p + facing),
						Color = FAN_COLORS[rng:NextInteger(1, #FAN_COLORS)], CanCollide = false, CastShadow = false })
				end
			end
		end
	end
end

local function boards(parent: Instance)
	local texts = { "FOOT ARENA", "FC27", "MATCH DU SOIR", "LUXEMBOURG" }
	local cols = { Color3.fromRGB(215, 38, 61), Color3.fromRGB(43, 111, 214), Color3.fromRGB(242, 194, 48), Color3.fromRGB(20, 20, 24) }
	local function board(x1: number, y1: number, x2: number, y2: number, i: number)
		local a, b = toWorld(x1, y1, 0.5), toWorld(x2, y2, 0.5)
		local mid = (a + b) / 2
		local p = part(parent, { Name = "Board", Size = Vector3.new((b - a).Magnitude, 1 * M, 0.4),
			CFrame = CFrame.fromMatrix(mid, (b - a).Unit, Vector3.yAxis), Color = cols[i % #cols + 1] })
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 20
		gui.Parent = p
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Text = texts[i % #texts + 1]
		t.TextScaled = true
		t.Font = Enum.Font.GothamBlack
		t.TextColor3 = Color3.new(1, 1, 1)
		t.Parent = gui
		local back = gui:Clone()
		back.Face = Enum.NormalId.Back
		back.Parent = p
	end
	local seg, i = 15, 0
	for x = 0, L - seg, seg do
		board(x, -3, x + seg, -3, i); i += 1
		board(x + seg, W + 3, x, W + 3, i); i += 1
	end
	for _, gx in { -3, L + 3 } do
		board(gx, 0, gx, W / 2 - 6, i); i += 1
		board(gx, W / 2 + 6, gx, W, i); i += 1
	end
end

local function floodlights(parent: Instance)
	for _, c in { { -14, -14 }, { L + 14, -14 }, { -14, W + 14 }, { L + 14, W + 14 } } do
		local base = toWorld(c[1], c[2], 0)
		part(parent, { Name = "Mast", Size = Vector3.new(2, 90, 2), CFrame = CFrame.new(base + Vector3.new(0, 45, 0)), Color = Color3.fromRGB(90, 94, 100), Material = Enum.Material.Metal })
		local head = part(parent, { Name = "Lamps", Size = Vector3.new(14, 6, 2), CFrame = CFrame.lookAt(base + Vector3.new(0, 92, 0), toWorld(L / 2, W / 2, 0)),
			Color = Color3.fromRGB(255, 252, 235), Material = Enum.Material.Neon })
		local light = Instance.new("SpotLight")
		light.Face = Enum.NormalId.Front
		light.Range = 60
		light.Angle = 70
		light.Brightness = 3
		light.Parent = head
	end
end

local function spawns(parent: Instance)
	for i, t in Config.TEAMS do
		local team = Teams:FindFirstChild(t.name)
		local sp = Instance.new("SpawnLocation")
		sp.Name = "Spawn" .. t.name
		sp.Anchored = true
		sp.Size = Vector3.new(12, 1, 6)
		sp.Neutral = false
		sp.TeamColor = BrickColor.new(t.brick)
		sp.AllowTeamChangeOnTouch = false
		sp.Duration = 0
		sp.Transparency = 0.6
		sp.CanCollide = true
		sp.Position = toWorld(L / 2 + (if i == 1 then -12 else 12), W + 6, 0) + Vector3.new(0, 0.5, 0)
		sp.Parent = parent
		if team then sp.TeamColor = (team :: Team).TeamColor end
	end
end

-- The web game's stadium: in its model the pitch is 137 units wide, scaled to 68 m (S = 68 / 137) and lowered by
-- 3 units. Its outer walls span 551.9 units along the pitch; its lowest point (the railing) is 1.545 units up.
local STADIUM_S = 68 / 137
local STADIUM_LENGTH = 551.889
local STADIUM_MIN_Y = 1.5455

local function placeStadium(parent: Instance, tpl: Model)
	local m = tpl:Clone()
	-- Roblox may have imported it at another scale or turned a quarter: the long side goes along the pitch (x)
	local size = m:GetExtentsSize()
	if size.Z > size.X then
		m:PivotTo(m:GetPivot() * CFrame.Angles(0, math.pi / 2, 0))
		size = m:GetExtentsSize()
	end
	local want = STADIUM_LENGTH * STADIUM_S * M
	m:ScaleTo(m:GetScale() * want / size.X)
	local cf, sz = m:GetBoundingBox()
	-- Its own grass 6 cm under ours, as in the web game, so the two never flicker
	local bottom = Config.GROUND_Y + ((STADIUM_MIN_Y - 3) * STADIUM_S - 0.06) * M
	local centre = toWorld(L / 2, W / 2, 0)
	local target = Vector3.new(centre.X, bottom + sz.Y / 2, centre.Z)
	m:PivotTo(m:GetPivot() + (target - cf.Position))
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		end
	end
	m.Parent = parent
end

function Pitch.build(stadium: Model?)
	local root = Instance.new("Folder")
	root.Name = "Stadium"
	root.Parent = workspace

	-- Ground around the pitch, then the mown stripes
	part(root, { Name = "Ground", Size = Vector3.new((L + 70) * M, 2, (W + 70) * M), CFrame = CFrame.new(toWorld(L / 2, W / 2, 0) - Vector3.new(0, 1, 0)),
		Color = Color3.fromRGB(46, 110, 52), Material = Enum.Material.Grass })
	local stripes = 18
	local pw, ph = (L + 8) / stripes, W + 8
	for i = 0, stripes - 1 do
		part(root, { Name = "Stripe", Size = Vector3.new(pw * M, 0.1, ph * M), CFrame = CFrame.new(toWorld(-4 + (i + 0.5) * pw, W / 2, 0) + Vector3.new(0, 0.05, 0)),
			Color = if i % 2 == 0 then Color3.fromRGB(64, 150, 64) else Color3.fromRGB(56, 136, 58), Material = Enum.Material.Grass, CastShadow = false })
	end

	local lines = Instance.new("Folder")
	lines.Name = "Markings"
	lines.Parent = root
	markings(lines)
	goal(root, 0)
	goal(root, L)

	spawns(root)
	if stadium then
		local ok, err = pcall(placeStadium, root, stadium)
		if not ok then
			warn(`[FC27] Could not place the stadium model: {err}`)
			local bad = root:FindFirstChild(stadium.Name)
			if bad then bad:Destroy() end
			stadium = nil
		end
	end
	if not stadium then
		local stands = Instance.new("Folder")
		stands.Name = "Stands"
		stands.Parent = root
		stand(stands, toWorld(L / 2, -9, 0), (L + 20) * M, Vector3.new(0, 0, 1), 10)
		stand(stands, toWorld(L / 2, W + 9, 0), (L + 20) * M, Vector3.new(0, 0, -1), 10)
		stand(stands, toWorld(-9, W / 2, 0), (W + 6) * M, Vector3.new(1, 0, 0), 8)
		stand(stands, toWorld(L + 9, W / 2, 0), (W + 6) * M, Vector3.new(-1, 0, 0), 8)
		boards(root)
		floodlights(root)
	end

	Lighting.ClockTime = 16.5
	Lighting.Brightness = 2.2
	Lighting.GlobalShadows = true
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 140, 150)
	if not Lighting:FindFirstChildOfClass("Atmosphere") then
		local atm = Instance.new("Atmosphere")
		atm.Density = 0.25
		atm.Haze = 1
		atm.Parent = Lighting
	end
	return root
end

return Pitch
