local module = {}

local function readNumber(parent, name, default)
    local value = parent and parent:FindFirstChild(name)
    return value and tonumber(value.Value) or default
end

function module:CreateBeam(part1, part2, conf)
    self:DestroyBeam(part1, part2)

    local beamConf = conf and conf:FindFirstChild("Beam")
    local fromAttachment = Instance.new("Attachment")
    fromAttachment.Name = "BeamFrom"
    fromAttachment.Parent = part1

    local toAttachment = Instance.new("Attachment")
    toAttachment.Name = "BeamTo"
    toAttachment.Parent = part2

    local beam = Instance.new("Beam")
    beam.Name = "PromptBeam"
    beam.Attachment0 = fromAttachment
    beam.Attachment1 = toAttachment
    beam.Width0 = readNumber(beamConf, "BeamWidth", 0.05)
    beam.Width1 = beam.Width0
    local colorValue = beamConf and beamConf:FindFirstChild("BeamColor")
    beam.Color = ColorSequence.new(colorValue and colorValue.Value or Color3.fromRGB(255, 255, 255))
    beam.Transparency = NumberSequence.new(readNumber(beamConf, "BeamTransparency", 0.2))
    beam.FaceCamera = true
    beam.Parent = part1
end

function module:DestroyBeam(part1, part2)
    if part1 then
        local beam = part1:FindFirstChild("PromptBeam")
        if beam then beam:Destroy() end
        local fromAttachment = part1:FindFirstChild("BeamFrom")
        if fromAttachment then fromAttachment:Destroy() end
    end
    if part2 then
        local toAttachment = part2:FindFirstChild("BeamTo")
        if toAttachment then toAttachment:Destroy() end
    end
end

function module:CreateHighlight(part1, conf)
    self:DestroyHighlight(part1)
    local highlightConf = conf and conf:FindFirstChild("Highlight")
    local highlight = Instance.new("Highlight")
    highlight.Name = "PromptHighlight"
    highlight.FillTransparency = 1
    local colorValue = highlightConf and highlightConf:FindFirstChild("HighlightColor")
    highlight.OutlineColor = colorValue and colorValue.Value or Color3.fromRGB(255, 255, 255)
    highlight.OutlineTransparency = readNumber(highlightConf, "HighlightTransparency", 0.15)
    highlight.Parent = part1
end

function module:DestroyHighlight(part1)
    local highlight = part1 and part1:FindFirstChild("PromptHighlight")
    if highlight then highlight:Destroy() end
end

return module
