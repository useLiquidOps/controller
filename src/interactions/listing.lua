local assertions = require ".utils.assertions"
local tokens = require ".utils.tokens"
local utils = require ".utils"
local json = require "json"

local mod = {}

-- Action: "List"
---@type HandlerFunction
function mod.list(msg)
  -- token to be listed
  local token = msg.Tags.Token

  assert(
    assertions.isAddress(token),
    "Invalid token address"
  )
  assert(
    utils.find(function (t) return t.id == token end, Tokens) == nil,
    "Token already listed"
  )

  -- check configuration
  local liquidationThreshold = tonumber(msg.Tags["Liquidation-Threshold"])
  local collateralFactor = tonumber(msg.Tags["Collateral-Factor"])
  local reserveFactor = tonumber(msg.Tags["Reserve-Factor"])
  local baseRate = tonumber(msg.Tags["Base-Rate"])
  local initRate = tonumber(msg.Tags["Init-Rate"])
  local jumpRate = tonumber(msg.Tags["Jump-Rate"])
  local cooldownPeriod = tonumber(msg.Tags["Cooldown-Period"])
  local kinkParam = tonumber(msg.Tags["Kink-Param"])

  assert(
    collateralFactor ~= nil and type(collateralFactor) == "number",
    "Invalid collateral factor"
  )
  assert(
    collateralFactor // 1 == collateralFactor and collateralFactor >= 0 and collateralFactor <= 100,
    "Collateral factor has to be a whole percentage between 0 and 100"
  )
  assert(
    liquidationThreshold ~= nil and type(liquidationThreshold) == "number",
    "Invalid liquidation threshold"
  )
  assert(
    liquidationThreshold // 1 == liquidationThreshold and liquidationThreshold >= 0 and liquidationThreshold <= 100,
    "Liquidation threshold has to be a whole percentage between 0 and 100"
  )
  assert(
    liquidationThreshold > collateralFactor,
    "Liquidation threshold must be greater than the collateral factor"
  )
  assert(
    reserveFactor ~= nil and type(reserveFactor) == "number",
    "Invalid reserve factor"
  )
  assert(
    reserveFactor // 1 == reserveFactor and reserveFactor >= 0 and reserveFactor <= 100,
    "Reserve factor has to be a whole percentage between 0 and 100"
  )
  assert(
    baseRate ~= nil and assertions.isValidNumber(baseRate),
    "Invalid base rate"
  )
  assert(
    initRate ~= nil and assertions.isValidNumber(initRate),
    "Invalid init rate"
  )
  assert(
    jumpRate ~= nil and assertions.isValidNumber(jumpRate),
    "Invalid jump rate"
  )
  assert(
    assertions.isTokenQuantity(msg.Tags["Value-Limit"]),
    "Invalid value limit"
  )
  assert(
    cooldownPeriod ~= nil and assertions.isValidInteger(cooldownPeriod),
    "Invalid cooldown period"
  )
  assert(
    kinkParam ~= nil and type(kinkParam) == "number",
    "Invalid kink parameter"
  )
  assert(
    kinkParam // 1 == kinkParam and kinkParam >= 0 and kinkParam <= 100,
    "Kink parameter has to be a whole percentage between 0 and 100"
  )

  -- check if token is supported
  local supported, info = tokens.isSupported(token)

  assert(supported, "Token not supported by the protocol")

  -- spawn logo
  local logo = msg.Tags.Logo or info.Tags.Logo

  -- the oToken configuration
  local config = {
    Name = "LiquidOps " .. tostring(info.Tags.Name or info.Tags.Ticker or ""),
    ["Collateral-Id"] = token,
    ["Collateral-Ticker"] = info.Tags.Ticker,
    ["Collateral-Name"] = info.Tags.Name,
    ["Collateral-Denomination"] = info.Tags.Denomination,
    ["Collateral-Factor"] = msg.Tags["Collateral-Factor"],
    ["Liquidation-Threshold"] = tostring(liquidationThreshold),
    ["Reserve-Factor"] = tostring(reserveFactor),
    ["Base-Rate"] = msg.Tags["Base-Rate"],
    ["Init-Rate"] = msg.Tags["Init-Rate"],
    ["Jump-Rate"] = msg.Tags["Jump-Rate"],
    ["Kink-Param"] = msg.Tags["Kink-Param"],
    ["Value-Limit"] = msg.Tags["Value-Limit"],
    ["Cooldown-Period"] = msg.Tags["Cooldown-Period"],
    Oracle = Oracle,
    ["Oracle-Delay-Tolerance"] = tostring(MaxOracleDelay),
    Logo = logo,
    Authority = ao.authorities[1],
    Friends = json.encode(Tokens)
  }

  -- spawn new oToken process
  local spawnResult = ao.spawn(Module, config).receive()
  local spawnedID = spawnResult.Tags.Process

  -- notify all other tokens
  for _, t in ipairs(Tokens) do
    if t.oToken ~= spawnedID then
      ao.send({
        Target = t.oToken,
        Action = "Add-Friend",
        Friend = spawnedID,
        Token = token,
        Ticker = info.Tags.Ticker,
        Denomination = info.Tags.Denomination
      })
    end
  end

  -- add token to tokens list
  table.insert(Tokens, {
    id = token,
    ticker = info.Tags.Ticker,
    oToken = spawnedID,
    denomination = tonumber(info.Tags.Denomination) or 0
  })

  msg.reply({
    Action = "Token-Listed",
    Token = token,
    ["Spawned-Id"] = spawnedID,
    Data = json.encode(config)
  })
end

-- Action: "Unlist"
---@type HandlerFunction
function mod.unlist(msg)
  -- token to be removed
  local token = msg.Tags.Token

  assert(
    assertions.isAddress(token),
    "Invalid token address"
  )

  -- find token index
  ---@type integer|nil
  local idx = utils.find(
    function (t) return t.id == token end,
    Tokens
  )

  assert(type(idx) == "number", "Token is not listed")

  -- id of the oToken for this token
  local oToken = Tokens[idx].oToken

  -- unlist
  table.remove(Tokens, idx)

  -- notify all other oTokens
  for _, t in ipairs(Tokens) do
    ao.send({
      Target = t.oToken,
      Action = "Remove-Friend",
      Friend = oToken
    })
  end

  msg.reply({
    Action = "Token-Unlisted",
    Token = token,
    ["Removed-Id"] = oToken
  })
end

return mod
