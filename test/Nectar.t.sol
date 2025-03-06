// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {LPFeeLibrary} from "v4-core/src/libraries/LPFeeLibrary.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";

import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";

import {Nectar, ComputeNode} from "../src/Nectar.sol";

import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";

import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";


contract NectarTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Nectar hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    address eas = 0xA1207F3BBa224E2c9c3c6D5aF63D0eb1582Ce587;
    address schemaRegistry =  0xA7b39296258348C78294F95B872b282326A97BDF;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address resolver = makeAddr("resolver");


    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();
        deployAndApprovePosm(manager);
        
        ComputeNode memory computeNode = ComputeNode({
            resolver: resolver,
            resolverURL: "https://compute.node.com",
            containerName: "cowsay:latest",
            payoutCurrency: usdc,
            payoutAmount: 10*10**18,
            lastRun: 0,
            downTime: 3600 * 24 * 7 // 1 week
        });
        


        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.AFTER_INITIALIZE_FLAG |
                Hooks.AFTER_ADD_LIQUIDITY_FLAG |
                Hooks.AFTER_REMOVE_LIQUIDITY_FLAG |
                Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG |
                Hooks.AFTER_DONATE_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(
            manager,
            eas,
            schemaRegistry,
            computeNode
            ); //Add all the necessary constructor arguments from the hook
        deployCodeTo("Nectar.sol:Nectar", constructorArgs, flags);
        hook = Nectar(flags);

        // Create the pool
        key = PoolKey(
            currency0,
            currency1,
            LPFeeLibrary.DYNAMIC_FEE_FLAG, // signal that the pool has a dynamic fee
            60,
            IHooks(hook)
        );
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testCounterHooks() public {
        // positions were created in setup()
        // Perform a test swap //
        bool zeroForOne = true;
        int256 amountSpecified = -1e18; // negative number indicates exact input swap!
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), amountSpecified);

    }

    function testLiquidityHooks() public {
        // positions were created in setup()

        // remove liquidity
        uint256 liquidityToRemove = 1e18;
        posm.decreaseLiquidity(
            tokenId,
            liquidityToRemove,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            MAX_SLIPPAGE_REMOVE_LIQUIDITY,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );

    }
}
