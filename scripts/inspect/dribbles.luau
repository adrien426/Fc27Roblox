-- Checks the skill moves on a real server: every move's data runs, and a move's body animation turns the bones
-- the right way on a dressed footballer (same bone-turning code as client/Bodies). Run with scripts/run-luau.mjs.
local ServerScriptService = game:GetService("ServerScriptService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Skeleton = require(Shared.Skeleton)
local Dribbles = require(Shared.Dribbles)
local Rig = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Rig"))
local M = Config.M

local errors = 0
for _, m in Dribbles.list do
	for i = 0, 10 do
		local ok, err = pcall(function()
			m.v(i / 10)
			if m.ball then m.ball(i / 10) end
			Dribbles.pose(m, i / 10)
		end)
		if not ok then errors += 1; print(`ERROR {m.key} k={i / 10}: {err}`) end
	end
end
print(`{#Dribbles.list} moves checked, {errors} errors`)

-- Same as client/Bodies
local function worldOf(i: Instance): CFrame
	if i:IsA("Bone") then
		local p = i.Parent
		return (if p then worldOf(p) else CFrame.identity) * i.CFrame * i.Transform
	elseif i:IsA("BasePart") then
		return i.CFrame
	end
	return CFrame.identity
end
local function turnBone(b: Bone?, rot: CFrame?, lift: Vector3?)
	if not b then return end
	local p = b.Parent
	local base = (if p then worldOf(p) else CFrame.identity) * b.CFrame
	local w = base * b.Transform
	local r = if rot then rot * w.Rotation else w.Rotation
	b.Transform = base:Inverse() * (CFrame.new(w.Position + (lift or Vector3.zero)) * r)
end

local model = Rig.createBot("Test", 1, 10, Random.new(1))
model:PivotTo(CFrame.new(0, 50, 0))
model.Parent = workspace
local body = model:FindFirstChild("Body") :: Model
local rig = Skeleton.bind(body)
assert(rig, "no bones")
local function b(k: string): Bone return rig.bones[k][1] end
local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
local F = root.CFrame.LookVector
local R = F:Cross(Vector3.yAxis)
local function rel(bn: Bone): Vector3
	local p = worldOf(bn).Position - root.Position
	return Vector3.new(p:Dot(R), p.Y, p:Dot(F)) / M -- metres: right, up, forward
end
local function v3(v: Vector3): string return string.format("(right %.2f up %.2f fwd %.2f)", v.X, v.Y, v.Z) end

print("Rest: right foot " .. v3(rel(b("RightFoot"))) .. "  left foot " .. v3(rel(b("LeftFoot"))) .. "  head " .. v3(rel(b("Head"))))
-- Right leg swung forward 0.8 rad (a kick's back-lift reversed): the right foot must go forward and up
turnBone(b("RightUpLeg"), CFrame.fromAxisAngle(R, 0.8))
print("Right thigh +0.8 about right axis: right foot " .. v3(rel(b("RightFoot"))))
-- Body spun a quarter turn and lifted 0.3 m
turnBone(b("Hips"), CFrame.Angles(0, math.pi / 2, 0), Vector3.new(0, 0.3 * M, 0))
print("Quarter spin + hop 0.3 m: head " .. v3(rel(b("Head"))) .. "  left foot " .. v3(rel(b("LeftFoot"))))
model:Destroy()
return "done" -- dribbles
