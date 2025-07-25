local bint = require ".bint"(1024)
local utils = require ".utils"

local mod = {}

-- Verify if the caller of an admin function is
-- authorized to run this action
---@param action string Accepted action
---@return PatternFunction
function mod.isAdminAction(action)
  ---@param msg Message
  return function (msg)
    if msg.From ~= ao.env.Process.Id and not utils.includes(msg.From, Owners) then
      return false
    end

    return msg.Tags.Action == action
  end
end

-- Verify if the provided value is an address
---@param addr any Address to verify
---@return boolean
function mod.isAddress(addr)
  if type(addr) ~= "string" then return false end
  if string.len(addr) ~= 43 then return false end
  if string.match(addr, "^[A-z0-9_-]+$") == nil then return false end

  return true
end

-- Checks if an input is not inf or nan
---@param val number Input to check
function mod.isValidNumber(val)
  return type(val) == "number" and
    val == val and
    val ~= math.huge and
    val ~= -math.huge
end

-- Checks if an input is not inf or nan and is an integer
---@param val number Input to check
function mod.isValidInteger(val)
  return mod.isValidNumber(val) and val % 1 == 0
end

-- Validates if the provided value can be parsed as a Bint
---@param val any Value to validate
---@return boolean
function mod.isBintRaw(val)
  local success, result = pcall(
    function ()
      -- check if the value is convertible to a Bint
      if type(val) ~= "number" and type(val) ~= "string" and not bint.isbint(val) then
        return false
      end

      -- check if the val is an integer and not infinity, in case if the type is number
      if type(val) == "number" and not mod.isValidInteger(val) then
        return false
      end

      return true
    end
  )

  return success and result
end

-- Verify if the provided value can be converted to a valid token quantity
---@param qty any Raw quantity to verify
---@return boolean
function mod.isTokenQuantity(qty)
  local numVal = tonumber(qty)
  if not numVal or numVal <= 0 then return false end
  if not mod.isBintRaw(qty) then return false end
  if type(qty) == "number" and qty < 0 then return false end
  if type(qty) == "string" and string.sub(qty, 1, 1) == "-" then
    return false
  end

  return true
end

return mod
