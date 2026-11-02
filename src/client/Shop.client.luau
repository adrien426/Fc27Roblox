--!strict
-- The shop (walk up to the BOUTIQUE counter in the locker room, or the 🛒 button there): each item with its price in
-- Robux and in coins, and its picture (assets/art, uploaded as decals: Shared.AssetIds.art); once bought, its choices (celebration, boots, special shirt, shot trail) to equip. Coin packs
-- at the bottom. The game's creators get everything free (server/Economy), as a banner says. Also: your coins in
-- the corner of the screen, and a "+50 But" when you earn some.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")

local Shop = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Shop"))
local AssetIds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetIds")) :: any
local Net = ReplicatedStorage:WaitForChild("Net")
local Remote = Net:WaitForChild("Shop") :: RemoteFunction

local player = Players.LocalPlayer
local DARK = Color3.fromRGB(14, 24, 18)
local GOLD = Color3.fromRGB(242, 194, 48)
local GREEN = Color3.fromRGB(120, 230, 140)
local REASON = { goal = "But", pass = "Passe", tackle = "Tacle", win = "Victoire", draw = "Match nul" }

local gui = Instance.new("ScreenGui")
gui.Name = "FC27Shop"
gui.ResetOnSpawn = false
gui.DisplayOrder = 9
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
local function button(parent: Instance, text: string, color: Color3, textColor: Color3, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	b.BackgroundColor3 = color
	b.TextColor3 = textColor
	b.Font = Enum.Font.GothamBlack
	b.TextSize = 13
	b.AutoButtonColor = true
	for k, v in props do (b :: any)[k] = v end
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	b.Parent = parent
	return b
end

-- A coin drawn with frames (the 🪙 emoji does not exist in the game's fonts and shows as a box)
local function coinIcon(parent: Instance, size: number, pos: UDim2)
	local c = Instance.new("Frame")
	c.Size = UDim2.fromOffset(size, size)
	c.Position = pos
	c.AnchorPoint = Vector2.new(0, 0.5)
	c.BackgroundColor3 = GOLD
	c.Parent = parent
	Instance.new("UICorner", c).CornerRadius = UDim.new(1, 0)
	local ring = Instance.new("UIStroke")
	ring.Color = Color3.fromRGB(170, 120, 20)
	ring.Thickness = math.max(1, size / 9)
	ring.Parent = c
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Text = "C"
	t.TextScaled = true
	t.Font = Enum.Font.GothamBlack
	t.TextColor3 = Color3.fromRGB(150, 100, 10)
	t.Parent = c
	return c
end

-- An item's picture, rounded; nothing when it is not uploaded yet
local function picture(parent: Instance, id: string, size: number, pos: UDim2)
	local art = AssetIds.art or {}
	local assetId = art[id]
	if type(assetId) ~= "number" or assetId <= 0 then return end
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromOffset(size, size)
	img.Position = pos
	img.BackgroundColor3 = Color3.fromRGB(20, 26, 32)
	img.Image = `rbxthumb://type=Asset&id={assetId}&w=150&h=150`
	img.ScaleType = Enum.ScaleType.Crop
	img.Parent = parent
	Instance.new("UICorner", img).CornerRadius = UDim.new(0, 10)
end

-- ---------- Coins in the corner, and what you just earned ----------
local coins = label(gui, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -130, 0, 8), Size = UDim2.fromOffset(110, 32),
	BackgroundTransparency = 0.15, BackgroundColor3 = DARK, Text = "      0", TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = GOLD })
coinIcon(coins, 18, UDim2.new(0, 10, 0.5, 0))
Instance.new("UICorner", coins).CornerRadius = UDim.new(0, 8)
local function showCoins() coins.Text = "      " .. tostring(player:GetAttribute("Coins") or 0) end
player:GetAttributeChangedSignal("Coins"):Connect(showCoins)
showCoins()
player:GetAttributeChangedSignal("CoinGainAt"):Connect(function()
	local n = player:GetAttribute("CoinGain")
	local why = player:GetAttribute("CoinReason")
	if type(n) ~= "number" then return end
	local pop = label(gui, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -130, 0, 44), Size = UDim2.fromOffset(160, 24),
		Text = `+{n} pièces · {REASON[why] or ""}`, TextSize = 16, Font = Enum.Font.GothamBlack, TextColor3 = GREEN, TextXAlignment = Enum.TextXAlignment.Right })
	TweenService:Create(pop, TweenInfo.new(1.6), { Position = UDim2.new(1, -130, 0, 80), TextTransparency = 1 }):Play()
	task.delay(1.7, function() pop:Destroy() end)
end)

-- ---------- The shop panel ----------
local panel = Instance.new("Frame")
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.52)
panel.Size = UDim2.fromOffset(640, 400)
panel.BackgroundColor3 = DARK
panel.BackgroundTransparency = 0.05
panel.Visible = false
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
local scale = Instance.new("UIScale")
scale.Parent = panel
label(panel, { Size = UDim2.new(1, -60, 0, 32), Position = UDim2.fromOffset(16, 8), Text = "🛒 Boutique FC27", TextSize = 20,
	Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left })
local banner = label(panel, { Size = UDim2.new(1, -230, 0, 18), Position = UDim2.fromOffset(200, 14), TextSize = 12, TextColor3 = GOLD,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "" })
local status = label(panel, { Size = UDim2.new(1, -32, 0, 18), Position = UDim2.new(0, 16, 1, -24), TextSize = 13, TextColor3 = GREEN,
	TextXAlignment = Enum.TextXAlignment.Left, Text = "Tout est cosmétique : rien ne rend plus fort, tout se voit sur le terrain." })
local close = button(panel, "X", Color3.fromRGB(60, 66, 74), Color3.new(1, 1, 1), { Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -44, 0, 8), TextSize = 18 })

local list = Instance.new("ScrollingFrame")
list.Size = UDim2.new(1, -24, 1, -78)
list.Position = UDim2.fromOffset(12, 46)
list.BackgroundTransparency = 1
list.ScrollBarThickness = 6
list.AutomaticCanvasSize = Enum.AutomaticSize.Y
list.CanvasSize = UDim2.new()
list.Parent = panel
local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.Parent = list

local function decode(attr: string): { [string]: any }
	local raw = player:GetAttribute(attr)
	if type(raw) ~= "string" then return {} end
	local ok, t = pcall(function() return HttpService:JSONDecode(raw) end)
	return if ok and type(t) == "table" then t else {}
end

local busy = false
local render: () -> ()
local function call(action: string, a: string, b: string?)
	if busy then return end
	busy = true
	status.Text = "…"
	local ok, res, msg = pcall(function() return Remote:InvokeServer(action, a, b) end)
	busy = false
	if not ok then status.Text = "Erreur, réessaie"; return end
	status.TextColor3 = if res then GREEN else Color3.fromRGB(255, 140, 120)
	if msg ~= "…" then status.Text = tostring(msg) else status.Text = "Paiement Roblox en cours…" end
	render()
end

local function choiceRow(parent: Instance, y: number, slot: string, choices: { Shop.Choice }, equipped: string?)
	local x = 8
	for _, c in choices do
		local on = equipped == c.id
		local b = button(parent, c.name, if on then GOLD else Color3.fromRGB(44, 54, 62), if on then DARK else Color3.new(1, 1, 1),
			{ Size = UDim2.fromOffset(104, 24), Position = UDim2.fromOffset(x, y), TextSize = 12 })
		-- A colour dot on the left, the name pushed right of it (it used to be drawn over long names); a dark ring
		-- keeps a gold dot visible on the gold "equipped" button; "Classique" has a neutral grey dot
		local col = c.color or (if slot == "kit" then Color3.fromRGB(150, 150, 150) else nil)
		if col then
			local pad = Instance.new("UIPadding")
			pad.PaddingLeft = UDim.new(0, 14)
			pad.Parent = b
			local dot = Instance.new("Frame")
			dot.Size = UDim2.fromOffset(9, 9)
			dot.AnchorPoint = Vector2.new(0, 0.5)
			dot.Position = UDim2.new(0, -9, 0.5, 0)
			dot.BackgroundColor3 = col :: Color3
			dot.Parent = b
			Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
			local ring = Instance.new("UIStroke")
			ring.Color = Color3.fromRGB(20, 20, 20)
			ring.Thickness = 1
			ring.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			ring.Parent = dot
		end
		b.Activated:Connect(function() call("equip", slot, c.id) end)
		x += 110
	end
end

render = function()
	for _, c in list:GetChildren() do if c:IsA("Frame") then c:Destroy() end end
	banner.Text = if player:GetAttribute("ShopFree") == true then "CRÉATEUR : tout est offert" else ""
	local owned = decode("Owned")
	local equip = decode("Equip")
	local have = (player:GetAttribute("Coins") :: number?) or 0
	for i, it in Shop.ITEMS do
		local isOwned = owned[it.id] == true
		local rows = if isOwned then (if it.id == "style" then 2 elseif it.choices then 1 else 0) else 0
		local card = Instance.new("Frame")
		card.LayoutOrder = i
		card.Size = UDim2.new(1, -10, 0, 84 + rows * 30)
		card.BackgroundColor3 = if isOwned then Color3.fromRGB(34, 52, 40) else Color3.fromRGB(28, 36, 44)
		card.Parent = list
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)
		picture(card, it.id, 72, UDim2.fromOffset(6, 6))
		label(card, { Size = UDim2.new(1, -290, 0, 22), Position = UDim2.fromOffset(88, 5), Text = it.name .. (if isOwned then "  ✓" else ""),
			TextSize = 15, Font = Enum.Font.GothamBlack, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = if isOwned then GREEN else Color3.new(1, 1, 1) })
		label(card, { Size = UDim2.new(1, if isOwned then -100 else -290, 0, 50), Position = UDim2.fromOffset(88, 28), Text = it.desc, TextSize = 12,
			Font = Enum.Font.Gotham, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
			TextColor3 = Color3.fromRGB(190, 196, 204), TextWrapped = true })
		if not isOwned then
			local r = button(card, `{it.robux} R$`, Color3.fromRGB(40, 170, 90), Color3.new(1, 1, 1), { Size = UDim2.fromOffset(84, 30), Position = UDim2.new(1, -186, 0, 27) })
			r.Activated:Connect(function() call("buy", it.id, "robux") end)
			local c = button(card, `     {it.coins}`, if have >= it.coins then GOLD else Color3.fromRGB(70, 70, 70), DARK,
				{ Size = UDim2.fromOffset(90, 30), Position = UDim2.new(1, -96, 0, 27) })
			c.Activated:Connect(function() call("buy", it.id, "coins") end)
			coinIcon(c, 16, UDim2.new(0, 8, 0.5, 0))
		elseif it.choices and it.slot then
			choiceRow(card, 84, it.slot, it.choices, equip[it.slot])
			if it.id == "style" then choiceRow(card, 114, "kit", Shop.KITS, equip.kit) end
		end
	end
	-- Coin packs
	local packs = Instance.new("Frame")
	packs.LayoutOrder = 100
	packs.Size = UDim2.new(1, -10, 0, 128)
	packs.BackgroundColor3 = Color3.fromRGB(44, 38, 20)
	packs.Parent = list
	Instance.new("UICorner", packs).CornerRadius = UDim.new(0, 8)
	label(packs, { Size = UDim2.fromOffset(150, 22), Position = UDim2.fromOffset(10, 6), Text = "Pièces", TextSize = 15, Font = Enum.Font.GothamBlack,
		TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = GOLD })
	label(packs, { Size = UDim2.fromOffset(150, 80), Position = UDim2.fromOffset(10, 30), TextSize = 12, Font = Enum.Font.Gotham, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = Color3.fromRGB(220, 206, 170),
		Text = "Pour acheter les articles. Tu en gagnes aussi en jouant !" })
	for i, p in Shop.PACKS do
		local x = -(4 - i) * 138
		picture(packs, p.id, 72, UDim2.new(1, x + 29, 0, 8))
		local b = button(packs, `+{p.coins} · {p.robux} R$`, Color3.fromRGB(40, 170, 90), Color3.new(1, 1, 1),
			{ Size = UDim2.fromOffset(130, 30), Position = UDim2.new(1, x, 0, 88) })
		b.Activated:Connect(function() call("pack", p.id) end)
	end
end
for _, a in { "Owned", "Equip", "Coins" } do
	player:GetAttributeChangedSignal(a):Connect(function() if panel.Visible then render() end end)
end

-- 🛒 button in the locker room, and the counter
local open = button(gui, "🛒 Boutique", GOLD, DARK, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -250, 0, 8), Size = UDim2.fromOffset(110, 32), TextSize = 14 })
local function show(on: boolean)
	if on then render() end
	panel.Visible = on
end
open.Activated:Connect(function() show(not panel.Visible) end)
local dismissed = false
close.Activated:Connect(function() show(false); dismissed = true end)
RunService.Heartbeat:Connect(function()
	local inMatch = player:GetAttribute("InMatch") == true
	open.Visible = not inMatch and not panel.Visible
	if inMatch then
		if panel.Visible then show(false) end
		return
	end
	local cam = workspace.CurrentCamera
	if cam then scale.Scale = math.min(1, (cam.ViewportSize.X - 20) / 640, (cam.ViewportSize.Y - 20) / 400) end
	local lobby = workspace:FindFirstChild("Lobby")
	local zone = lobby and lobby:FindFirstChild("ShopZone")
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not zone or not root or not zone:IsA("BasePart") or not root:IsA("BasePart") then return end
	local rel = zone.CFrame:PointToObjectSpace(root.Position)
	local inside = math.abs(rel.X) < zone.Size.X / 2 and math.abs(rel.Z) < zone.Size.Z / 2 and math.abs(rel.Y) < 8
	if inside and not panel.Visible and not dismissed then
		show(true)
	elseif not inside then
		dismissed = false
	end
end)
