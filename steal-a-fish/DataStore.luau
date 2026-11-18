-- STEAL A FISH (Deep Dive Tycoon) · Persistence with DataStoreService
-- · Session locking so two servers never overwrite the same profile.
-- · Retries with exponential backoff.
-- · If loading fails, the profile is marked as NOT saveable (good data is never overwritten with empty data).
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.DeepDive.Config)

local Data = {}

local JOB_ID = game.JobId ~= "" and game.JobId or ("studio-" .. HttpService:GenerateGUID(false))
local store = nil
Data.Available = false
Data.UnavailableReason = nil

local function isFatal(err)
	err = tostring(err)
	return string.find(err, "publish", 1, true) ~= nil
		or string.find(err, "Studio access", 1, true) ~= nil
		or string.find(err, "API Services", 1, true) ~= nil
		or string.find(err, "403", 1, true) ~= nil
end

do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok and game.PlaceId ~= 0 then
		Data.Available = true
	else
		Data.UnavailableReason = ok and "the place is not published" or tostring(err)
	end
end

local function key(userId)
	return "player_" .. userId
end

local IS_STUDIO = string.sub(JOB_ID, 1, 7) == "studio-"

local function lockedByOther(data)
	local s = data and data.Session
	if s ~= nil and IS_STUDIO and string.sub(tostring(s.Job), 1, 7) == "studio-" then
		-- an older Studio test session (Studio doesn't always release the lock when you stop): take it over.
		-- Live servers are never affected: their JobId never starts with "studio-".
		return false
	end
	return s ~= nil and s.Job ~= JOB_ID and (os.time() - (s.Time or 0)) < Config.SessionLockTimeout
end

-- Returns: status ("ok" | "unavailable" | "error"), data (table, or nil for a new player)
function Data.Load(userId)
	if not Data.Available then
		return "unavailable", nil
	end
	for attempt = 1, 6 do
		local result, wasLocked = nil, false
		local ok, err = pcall(function()
			store:UpdateAsync(key(userId), function(old)
				if lockedByOther(old) then
					wasLocked = true
					return nil -- cancel: another server owns the session
				end
				old = old or {}
				old.Session = { Job = JOB_ID, Time = os.time() }
				result = old
				return old
			end)
		end)
		if ok and not wasLocked then
			result.Session = nil
			return "ok", result
		end
		if not ok then
			warn("[DeepDive] Load error (attempt " .. attempt .. "): " .. tostring(err))
			if isFatal(err) then
				Data.Available = false
				Data.UnavailableReason = tostring(err)
				return "unavailable", nil
			end
		end
		task.wait(wasLocked and 6 or math.min(2 ^ attempt, 10))
	end
	return "error", nil
end

-- Saves a copy of the profile. release = true releases the session lock.
function Data.Save(userId, data, release)
	if not Data.Available then
		return false
	end
	local payload = table.clone(data)
	payload.Session = (not release) and { Job = JOB_ID, Time = os.time() } or nil
	for attempt = 1, 4 do
		local blocked = false
		local ok, err = pcall(function()
			store:UpdateAsync(key(userId), function(old)
				if lockedByOther(old) then
					blocked = true
					return nil -- another server took the session: don't overwrite
				end
				return payload
			end)
		end)
		if ok then
			if blocked then
				warn("[DeepDive] Save skipped: the session belongs to another server (" .. userId .. ")")
			end
			return not blocked
		end
		warn("[DeepDive] Save error (attempt " .. attempt .. "): " .. tostring(err))
		if isFatal(err) then
			return false
		end
		task.wait(math.min(2 ^ attempt, 8))
	end
	return false
end

return Data
