local liquidations = require ".utils.liquidations"
local assertions = require ".utils.assertions"
local scheduler = require ".utils.scheduler"
local tokens = require ".utils.tokens"
local oracle = require ".utils.oracle"
local queue = require ".utils.queue"
local bint = require ".bint"(1024)
local utils = require ".utils"
local json = require "json"

local mod = {}

-- Action: "Get-Auctions"
---@type HandlerFunction
function mod.list(msg)
  msg.reply({
    ["Initial-Discount"] = tostring(MaxDiscount),
    ["Final-Discount"] = tostring(MinDiscount),
    ["Discount-Interval"] = tostring(DiscountInterval),
    Data = next(Auctions) ~= nil and json.encode(Auctions) or "{}"
  })
end

-- X-Action: "Liquidate", Action: "Credit-Notice"
---@type HandlerFunction
function mod.liquidate(msg)
  -- liquidation target
  local target = msg.Tags["X-Target"]

  -- liquidator address
  local liquidator = msg.Tags.Sender

  -- token to be liquidated, currently lent to the target
  -- (the token that is paying for the loan = transferred token)
  local liquidatedToken = msg.From

  -- the token that the liquidator will earn for
  -- paying off the loan
  -- the user has to have a position in this token
  local rewardToken = msg.Tags["X-Reward-Token"]

  -- prepare liquidation, check required environment
  local success, errorMsg, expectedRewardQty, oTokensParticipating, removeWhenDone = pcall(function ()
    assert(
      assertions.isAddress(target) and target ~= liquidator,
      "Invalid liquidation target"
    )
    assert(
      assertions.isAddress(liquidator),
      "Invalid liquidator address"
    )
    assert(
      assertions.isAddress(rewardToken),
      "Invalid reward token address"
    )
    assert(
      assertions.isTokenQuantity(msg.Tags.Quantity),
      "Invalid transfer quantity"
    )
    assert(
      assertions.isTokenQuantity(msg.Tags["X-Min-Expected-Quantity"]),
      "Invalid minimum expected quantity"
    )

    -- try to find the liquidated token, the reward token and
    -- generate the position messages in one loop for efficiency
    ---@type { liquidated: string; reward: string; }
    local oTokensParticipating = {}

    ---@type MessageParam[]
    local positionMsgs = {}

    for _, t in ipairs(Tokens) do
      if t.id == liquidatedToken then oTokensParticipating.liquidated = t.oToken end
      if t.id == rewardToken then oTokensParticipating.reward = t.oToken end

      table.insert(positionMsgs, {
        Target = t.oToken,
        Action = "Position",
        Recipient = target
      })
    end

    assert(
      oTokensParticipating.liquidated ~= nil,
      "Cannot liquidate the incoming token as it is not listed"
    )
    assert(
      oTokensParticipating.reward ~= nil,
      "Cannot liquidate for the reward token as it is not listed"
    )

    -- fetch prices first so the user positions won't be outdated
    local prices = oracle.sync()

    -- check user position
    ---@type Message[]
    local positions = scheduler.schedule(table.unpack(positionMsgs))

    -- check queue
    assert(
      not queue.isQueued(target),
      "User is queued for an operation"
    )

    -- get tokens that need a price fetch
    local zero = bint.zero()

    ---@type PriceParam[], PriceParam[]
    local liquidationLimits, borrowBalances = {}, {}

    -- symbols to sync
    ---@type string[]
    local symbols = {}

    -- incoming and outgoing token data
    ---@type TokenData, TokenData
    local inTokenData, outTokenData = {}, {}

    -- the total collateral of the desired reward token
    -- in the user's position for the reward token
    local availableRewardQty = zero

    -- the total borrow of the liquidated token in the
    -- user's position
    local availableLiquidateQty = zero

    -- check if the user has any open positions (active loans)
    local hasOpenPosition = false

    -- populate capacities, symbols, incoming/outgoing token data and collateral qty
    for _, pos in ipairs(positions) do
      local symbol = pos.Tags["Collateral-Ticker"]
      local denomination = tonumber(pos.Tags["Collateral-Denomination"]) or 0

      -- convert quantities
      local liquidationLimit = bint(pos.Tags["Liquidation-Limit"] or 0)
      local borrowBalance = bint(pos.Tags["Borrow-Balance"] or 0)

      if pos.From == oTokensParticipating.liquidated then
        inTokenData = { ticker = symbol, denomination = denomination }
        availableLiquidateQty = borrowBalance
      end

      if pos.From == oTokensParticipating.reward then
        outTokenData = { ticker = symbol, denomination = denomination }
        availableRewardQty = bint(pos.Tags.Collateralization or 0)
      end

      -- only sync if there is a position
      if bint.ult(zero, borrowBalance) or bint.ult(zero, liquidationLimit) then
        table.insert(symbols, symbol)
        table.insert(borrowBalances, {
          ticker = symbol,
          quantity = borrowBalance,
          denomination = denomination
        })
        table.insert(liquidationLimits, {
          ticker = symbol,
          quantity = liquidationLimit,
          denomination = denomination
        })
      end

      -- update user position indicator
      if bint.ult(zero, borrowBalance) then
        hasOpenPosition = true
      end
    end

    assert(
      inTokenData.ticker ~= nil and inTokenData.denomination ~= nil,
      "Incoming token data not found"
    )
    assert(
      outTokenData.ticker ~= nil and outTokenData.denomination ~= nil,
      "Outgoing token data not found"
    )
    assert(
      bint.ult(zero, availableRewardQty),
      "No available reward quantity"
    )
    assert(
      bint.ult(zero, availableLiquidateQty),
      "No available liquidate quantity"
    )

    -- check if the user has any open positions
    if not hasOpenPosition then
      -- remove from auctions if present
      liquidations.removeAuction(target)

      -- error and trigger refund
      error("User does not have an active loan")
    end

    -- ensure "liquidation-limit / borrow-balance < 1"
    -- this means that the user is eligible for liquidation
    local totalLiquidationLimit = utils.reduce(
      function (acc, curr) return acc + curr.value end,
      zero,
      oracle.getValues(prices, liquidationLimits)
    )
    local totalBorrowBalance = utils.reduce(
      function (acc, curr) return acc + curr.value end,
      zero,
      oracle.getValues(prices, borrowBalances)
    )

    assert(
      bint.ult(totalLiquidationLimit, totalBorrowBalance),
      "Target not eligible for liquidation"
    )

    -- get token quantities
    local inQty = bint(msg.Tags.Quantity)

    -- USD value of the liquidation
    local usdValue = oracle.getValue(
      prices,
      inQty,
      inTokenData.ticker,
      inTokenData.denomination
    )

    -- ensure that at least the minimum threshold is reached
    -- when repaying the loan or the liquidator is repaying the
    -- full amount, in case the total value of the loan they're
    -- repaying is under 20% of the user's loans' total value
    assert(
      bint.ule(availableLiquidateQty, inQty) or bint.ule(
        bint.udiv(
          totalBorrowBalance * bint(MinLiquidationThreshold * 100 // 1),
          bint(100 * 100)
        ),
        usdValue
      ),
      "Liquidators are required to repay at least " ..
      tostring(MinLiquidationThreshold) ..
      "% of the total loan or the entire loan of a token"
    )

    -- market value of the liquidation
    local marketValueInQty = oracle.getValueInToken(
      {
        ticker = inTokenData.ticker,
        quantity = inQty,
        denomination = inTokenData.denomination
      },
      outTokenData,
      prices
    )

    -- make sure that the user's position is enough to pay the liquidator
    -- (at least the market value of the tokens)
    assert(
      bint.ule(marketValueInQty, availableRewardQty),
      "The user does not have enough tokens in their position for this liquidation"
    )

    -- apply auction
    local discount = tokens.getDiscount(target)

    -- update the expected reward quantity using the discount
    local expectedRewardQty = marketValueInQty

    if discount > 0 then
      expectedRewardQty = bint.udiv(
        expectedRewardQty * bint(100 * PrecisionFactor + discount),
        bint(100 * PrecisionFactor)
      )
    end

    -- if the discount is higher than the position in the
    -- reward token, we need to update it with the maximum
    -- possible amount
    if bint.ult(availableRewardQty, expectedRewardQty) then
      expectedRewardQty = availableRewardQty
    end

    -- the minimum quantity expected by the user
    local minExpectedRewardQty = bint(msg.Tags["X-Min-Expected-Quantity"] or 0)

    -- make sure the user is receiving at least
    -- the minimum amount of tokens they're expecting
    assert(
      bint.ule(minExpectedRewardQty, expectedRewardQty),
      "Could not meet the defined slippage"
    )

    -- check queue
    assert(
      not queue.isQueued(target),
      "User is already queued for liquidation"
    )

    -- whether or not to remove the auction after this liquidation is complete.
    -- this checks if the position becomes healthy after the liquidation
    local removeWhenDone = bint.ule(
      totalBorrowBalance - oracle.getValue(prices, bint.min(inQty, availableLiquidateQty), inTokenData.ticker, inTokenData.denomination),
      totalLiquidationLimit - oracle.getValue(prices, expectedRewardQty, outTokenData.ticker, outTokenData.denomination)
    )

    return "", expectedRewardQty, oTokensParticipating, removeWhenDone
  end)

  -- check if liquidation is possible
  if not success then
    -- signal error
    ao.send({
      Target = liquidator,
      Action = "Liquidate-Error",
      Error = string.gsub(errorMsg, "%[[%w_.\" ]*%]:%d*: ", "")
    })

    -- refund
    return ao.send({
      Target = msg.From,
      Action = "Transfer",
      Quantity = msg.Tags.Quantity,
      Recipient = liquidator
    })
  end

  -- since a liquidation is possible for the target
  -- we add it to the list of discovered auctions
  liquidations.addAuction(target, msg.Timestamp)

  -- queue the liquidation at this point, because
  -- the user position has been checked, so the liquidation is valid
  -- we don't want anyone to be able to liquidate from this point
  queue.add(target, ao.id)

  -- TODO: timeout here? (what if this doesn't return in time, the liquidation remains in a pending state)
  -- TODO: this timeout can be done with a Handler that removed this coroutine

  -- liquidation reference to identify the result
  -- (we cannot use .receive() here, since both the target
  -- and the default response reference will change, because
  -- of the chained messages)
  local liquidationReference = msg.Id .. "-" .. liquidator

  -- liquidate the loan
  ao.send({
    Target = liquidatedToken,
    Action = "Transfer",
    Quantity = msg.Tags.Quantity,
    Recipient = oTokensParticipating.liquidated,
    ["X-Action"] = "Liquidate-Borrow",
    ["X-Liquidator"] = liquidator,
    ["X-Liquidation-Target"] = target,
    ["X-Reward-Market"] = oTokensParticipating.reward,
    ["X-Reward-Quantity"] = tostring(expectedRewardQty),
    ["X-Liquidation-Reference"] = liquidationReference
  })

  -- wait for result
  local loanLiquidationRes = Handlers.receive({
    From = oTokensParticipating.liquidated,
    ["Liquidation-Reference"] = liquidationReference
  })

  -- remove from queue (discard result - if we get to this point, the user should be queued by the controller)
  queue.remove(target, ao.id)

  -- check loan liquidation result
  -- (at this point, we do not need to refund the user
  -- because the oToken process handles that)
  if loanLiquidationRes.Tags.Error or loanLiquidationRes.Tags.Action ~= "Liquidate-Borrow-Confirmation" then
    return ao.send({
      Target = liquidator,
      Action = "Liquidate-Error",
      Error = loanLiquidationRes.Tags.Error
    })
  end

  -- if the auction is done (no more loans to liquidate)
  -- we need to remove it from the discovered auctions
  if removeWhenDone then
    liquidations.removeAuction(target)
  end

  -- send confirmation to the liquidator
  ao.send({
    Target = liquidator,
    Action = "Liquidate-Confirmation",
    ["Liquidation-Target"] = target,
    ["From-Quantity"] = msg.Tags.Quantity,
    ["From-Token"] = liquidatedToken,
    ["To-Quantity"] = tostring(expectedRewardQty),
    ["To-Token"] = rewardToken
  })

  -- send notice to the target
  ao.send({
    Target = target,
    Action = "Liquidate-Notice",
    ["From-Quantity"] = msg.Tags.Quantity,
    ["To-Quantity"] = tostring(expectedRewardQty)
  })
end

return mod
