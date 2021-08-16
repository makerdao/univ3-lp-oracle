# Uniswap V3 LP Oracles

Contains vendor-specific implementations for Uniswap V3 oracles. The specific functions being called to determine underlying balances will vary between LP implementations, but the underlying logic should be roughly equivalent between all vendors.

## General Price Calculation

We derive the sqrtPriceX96 via Maker's own oracles to prevent price manipulation in the pool:

```
Define:

p0 = price of token0 in USD
p1 = price of token1 in USD

token1/token0 = (p0 / 10^UNITS_0) / (p1 / 10^UNITS_1)               [Conversion from Maker's price ratio into Uniswap's format]
              = (p0 * 10^UNITS_1) / (p1 * 10^UNITS_0)

sqrtPriceX96 = sqrt(token1/token0) * 2^96                           [From Uniswap's definition]
             = sqrt((p0 * 10^UNITS_1) / (p1 * 10^UNITS_0)) * 2^96
             = sqrt((p0 * 10^UNITS_1) / (p1 * 10^UNITS_0)) * 2^68 * 2^28
             = sqrt((p0 * 10^UNITS_1 * 2^136) / (p1 * 10^UNITS_0)) * 2^28
```
