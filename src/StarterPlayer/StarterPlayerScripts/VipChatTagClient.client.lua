-- Gold [VIP] chat tag for VIP owners. GamePassService keeps the replicated
-- "VIP" player attribute current for both the bought gamepass and gifted VIP
-- (GiftPass_VIP entitlement), so reading the attribute covers every path.
local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local VIP_TAG = "<font color='#FFD700'>[VIP]</font> "

TextChatService.OnIncomingMessage = function(message)
	local source = message.TextSource
	if not source then return end
	local sender = Players:GetPlayerByUserId(source.UserId)
	if sender and sender:GetAttribute("VIP") == true then
		local properties = Instance.new("TextChatMessageProperties")
		properties.PrefixText = VIP_TAG .. message.PrefixText
		return properties
	end
end