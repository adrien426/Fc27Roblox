-- Dresses a computer player the way the game does (server/Rig) and measures, on a real Roblox server: the
-- footballer's height, where his feet are compared with the grass and the R15 body, which way he faces, and
-- how far the shirt-number spot is from his back. Run with scripts/run-luau.mjs after a deploy.
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)
local Skeleton = require(Shared.Skeleton)
local Rig = require(ServerScriptService:WaitForChild("Server"):WaitForChild("Rig"))

local function v3(v: Vector3): string return string.format("(%.2f %.2f %.2f)", v.X, v.Y, v.Z) end

local model = Rig.createBot("Test", 1, 10, Random.new(1))
local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
model:PivotTo(CFrame.new(0, 50, 0))
model.Parent = workspace
local hum = model:FindFirstChildOfClass("Humanoid") :: Humanoid
local body = model:FindFirstChild("Body") :: Model
print(`R15 root {v3(root.Position)} size {v3(root.Size)} hip {hum.HipHeight} look {v3(root.CFrame.LookVector)}`)
if not body then
	print("NO BODY: the footballer was not put on")
	return "no body"
end

local feetY = root.Position.Y - hum.HipHeight - root.Size.Y / 2
local cf, size = Skeleton.meshBox(body)
print(`BODY mesh box size {v3(size)} -> height {string.format("%.2f", size.Y / Config.M)} m (want {Config.PLAYER_HEIGHT})`)
print(`BODY bottom {string.format("%.2f", cf.Position.Y - size.Y / 2)} vs R15 feet {string.format("%.2f", feetY)} (studs)`)

-- Avatar's own lowest point, for comparison
local lo = math.huge
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") and not d:IsDescendantOf(body) and d.Name ~= "HumanoidRootPart" then
		lo = math.min(lo, d.Position.Y - d.Size.Y / 2)
	end
end
print(`R15 avatar lowest point {string.format("%.2f", lo)}`)

local bones = {}
for _, d in body:GetDescendants() do
	if d:IsA("Bone") then bones[Skeleton.boneKey(d.Name)] = d end
end
local l, r, sp, head, foot = bones.LeftUpLeg, bones.RightUpLeg, bones.Spine2, bones.Head, bones.LeftFoot
if l and r then
	local fwd = (l.WorldPosition - r.WorldPosition):Cross(Vector3.yAxis).Unit
	print(`FACING from hips {v3(fwd)} vs root look {v3(root.CFrame.LookVector)} (dot {string.format("%.2f", fwd:Dot(root.CFrame.LookVector))})`)
end
if sp then print(`Spine2 {v3(sp.WorldPosition)}  height above feet {string.format("%.2f", (sp.WorldPosition.Y - feetY) / Config.M)} m`) end
if head then print(`Head {v3(head.WorldPosition)}  height above feet {string.format("%.2f", (head.WorldPosition.Y - feetY) / Config.M)} m`) end
if foot then print(`LeftFoot {v3(foot.WorldPosition)}  height above feet {string.format("%.2f", (foot.WorldPosition.Y - feetY) / Config.M)} m`) end

-- Shirt back: where a ray from behind, at the number's height, meets the shirt
local shirt
for _, d in body:GetDescendants() do
	if d:IsA("MeshPart") and d.Name:find("Shirt") then shirt = d end
end
if sp and shirt then
	local look = root.CFrame.LookVector
	local spot = sp.WorldPosition - look * (0.115 * Config.M) - Vector3.new(0, 0.03 * Config.M, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { shirt }
	shirt.CanQuery = true
	local from = spot - look * 3
	local hit = workspace:Raycast(from, look * 6, params)
	if hit then
		print(`NUMBER spot is {string.format("%.3f", (hit.Position - spot):Dot(look) / Config.M)} m behind the shirt surface (0 = on it)`)
	else
		print("NUMBER: no shirt hit by the ray (skinned meshes may not be raycastable)")
	end
end
model:Destroy()
return "done" -- body
