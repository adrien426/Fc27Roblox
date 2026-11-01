--!strict
-- Plays the web game's Mixamo clips (Shared.Clips, made by scripts/build-anims.mjs) on the bones of the player
-- model (player.glb, the Ch38 footballer). The clips hold each bone's local rotation, exactly what three.js sets in
-- the web version; Roblox wants the change from the bone's rest pose, so Bone.Transform = rest⁻¹ · (clip pose).
-- The hips only move up and down (the game moves the player), scaled to the model's own hip height.
local Clips = script.Parent:WaitForChild("Clips")

local Skeleton = {}

export type Clip = {
	duration: number,
	frames: number,
	loop: boolean,
	hy: { number }?,
	bones: { [string]: { CFrame } },
}

export type Rig = {
	bones: { [string]: { Bone } },
	rest: { [string]: CFrame },
	restInv: { [string]: CFrame },
}

export type Pose = { [string]: CFrame }

local FPS = 30

-- ---------- Clip data ----------
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64MAP: { [number]: number } = {}
for i = 1, #B64 do
	B64MAP[string.byte(B64, i)] = i - 1
end

local function decode64(s: string): buffer
	local n = #s
	local pad = if string.sub(s, -2) == "==" then 2 elseif string.sub(s, -1) == "=" then 1 else 0
	local size = n // 4 * 3 - pad
	local out = buffer.create(size)
	local o = 0
	for i = 1, n, 4 do
		local a, b, c, d = string.byte(s, i, i + 3)
		local v = B64MAP[a] * 262144 + B64MAP[b] * 4096 + (B64MAP[c or 61] or 0) * 64 + (B64MAP[d or 61] or 0)
		local b1, b2, b3 = v // 65536, (v // 256) % 256, v % 256
		if o < size then buffer.writeu8(out, o, b1) end
		if o + 1 < size then buffer.writeu8(out, o + 1, b2) end
		if o + 2 < size then buffer.writeu8(out, o + 2, b3) end
		o += 3
	end
	return out
end

local cache: { [string]: Clip | false } = {}

-- The clip called `name`, decoded on first use (nil if there is no such clip)
function Skeleton.clip(name: string): Clip?
	local c = cache[name]
	if c == false then return nil end
	if c then return c :: Clip end
	local mod = Clips:FindFirstChild(name)
	if not mod or not mod:IsA("ModuleScript") then
		cache[name] = false
		return nil
	end
	local raw = require(mod) :: any
	local bones: { [string]: { CFrame } } = {}
	for bone, data in raw.bones do
		local buf = decode64(data)
		local list = table.create(raw.frames)
		for f = 0, raw.frames - 1 do
			local o = f * 8
			local x = buffer.readi16(buf, o) / 32767
			local y = buffer.readi16(buf, o + 2) / 32767
			local z = buffer.readi16(buf, o + 4) / 32767
			local w = buffer.readi16(buf, o + 6) / 32767
			list[f + 1] = CFrame.new(0, 0, 0, x, y, z, w)
		end
		bones[bone] = list
	end
	local hy: { number }? = nil
	if raw.hy then
		local buf = decode64(raw.hy)
		local list = table.create(raw.frames)
		for f = 0, raw.frames - 1 do
			list[f + 1] = buffer.readi16(buf, f * 2) / 10000
		end
		hy = list
	end
	local clip: Clip = { duration = raw.duration, frames = raw.frames, loop = raw.loop, hy = hy, bones = bones }
	cache[name] = clip
	return clip
end

-- ---------- Rig ----------
-- "mixamorig5:LeftArm" -> "LeftArm" (also when the importer turned the ":" into "_" or ".")
local function boneKey(name: string): string
	return (string.gsub(name, "^mixamorig%d*[:_%.]?", ""))
end
Skeleton.boneKey = boneKey

-- Finds the bones of a body and remembers their rest pose (call before animating it)
function Skeleton.bind(body: Instance): Rig?
	local bones: { [string]: { Bone } } = {}
	local rest: { [string]: CFrame } = {}
	local restInv: { [string]: CFrame } = {}
	local any = false
	for _, d in body:GetDescendants() do
		if d:IsA("Bone") then
			local k = boneKey(d.Name)
			if not bones[k] then
				bones[k] = {}
				rest[k] = d.CFrame
				restInv[k] = d.CFrame:Inverse()
			end
			table.insert(bones[k], d)
			any = true
		end
	end
	if not any then return nil end
	return { bones = bones, rest = rest, restInv = restInv }
end

-- Local pose of every animated bone at time t (seconds) of the clip
function Skeleton.sample(rig: Rig, clip: Clip, t: number, out: Pose?): Pose
	local pose: Pose = out or {}
	local d = clip.duration
	if clip.loop and d > 0 then
		t %= d
	else
		t = math.clamp(t, 0, d)
	end
	local f = t * FPS
	local i = math.floor(f)
	local k = f - i
	local last = clip.frames
	local i1 = math.clamp(i + 1, 1, last)
	local i2 = math.clamp(i + 2, 1, last)
	for name, frames in clip.bones do
		local r = rig.rest[name]
		if not r then continue end
		local rot = frames[i1]:Lerp(frames[i2], k)
		local pos = r.Position
		if name == "Hips" and clip.hy then
			local hy = clip.hy :: { number }
			local h = hy[i1] + (hy[i2] - hy[i1]) * k
			pos = Vector3.new(pos.X, pos.Y * h, pos.Z)
		end
		pose[name] = CFrame.new(pos) * rot
	end
	return pose
end

-- Mix of two poses (w = 0: a, w = 1: b); bones missing from one side keep the other
function Skeleton.blend(a: Pose, b: Pose, w: number, out: Pose?): Pose
	local pose: Pose = out or {}
	for name, cb in b do
		local ca = a[name]
		pose[name] = if ca then ca:Lerp(cb, w) else cb
	end
	for name, ca in a do
		if not b[name] then pose[name] = ca end
	end
	return pose
end

-- Puts the body in this pose
function Skeleton.apply(rig: Rig, pose: Pose)
	for name, cf in pose do
		local inv = rig.restInv[name]
		local list = rig.bones[name]
		if not inv or not list then continue end
		local tr = inv * cf
		for _, b in list do
			b.Transform = tr
		end
	end
end

return Skeleton
