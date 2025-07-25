local utils = require ".utils"

local mod = {}

-- Check if a provided address is an oToken address
-- (an oToken is part of the Tokens table)
---@param addr string oToken address to check
function mod.isoToken(addr)
  return utils.find(
    function (t) return t.oToken == addr end,
    Tokens
  ) ~= nil
end

-- Check if a provided address is a listed token
---@param addr string Token address to check
function mod.isListedToken(addr)
  return utils.find(
    function (t) return t.id == addr end,
    Tokens
  ) ~= nil
end

-- Check if token is supported by the protocol
-- (token supports aos 2.0 replies and replies with a proper info response)
-- Returns if the token is supported and the token info
---@param addr string Token address
function mod.isSupported(addr)
  -- send info request
  ao.send({
    Target = addr,
    Action = "Info",
  })

  -- wait for proper response
  local res = Handlers.receive({
    From = addr,
    Ticker = "^.+$",
    Name = "^.+$",
    Denomination = "^.+$"
  })

  local repliesSupported = res.Tags["X-Reference"] ~= nil

  local denomination = tonumber(res.Tags.Denomination)
  local validDenomination = denomination ~= nil and
    denomination == denomination // 1 and
    denomination > 0 and
    denomination <= 18

  return repliesSupported and validDenomination, res
end

return mod
