local GroupService = game:GetService("GroupService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local function ownerGroupId()
    if game.CreatorType == Enum.CreatorType.Group then
        return game.CreatorId
    end
    return nil
end

ProximityPromptService.PromptTriggered:Connect(function(prompt)
    local attachment = prompt.Parent
    local part = attachment and attachment.Parent
    local folder = part and part.Parent
    if folder and folder.Name == "Group" then
        local groupId = ownerGroupId()
        if groupId then
            pcall(function()
                GroupService:PromptJoinAsync(groupId)
            end)
        end
    end
end)
