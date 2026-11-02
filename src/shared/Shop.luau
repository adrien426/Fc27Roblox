--!strict
-- The shop: what can be bought (with Robux, as a Roblox game pass, or with coins earned by playing), what each item
-- lets you choose, the coin packs, and what earns coins in a match. Shared by the server (server/Economy) and the
-- players' machines (client/Shop). Everything sold is cosmetic or comfort: nothing makes a player stronger.
local Shop = {}

export type Choice = { id: string, name: string, color: Color3? }
export type Item = {
	id: string, name: string, desc: string, robux: number, coins: number,
	slot: string?, -- what it lets you choose (Equip[slot]), if anything
	choices: { Choice }?,
}

local ITEMS: { Item } = {
	{ id = "celebrations", name = "Célébrations", desc = "Ta célébration après chaque but : tout le stade la voit.",
		robux = 99, coins = 1500, slot = "celebration",
		choices = { { id = "siuu", name = "Siuu" }, { id = "dance", name = "Danse" }, { id = "victory", name = "Victoire" }, { id = "clap", name = "Applaudir" } } },
	{ id = "style", name = "Crampons et maillots", desc = "Crampons de couleur et maillots en édition spéciale.",
		robux = 149, coins = 2000, slot = "boots",
		choices = {
			{ id = "gold", name = "Dorés", color = Color3.fromRGB(230, 180, 40) },
			{ id = "black", name = "Noirs", color = Color3.fromRGB(20, 20, 22) },
			{ id = "white", name = "Blancs", color = Color3.fromRGB(240, 240, 240) },
			{ id = "pink", name = "Roses", color = Color3.fromRGB(235, 60, 140) },
			{ id = "cyan", name = "Cyan", color = Color3.fromRGB(40, 200, 230) },
		} },
	{ id = "vip", name = "Pass VIP", desc = "Nom en doré ★ sur le terrain et accès au coin VIP du vestiaire.",
		robux = 299, coins = 5000 },
	{ id = "trail", name = "Effet de tir", desc = "Une traînée derrière le ballon sur tes frappes.",
		robux = 149, coins = 2000, slot = "trail",
		choices = {
			{ id = "fire", name = "Feu", color = Color3.fromRGB(255, 120, 30) },
			{ id = "stars", name = "Étoiles", color = Color3.fromRGB(255, 230, 120) },
			{ id = "ice", name = "Glace", color = Color3.fromRGB(120, 210, 255) },
		} },
}

Shop.ITEMS = ITEMS

-- The special shirts that come with "style" (the team colour stays, so that everybody still knows who is who)
local KITS: { Choice } = {
	{ id = "classic", name = "Classique" },
	{ id = "gold", name = "Édition or", color = Color3.fromRGB(230, 180, 40) },
	{ id = "dark", name = "Édition noire", color = Color3.fromRGB(20, 20, 22) },
}

Shop.KITS = KITS

-- Coin packs bought with Robux (Roblox developer products: can be bought again and again)
Shop.PACKS = {
	{ id = "coins500", coins = 500, robux = 49 },
	{ id = "coins1500", coins = 1500, robux = 129 },
	{ id = "coins5000", coins = 5000, robux = 399 },
}

-- What earns coins in a match (humans only)
Shop.EARN = { goal = 50, pass = 3, tackle = 10, win = 100, draw = 30 }

Shop.byId = {} :: { [string]: Item }
for _, it in Shop.ITEMS do Shop.byId[it.id] = it end

function Shop.choice(itemOrSlot: string, id: string?): Choice?
	local list: { Choice }? = nil
	if itemOrSlot == "kit" then list = Shop.KITS end
	for _, it in Shop.ITEMS do
		if it.slot == itemOrSlot or it.id == itemOrSlot then list = it.choices end
	end
	if not list or not id then return nil end
	for _, c in list :: { Choice } do
		if c.id == id then return c end
	end
	return nil
end

return Shop
