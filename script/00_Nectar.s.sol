// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";

import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";

import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

import {Constants} from "./base/Constants.sol";
import {Nectar, ComputeNode} from "../src/Nectar.sol";

/// @notice Mines the address and deploys the Nectar.sol Hook contract
contract NectarScript is Script, Constants {
    address eas = 0xA1207F3BBa224E2c9c3c6D5aF63D0eb1582Ce587;
    address schemaRegistry =  0xA7b39296258348C78294F95B872b282326A97BDF;
    address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address resolver = makeAddr("resolver");
    ComputeNode computeNode = ComputeNode({
        containerName: "cowsay:latest",
        resolverURL: "https://compute.node.com",
        resolver: resolver,
        payoutCurrency: usdc,
        payoutAmount: 10*10**18,
        lastRun: 0,
        downTime: 3600 * 24 * 7 // 1 week
    });

    function setUp() public {}
    function run() public {
        // hook contracts must have specific flags encoded in the address
        uint160 flags = uint160(
            Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG
                | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG | Hooks.BEFORE_DONATE_FLAG | Hooks.AFTER_DONATE_FLAG
        );

        // Mine a salt that will produce a hook address with the correct flags
        bytes memory constructorArgs = abi.encode(POOLMANAGER);
        (address hookAddress, bytes32 salt) =
            HookMiner.find(CREATE2_DEPLOYER, flags, type(Nectar).creationCode, constructorArgs);

        // Deploy the hook using CREATE2
        vm.broadcast();

        
        Nectar nectar = new Nectar{salt: salt}(
            IPoolManager(POOLMANAGER),
            eas,
            schemaRegistry,
            computeNode
        );
        require(address(nectar) == hookAddress, "NectarScript: hook address mismatch");
    }
}
