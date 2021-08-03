// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity =0.6.12;

import "ds-test/test.sol";

import "./GUniLPOracle.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
    function load(address, bytes32 slot) external returns (bytes32);
}

interface OSMLike {
    function bud(address) external returns (uint);
    function peek() external returns (bytes32, bool);
}

interface UniPoolLike {
    function slot0() external view returns (uint160, int24, uint16, uint16, uint16, uint8, bool);
    function swap(address, bool, int256, uint160, bytes calldata) external;
}

contract GUniLPOracleTest is DSTest {

    function assertEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b > _tolerance * a / 1e4) {
            emit log_bytes32("Error: Wrong `uint' value");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function assertNotEqApprox(uint256 _a, uint256 _b, uint256 _tolerance) internal {
        uint256 a = _a;
        uint256 b = _b;
        if (a < b) {
            uint256 tmp = a;
            a = b;
            b = tmp;
        }
        if (a - b < _tolerance * a / 1e4) {
            emit log_bytes32("Error: `uint' should not match");
            emit log_named_uint("  Expected", _b);
            emit log_named_uint("    Actual", _a);
            fail();
        }
    }

    function giveTokens(address token, uint256 amount) internal {
        // Edge case - balance is already set for some reason
        if (ERC20Like(token).balanceOf(address(this)) == amount) return;

        for (int i = 0; i < 100; i++) {
            // Scan the storage for the balance storage slot
            bytes32 prevValue = hevm.load(
                token,
                keccak256(abi.encode(address(this), uint256(i)))
            );
            hevm.store(
                token,
                keccak256(abi.encode(address(this), uint256(i))),
                bytes32(amount)
            );
            if (ERC20Like(token).balanceOf(address(this)) == amount) {
                // Found it
                return;
            } else {
                // Keep going after restoring the original value
                hevm.store(
                    token,
                    keccak256(abi.encode(address(this), uint256(i))),
                    prevValue
                );
            }
        }

        // We have failed if we reach here
        assertTrue(false);
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
    function div(uint x, uint y) internal pure returns (uint z) {
        require(y > 0 && (z = x / y) * y == x, "ds-math-divide-by-zero");
    }
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }
    function wmul(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, y), WAD / 2) / WAD;
    }
    function wdiv(uint x, uint y) internal pure returns (uint z) {
        z = add(mul(x, WAD), y / 2) / y;
    }

    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt1(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    // FROM https://github.com/abdk-consulting/abdk-libraries-solidity/blob/16d7e1dd8628dfa2f88d5dadab731df7ada70bdd/ABDKMath64x64.sol#L687
    function sqrt2(uint256 _x) private pure returns (uint128) {
        if (_x == 0) return 0;
        else {
            uint256 xx = _x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) { xx >>= 128; r <<= 64; }
            if (xx >= 0x10000000000000000) { xx >>= 64; r <<= 32; }
            if (xx >= 0x100000000) { xx >>= 32; r <<= 16; }
            if (xx >= 0x10000) { xx >>= 16; r <<= 8; }
            if (xx >= 0x100) { xx >>= 8; r <<= 4; }
            if (xx >= 0x10) { xx >>= 4; r <<= 2; }
            if (xx >= 0x8) { r <<= 1; }
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1;
            r = (r + _x / r) >> 1; // Seven iterations should be enough
            uint256 r1 = _x / r;
            return uint128 (r < r1 ? r : r1);
        }
    }

    Hevm                 hevm;
    GUniLPOracleFactory  factory;
    GUniLPOracle         daiUsdcLPOracle;

    address constant DAI_USDC_GUNI_POOL = 0xAbDDAfB225e10B90D798bB8A886238Fb835e2053;
    address constant DAI_USDC_UNI_POOL  = 0x6c6Bc977E13Df9b0de53b251522280BB72383700;
    address constant USDC_ORACLE        = 0x77b68899b99b686F415d074278a9a16b336085A0;
    address constant DAI_ORACLE         = 0x47c3dC029825Da43BE595E21fffD0b66FfcB7F6e;
    address constant DAI                = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant USDC               = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    bytes32 constant poolNameDAI       = "DAI-USDC-GUNI-LP";

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        factory = new GUniLPOracleFactory();

        daiUsdcLPOracle = GUniLPOracle(factory.build(
            address(this),
            DAI_USDC_GUNI_POOL,
            poolNameDAI,
            DAI_ORACLE,
            USDC_ORACLE)
        );
        daiUsdcLPOracle.kiss(address(this));

        assertEq(GUNILike(DAI_USDC_GUNI_POOL).pool(), DAI_USDC_UNI_POOL);
    }

    ///////////////////////////////////////////////////////
    //                                                   //
    //                  Factory Tests                    //
    //                                                   //
    ///////////////////////////////////////////////////////

    function test_build() public {
        GUniLPOracle oracle = GUniLPOracle(factory.build(
            address(this),
            DAI_USDC_GUNI_POOL,
            poolNameDAI,
            DAI_ORACLE,
            USDC_ORACLE)
        );                                                  // Deploy new LP oracle
        assertTrue(address(oracle) != address(0));          // Verify oracle deployed successfully
        assertEq(oracle.wards(address(this)), 1);           // Verify caller is owner
        assertEq(oracle.wards(address(factory)), 0);        // Vérify factory is not owner
        assertEq(oracle.src(), DAI_USDC_GUNI_POOL);           // Verify uni pool is source
        assertEq(oracle.orb0(), DAI_ORACLE);               // Verify oracle configured correctly
        assertEq(oracle.orb1(), USDC_ORACLE);                // Verify oracle configured correctly
        assertEq(oracle.wat(), poolNameDAI);                // Verify name is set correctly
        assertEq(uint256(oracle.stopped()), 0);             // Verify contract is active
        assertTrue(factory.isOracle(address(oracle)));      // Verify factory recorded oracle
    }

    function testFail_build_invalid_pool() public {
        factory.build(
            address(this),
            address(0),
            poolNameDAI,
            DAI_ORACLE,
            USDC_ORACLE
        );                                                  // Attempt to deploy new LP oracle
    }

    function testFail_build_invalid_pool2() public {
        factory.build(
            address(this),
            USDC_ORACLE,
            poolNameDAI,
            DAI_ORACLE,
            USDC_ORACLE
        );                                                  // Attempt to deploy with invalid pool
    }

    function testFail_build_invalid_oracle() public {
        factory.build(
            address(this),
            DAI_USDC_GUNI_POOL,
            poolNameDAI,
            DAI_ORACLE,
            address(0)
        );                                                  // Attempt to deploy new LP oracle
    }

    function testFail_build_invalid_oracle2() public {
        factory.build(
            address(this),
            DAI_USDC_GUNI_POOL,
            poolNameDAI,
            address(0),
            USDC_ORACLE
        );                                                  // Attempt to deploy new LP oracle
    }

    ///////////////////////////////////////////////////////
    //                                                   //
    //                   Oracle Tests                    //
    //                                                   //
    ///////////////////////////////////////////////////////

    function test_dai_oracle_constructor() public {
        assertEq(daiUsdcLPOracle.src(), DAI_USDC_GUNI_POOL);
        assertEq(daiUsdcLPOracle.orb0(), DAI_ORACLE);
        assertEq(daiUsdcLPOracle.orb1(), USDC_ORACLE);
        assertEq(daiUsdcLPOracle.wat(), poolNameDAI);
        assertEq(daiUsdcLPOracle.wards(address(this)), 1);
        assertEq(daiUsdcLPOracle.wards(address(factory)), 0);
        assertEq(uint256(daiUsdcLPOracle.stopped()), 0);
    }

    function test_calc_sqrt_price() public {
        // Both these oracles should be hard coded to 1
        uint256 dec0 = uint256(ERC20Like(GUNILike(daiUsdcLPOracle.src()).token0()).decimals());
        uint256 dec1 = uint256(ERC20Like(GUNILike(daiUsdcLPOracle.src()).token1()).decimals());
        uint256 p0 = OracleLike(DAI_ORACLE).read();
        assertEq(p0, 1e18);
        uint256 p1 = OracleLike(USDC_ORACLE).read();
        assertEq(p1, 1e18);
        p0 /= 10 ** (18 - dec0);
        p1 /= 10 ** (18 - dec1);
        
        // Check both square roots produce the same results
        uint256 sqrtPriceX96_1 = sqrt1(mul(p1, (1 << 136)) / p0) << 28;
        assertEq(sqrtPriceX96_1, 79228162514264115904512);
        uint256 sqrtPriceX96_2 = sqrt2(mul(p1, (1 << 136)) / p0) << 28;
        assertEq(sqrtPriceX96_2, 79228162514264115904512);

        // Check that the price roughly matches the Uniswap pool price during normal conditions
        (uint256 sqrtPriceX96_uni,,,,,,) = UniPoolLike(DAI_USDC_UNI_POOL).slot0();
        assertEqApprox(sqrtPriceX96_uni, 79228162514264115904512, 10);
    }

    function test_seek_dai() public {
        daiUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        daiUsdcLPOracle.poke();
        uint128 lpTokenPrice128 = uint128(uint256(daiUsdcLPOracle.read()));
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPrice = uint256(lpTokenPrice128);
        // Price should be the value of all the tokens combined divided by totalSupply()
        (uint256 balDai, uint256 balUsdc) = GUNILike(daiUsdcLPOracle.src()).getUnderlyingBalances();
        uint256 expectedPrice = (balDai + balUsdc * 1e12) * WAD / ERC20Like(daiUsdcLPOracle.src()).totalSupply();
        // Price is slightly off due to difference between Uniswap spot price and the Maker oracles
        // Allow for a 0.1% discrepancy
        assertEqApprox(lpTokenPrice, expectedPrice, 10);    
    }

    /// @notice Uniswap v3 callback fn, called back on pool.swap
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata /*data*/
    ) external {
        if (amount0Delta > 0)
            ERC20Like(DAI).transfer(msg.sender, uint256(amount0Delta));
        else if (amount1Delta > 0)
            ERC20Like(USDC).transfer(msg.sender, uint256(amount1Delta));
    }

    function test_flash_loan_protection_dai_to_usdc() public {
        uint256 balOrig = ERC20Like(USDC).balanceOf(DAI_USDC_UNI_POOL);
        assertGt(balOrig, 0);

        daiUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        daiUsdcLPOracle.poke();
        uint128 lpTokenPrice128 = uint128(uint256(daiUsdcLPOracle.read()));
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPriceOrig = uint256(lpTokenPrice128);
        (uint256 balDai, uint256 balUsdc) = GUNILike(daiUsdcLPOracle.src()).getUnderlyingBalances();
        uint256 naivePriceOrig = (balDai + balUsdc * 1e12) * WAD / ERC20Like(daiUsdcLPOracle.src()).totalSupply();

        // Give enough tokens to totally skew the reserves to almost all USDC
        uint256 amount = 10 * ERC20Like(DAI).balanceOf(DAI_USDC_UNI_POOL);
        giveTokens(DAI, amount);
        UniPoolLike(DAI_USDC_UNI_POOL).swap(address(this), true, int256(amount), 69260490254391874038245, "");
        assertLt(ERC20Like(USDC).balanceOf(DAI_USDC_UNI_POOL) * 1e4 / balOrig, 100);    // New USDC balance should be less than 1% of original balance

        hevm.warp(now + 1 hours);
        daiUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        daiUsdcLPOracle.poke();
        lpTokenPrice128 = uint128(uint256(daiUsdcLPOracle.read()));
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPrice = uint256(lpTokenPrice128);
        (balDai, balUsdc) = GUNILike(daiUsdcLPOracle.src()).getUnderlyingBalances();
        uint256 naivePrice = (balDai + balUsdc * 1e12) * WAD / ERC20Like(daiUsdcLPOracle.src()).totalSupply();

        assertEqApprox(naivePrice, naivePriceOrig, 10);         // Due to range being so tight this won't deviate much (this won't be the case for larger ranges)
        assertEqApprox(lpTokenPrice, lpTokenPriceOrig, 10);     // This should not deviate by much as it is not using the Uniswap pool price to calculate reserves
    }

    function test_flash_loan_protection_usdc_to_dai() public {
        uint256 balOrig = ERC20Like(DAI).balanceOf(DAI_USDC_UNI_POOL);
        assertGt(balOrig, 0);

        daiUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        daiUsdcLPOracle.poke();
        uint128 lpTokenPrice128 = uint128(uint256(daiUsdcLPOracle.read()));
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPriceOrig = uint256(lpTokenPrice128);
        (uint256 balDai, uint256 balUsdc) = GUNILike(daiUsdcLPOracle.src()).getUnderlyingBalances();
        uint256 naivePriceOrig = (balDai + balUsdc * 1e12) * WAD / ERC20Like(daiUsdcLPOracle.src()).totalSupply();

        // Give enough tokens to totally skew the reserves to almost all USDC
        uint256 amount = 10 * ERC20Like(USDC).balanceOf(DAI_USDC_UNI_POOL);
        giveTokens(USDC, amount);
        UniPoolLike(DAI_USDC_UNI_POOL).swap(address(this), false, int256(amount), 89260490254391874038245, "");
        assertLt(ERC20Like(DAI).balanceOf(DAI_USDC_UNI_POOL) * 1e4 / balOrig, 100);    // New DAI balance should be less than 1% of original balance

        hevm.warp(now + 1 hours);
        daiUsdcLPOracle.poke();
        hevm.warp(now + 1 hours);
        daiUsdcLPOracle.poke();
        lpTokenPrice128 = uint128(uint256(daiUsdcLPOracle.read()));
        assertTrue(lpTokenPrice128 > 0);                                          // Verify price was set
        uint256 lpTokenPrice = uint256(lpTokenPrice128);
        (balDai, balUsdc) = GUNILike(daiUsdcLPOracle.src()).getUnderlyingBalances();
        uint256 naivePrice = (balDai + balUsdc * 1e12) * WAD / ERC20Like(daiUsdcLPOracle.src()).totalSupply();

        assertNotEqApprox(naivePrice, naivePriceOrig, 10);      // Due to the lop-sidedness of the current DAI/USDC price this will actually deviate by a bit more than the other way
        assertEqApprox(lpTokenPrice, lpTokenPriceOrig, 10);     // This should not deviate by much as it is not using the Uniswap pool price to calculate reserves
    }

    // TODO add tests for non-stablecoin oracles when they become available

}
