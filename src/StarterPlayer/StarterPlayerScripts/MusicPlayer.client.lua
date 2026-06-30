--[[
	MusicPlayer (LocalScript — StarterPlayerScripts)
	SYNC: Now follows MusicServer's track selection instead of picking randomly.
	      All clients hear the same track starting at the same position, using
	      workspace:GetServerTimeNow() for clock sync between server and client.
	      When a client's track ends, it fires "ended" so the server can advance.
	FIX: fadeIn checks musicEnabled before tweening volume up so the settings
	     toggle actually works and isn't overridden on every track start.
]]

local SoundService      = game:GetService("SoundService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteEvents = ReplicatedStorage:WaitForChild("Remotes")
local MusicSync    = RemoteEvents:WaitForChild("MusicSync", 30)

local bgMusic = SoundService:WaitForChild("BackgroundMusic")

local FADE_IN_TIME = 1.5
local DEFAULT_VOL  = 0.5

local musicEnabled     = true
local currentTrack     = nil
local currentFadeTween = nil
local endedConn        = nil

local function cancelFade()
	if currentFadeTween then
		currentFadeTween:Cancel()
		currentFadeTween = nil
	end
end

local function stopAll()
	cancelFade()
	if endedConn then endedConn:Disconnect(); endedConn = nil end
	for _, s in ipairs(bgMusic:GetChildren()) do
		if s:IsA("Sound") and s.IsPlaying then s:Stop() end
	end
end

local function fadeIn(sound)
	cancelFade()
	if not musicEnabled then
		sound.Volume = 0
		return
	end
	sound.Volume  = 0
	currentFadeTween = TweenService:Create(sound, TweenInfo.new(FADE_IN_TIME), { Volume = DEFAULT_VOL })
	currentFadeTween:Play()
end

local MusicPlayer = {}

function MusicPlayer.setEnabled(on)
	musicEnabled = on
	if not on then
		cancelFade()
		for _, s in ipairs(bgMusic:GetChildren()) do
			if s:IsA("Sound") then s.Volume = 0 end
		end
	else
		if currentTrack and currentTrack.IsPlaying then
			fadeIn(currentTrack)
		end
	end
end

_G.MusicPlayer = MusicPlayer

local function playTrack(soundId, startTime)
	stopAll()

	local track = nil
	for _, s in ipairs(bgMusic:GetChildren()) do
		if s:IsA("Sound") and s.SoundId == soundId then
			track = s; break
		end
	end

	if not track then
		warn("[MusicPlayer] Track not found for id:", soundId)
		return
	end

	currentTrack  = track
	track.Looped  = false
	track:Play()
	fadeIn(track)

	-- Seek to the correct position for players who joined mid-track
	local offset = workspace:GetServerTimeNow() - startTime
	if offset > 1 and offset < 240 then
		task.delay(0.3, function()
			if track and track.IsPlaying then
				pcall(function() track.TimePosition = offset end)
			end
		end)
	end

	-- Tell server when this track finishes so it can pick the next one
	if endedConn then endedConn:Disconnect() end
	endedConn = track.Ended:Once(function()
		currentTrack = nil
		if MusicSync then
			pcall(function() MusicSync:FireServer("ended") end)
		end
	end)
end

if MusicSync then
	MusicSync.OnClientEvent:Connect(function(action, soundId, startTime)
		if action == "play" then
			playTrack(soundId, startTime)
		end
	end)

end