local utils = require ".utils"

local mod = {}

-- Add a user to the queue list
---@param addr string User address
---@param origin string Queue request origin
function mod.add(addr, origin)
  table.insert(Queue, {
    address = addr,
    origin = origin
  })
end

-- Remove a user from the queue list, if the origin matches
---@param addr string User address
---@param origin string Queue request origin
---@return "removed"|"not_queued"|"invalid_origin"
function mod.remove(addr, origin)
  -- find entry to remove
  local idx = nil

  for i, entry in ipairs(Queue) do
    if entry.address == addr then
      -- different origin
      if entry.origin ~= origin then
        return "invalid_origin"
      end

      idx = i
    end
  end

  -- the address was not found in the queue
  if not idx then
    return "not_queued"
  end

  -- remove from queue table
  table.remove(Queue, idx)

  return "removed"
end

-- Check if an address is queued
---@param addr string User address
---@param origin string? Optional origin to verify against
function mod.isQueued(addr, origin)
  return utils.find(
    function (u)
      if origin ~= nil and u.origin ~= origin then
        return false
      end

      return u.address == addr
    end,
    Queue
  ) ~= nil
end

return mod
