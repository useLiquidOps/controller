local assertions = require ".utils.assertions"
local queue = require ".utils.queue"
local utils = require ".utils"
local json = require "json"

local mod = {}

-- A wrapper for patterns to validate if the message is coming
-- from an oToken or not
function mod.fromoToken(pattern)
  return function (msg)
    local match = utils.matchesSpec(msg, pattern)

    if not match or match == 0 or match == "skip" then
      return match
    end

    return utils.find(
      function (t) return t.oToken == msg.From end,
      Tokens
    ) ~= nil
  end
end

-- Action: "Add-To-Queue"
---@type HandlerFunction
function mod.add(msg)
  local user = msg.Tags.User

  -- validate address
  if not assertions.isAddress(user) then
    return msg.reply({ Error = "Invalid user address" })
  end

  -- check if the user has already been added
  if queue.isQueued(user) or UpdateInProgress then
    return msg.reply({ Error = "User already queued" })
  end

  -- add to queue
  queue.add(user, msg.From)

  msg.reply({ ["Queued-User"] = user })
end

-- Action: "Remove-From-Queue"
---@type HandlerFunction
function mod.remove(msg)
  local user = msg.Tags.User

  -- validate address
  if not assertions.isAddress(user) then
    return msg.reply({ Error = "Invalid user address" })
  end

  -- try to remove the user from the queue
  local res = queue.remove(user, msg.From)

  if res ~= "removed" then
    return msg.reply({
      Error = res == "not_queued" and
        "The user is not queued" or
        "The user was queued from another origin"
    })
  end

  -- reply with confirmation
  msg.reply({ ["Unqueued-User"] = user })
end

-- Action: "Check-Queue-For"
---@type HandlerFunction
function mod.check(msg)
  local user = msg.Tags.User

  -- validate address
  if not assertions.isAddress(user) then
    return msg.reply({ ["In-Queue"] = "false" })
  end

  -- the user is queued if they're either in the collateral
  -- or the liquidation queues
  return msg.reply({
    ["In-Queue"] = json.encode(queue.isQueued(user) or UpdateInProgress)
  })
end

return mod
