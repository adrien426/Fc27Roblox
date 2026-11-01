-- Roblox ids of the shop's game passes and Robux coin packs (developer products), written by
-- scripts/create-shop.mjs when the main branch is deployed. 0 = not created yet: buying with Robux is not offered
-- for it in the real game (coins still work; on the test branch every purchase is simulated anyway).
return {
	passes = { celebrations = 0, style = 0, vip = 0, trail = 0 },
	products = { coins500 = 0, coins1500 = 0, coins5000 = 0 },
}
