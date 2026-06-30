--[[
    MusicServer (Script — ServerScriptService)
    Syncs background music so all players hear the same track at the same time.

    Server owns track selection. When a track ends (any client reports it),
    server picks the next one and broadcasts to everyone with a start timestamp
    using workspace:GetServerTimeNow(), which is synchronized between server
    and client. Late joiners receive the current track + its start time so
    they can seek to the right position.
]]

local Players       = game:GetService("Players")
local SoundService  = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:WaitForChild("Remotes")
local MusicSync = Instance.new("RemoteEvent")
MusicSync.Name   = "MusicSync"
MusicSync.Parent = RemoteEvents

local bgMusic = SoundService:WaitForChild("BackgroundMusic")

local function getTracks()
	local t = {}
	for _, s in ipairs(bgMusic:GetChildren()) do
		if s:IsA("Sound") then table.insert(t, s) end
	end
	return t
end

local function shuffle(t)
	for i = #t, 2, -1 do
		local j = math.random(i)
		t[i], t[j] = t[j], t[i]
	end
end

local tracks = getTracks()
if #tracks == 0 then
	warn("[MusicServer] No sounds in SoundService.BackgroundMusic — music sync disabled")
	return
end
shuffle(tracks)

local currentIndex     = 1
local currentSoundId   = ""
local currentStartTime = 0
local changePending    = false

local function broadcastTrack()
	local track = tracks[currentIndex]
	currentSoundId   = track.SoundId
	currentStartTime = workspace:GetServerTimeNow()
	MusicSync:FireAllClients("play", currentSoundId, currentStartTime)
end

local function nextTrack()
	if changePending then return end
	changePending = true
	task.delay(2, function()  -- small debounce so rapid "ended" fires don't double-skip
		changePending = false
		currentIndex  = (currentIndex % #tracks) + 1
		if currentIndex == 1 then shuffle(tracks) end
		broadcastTrack()
	end)
end

-- start after a few seconds so everything else finishes loading
task.delay(5, function()
	broadcastTrack()
end)

-- any client reporting "ended" triggers the next track for everyone
MusicSync.OnServerEvent:Connect(function(player, action)
	if action == "ended" then
		nextTrack()
	end
end)

-- send current state to players joining mid-track
Players.PlayerAdded:Connect(function(player)
	task.wait(4)
	if player.Parent and currentSoundId ~= "" then
		MusicSync:FireClient(player, "play", currentSoundId, currentStartTime)
	end
end)