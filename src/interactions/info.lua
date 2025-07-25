local json = require "json"

local mod = {}

-- Action: "Info"
---@type HandlerFunction
function mod.info(msg)
  msg.reply({
    Name = "LiquidOps Controller",
    Module = Module,
    Oracle = Oracle,
    ["Max-Discount"] = tostring(MaxDiscount),
    ["Min-Discount"] = tostring(MinDiscount),
    ["Discount-Interval"] = tostring(DiscountInterval),
    Data = json.encode(Tokens)
  })
end

-- Action: "Get-Tokens"
---@type HandlerFunction
function mod.tokens(msg)
  msg.reply({
    Data = json.encode(Tokens)
  })
end

-- Action: "Get-Oracle"
---@type HandlerFunction
function mod.oracle(msg)
	msg.reply({ Oracle = Oracle })
end

-- Action: "Get-Queue"
---@type HandlerFunction
function mod.queue(msg)
	msg.reply({
	  Data = json.encode(Queue)
	})
end

return mod
