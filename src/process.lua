local coroutine = require "coroutine"
local bint = require ".bint"(1024)
local utils = require ".utils"
local json = require "json"

-- oToken module ID
Module = Module or "C6CQfrL29jZ-LYXV2lKn09d3pBIM6adDFwWqh2ICikM"

-- oracle id and tolerance
Oracle = Oracle or "4fVi8P-xSRWxZ0EE0EpltDe8WJJvcD9QyFXMqfk-1UQ"
MaxOracleDelay = MaxOracleDelay or 1200000

-- admin addresses
Owners = Owners or {}

-- liquidops logo tx id
ProtocolLogo = ProtocolLogo or ""

-- holds all the processes that are part of the protocol
-- a member consists of the following fields:
-- - id: string (this is the address of the collateral supported by LiquidOps)
-- - ticker: string (the ticker of the collateral)
-- - oToken: string (the address of the oToken process for the collateral)
-- - denomination: integer (the denomination of the collateral)
---@type Friend[]
Tokens = Tokens or {}

-- queue for operations that change the user's position
---@type { address: string, origin: string }[]
Queue = Queue or {}

-- current timestamp
Timestamp = Timestamp or 0

-- cached auctions (position wallet address, timestamp when discovered)
---@type table<string, number>
Auctions = Auctions or {}

-- maximum and minimum discount that can be applied to a loan in percentages
MaxDiscount = MaxDiscount or 5
MinDiscount = MinDiscount or 1

-- the period till the auction reaches the minimum discount (market price)
DiscountInterval = DiscountInterval or 1000 * 60 * 60 -- 1 hour

PrecisionFactor = 1000000

-- minimum liquidation percentage (a liquidator is required to liquidate at least this percentage of the total loan)
MinLiquidationThreshold = MinLiquidationThreshold or 20

---@alias TokenData { ticker: string, denomination: number }
---@alias PriceParam { ticker: string, quantity: Bint?, denomination: number }
---@alias CollateralBorrow { token: string, ticker: string, quantity: string }
---@alias QualifyingPosition { target: string, depts: CollateralBorrow[], collaterals: CollateralBorrow[], discount: string }
---@alias Friend { id: string, ticker: string, oToken: string, denomination: number }

Handlers.add(
  "sync-timestamp",
  function () return "continue" end,
  function (msg) Timestamp = msg.Timestamp end
)

Handlers.add(
  "info",
  { Action = "Info" },
  function (msg)
    msg.reply({
      Name = "LiquidOps Controller",
      Module = Module,
      Oracle = Oracle,
      ["Max-Discount"] = tostring(MaxDiscount),
      ["Min-Discount"] = tostring(MinDiscount),
      ["Discount-Interval"] = tostring(DiscountInterval),
      Data = json.encode(Tokens)
    })
  end
)
