// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

// Inspired by https://github.com/maple-labs/maple-core/blob/main/contracts/test/TestUtil.sol

import "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../../lib/ds-test/src/test.sol";
import "./mocks/MockPriceFeed.sol";
import "./mocks/MockRollupProcessor.sol";

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
    Hevm internal hevm;

    DefiBridgeProxy defiBridgeProxy;
    MockRollupProcessor rollupProcessor;

    struct Token {
        address addr; // ERC20 Mainnet address
        uint256 slot; // Balance storage slot
        IERC20 erc;
    }

    address internal constant LIQUITY_PRICE_FEED_ADDR = 0x4c517D4e2C851CA76d7eC94B805269Df0f2201De;

    mapping(bytes32 => Token) internal tokens;

    constructor() {
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
        hevm.etch(LIQUITY_PRICE_FEED_ADDR, address(mockFeed).code);
        IPriceFeed feed = IPriceFeed(LIQUITY_PRICE_FEED_ADDR);
        assertEq(feed.fetchPrice(), price);
    }

    function dropLiquityPriceByHalf() public {
        uint256 currentPrice = IPriceFeed(LIQUITY_PRICE_FEED_ADDR).fetchPrice();
        setLiquityPrice(currentPrice / 2);
    }

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new MockRollupProcessor(address(defiBridgeProxy));
    }
}
