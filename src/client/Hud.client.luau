-- On-screen TV graphics: score and clock, big messages (goal, half-time...), your team and number,
-- the power bar while charging a shot or a lob, stamina, and the key list on computers.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Version = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Version")) :: string
local Lang = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Lang"))
local t = Lang.t
local Net = ReplicatedStorage:WaitForChild("Net")
local Message = Net:WaitForChild("Message") :: RemoteEvent

local player = Players.LocalPlayer
local gui = Instance.new("ScreenGui")
gui.Name = "FC27Hud"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = false
gui.Parent = player:WaitForChild("PlayerGui")

local DARK = Color3.fromRGB(14, 24, 18)
local FONT = Enum.Font.GothamBlack

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do (t :: any)[k] = v end
	t.Parent = parent
	return t
end

-- Scoreboard
local board = Instance.new("Frame")
board.Size = UDim2.fromOffset(212, 40)
board.Position = UDim2.new(0, 12, 0, 8)
board.BackgroundColor3 = DARK
board.BackgroundTransparency = 0.15
board.Parent = gui
Instance.new("UICorner", board).CornerRadius = UDim.new(0, 6)
local function teamTag(i: number, x: number)
	local bar = Instance.new("Frame")
	bar.Size = UDim2.fromOffset(5, 26)
	bar.Position = UDim2.fromOffset(x, 7)
	bar.BackgroundColor3 = Config.TEAMS[i].color
	bar.BorderSizePixel = 0
	bar.Parent = board
	label(board, { Size = UDim2.fromOffset(46, 40), Position = UDim2.fromOffset(x + 8, 0), Text = t("abbr." .. i), TextSize = 18 })
end
teamTag(1, 8)
local scoreText = label(board, { Size = UDim2.fromOffset(80, 30), Position = UDim2.fromOffset(66, 5), Text = "0 – 0", TextSize = 22, BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), TextColor3 = DARK })
teamTag(2, 154)
-- Match clock in its own box, away from the score (next to BLE it read like the Blues' goals)
local clockBox = Instance.new("Frame")
clockBox.Size = UDim2.fromOffset(92, 40)
clockBox.Position = UDim2.new(0, 12 + 212 + 8, 0, 8)
clockBox.BackgroundColor3 = Color3.fromRGB(32, 36, 44)
clockBox.BackgroundTransparency = 0.15
clockBox.Parent = gui
Instance.new("UICorner", clockBox).CornerRadius = UDim.new(0, 6)
local clockText = label(clockBox, { Size = UDim2.fromOffset(92, 26), Position = UDim2.fromOffset(0, 1), Text = "⏱ 0’", TextSize = 18, TextColor3 = Color3.fromRGB(242, 194, 48) })
local halfText = label(clockBox, { Size = UDim2.fromOffset(92, 12), Position = UDim2.fromOffset(0, 26), Text = t("hud.half1"), TextSize = 10,
	Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(190, 196, 206) })

-- Commentary: a line at the bottom of the screen, like the web game's commentator (Net attribute Comment)
local commentBox = label(gui, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -24), Size = UDim2.fromOffset(520, 30),
	Text = "", TextSize = 16, Font = Enum.Font.GothamBold, BackgroundTransparency = 0.25, BackgroundColor3 = DARK, Visible = false,
	TextWrapped = true })
Instance.new("UICorner", commentBox).CornerRadius = UDim.new(0, 8)
local commentSerial = 0
Net:GetAttributeChangedSignal("CommentAt"):Connect(function()
	local text = Net:GetAttribute("Comment")
	if type(text) ~= "string" then return end
	commentSerial += 1
	local mine = commentSerial
	commentBox.Text = Lang.show(text)
	commentBox.Visible = true
	task.delay(3.2, function() if commentSerial == mine then commentBox.Visible = false end end)
end)

-- Build version, small, bottom left, with what the server sees (phase, who has the ball, who goes for it): it
-- shows on screenshots, to understand a ball nobody goes for
local versionText = label(gui, { Size = UDim2.new(1, -12, 0, 14), Position = UDim2.new(0, 6, 1, -16), Text = "v " .. Version, TextSize = 11,
	Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextTransparency = 0.35 })
local function showDebug()
	local d = Net:GetAttribute("Debug")
	local a = player:GetAttribute("Audio")
	versionText.Text = "v " .. Version .. (if type(d) == "string" then "   ·   " .. d else "") .. (if type(a) == "string" then "   ·   " .. a else "")
end
Net:GetAttributeChangedSignal("Debug"):Connect(showDebug)
player:GetAttributeChangedSignal("Audio"):Connect(showDebug)
showDebug()

local function refresh()
	scoreText.Text = string.format("%d – %d", Net:GetAttribute("Score1") or 0, Net:GetAttribute("Score2") or 0)
	local c = Net:GetAttribute("Clock") or 0
	local half = Net:GetAttribute("Half") or 1
	local base = if half == 1 then 45 else 90
	clockText.Text = "⏱ " .. (if c >= base then string.format("%d+%d’", base, c - base + 1) else string.format("%d’", c))
	halfText.Text = if half == 1 then t("hud.half1") else t("hud.half2")
	if Net:GetAttribute("Phase") == "break" then clockText.Text = "⏱ " .. t("hud.ht"); halfText.Text = t("say.half") end
	if Net:GetAttribute("Phase") == "done" then halfText.Text = t("hud.over") end
end
for _, k in { "Score1", "Score2", "Clock", "Half", "Phase" } do Net:GetAttributeChangedSignal(k):Connect(refresh) end
refresh()

-- Your team and shirt
local me = label(gui, { Size = UDim2.fromOffset(300, 20), Position = UDim2.new(0, 12, 0, 52), Text = "", TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left, Font = Enum.Font.GothamBold })
local function refreshMe()
	local char = player.Character
	local tm = char and char:GetAttribute("Team")
	me.Text = if type(tm) == "number" and Config.TEAMS[tm] then t("hud.youplay", { team = Lang.team(tm) }) else t("hud.spectator")
	me.TextColor3 = if type(tm) == "number" and Config.TEAMS[tm] then Config.TEAMS[tm].color:Lerp(Color3.new(1, 1, 1), 0.35) else Color3.new(1, 1, 1)
end
player.CharacterAdded:Connect(function(char)
	char:GetAttributeChangedSignal("Team"):Connect(refreshMe)
	task.delay(1, refreshMe)
end)
if player.Character then player.Character:GetAttributeChangedSignal("Team"):Connect(refreshMe) end
task.delay(1, refreshMe)

-- Big message in the middle (goal, half-time, corner...)
local banner = Instance.new("Frame")
banner.Size = UDim2.fromOffset(460, 92)
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0, 70)
banner.BackgroundTransparency = 1
banner.Visible = false
banner.Parent = gui
local mainText = label(banner, { Size = UDim2.new(1, 0, 0, 60), Text = "", TextSize = 52, TextStrokeTransparency = 0.4 })
local subText = label(banner, { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 60), Text = "", TextSize = 20, Font = Enum.Font.GothamBold, TextStrokeTransparency = 0.5 })
local bannerUntil = 0
Message.OnClientEvent:Connect(function(text: any, sub: any, dur: any)
	mainText.Text = Lang.show(text)
	subText.Text = Lang.show(sub or "")
	mainText.TextSize = if (utf8.len(mainText.Text) or 0) > 12 then 36 else 52
	banner.Visible = true
	bannerUntil = os.clock() + (tonumber(dur) or 2)
end)

-- Power bar while a shot or a lob is charged, then stamina
local power = Instance.new("Frame")
power.Size = UDim2.fromOffset(220, 12)
power.AnchorPoint = Vector2.new(0.5, 1)
power.Position = UDim2.new(0.5, 0, 1, -70)
power.BackgroundColor3 = Color3.new(0, 0, 0)
power.BackgroundTransparency = 0.4
power.Visible = false
power.Parent = gui
Instance.new("UICorner", power).CornerRadius = UDim.new(0, 6)
local fill = Instance.new("Frame")
fill.Size = UDim2.fromScale(0, 1)
fill.BorderSizePixel = 0
fill.Parent = power
Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 6)
local powerLab = label(power, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, -20), Text = "", TextSize = 15, Font = Enum.Font.GothamBold, TextStrokeTransparency = 0.5 })

local stam = Instance.new("Frame")
stam.Size = UDim2.fromOffset(120, 6)
stam.AnchorPoint = Vector2.new(0.5, 1)
stam.Position = UDim2.new(0.5, 0, 1, -52)
stam.BackgroundColor3 = Color3.new(0, 0, 0)
stam.BackgroundTransparency = 0.5
stam.Parent = gui
local stamFill = Instance.new("Frame")
stamFill.Size = UDim2.fromScale(1, 1)
stamFill.BorderSizePixel = 0
stamFill.BackgroundColor3 = Color3.fromRGB(155, 227, 122)
stamFill.Parent = stam

-- Key list on computers
if not UserInputService.TouchEnabled or UserInputService.KeyboardEnabled then
	local keys = Instance.new("Frame")
	keys.Size = UDim2.fromOffset(360, 150)
	keys.AnchorPoint = Vector2.new(0, 1)
	keys.Position = UDim2.new(0, 12, 1, -12)
	keys.BackgroundColor3 = DARK
	keys.BackgroundTransparency = 0.3
	keys.Parent = gui
	Instance.new("UICorner", keys).CornerRadius = UDim.new(0, 6)
	local lines = {}
	for i = 1, 7 do table.insert(lines, t("keys." .. i)) end
	for i, s in lines do
		label(keys, { Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 6 + (i - 1) * 20), Text = s, TextSize = 14, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Left })
	end
end

RunService.RenderStepped:Connect(function()
	if banner.Visible and os.clock() > bannerUntil then banner.Visible = false end
	local ch = player:GetAttribute("Charge")
	local kind = player:GetAttribute("ChargeKind")
	if type(ch) == "number" and ch > 0 then
		power.Visible = true
		fill.Size = UDim2.fromScale(ch, 1)
		fill.BackgroundColor3 = if kind == "lob" then Color3.fromRGB(127, 212, 255) elseif ch > 0.82 then Color3.fromRGB(255, 90, 60) else Color3.fromRGB(242, 194, 48)
		powerLab.Text = if kind == "lob" then t("hud.lob") else (if ch > 0.82 then t("hud.shotstrong") else t("hud.shot"))
	else
		power.Visible = false
	end
	local s = player:GetAttribute("Stamina")
	if type(s) == "number" then
		stamFill.Size = UDim2.fromScale(s, 1)
		stamFill.BackgroundColor3 = if s < 0.25 then Color3.fromRGB(255, 90, 60) elseif player:GetAttribute("Sprinting") then Color3.fromRGB(242, 194, 48) else Color3.fromRGB(155, 227, 122)
		stam.Visible = s < 0.99
	end
end)
