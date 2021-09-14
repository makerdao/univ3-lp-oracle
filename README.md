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

## sqrtPriceX96 Calculation Analysis

The goal is to check that this calculation does not overflow or lose precision:

```
uint160 sqrtPriceX96 = sqrt((p0 * 10^UNITS_1 * 2^96) / (p1 * 10^UNITS_0)) * 2^48
```


*Notes:*
* `p0` and `p1` are uint256 `wad`s, denoting token price in `usd`.
* We assume that the `sqrt` function does not have overflow or precision problems as it is used in `univ2-lp-oracle` and tested through unit tests.


*Analysis:*

1. For numerator expression to not overflow this needs to hold:
```
   p0 * 10^UNITS_1 * 2^96 < 2^256                     // 2^96 < 10^29, 2^256 > 10^77 =>
   p0 * 10^UNITS_1 * 10^29 < 10^77                    // p0 = token0_usd_price * 10^18, UNITS_1 <= 18
   token0_usd_price * 10^18 * 10^18 * 10^29 < 10^77
   token0_usd_price < 10^12
```

2. For the division operation not to lose precision this needs to hold:
```
   (p0 * 10^UNITS_1 * 2^96) >> (p1 * 10^UNITS_0) // 2^96 > 10^28, UNITS_1 >= 0, UNITS_0 <= 18
   (p0 * 10^0 * 10^28) >> p1 * 10^18             // p0 = token0_usd_price * 10^18, p1 = token1_usd_price * 10^18
   10^10 >> token1_usd_price / token0_usd_price
```

3. For the full expression not to overflow a uint160 this needs to hold:
```
   sqrt((p0 * 10^UNITS_1 * 2^96) / (p1 * 10^UNITS_0)) * 2^48 < 2^160
   sqrt((p0 * 10^UNITS_1 * 2^96) / (p1 * 10^UNITS_0)) < 2^112         // 2^96 < 10^29, UNITS_1 <= 18, UNITS_0 >= 0, 2^112 > 10^33
   sqrt((p0 * 10^18 * 10^29) / (p1 * 10^0)) < 10^33
   sqrt((p0 * 10^18 * 10^29) / p1) < 10^33                            // ^2
   (p0 * 10^47) / p1 < 10^66
   (p0 / p1) < 10^19                                                  // p0 = token0_usd_price * 10^18, p1 = token1_usd_price * 10^18
   token0_usd_price / token1_usd_price < 10^19
   
