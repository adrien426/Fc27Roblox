-- Looks at the uploaded footballer as Roblox imported it: pieces, bones (names, parents, rest frames), and
-- compares each bone's rest rotation with player.glb's. Then dresses a body like the game does and checks
-- where the bones and the shirt-number spot end up. Run with scripts/run-luau.mjs.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local AssetIds = require(Shared.AssetIds)
local PlayerRest = require(Shared.PlayerRest)

local function v3(v: Vector3): string return string.format("(%.2f %.2f %.2f)", v.X, v.Y, v.Z) end
local function rot(cf: CFrame): string
	local rx, ry, rz = cf:ToEulerAnglesXYZ()
	return string.format("[%.0f %.0f %.0f]", math.deg(rx), math.deg(ry), math.deg(rz))
end

local wrapper = InsertService:LoadAsset(AssetIds.player)
local function tree(i: Instance, depth: number)
	if depth > 6 then return end
	local line = string.rep("  ", depth) .. i.ClassName .. " " .. i.Name
	if i:IsA("BasePart") then
		local sk = false
		pcall(function() sk = (i :: any).HasSkinnedMesh end)
		line ..= " size " .. v3(i.Size) .. " at " .. v3(i.Position) .. " rot " .. rot(i.CFrame) .. (if sk then " SKINNED" else "")
	elseif i:IsA("Bone") then
		line ..= " pos " .. v3(i.CFrame.Position) .. " rot " .. rot(i.CFrame)
	end
	print(line)
	local kids = i:GetChildren()
	local bones = 0
	for _, c in kids do
		if c:IsA("Bone") then bones += 1 end
		if not c:IsA("Bone") or depth < 4 then tree(c, depth + 1) end
	end
end
tree(wrapper, 0)

local all, names = 0, {}
for _, d in wrapper:GetDescendants() do
	if d:IsA("Bone") then
		all += 1
		names[d.Name] = (names[d.Name] or 0) + 1
	end
end
local list = {}
for n, c in names do table.insert(list, n .. "x" .. c) end
table.sort(list)
print(`BONES {all}: {table.concat(list, ", ")}`)

-- Rest rotation of each bone vs player.glb
local key = function(n: string) return (string.gsub(n, "^mixamorig%d*[:_%.]?", "")) end
local seen = {}
for _, d in wrapper:GetDescendants() do
	if d:IsA("Bone") and not seen[key(d.Name)] then
		local k = key(d.Name)
		seen[k] = true
		local q = PlayerRest.rot[k]
		if q then
			local gl = CFrame.new(0, 0, 0, q[1], q[2], q[3], q[4])
			local diff = gl:Inverse() * d.CFrame.Rotation
			local _, ang = diff:ToAxisAngle()
			if math.deg(ang) > 2 then
				print(`ROT DIFF {k}: roblox {rot(d.CFrame)} gltf {rot(gl)} diff {math.floor(math.deg(ang))} deg, parent {d.Parent and d.Parent.Name}`)
			end
		else
			print(`NO REST for {d.Name}`)
		end
	end
end

-- World frames of a few bones in the bind pose
for _, d in wrapper:GetDescendants() do
	if d:IsA("Bone") and ({ Hips = 1, Spine2 = 1, Head = 1, LeftFoot = 1, LeftUpLeg = 1 } :: any)[key(d.Name)] then
		print(`WORLD {d.Name} in {d.Parent and d.Parent.Name}: {v3(d.WorldPosition)} look {v3(d.WorldCFrame.LookVector)} up {v3(d.WorldCFrame.UpVector)}`)
	end
end
local m = wrapper:FindFirstChildWhichIsA("Model") or wrapper
local cf, size = (m :: Model):GetBoundingBox()
print(`BOX {m.Name}: centre {v3(cf.Position)} size {v3(size)} rot {rot(cf)}`)
return "done"
