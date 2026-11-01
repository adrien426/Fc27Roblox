-- Starts the match (server/MatchCore). The match is a module so that scripts/inspect/match.luau can run the same
-- code on a Roblox server through Open Cloud, where only modules can be loaded.
require(script.Parent:WaitForChild("MatchCore"))
