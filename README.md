# Uniswap V3 LP Oracles

Contains vendor-specific implementations for Uniswap V3 oracles. The specific functions being called to determine underlying balances will vary between LP implementations, but the underlying logic should be roughly equivalent between all vendors.

## General Price Calculation

We derive the sqrtPriceX96 via Maker's own oracles to prevent price manipulation in the pool:

```
Define:

p0 = price of token0 in USD
p1 = price of token1 in USD
UNITS_0 = decimals of token0
UNITS_1 = decimals of token1

token1/token0 = (p0 / 10^UNITS_0) / (p1 / 10^UNITS_1)               [Conversion from Maker's price ratio into Uniswap's format]
              = (p0 * 10^UNITS_1) / (p1 * 10^UNITS_0)

sqrtPriceX96 = sqrt(token1/token0) * 2^96                           [From Uniswap's definition]
             = sqrt((p0 * 10^UNITS_1) / (p1 * 10^UNITS_0)) * 2^96
             = sqrt((p0 * 10^UNITS_1) / (p1 * 10^UNITS_0)) * 2^48 * 2^48
             = sqrt((p0 * 10^UNITS_1 * 2^96) / (p1 * 10^UNITS_0)) * 2^48
```

Once we have the `sqrtPriceX96` we can use that to compute the fair reserves for each token. This part may be slightly subjective depending on the implementation, but we expect most tokens to provide something like `getUnderlyingBalancesAtPrice(uint160 sqrtPriceX96)` which will forward our oracle-calculated `sqrtPriceX96` to the Uniswap-provided [`LiquidityAmounts.getAmountsForLiquidity(...)`](https://github.com/Uniswap/uniswap-v3-periphery/blob/main/contracts/libraries/LiquidityAmounts.sol#L120). This function will return the fair reserves for each token. Vendor-specific logic is then used to tack any uninvested fees on top of those amounts.

Once we have the fair reserves and the prices we can compute the token price by:

```
Token Price = TVL / Token Supply
            = (r0 * p0 + r1 * p1) / totalSupply
```
