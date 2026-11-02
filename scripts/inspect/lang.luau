-- Checks the translations (shared/Lang): a few coded messages, as the server sends them, shown in each language
local Lang = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Lang"))
local T = Lang.L
local samples = {
	T("c.goal", { a = "Martin", team = Lang.team(1) }),
	T("say.goal"),
	T("sub.goal", { team = Lang.team(2), who = T("sub.og") }),
	T("c.setpiece", { kind = "§set.corner", team = Lang.team(2), a = "Dubois" }),
	T("lab.drib", { move = "§drib.roulette", pct = 87, res = "§res.3" }),
	T("shop.unlocked", { item = "§item.vip.name" }),
	"§board.row|{\"i\":1,\"a\":\"Adrien\",\"n\":3}" .. "\n" .. T("board.row1", { i = 2, a = "Léo", n = 1 }),
	"Martin", -- a plain name stays as it is
}
local missing = {}
for key, row in Lang.STRINGS do
	if #row ~= 6 then table.insert(missing, key .. " (" .. #row .. ")") end
end
local out = {}
for _, lang in Lang.LANGS do
	local lines = {}
	for _, s in samples do table.insert(lines, Lang.show(s, lang)) end
	table.insert(out, "[" .. lang .. "] " .. table.concat(lines, " | "))
end
print(table.concat(out, "\n"))
return { missing = missing, count = #out }
