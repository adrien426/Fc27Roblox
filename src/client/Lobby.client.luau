--!strict
-- The locker room: walking into the glowing MATCH ring opens the picker. Both teams are shown with their eleven
-- places (number, position, and who plays there: a computer player or a human); picking a free place sends you onto
-- the pitch there (Net.Join). Computer players fill every place nobody takes. While you play, a "Vestiaire" button
-- brings you back here (Net.Leave) and a computer player takes your place again.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))
local Net = ReplicatedStorage:WaitForChild("Net")
local Join = Net:WaitForChild("Join") :: RemoteFunction
local Leave = Net:WaitForChild("Leave") :: RemoteEvent

local player = Players.LocalPlayer
local DARK = Color3.fromRGB(14, 24, 18)
local GOLD = Color3.fromRGB(242, 194, 48)
local ROLE = { GK = "Gardien", DF = "Défenseur", MF = "Milieu", FW = "Attaquant" }

local gui = Instance.new("ScreenGui")
gui.Name = "FC27Lobby"
gui.ResetOnSpawn = false
gui.DisplayOrder = 8
gui.Parent = player:WaitForChild("PlayerGui")

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamBold
	t.TextColor3 = Color3.new(1, 1, 1)
	for k, v in props do (t :: any)[k] = v end
	t.Parent = parent
	return t
end

-- ---------- Picker ----------
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.Size = UDim2.new(0, 620, 0, 380)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.08
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local scale = Instance.new("UIScale")
scale.Parent = panel
label(panel, { Size = UDim2.new(1, -60, 0, 34), Position = UDim2.fromOffset(16, 8), Text = "Choisis ton équipe et ton poste",
	TextSize = 20, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left })
local status = label(panel, { Size = UDim2.new(1, -32, 0, 18), Position = UDim2.new(0, 16, 1, -26), Text = "", TextSize = 13,
	TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Left })
local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(36, 36)
close.Position = UDim2.new(1, -46, 0, 8)
close.BackgroundColor3 = Color3.fromRGB(60, 66, 74)
close.Text = "X"
close.TextColor3 = Color3.new(1, 1, 1)
close.Font = Enum.Font.GothamBlack
close.TextSize = 18
close.Parent = panel
Instance.new("UICorner", close).CornerRadius = UDim.new(1, 0)

local columns = Instance.new("Frame")
columns.Size = UDim2.new(1, -32, 1, -84)
columns.Position = UDim2.fromOffset(16, 48)
columns.BackgroundTransparency = 1
columns.Parent = panel

local busy = false
local function render()
	for _, c in columns:GetChildren() do c:Destroy() end
	local raw = Net:GetAttribute("Lineups")
	if type(raw) ~= "string" then return end
	local ok, teams = pcall(function() return HttpService:JSONDecode(raw) end)
	if not ok or type(teams) ~= "table" then return end
	for t = 1, 2 do
		local team = Config.TEAMS[t]
		local list = teams[t] or {}
		local humans = 0
		for _, p in list do if p.human then humans += 1 end end
		local col = Instance.new("Frame")
		col.Size = UDim2.new(0.5, -6, 1, 0)
		col.Position = UDim2.new(if t == 1 then 0 else 0.5, if t == 1 then 0 else 6, 0, 0)
		col.BackgroundColor3 = Color3.fromRGB(24, 34, 30)
		col.Parent = columns
		Instance.new("UICorner", col).CornerRadius = UDim.new(0, 10)
		local bar = Instance.new("Frame")
		bar.Size = UDim2.new(1, 0, 0, 4)
		bar.BackgroundColor3 = team.color
		bar.BorderSizePixel = 0
		bar.Parent = col
		label(col, { Size = UDim2.new(1, -16, 0, 24), Position = UDim2.fromOffset(8, 6), Text = `{string.upper(team.name)}  ·  {humans} joueur{if humans > 1 then "s" else ""}`,
			TextSize = 15, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left })
		for i, p in list do
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, -12, 0, 21)
			row.Position = UDim2.fromOffset(6, 32 + (i - 1) * 23)
			row.AutoButtonColor = true
			row.Text = ""
			local free = not p.human
			row.BackgroundColor3 = if p.human then Color3.fromRGB(90, 70, 20) elseif free then Color3.fromRGB(40, 56, 48) else Color3.fromRGB(34, 38, 42)
			row.Parent = col
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)
			label(row, { Size = UDim2.new(0.62, 0, 1, 0), Position = UDim2.fromOffset(6, 0), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Left,
				Text = `{p.num}  {ROLE[p.role] or p.role}`, TextColor3 = if free then Color3.new(1, 1, 1) else Color3.fromRGB(170, 176, 184) })
			label(row, { Size = UDim2.new(0.38, -6, 1, 0), Position = UDim2.new(0.62, 0, 0, 0), TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right,
				Text = if p.human then (if p.vip then "★ " else "") .. p.name else "libre  »",
				TextColor3 = if p.human then GOLD elseif free then Color3.fromRGB(140, 230, 150) else Color3.fromRGB(150, 150, 150) })
			if free then
				row.Activated:Connect(function()
					if busy then return end
					busy = true
					status.Text = "On t’envoie sur le terrain…"
					local okJ, res, msg = pcall(function() return Join:InvokeServer(t, p.slot) end)
					busy = false
					if okJ and res then
						panel.Visible = false
					else
						status.Text = if okJ then tostring(msg) else "Erreur, réessaie"
					end
				end)
			end
		end
	end
end
Net:GetAttributeChangedSignal("Lineups"):Connect(function() if panel.Visible then render() end end)

-- ---------- The ring ----------
local dismissed = false -- closed with X: it opens again after stepping out of the ring and back in
close.Activated:Connect(function() panel.Visible = false; dismissed = true end)
RunService.Heartbeat:Connect(function()
	if player:GetAttribute("InMatch") == true then
		panel.Visible = false
		return
	end
	local lobby = workspace:FindFirstChild("Lobby")
	local ring = lobby and lobby:FindFirstChild("Ring")
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not ring or not root or not ring:IsA("BasePart") or not root:IsA("BasePart") then return end
	local d = Vector3.new(root.Position.X - ring.Position.X, 0, root.Position.Z - ring.Position.Z).Magnitude
	local inside = d < ring.Size.Y / 2 and math.abs(root.Position.Y - ring.Position.Y) < 12
	if inside and not panel.Visible and not dismissed then
		status.Text = "Touche une place libre pour entrer sur le terrain. Les robots jouent les autres."
		render()
		panel.Visible = true
	elseif not inside then
		dismissed = false
		panel.Visible = false
	end
	-- Smaller screens: shrink the picker
	local cam = workspace.CurrentCamera
	if cam then scale.Scale = math.min(1, (cam.ViewportSize.X - 20) / 620, (cam.ViewportSize.Y - 20) / 380) end
end)

-- ---------- Back to the locker room ----------
local back = Instance.new("TextButton")
back.AnchorPoint = Vector2.new(1, 0)
back.Position = UDim2.new(1, -12, 0, 8)
back.Size = UDim2.fromOffset(110, 32)
back.BackgroundColor3 = Color3.fromRGB(20, 38, 28)
back.BackgroundTransparency = 0.1
back.Text = "↩ Vestiaire"
back.TextColor3 = Color3.new(1, 1, 1)
back.Font = Enum.Font.GothamBold
back.TextSize = 14
back.Visible = false
back.Parent = gui
Instance.new("UICorner", back).CornerRadius = UDim.new(0, 8)
back.Activated:Connect(function() Leave:FireServer() end)
local function showBack() back.Visible = player:GetAttribute("InMatch") == true end
player:GetAttributeChangedSignal("InMatch"):Connect(showBack)
showBack()
