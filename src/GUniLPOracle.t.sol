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

    Hevm                 hevm;
    GUniLPOracleFactory  factory;
    GUniLPOracle         daiUsdcLPOracle;

    address constant DAI_USDC_GUNI_POOL = 0xAbDDAfB225e10B90D798bB8A886238Fb835e2053;
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

}
