--!strict
-- The end-of-match screen (Net attribute MatchStats, written by the server at full time): the score, who scored and
-- when, both teams' statistics side by side (shots, passes, tackles, fouls, cards, offsides, possession) and the man
-- of the match. Shown for 12 seconds, or until closed.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = ReplicatedStorage:WaitForChild("Net")

local player = Players.LocalPlayer
local DARK = Color3.fromRGB(14, 24, 18)
local GOLD = Color3.fromRGB(242, 194, 48)

local gui = Instance.new("ScreenGui")
gui.Name = "FC27Stats"
gui.ResetOnSpawn = false
gui.DisplayOrder = 12
gui.Enabled = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(560, 380)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.05
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local scale = Instance.new("UIScale")
scale.Parent = panel

local function label(props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do (t :: any)[k] = v end
	t.Parent = panel
	return t
end

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(34, 34)
close.Position = UDim2.new(1, -44, 0, 10)
close.BackgroundColor3 = Color3.fromRGB(60, 66, 74)
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.GothamBlack
close.TextSize = 18
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(1, 0)
close.Activated:Connect(function() gui.Enabled = false end)

local content: { Instance } = {}
local function clear()
	for _, c in content do c:Destroy() end
	content = {}
end
local function add(props: { [string]: any }): TextLabel
	local t = label(props)
	table.insert(content, t)
	return t
end

local serial = 0
local function show()
	local raw = Net:GetAttribute("MatchStats")
	if type(raw) ~= "string" then return end
	local ok, st = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(st) ~= "table" then return end
	if type(st.at) == "number" and workspace:GetServerTimeNow() - st.at > 30 then return end
	clear()
	local t1, t2 = Config.TEAMS[1], Config.TEAMS[2]
	add({ Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 10), Text = "FIN DU MATCH", TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = GOLD })
	add({ Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 34), TextSize = 30, Font = Enum.Font.GothamBlack,
		Text = `{t1.abbr}  {st.score[1]} – {st.score[2]}  {t2.abbr}` })
	-- Scorers, under their team
	for t = 1, 2 do
		local lines = {}
		for _, g in st.scorers or {} do
			if g.team == t then table.insert(lines, `{if g.name == "csc" then "contre son camp" else g.name} {g.minute}’`) end
		end
		add({ Size = UDim2.new(0.5, -20, 0, 40), Position = UDim2.new(if t == 1 then 0 else 0.5, 10, 0, 76), TextSize = 12, TextWrapped = true,
			TextXAlignment = if t == 1 then Enum.TextXAlignment.Right else Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			Font = Enum.Font.Gotham, Text = if #lines > 0 then "⚽ " .. table.concat(lines, ", ") else "", TextColor3 = Color3.fromRGB(200, 206, 214) })
	end
	-- Statistics side by side
	local rows = {
		{ "Possession", `{st.poss[1]} %`, `{st.poss[2]} %` },
		{ "Tirs", st.teams[1].shots, st.teams[2].shots },
		{ "Passes réussies", st.teams[1].passes, st.teams[2].passes },
		{ "Tacles gagnés", st.teams[1].tackles, st.teams[2].tackles },
		{ "Fautes", st.teams[1].fouls, st.teams[2].fouls },
		{ "Cartons", st.teams[1].cards, st.teams[2].cards },
		{ "Hors-jeu", st.teams[1].offsides, st.teams[2].offsides },
	}
	for i, r in rows do
		local y = 122 + (i - 1) * 28
		add({ Size = UDim2.fromOffset(120, 24), Position = UDim2.new(0.5, -230, 0, y), Text = tostring(r[2]), TextSize = 18, Font = Enum.Font.GothamBlack, TextColor3 = t1.color:Lerp(Color3.new(1, 1, 1), 0.3) })
		add({ Size = UDim2.fromOffset(200, 24), Position = UDim2.new(0.5, -100, 0, y), Text = r[1], TextSize = 14, TextColor3 = Color3.fromRGB(190, 196, 204) })
		add({ Size = UDim2.fromOffset(120, 24), Position = UDim2.new(0.5, 110, 0, y), Text = tostring(r[3]), TextSize = 18, Font = Enum.Font.GothamBlack, TextColor3 = t2.color:Lerp(Color3.new(1, 1, 1), 0.3) })
	end
	local best = st.best
	if type(best) == "table" then
		add({ Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 1, -36), TextSize = 15, TextColor3 = GOLD,
			Text = `★ Homme du match : {best.name} ({Config.TEAMS[best.team] and Config.TEAMS[best.team].abbr or ""}) · {best.goals} but{if best.goals > 1 then "s" else ""}, {best.passes} passes, {best.tackles} tacles` })
	end
	local cam = workspace.CurrentCamera
	if cam then scale.Scale = math.min(1, (cam.ViewportSize.X - 20) / 560, (cam.ViewportSize.Y - 20) / 380) end
	gui.Enabled = true
	serial += 1
	local mine = serial
	task.delay(12, function() if serial == mine then gui.Enabled = false end end)
end
Net:GetAttributeChangedSignal("MatchStats"):Connect(show)
