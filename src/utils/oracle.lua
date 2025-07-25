local bint = require ".bint"(1024)
local utils = require ".utils"
local json = require "json"

local mod = {}

-- Get price data for an array of token symbols
function mod.sync()
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

-- Get the value of a single quantity
---@param rawPrices RawPrices Raw price data
---@param quantity Bint Token quantity
---@param ticker string Token ticker
---@param denomination number Token denomination
function mod.getValue(rawPrices, quantity, ticker, denomination)
  local res = mod.getValues(rawPrices, {
    { ticker = ticker, denomination = denomination, quantity = quantity }
  })

  assert(res[1] ~= nil, "No price calculated")

  return res[1].value
end

-- Get the value of quantities of the provided assets. The function
-- will only provide up to date values, outdated and nil values will be
-- filtered out
---@param rawPrices RawPrices Raw results from the oracle
---@param quantities PriceParam[] Token quantities
function mod.getValues(rawPrices, quantities)
  ---@type { ticker: string, value: Bint }[]
  local results = {}

  local one = bint.one()
  local zero = bint.zero()

  for _, v in ipairs(quantities) do
    if not v.quantity then v.quantity = one end
    if not bint.eq(v.quantity, zero) then
      -- make sure the oracle returned the price
      assert(rawPrices[v.ticker] ~= nil, "No price returned from the oracle for " .. v.ticker)

      -- the value of the quantity
      -- (USD price value is denominated for precision,
      -- but the result needs to be divided according
      -- to the underlying asset's denomination,
      -- because the price data is for the non-denominated
      -- unit)
      local value = bint.udiv(
        v.quantity * mod.getUSDDenominated(rawPrices[v.ticker].price),
        -- optimize performance by repeating "0" instead of a power operation
        bint("1" .. string.rep("0", v.denomination))
      )

      -- add data
      table.insert(results, {
        ticker = v.ticker,
        value = value
      })
    else
      table.insert(results, {
        ticker = v.ticker,
        value = zero
      })
    end
  end

  return results
end

-- Get the value of one token quantity in another
-- token quantity
---@param from { ticker: string, quantity: Bint, denomination: number } From token ticker, quantity and denomination
---@param to TokenData Target token ticker and denomination
---@param rawPrices RawPrices Pre-fetched prices
---@return Bint
function mod.getValueInToken(from, to, rawPrices)
  -- prices
  local fromPrice = mod.getUSDDenominated(rawPrices[from.ticker].price)
  local toPrice = mod.getUSDDenominated(rawPrices[to.ticker].price)

  -- get value of the "from" token quantity in USD with extra precision
  local usdValue = bint.udiv(
    from.quantity * fromPrice,
    bint("1" .. string.rep("0", from.denomination))
  )

  -- convert usd value to the token quantity
  -- accounting for the denomination
  return bint.udiv(
    usdValue * bint("1" .. string.rep("0", to.denomination)),
    toPrice
  )
end

-- Get the precision used for USD biginteger values
function mod.getUSDDenomination() return 12 end

-- Get the fractional part's length
---@param val number Full number
function mod.getFractionsCount(val)
  -- check if there is a fractional part
  -- by trying to find it with a pattern
  local fractionalPart = string.match(mod.floatToString(val), "%.(.*)")

  if not fractionalPart then return 0 end

  -- get the length of the fractional part
  return string.len(fractionalPart)
end

-- Get a USD value in a 12 denominated form
---@param val number USD value as a floating point number
---@return Bint
function mod.getUSDDenominated(val)
  local denominator = mod.getUSDDenomination()

  -- remove decimal point
  local denominated = string.gsub(mod.floatToString(val), "%.", "")

  -- get the count of decimal places after the decimal point
  local fractions = mod.getFractionsCount(val)

  local wholeDigits = string.len(denominated) - fractions
  denominated = denominated .. string.rep("0", denominator)
  denominated = string.sub(denominated, 1, wholeDigits + denominator)

  return bint(denominated)
end

-- Convert a lua number to a string
---@param val number The value to convert
function mod.floatToString(val)
  return string.format("%.17f", val):gsub("0+$", ""):gsub("%.$", "")
end

return mod
