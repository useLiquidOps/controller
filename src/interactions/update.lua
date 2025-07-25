local scheduler = require ".utils.scheduler"
local tokens = require ".utils.tokens"
local utils = require ".utils"
local json = require "json"

local mod = {}

-- Action: "Batch-Update"
---@type HandlerFunction
function mod.batchUpdate(msg)
  -- check if update is already in progress
  assert(not UpdateInProgress, "An update is already in progress")

  -- allow skipping oTokens
  local skip = msg.Tags.Skip and json.decode(msg.Tags.Skip)

  -- generate update msgs
  ---@type MessageParam[]
  local updateMsgs = {}

  for _, t in ipairs(Tokens) do
    if not skip or utils.includes(t.oToken, skip) then
      table.insert(updateMsgs, {
        Target = t.oToken,
        Action = "Update",
        Data = msg.Data
      })
    end
  end

  -- set updating in progress. this will halt interactions
  -- by making the queue check always return true for any
  -- address
  UpdateInProgress = true

  -- request updates
  ---@type Message[]
  local updates = scheduler.schedule(table.unpack(updateMsgs))

  UpdateInProgress = false

  -- filter failed updates
  local failed = utils.filter(
    ---@param res Message
    function (res) return res.Tags.Error ~= nil or res.Tags.Updated ~= "true" end,
    updates
  )

  -- reply with results
  msg.reply({
    Updated = tostring(#Tokens - #failed),
    Failed = tostring(#failed),
    Data = json.encode(utils.map(
      ---@param res Message
      function (res) return res.From end,
      failed
    ))
  })
end

-- Action: "Solo-Update"
---@type HandlerFunction
function mod.soloUpdate(msg)
  -- check if update is already in progress
  assert(not UpdateInProgress, "An update is already in progress")

  -- check update recipient
  local recipient = msg.Tags.Recipient

  assert(tokens.isListed(recipient), "The provided recipient is not listed")

  UpdateInProgress = true

  -- send update
  local res = ao.send({
    Target = recipient,
    Action = "Update",
    Data = msg.Data
  }).receive()

  UpdateInProgress = false

  -- reply
  msg.reply({ Updated = res.Tags.Updated })
end

return mod
