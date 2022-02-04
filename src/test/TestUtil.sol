// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.6.11;

// Inspired by https://github.com/maple-labs/maple-core/blob/main/contracts/test/TestUtil.sol

import "../../lib/openzeppelin-contracts/contracts/math/SafeMath.sol";
import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/ds-test/src/test.sol";
import "./mocks/MockPriceFeed.sol";

interface Hevm {
    function store(
        address,
        bytes32,
        bytes32
    ) external;

    function prank(address) external;

    function startPrank(address) external;

    function stopPrank() external;

    function deal(address, uint256) external;

    function etch(address, bytes calldata) external;
}

contract TestUtil is DSTest {
    using SafeMath for uint256;

    Hevm internal hevm;

    struct Token {
        address addr; // ERC20 Mainnet address
        uint256 slot; // Balance storage slot
        IERC20 erc;
    }

    address internal constant LIQUITY_PRICE_FEED_ADDR = 0x4c517D4e2C851CA76d7eC94B805269Df0f2201De;

    mapping(bytes32 => Token) internal tokens;

    constructor() public {
        hevm = Hevm(address(bytes20(uint160(uint256(keccak256("hevm cheat code"))))));
    }

    function setUpTokens() public {
        tokens["LUSD"].addr = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
        tokens["LUSD"].erc = IERC20(tokens["LUSD"].addr);
        tokens["LUSD"].slot = 2;

        tokens["WETH"].addr = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        tokens["WETH"].erc = IERC20(tokens["WETH"].addr);
        tokens["WETH"].slot = 3;

        tokens["LQTY"].addr = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
        tokens["LQTY"].erc = IERC20(tokens["LQTY"].addr);
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

    function setLiquityPrice(uint256 price) public {
        IPriceFeed mockFeed = new MockPriceFeed(price);
        hevm.etch(LIQUITY_PRICE_FEED_ADDR, _getCode(address(mockFeed)));
        IPriceFeed feed = IPriceFeed(LIQUITY_PRICE_FEED_ADDR);
        assertEq(feed.fetchPrice(), price);
    }

    function dropLiquityPriceByHalf() public {
        uint256 currentPrice = IPriceFeed(LIQUITY_PRICE_FEED_ADDR).fetchPrice();
        setLiquityPrice(currentPrice.div(2));
    }

    /*
     * @notice Loads contract code at address.
     *
     * @param _addr Address of the contract.
     *
     * @dev I am using assembly here because solidity versions <0.8.0 do not have address.code attribute.
     */
    function _getCode(address _addr) private view returns (bytes memory o_code) {
        assembly {
            // retrieve the size of the code, this needs assembly
            let size := extcodesize(_addr)
            // allocate output byte array - this could also be done without assembly
            // by using o_code = new bytes(size)
            o_code := mload(0x40)
            // new "memory end" including padding
            mstore(0x40, add(o_code, and(add(add(size, 0x20), 0x1f), not(0x1f))))
            // store length in memory
            mstore(o_code, size)
            // actually retrieve the code, this needs assembly
            extcodecopy(_addr, add(o_code, 0x20), 0, size)
        }
    }
}
