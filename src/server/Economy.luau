--!strict
-- Coins, purchases and what each player has chosen to wear, saved between visits (DataStore).
-- - The game's creators (its owner, the user ids in Config.CREATORS, high ranks of an owning group, and anyone in
--   Roblox Studio) get every item free, on any branch: they are building the game.
-- - Everybody else pays through Roblox (game passes and developer products, ids in Shared.ShopIds, created by
--   scripts/create-shop.mjs at each deploy): the item is given when Roblox confirms the payment.
-- Each player's coins, items and choices are on his Player as attributes (Coins, Owned, Equip, VIP), for the HUD
-- and the shop on his machine. Net.Shop handles "buy", "pack" and "equip".
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Shop = require(Shared:WaitForChild("Shop"))
local ShopIds = require(Shared:WaitForChild("ShopIds")) :: any
local Config = require(Shared:WaitForChild("Config")) :: any
local RunService = game:GetService("RunService")

local Economy = {}
-- The game's creators: free purchases
local function isCreator(pl: Player): boolean
	if RunService:IsStudio() then return true end
	if game.CreatorType == Enum.CreatorType.User and pl.UserId == game.CreatorId then return true end
	if table.find(Config.CREATORS or {}, pl.UserId) then return true end
	if game.CreatorType == Enum.CreatorType.Group then
		local ok, rank = pcall(function() return pl:GetRankInGroup(game.CreatorId) end)
		if ok and rank >= 254 then return true end
	end
	return false
end
local creators: { [Player]: boolean } = {}

export type Data = {
	coins: number, owned: { [string]: boolean }, equip: { [string]: string },
	goals: number, matches: number, wins: number, receipts: { string },
}

local store: DataStore? = nil
pcall(function() store = DataStoreService:GetDataStore("FC27Players_v1") end)
local data: { [Player]: Data } = {}
local dirty: { [Player]: boolean } = {}

local function fresh(): Data
	return { coins = 0, owned = {}, equip = {}, goals = 0, matches = 0, wins = 0, receipts = {} }
end

-- What the player's machine needs to know
local function publish(pl: Player)
	local d = data[pl]
	if not d then return end
	pl:SetAttribute("Coins", d.coins)
	pl:SetAttribute("Owned", HttpService:JSONEncode(d.owned))
	pl:SetAttribute("Equip", HttpService:JSONEncode(d.equip))
	pl:SetAttribute("VIP", d.owned.vip == true)
	pl:SetAttribute("ShopFree", creators[pl] == true)
end

local function save(pl: Player)
	local d = data[pl]
	if not d or not store then return end
	dirty[pl] = false
	pcall(function() (store :: DataStore):SetAsync(tostring(pl.UserId), d) end)
end

local function load(pl: Player)
	local d = fresh()
	if store then
		local ok, saved = pcall(function() return (store :: DataStore):GetAsync(tostring(pl.UserId)) end)
		if ok and type(saved) == "table" then
			for k, v in saved do (d :: any)[k] = v end
		end
	end
	data[pl] = d
	creators[pl] = isCreator(pl)
	-- Game passes bought on Roblox (outside the game too): owned for good
	do
		for id, passId in ShopIds.passes do
			if passId > 0 and not d.owned[id] then
				local ok, has = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(pl.UserId, passId) end)
				if ok and has then d.owned[id] = true end
			end
		end
	end
	-- Default choices for what he owns
	for _, it in Shop.ITEMS do
		if d.owned[it.id] and it.slot and it.choices and not d.equip[it.slot] then d.equip[it.slot] = it.choices[1].id end
	end
	publish(pl)
end

local function grant(pl: Player, itemId: string)
	local d = data[pl]
	if not d then return end
	d.owned[itemId] = true
	local it = Shop.byId[itemId]
	if it and it.slot and it.choices and not d.equip[it.slot] then d.equip[it.slot] = it.choices[1].id end
	dirty[pl] = true
	publish(pl)
	save(pl)
end

function Economy.get(pl: Player): Data?
	return data[pl]
end

function Economy.equipOf(pl: Player): { [string]: string }
	local d = data[pl]
	return if d then d.equip else {}
end

function Economy.owns(pl: Player, itemId: string): boolean
	local d = data[pl]
	return d ~= nil and d.owned[itemId] == true
end

-- Coins for something done in the match (Shop.EARN), shown on his screen
function Economy.earn(pl: Player, reason: string, extra: number?)
	local d = data[pl]
	local n = (Shop.EARN :: any)[reason] or extra or 0
	if not d or n <= 0 then return end
	d.coins += n
	dirty[pl] = true
	pl:SetAttribute("Coins", d.coins)
	pl:SetAttribute("CoinGain", n)
	pl:SetAttribute("CoinReason", reason)
	pl:SetAttribute("CoinGainAt", os.clock())
end

function Economy.stat(pl: Player, key: string, n: number?)
	local d = data[pl]
	if not d then return end
	(d :: any)[key] = ((d :: any)[key] or 0) + (n or 1)
	dirty[pl] = true
end

-- ---------- Purchases ----------
local Remote = Instance.new("RemoteFunction")
Remote.Name = "Shop"
Remote.OnServerInvoke = function(pl: Player, action: any, a: any, b: any): (boolean, string)
	local d = data[pl]
	if not d then return false, "Chargement…" end
	if action == "buy" and type(a) == "string" then
		local it = Shop.byId[a]
		if not it then return false, "Article inconnu" end
		if d.owned[a] then return false, "Tu l’as déjà" end
		if b == "coins" then
			if d.coins < it.coins then return false, `Il te manque {it.coins - d.coins} pièces` end
			d.coins -= it.coins
			grant(pl, a)
			return true, `{it.name} débloqué !`
		end
		if creators[pl] then
			grant(pl, a)
			return true, `{it.name} : offert (créateur du jeu)`
		end
		local passId = ShopIds.passes[a] or 0
		if passId <= 0 then return false, "Bientôt disponible en Robux" end
		MarketplaceService:PromptGamePassPurchase(pl, passId)
		return true, "…"
	elseif action == "pack" and type(a) == "string" then
		local pack = nil
		for _, p in Shop.PACKS do if p.id == a then pack = p end end
		if not pack then return false, "Pack inconnu" end
		if creators[pl] then
			d.coins += pack.coins
			dirty[pl] = true
			publish(pl)
			return true, `+{pack.coins} pièces : offertes (créateur du jeu)`
		end
		local productId = ShopIds.products[a] or 0
		if productId <= 0 then return false, "Bientôt disponible" end
		MarketplaceService:PromptProductPurchase(pl, productId)
		return true, "…"
	elseif action == "equip" and type(a) == "string" and type(b) == "string" then
		-- a: slot (celebration, boots, kit, trail); b: choice
		local itemFor = if a == "kit" then "style" else nil
		for _, it in Shop.ITEMS do if it.slot == a then itemFor = it.id end end
		if not itemFor or not d.owned[itemFor] then return false, "Article non acheté" end
		if b ~= "none" and not Shop.choice(a, b) then return false, "Choix inconnu" end
		if b == "none" then d.equip[a] = nil else d.equip[a] = b end
		dirty[pl] = true
		publish(pl)
		return true, "Équipé"
	end
	return false, "?"
end
Remote.Parent = ReplicatedStorage:WaitForChild("Net")

-- Real purchases (main): a game pass bought in the game, and coin packs
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(pl: Player, passId: number, bought: boolean)
	if not bought then return end
	for id, pid in ShopIds.passes do
		if pid == passId then grant(pl, id) end
	end
end)
MarketplaceService.ProcessReceipt = function(info: any): Enum.ProductPurchaseDecision
	local pl = Players:GetPlayerByUserId(info.PlayerId)
	local d = pl and data[pl]
	if not pl or not d then return Enum.ProductPurchaseDecision.NotProcessedYet end
	-- Never give a pack twice for the same receipt
	if table.find(d.receipts, info.PurchaseId) then return Enum.ProductPurchaseDecision.PurchaseGranted end
	for id, pid in ShopIds.products do
		if pid == info.ProductId then
			for _, p in Shop.PACKS do
				if p.id == id then d.coins += p.coins end
			end
		end
	end
	table.insert(d.receipts, info.PurchaseId)
	if #d.receipts > 50 then table.remove(d.receipts, 1) end
	publish(pl)
	local ok = pcall(function() if store then (store :: DataStore):SetAsync(tostring(pl.UserId), d) end end)
	return if ok or not store then Enum.ProductPurchaseDecision.PurchaseGranted else Enum.ProductPurchaseDecision.NotProcessedYet
end

-- ---------- Loading and saving ----------
Players.PlayerAdded:Connect(load)
for _, pl in Players:GetPlayers() do task.spawn(load, pl) end
Players.PlayerRemoving:Connect(function(pl)
	save(pl)
	data[pl] = nil
	dirty[pl] = nil
	creators[pl] = nil
end)
task.spawn(function()
	while true do
		task.wait(60)
		for pl, isDirty in dirty do
			if isDirty then save(pl) end
		end
	end
end)
game:BindToClose(function()
	for pl in data do save(pl) end
end)

return Economy
