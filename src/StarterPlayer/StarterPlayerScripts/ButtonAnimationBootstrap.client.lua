local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local gui = playerGui:WaitForChild("GUI")

local ButtonAnimator = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ButtonAnimator"))
ButtonAnimator.BindDescendants(gui, {
    HoverScale = 1.25,
    PressScale = 0.9,
    HoverRotation = -1.5,
    PressRotation = 1.5,
})

local count = 0
for _, descendant in ipairs(gui:GetDescendants()) do
    if descendant:IsA("GuiButton") then count += 1 end
end
gui:SetAttribute("ButtonAnimationBoundCount", count)
print("[ButtonAnimation] bound", count, "GUI buttons")
