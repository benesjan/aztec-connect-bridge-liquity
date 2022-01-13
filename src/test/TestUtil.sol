// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;

// Inspired by https://github.com/maple-labs/maple-core/blob/main/contracts/test/TestUtil.sol

import "../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/ds-test/src/test.sol";

interface Hevm {
    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract TestUtil is DSTest {
    using SafeMath for uint256;

    Hevm internal hevm;

    uint256 internal constant WAD = 10**18;

    struct Token {
        address addr; // ERC20 Mainnet address
        uint256 slot; // Balance storage slot
    }

    mapping(bytes32 => Token) internal tokens;

    constructor() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    }

    function setUpTokens() public {
        tokens["LUSD"].addr = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
        tokens["LUSD"].slot = 2;
        tokens["WETH"].addr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokens["WETH"].slot = 3;
        tokens["LQTY"].addr = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
        tokens["LQTY"].slot = 0;
    }

    // Manipulate mainnet ERC20 balance
    function mint(
        bytes32 symbol,
        address account,
        uint256 amt
    ) public {
        address addr = tokens[symbol].addr;
        uint256 slot = tokens[symbol].slot;
        uint256 bal = IERC20(addr).balanceOf(account);

        hevm.store(
            addr,
            keccak256(abi.encode(account, slot)), // Mint tokens
            bytes32(bal + amt)
        );

        assertEq(IERC20(addr).balanceOf(account), bal + amt);
        // Assert new balance
    }

    function rand(uint256 seed) public pure returns (uint256) {
        // I want a number between 1 WAD and 10 million WAD
        return uint256(keccak256(abi.encodePacked(seed))) % 10**25;
    }
}
