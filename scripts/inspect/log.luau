-- Reads the telltale (server/Telemetry, DataStore FC27Log_v1): what went wrong in real matches over the last days,
-- counted by kind, then the latest entries in full.
local HttpService = game:GetService("HttpService")
local store = game:GetService("DataStoreService"):GetDataStore("FC27Log_v1")
local DAYS = 3
local all = {}
for i = DAYS - 1, 0, -1 do
	local key = os.date("!%Y-%m-%d", os.time() - i * 86400)
	local ok, list = pcall(function() return store:GetAsync(key) end)
	if ok and type(list) == "table" then
		for _, e in list do table.insert(all, e) end
	elseif not ok then
		print("cannot read " .. key .. ": " .. tostring(list))
	end
end
local count = {}
for _, e in all do count[e.k] = (count[e.k] or 0) + 1 end
local parts = {}
for k, n in count do table.insert(parts, k .. " " .. n) end
print(`{#all} entries · ` .. table.concat(parts, ", "))
for i = math.max(1, #all - 60), #all do
	local e = all[i]
	print(os.date("!%d/%m %H:%M:%S", e.t), e.env or "?", e.v or "?", e.k, if e.u then "user " .. e.u else "", HttpService:JSONEncode(e.d))
end
return #all
