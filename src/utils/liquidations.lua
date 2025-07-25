local mod = {}

-- Removes an auction with a cooldown
---@param target string Auction target address
function mod.removeAuction(target)
  if Auctions[target] == nil then return end

  local removeAuctionAfter = Timestamp + 1000 * 60 * 60 * 3 -- in 3 hours
  local handlerName = "auctions-remove-" .. target

  Handlers.remove(handlerName)
  Handlers.once(
    handlerName,
    function (msg)
      if msg.Timestamp > removeAuctionAfter then
        return "continue"
      end
      return false
    end,
    function () Auctions[target] = nil end
  )
end

-- Adds a newly discovered auction
---@param target string Auction target address
---@param discovered number Discovery timestamp
function mod.addAuction(target, discovered)
  -- delete handler that would remove the auction and add auction
  Handlers.remove("auctions-remove-" .. target)

  -- add discovery date if the user isn't already in auctions
  if Auctions[target] == nil then
    Auctions[target] = discovered
  end
end

-- Get current discount for a target
---@param target string Target address
function mod.getDiscount(target)
  -- apply auction model
  -- time passed in milliseconds since the discovery of this auction
  local timePassed = Timestamp - (Auctions[target] or Timestamp)

  -- if the time passed is higher than the discount interval
  -- we reached the minimum discount price, so we
  -- set the time passed to the corresponding interval
  if timePassed > DiscountInterval then
    timePassed = DiscountInterval
  end

  -- current discount percentage:
  -- a linear function of the time passed,
  -- the discount becomes 0 when the discount
  -- interval is over
  local discount = math.max((DiscountInterval - timePassed) * MaxDiscount * PrecisionFactor // DiscountInterval, MinDiscount)

  return discount
end

return mod
