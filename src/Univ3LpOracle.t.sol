pragma solidity ^0.6.7;

import "ds-test/test.sol";

import "./Univ3LpOracle.sol";

contract Univ3LpOracleTest is DSTest {
    Univ3LpOracle oracle;

    function setUp() public {
        oracle = new Univ3LpOracle();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
