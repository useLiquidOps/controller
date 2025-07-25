local mod = {}

-- Action: "Credit-Notice"
-- Refunds token transfers with an invalid action
---@type HandlerFunction
function mod.refundInvalidToken(msg)
  ao.send({
    Target = msg.From,
    Action = "Transfer",
    Quantity = msg.Tags.Quantity,
    Recipient = msg.Tags.Sender,
    ["X-Action"] = "Refund",
    ["X-Refund-Reason"] = "This process does not accept the transferred token " .. msg.From
  })
end

-- Sync current timestamp and block
---@type HandlerFunction
function mod.sync(msg)
  Timestamp = msg.Timestamp
  Block = msg["Block-Height"]
end

return mod
