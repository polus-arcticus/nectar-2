// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/src/types/BeforeSwapDelta.sol";

import { JobResultObligation } from "alkahest-mocks/src/Statements/JobResultObligation.sol";
import { ERC20EscrowObligation } from "alkahest-mocks/src/Statements/ERC20EscrowObligation.sol";
import { TrustedPartyArbiter } from "alkahest-mocks/src/Validators/TrustedPartyArbiter.sol";

import {IEAS} from "eas-contracts/IEAS.sol";
import {ISchemaRegistry} from "eas-contracts/ISchemaRegistry.sol";

import "forge-std/console.sol";

/**
 * @notice ComputeNode is the struct that contains the information about the compute node
 * @param containerName The name of the docker container to run
 * @param resolverURL The url of the resolver
 * @param resolver The address of the resolver
 * @param frequency If sufficient fees have accumulated within frequency excess fees are sent to LP providers
 */
struct ComputeNode {
    string containerName; // Docker image to run
    string resolverURL;
    address resolver;
    address payoutCurrency;
    uint256 payoutAmount;
    uint256 downTime;
    uint256 lastRun;
}


struct ComputePool {
    uint256 amountToken0;
    uint256 amountToken1;
}

struct EASParams {
    IEAS eas;
    ISchemaRegistry schemaRegistry;
}

contract Nectar is BaseHook {
    using PoolIdLibrary for PoolKey;

    event RequestJob(
        address indexed sender,
        address indexed pool,
        address indexed resolver,
        uint256 nonce,
        string resolverURL,
        string containerName
    );
    // NOTE: ---------------------------------------------------------
    // state variables should typically be unique to a pool
    // a single hook contract should be able to service multiple pools
    // ---------------------------------------------------------------

    ComputeNode computeNode;
    EASParams easParams;

    uint256 usedNonces;
    mapping (PoolId => ComputePool) computePools;
    // with flashloan, flash accounting maybe


    constructor(
        IPoolManager _poolManager,
        address _eas,
        address _schemaRegistry,
        ComputeNode memory _computeNode
    )
    BaseHook(_poolManager)
    {
        computeNode = _computeNode;
        easParams = EASParams({
            eas: IEAS(_eas),
            schemaRegistry: ISchemaRegistry(_schemaRegistry)
        });
    }
    
    modifier onlyComputeNode() {
        require(msg.sender == address(computeNode.resolver), "Only compute node can call this function");
        _;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            // Provide Subscription Tier
            afterAddLiquidity: true,
            beforeRemoveLiquidity: false,
            // Revoke Subscription Tier
            afterRemoveLiquidity: true,
            // Catch LP Fees
            beforeSwap: true,
            // Check Conditions for run execution
            afterSwap: true,
            beforeDonate: false,
            // Check Conditions for run execution
            afterDonate: true,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    // -----------------------------------------------
    // NOTE: see IHooks.sol for function documentation
    // -----------------------------------------------

    function _afterInitialize(
        address sender,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        int24 tick
    ) internal override returns (bytes4) {
        console.log("afterInitialize");
        poolManager.updateDynamicLPFee(key, 0);
        return (BaseHook.afterInitialize.selector);
    }

    function _afterAddLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        console.log("afterAddLiquidity");
        return (BaseHook.afterAddLiquidity.selector, delta);
    }

    function _afterRemoveLiquidity(
        address sender,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        BalanceDelta delta,
        BalanceDelta feesAccrued,
        bytes calldata hookData
    ) internal override returns (bytes4, BalanceDelta) {
        console.log("afterRemoveLiquidity");
        return (BaseHook.afterRemoveLiquidity.selector, delta);
    }

    function _beforeSwap(
        address sender,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        console.log("beforeSwap");
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, IPoolManager.SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        return (BaseHook.afterSwap.selector, 0);
    }
    
    function _afterDonate(
        address sender,
        PoolKey calldata key,
        uint256 amount0,
        uint256 amount1,
        bytes calldata hookData
    ) internal override  returns (bytes4) {
        console.log("afterDonate");
        return BaseHook.afterDonate.selector;
    }

    function isTimeToRun() internal view returns (bool) {
        uint256 timeSinceLastRun = block.timestamp - computeNode.lastRun;
        return timeSinceLastRun > computeNode.downTime;
    }

    function requestJob(
    ) internal  { 
        emit RequestJob(
            address(this),
            address(this),
            computeNode.resolver,
            usedNonces,
            computeNode.resolverURL,
            computeNode.containerName
        );
    }

    function fulfillJob() onlyComputeNode() public {
        usedNonces++;
        console.log("fulfillJob");
    }

    function setComputePrice(
        address payoutCurrency,
        uint256 payoutAmount
    ) onlyComputeNode() public {
        computeNode.payoutCurrency = payoutCurrency;
        computeNode.payoutAmount = payoutAmount;
    }

    function getComputePrice() public view returns (address, uint256) {
        return (computeNode.payoutCurrency, computeNode.payoutAmount);
    }

    function changeComputeNode(ComputeNode memory newComputeNode) onlyComputeNode() public {
        computeNode = newComputeNode;
    }

    function getHookData(address user) public pure returns (bytes memory) {
        return abi.encode(user);
    }

    function parseHookData(
        bytes calldata data
    ) public pure returns (address user) {
        return abi.decode(data, (address));
    }

}
