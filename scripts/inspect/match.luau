-- Plays a match between computer players on a real server for about 3 minutes (half a match) and prints every goal
-- with what led to it: where the ball was, who touched it last, whether it was carried or kicked.
-- Run with scripts/run-luau.mjs: it loads the match module (server/MatchCore), which exposes ServerStorage.FC27Test.
-- In an Open Cloud session the place's scripts do not run: load the match module (what Match.server does)
local ServerStorage = game:GetService("ServerStorage")
local hook = ServerStorage:FindFirstChild("FC27Test") :: BindableFunction?
if not hook then
	require(game:GetService("ServerScriptService"):WaitForChild("Server"):WaitForChild("MatchCore"))
	hook = ServerStorage:WaitForChild("FC27Test", 30) :: BindableFunction?
end
assert(hook, "no test hook: deploy first")
hook:Invoke("start")
local last = 0
for i = 1, 36 do
	task.wait(5)
	local st = hook:Invoke("state")
	if #st.goals > last or i % 6 == 0 then
		print(string.format("t=%3ds  %d' (half %d) phase %s  score %d-%d", i * 5, st.clock, st.half, st.phase, st.score1, st.score2))
	end
	for g = last + 1, #st.goals do
		local x = st.goals[g]
		print(string.format("  GOAL team %d at %d': %s ball (%.2f, %.2f, z %.2f) v (%.1f, %.1f) last touch %s, owner %s, shotBy %s, held %s, phase %s",
			x.team, x.clock, x.how, x.x, x.y, x.z, x.vx, x.vy, x.last, x.owner, tostring(x.shot), tostring(x.held), x.phase))
	end
	last = #st.goals
end
local st = hook:Invoke("state")
return `score {st.score1}-{st.score2} after {math.floor(st.clock)}'`
