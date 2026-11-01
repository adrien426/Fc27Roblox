-- Loads the web game's models from Roblox (ids in Shared.AssetIds) when the server starts:
-- the footballer and the stadium stay on the server (ServerStorage.FC27Assets), the balls go to
-- ReplicatedStorage.FC27Assets because each player's machine draws its own ball.
-- A model that is missing or fails to load is simply absent: the game keeps its built-in stand-in.
local InsertService = game:GetService("InsertService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local AssetIds = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AssetIds"))

local Assets = {}

local function folder(parent: Instance): Folder
	local f = parent:FindFirstChild("FC27Assets")
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = "FC27Assets"
	nf.Parent = parent
	return nf
end

local serverFolder = folder(ServerStorage)
local sharedFolder = folder(ReplicatedStorage)

-- LoadAsset returns a Model wrapping what was uploaded: that content becomes a single Model named `name`
local function prepare(name: string, wrapper: Model, parent: Instance): Model
	local kids = wrapper:GetChildren()
	local m: Model
	if #kids == 1 and kids[1]:IsA("Model") then
		m = kids[1] :: Model
		m.Parent = nil -- out of the wrapper first: destroying the wrapper would lock it
	else
		m = Instance.new("Model")
		for _, c in kids do c.Parent = m end
	end
	wrapper:Destroy()
	m.Name = name
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	m.Parent = parent
	return m
end

-- Never throws: any problem is reported in the console and the model is left out
local function load(name: string, id: number, parent: Instance): Model?
	if id <= 0 then return nil end
	local ok, res = pcall(function() return InsertService:LoadAsset(id) end)
	if not ok or not res then
		warn(`[FC27] Could not load the {name} model (asset {id}): {res}`)
		return nil
	end
	local ok2, m = pcall(prepare, name, res :: Model, parent)
	if not ok2 then
		warn(`[FC27] Could not prepare the {name} model (asset {id}): {m}`)
		return nil
	end
	return m
end

Assets.player = load("Player", AssetIds.player, serverFolder)
-- What the footballer was imported as (console, F9 > Server): the animations need its bones
if Assets.player then
	local parts, bones, skinned, names = 0, 0, 0, {}
	for _, d in Assets.player:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			local ok, sk = pcall(function() return (d :: any).HasSkinnedMesh end)
			if ok and sk then skinned += 1 end
		elseif d:IsA("Bone") then
			bones += 1
			if #names < 4 then table.insert(names, d.Name) end
		end
	end
	print(`[FC27] Player model: {parts} parts ({skinned} skinned), {bones} bones ({table.concat(names, ", ")})`)
end
Assets.stadium = load("Stadium", AssetIds.stadium, serverFolder)
Assets.balls = load("Balls", AssetIds.balls, sharedFolder)

return Assets
