local humanoid = script.Parent:WaitForChild("Humanoid")
local anim = humanoid:LoadAnimation(script:FindFirstChild("danceanim"))
anim.Looped = true
anim:Play()