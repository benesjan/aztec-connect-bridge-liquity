// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;

// Inspired by https://github.com/maple-labs/maple-core/blob/main/contracts/test/TestUtil.sol

import "../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/ds-test/src/test.sol";

interface Hevm {
    function store(address, bytes32, bytes32) external;
}

contract TestUtil is DSTest {

    using SafeMath for uint256;

    Hevm hevm;

    struct Token {
        address addr; // ERC20 Mainnet address
        uint256 slot; // Balance storage slot
    }

    mapping(bytes32 => Token) tokens;

    constructor() public {hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));}

    function setUpTokens() public {
        tokens["LUSD"].addr = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
        tokens["LUSD"].slot = 2;
    }

    // Manipulate mainnet ERC20 balance
    function mint(bytes32 symbol, address account, uint256 amt) public {
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
}