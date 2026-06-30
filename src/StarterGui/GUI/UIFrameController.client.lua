local StarterGui = game:GetService("StarterGui")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local gui = script.Parent
local top = gui:WaitForChild("Top")
local bottom = gui:WaitForChild("Bottom")
local hud = gui:WaitForChild("HUD")
local frames = gui:WaitForChild("Frames")

local openFrameRequest = gui:FindFirstChild("OpenFrameRequest") or Instance.new("BindableEvent")
openFrameRequest.Name = "OpenFrameRequest"
openFrameRequest.Parent = gui
local closeFrameRequest = gui:FindFirstChild("CloseFrameRequest") or Instance.new("BindableEvent")
closeFrameRequest.Name = "CloseFrameRequest"
closeFrameRequest.Parent = gui

local camera = Workspace.CurrentCamera
local DEFAULT_FOV = camera and camera.FieldOfView or 70
local OPEN_FOV = math.max(50, DEFAULT_FOV - 8)
local TWEEN_IN = TweenInfo.new(0.34, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TWEEN_OUT = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
local POP_IN = TweenInfo.new(0.28, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local POP_OUT = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local FOV_TWEEN = TweenInfo.new(0.26, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

local currentFrame=nil
local busy=false
local activeTweens={}
local originals={}

local function clearStartupBlur()
    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect:IsA("BlurEffect") then
            effect.Enabled = false
            effect.Size = 0
        end
    end
end
clearStartupBlur()

local function capture(o) if o and not originals[o] then originals[o]={Position=o.Position,Size=o.Size,Rotation=o.Rotation,Visible=o.Visible} end end
capture(top); capture(bottom); capture(hud)
for _,child in ipairs(frames:GetChildren()) do if child:IsA("GuiObject") then capture(child); child.Visible=false end end
hud.Visible=true

task.spawn(function() for _=1,12 do if pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,false) end) then break end task.wait(.25) end end)

local function cancel(o) local tw=activeTweens[o]; if tw then tw:Cancel() end; activeTweens[o]=nil end
local function tween(o,info,props) if not o then return nil end; cancel(o); local tw=TweenService:Create(o,info,props); activeTweens[o]=tw; tw.Completed:Once(function() if activeTweens[o]==tw then activeTweens[o]=nil end end); tw:Play(); return tw end
local function offLeft(o)local r=originals[o]; return UDim2.new(r.Position.X.Scale-1.15,r.Position.X.Offset,r.Position.Y.Scale,r.Position.Y.Offset) end
local function offRight(o)local r=originals[o]; return UDim2.new(r.Position.X.Scale+1.15,r.Position.X.Offset,r.Position.Y.Scale,r.Position.Y.Offset) end
local function offTop(o)local r=originals[o]; return UDim2.new(r.Position.X.Scale,r.Position.X.Offset,r.Position.Y.Scale-1.1,r.Position.Y.Offset) end
local function offBottom(o)local r=originals[o]; return UDim2.new(r.Position.X.Scale,r.Position.X.Offset,r.Position.Y.Scale+1.1,r.Position.Y.Offset) end
local function smallCentered(f)local r=originals[f]; return {Position=UDim2.fromScale(.5,.5),Size=UDim2.new(r.Size.X.Scale*.55,math.floor(r.Size.X.Offset*.55+.5),r.Size.Y.Scale*.55,math.floor(r.Size.Y.Offset*.55+.5))} end
local function resetHidden(f)local r=originals[f]; f.Visible=false; f.Position=r.Position; f.Size=r.Size; f.Rotation=r.Rotation end
local function restoreChrome() top.Visible=true; bottom.Visible=true; hud.Visible=true; tween(top,TWEEN_IN,{Position=originals[top].Position}); tween(bottom,TWEEN_IN,{Position=originals[bottom].Position}); tween(hud,TWEEN_IN,{Position=originals[hud].Position}) end
local function fov(open) camera=Workspace.CurrentCamera; if camera then tween(camera,FOV_TWEEN,{FieldOfView=open and OPEN_FOV or DEFAULT_FOV}) end end

local hotbarIndicators = {}
for i = 1, 3 do
    local button = bottom:FindFirstChild(tostring(i))
    local indicator = button and button:FindFirstChild("Frame")
    if indicator and indicator:IsA("GuiObject") then
        local scale = indicator:FindFirstChild("ActiveScale") or Instance.new("UIScale")
        scale.Name = "ActiveScale"
        scale.Scale = 0.82
        scale.Parent = indicator
        indicator.Visible = false
        hotbarIndicators[i] = { frame = indicator, scale = scale, active = false, version = 0 }
    end
end

local function setIndicator(index, active)
    local entry = hotbarIndicators[index]
    if not entry or entry.active == active then return end
    entry.active = active
    entry.version += 1
    local version = entry.version
    if active then
        entry.frame.Visible = true
        entry.frame.BackgroundTransparency = 1
        entry.scale.Scale = 0.82
        tween(entry.frame, TweenInfo.new(0.16, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { BackgroundTransparency = 0.5 })
        tween(entry.scale, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
    else
        tween(entry.frame, TweenInfo.new(0.12, Enum.EasingStyle.Sine, Enum.EasingDirection.In), { BackgroundTransparency = 1 })
        local out = tween(entry.scale, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Scale = 0.82 })
        if out then out.Completed:Once(function()
            if entry.version == version and not entry.active then entry.frame.Visible = false end
        end) end
    end
end

local function updateHotbarIndicators()
    local frameName = currentFrame and currentFrame.Name or nil
    local weaponActive = gui:GetAttribute("SwordEquipped") == true or frameName == "Swords" or frameName == "Weapons"
    local buildActive = not weaponActive and (gui:GetAttribute("PlacementActive") == true or frameName == "Build")
    local deleteActive = not weaponActive and not buildActive and gui:GetAttribute("DeleteMode") == true
    local anyActive = weaponActive or buildActive or deleteActive
    setIndicator(1, anyActive and not weaponActive)
    setIndicator(2, anyActive and not buildActive)
    setIndicator(3, anyActive and not deleteActive)
end
local function normalizeFrameName(frameName)
    if frameName == "Swords" and frames:FindFirstChild("Weapons") then return "Weapons" end
    return frameName
end
local function isSideFrame(frameName)
    return frameName == "Build" or frameName == "Weapons" or frameName == "Swords" or frameName == "Base"
end
local function slideChrome(frameName)
 frameName = normalizeFrameName(frameName)
 local side=isSideFrame(frameName)
 tween(hud,TWEEN_IN,{Position=offLeft(hud)})
 if side then tween(top,TWEEN_IN,{Position=originals[top].Position}); tween(bottom,TWEEN_IN,{Position=originals[bottom].Position}) else tween(top,TWEEN_IN,{Position=offTop(top)}); tween(bottom,TWEEN_IN,{Position=offBottom(bottom)}) end
end

local closeCurrentFrame
local function isRaidLocked(frameName)
    return gui:GetAttribute("RaidActive") == true
end
local function openFrame(frameName)
 if gui:GetAttribute("ChestModalActive") == true then return end
 frameName = normalizeFrameName(frameName)
 if isRaidLocked(frameName) then return end
 local frame=frames:FindFirstChild(frameName)
 if not frame or not frame:IsA("GuiObject") or busy then return end
 if currentFrame==frame then closeCurrentFrame(); return end
 busy=true
 if currentFrame then closeCurrentFrame(true) end
 currentFrame=frame
 local r=originals[frame]
 local side=isSideFrame(frameName)
 frame.Visible=true; frame.Rotation=r.Rotation
 if side then frame.Position=frameName=="Base" and offRight(frame) or offLeft(frame); frame.Size=r.Size; tween(frame,TWEEN_IN,{Position=r.Position}) else local s=smallCentered(frame); frame.Position=s.Position; frame.Size=s.Size; tween(frame,POP_IN,{Position=r.Position,Size=r.Size}) end
 slideChrome(frameName); fov(true); updateHotbarIndicators(); task.delay(.12,function() busy=false end)
end
function closeCurrentFrame(skipChrome)
 local frame=currentFrame
 if not frame then if not skipChrome then restoreChrome(); fov(false) end; return end
 currentFrame=nil
 local name=frame.Name
 local side=isSideFrame(name)
 local tw
 if side then tw=tween(frame,TWEEN_OUT,{Position=name=="Base" and offRight(frame) or offLeft(frame)}) else local s=smallCentered(frame); tw=tween(frame,POP_OUT,{Position=s.Position,Size=s.Size}) end
 if tw then tw.Completed:Once(function() resetHidden(frame) end) else resetHidden(frame) end
 if not skipChrome then restoreChrome(); fov(false) end
 updateHotbarIndicators()
end
local function bind(button,frameName) if not button or not button:IsA("GuiButton") then return end; button.Activated:Connect(function() openFrame(frameName) end) end
local weaponButton = bottom:FindFirstChild("1")
local buildButton = bottom:FindFirstChild("2")
local deleteButton = bottom:FindFirstChild("3")
bind(hud:FindFirstChild("Weapons") or hud:FindFirstChild("Swords"),frames:FindFirstChild("Weapons") and "Weapons" or "Swords"); bind(hud:FindFirstChild("Settings"),"Settings"); bind(hud:FindFirstChild("Shop"),"Shop"); bind(hud:FindFirstChild("Codes"),"Codes"); bind(hud:FindFirstChild("Maps"),"Maps")
for _,frame in ipairs(frames:GetChildren()) do if frame:IsA("GuiObject") then local close=frame:FindFirstChild("Close"); if close and close:IsA("GuiButton") then close.Activated:Connect(function() if currentFrame==frame then closeCurrentFrame() else frame.Visible=false; restoreChrome(); fov(false) end end) end end end
openFrameRequest.Event:Connect(function(frameName) if typeof(frameName)=="string" then openFrame(frameName) end end)
closeFrameRequest.Event:Connect(function() closeCurrentFrame(false) end)

local function characterHasSword()
    local character = game:GetService("Players").LocalPlayer.Character
    if not character then return false end
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") and child:GetAttribute("IsSword") then return true end
    end
    return false
end

local function syncSwordEquipped()
    gui:SetAttribute("SwordEquipped", characterHasSword())
end

local function hookCharacter(character)
    character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") and child:GetAttribute("IsSword") then task.defer(syncSwordEquipped) end
    end)
    character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") and child:GetAttribute("IsSword") then task.defer(syncSwordEquipped) end
    end)
    task.defer(syncSwordEquipped)
end

local localPlayer = game:GetService("Players").LocalPlayer
if localPlayer.Character then hookCharacter(localPlayer.Character) end
localPlayer.CharacterAdded:Connect(hookCharacter)

gui:GetAttributeChangedSignal("RaidActive"):Connect(function()
    if gui:GetAttribute("RaidActive") == true then
        closeCurrentFrame(false)
        gui:SetAttribute("DeleteMode", false)
    else
        task.defer(syncSwordEquipped)
    end
end)
local equipRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EquipSword")
gui:SetAttribute("SwordEquipped", false)

-- fire-and-forget so UI responds instantly; tool gets removed ~1 RTT later
local function unequipSword()
	local ok, success = pcall(function() return equipRemote:InvokeServer(nil) end)
	gui:SetAttribute("SwordEquipped", false)
	return ok and success == true
end

local function activateWeaponMode()
	if gui:GetAttribute("ChestModalActive") == true then return end
	gui:SetAttribute("DeleteMode", false)
	if characterHasSword() or gui:GetAttribute("SwordEquipped") == true then
		unequipSword()
	elseif gui:GetAttribute("RaidActive") == true then
		local lastSword = gui:GetAttribute("LastEquippedSword") or "WoodenSword"
		local ok = equipRemote:InvokeServer(lastSword)
		if ok then gui:SetAttribute("SwordEquipped", true) end
	else
		openFrame(frames:FindFirstChild("Weapons") and "Weapons" or "Swords")
	end
end

local function activateBuildMode()
	if gui:GetAttribute("RaidActive") == true or gui:GetAttribute("ChestModalActive") == true then return end
	gui:SetAttribute("DeleteMode", false)
	if characterHasSword() or gui:GetAttribute("SwordEquipped") == true then unequipSword() end
	openFrame("Build")
end

local function activateDeleteMode(ignorePlacement)
	if gui:GetAttribute("RaidActive") == true or gui:GetAttribute("ChestModalActive") == true then return end
	if not ignorePlacement and gui:GetAttribute("PlacementActive") == true then return end
	if characterHasSword() or gui:GetAttribute("SwordEquipped") == true then unequipSword() end
	local enabling = gui:GetAttribute("DeleteMode") ~= true
	closeCurrentFrame(false)
	gui:SetAttribute("DeleteMode", enabling)
	updateHotbarIndicators()
end

if weaponButton and weaponButton:IsA("GuiButton") then weaponButton.Activated:Connect(activateWeaponMode) end
if buildButton and buildButton:IsA("GuiButton") then buildButton.Activated:Connect(activateBuildMode) end
if deleteButton and deleteButton:IsA("GuiButton") then deleteButton.Activated:Connect(function() activateDeleteMode(true) end) end

gui:GetAttributeChangedSignal("SwordEquipped"):Connect(updateHotbarIndicators)
gui:GetAttributeChangedSignal("PlacementActive"):Connect(updateHotbarIndicators)
gui:GetAttributeChangedSignal("DeleteMode"):Connect(updateHotbarIndicators)
updateHotbarIndicators()

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if UserInputService:GetFocusedTextBox() then return end
	if gameProcessed then
		local activeMode = characterHasSword()
			or gui:GetAttribute("SwordEquipped") == true
			or gui:GetAttribute("PlacementActive") == true
			or gui:GetAttribute("DeleteMode") == true
		if not activeMode then return end
	end
	if input.KeyCode == Enum.KeyCode.Q then
		activateWeaponMode()
	elseif input.KeyCode == Enum.KeyCode.E then
		activateBuildMode()
	elseif input.KeyCode == Enum.KeyCode.R then
		activateDeleteMode(false)
	end
end)
