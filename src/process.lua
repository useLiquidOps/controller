local auctions = require ".interactions.auctions"
local listing = require ".interactions.listing"
local update = require ".interactions.update"
local gate = require ".interactions.gate"
local info = require ".interactions.info"

local assertions = require ".utils.assertions"

--
-- Setup GLOBAL variables
--

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

--
-- Types
--

---@alias TokenData { ticker: string, denomination: number }
---@alias PriceParam { ticker: string, quantity: Bint?, denomination: number }
---@alias CollateralBorrow { token: string, ticker: string, quantity: string }
---@alias QualifyingPosition { target: string, depts: CollateralBorrow[], collaterals: CollateralBorrow[], discount: string }
---@alias Friend { id: string, ticker: string, oToken: string, denomination: number }

--
-- Setup handlers
--

Handlers.add(
  "sync-timestamp",
  function () return "continue" end,
  gate.sync
)
Handlers.add(
  "refund-invalid",
  function (msg)
    return msg.Tags.Action == "Credit-Notice" and
      msg.Tags["X-Action"] ~= "Liquidate"
  end,
  gate.refundInvalidToken
)

Handlers.add(
  "info",
  { Action = "Info" },
  info.info
)
Handlers.add(
  "get-tokens",
  { Action = "Get-Tokens" },
  info.tokens
)
Handlers.add(
  "get-oracle",
  { Action = "Get-Oracle" },
  info.oracle
)
Handlers.add(
  "get-queue",
  { Action = "Get-Queue" },
  info.queue
)

Handlers.add(
  "liquidate",
  { Action = "Credit-Notice", ["X-Action"] = "Liquidate" },
  auctions.liquidate
)
Handlers.add(
  "get-auctions",
  { Action = "Get-Auctions" },
  auctions.list
)

--
-- Setup admin handlers
--

Handlers.add(
  "list",
  assertions.isAdminAction("List"),
  listing.list
)
Handlers.add(
  "unlist",
  assertions.isAdminAction("Unlist"),
  listing.unlist
)

Handlers.add(
  "batch-update",
  assertions.isAdminAction("Batch-Update"),
  update.batchUpdate
)
Handlers.add(
  "solo-update",
  assertions.isAdminAction("Solo-Update"),
  update.soloUpdate
)
