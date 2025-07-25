local coroutine = require "coroutine"
local utils = require ".utils"
local json = require "json"

local mod = {}

function mod.schedule(...)
  -- get the running handler's thread
  local thread = coroutine.running()

  -- repsonse handler
  local responses = {}
  local messages = {...}

  -- if there are no messages to be sent, we don't do anything
  if #messages == 0 then return {} end

  ---@type HandlerFunction
  local function responseHandler(msg)
    table.insert(responses, msg)

    -- continue execution when all responses are back
    if #responses == #messages then
      -- if the result of the resumed coroutine is an error, then we should bubble it up to the process
      local _, success, errmsg = coroutine.resume(thread, responses)

      assert(success, errmsg)
    end
  end

  -- send messages
  for _, msg in ipairs(messages) do
    ao.send(msg)

    -- wait for response
    Handlers.once(
      { From = msg.Target, ["X-Reference"] = tostring(ao.reference) },
      responseHandler
    )
  end

  -- yield execution, till all responses are back
  return coroutine.yield({ From = messages[#messages], ["X-Reference"] = tostring(ao.reference) })
end

-- Get price data for an array of token symbols
function oracle.sync()
  ---@type RawPrices
  local res = {}

  -- all collateral tickers
  local symbols = utils.map(
    ---@param f Friend
    function (f) return f.ticker end,
    Tokens
  )

  -- no tokens to sync
  if #symbols == 0 then return res end

  ---@type string|nil
  local rawData = ao.send({
    Target =  Oracle,
    Action = "v2.Request-Latest-Data",
    Tickers = json.encode(symbols)
  }).receive().Data

  -- no price data returned
  if not rawData or rawData == "" then return res end

  ---@type boolean, OracleData
  local parsed, data = pcall(json.decode, rawData)

  assert(parsed, "Could not parse oracle data")

  for ticker, p in pairs(data) do
    -- only add data if the timestamp is up to date
    if p.t + MaxOracleDelay >= Timestamp then
      res[ticker] = {
        price = p.v,
        timestamp = p.t
      }
    end
  end

  return res
end

return mod
