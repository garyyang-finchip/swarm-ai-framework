// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {SwarmRegistry} from "../assets/erc-sai/contracts/SwarmRegistry.sol";

/// Deploys a SwarmRegistry with no resource adapters and records the addresses under
/// deployments/<chainId>.json. Foundry deploys and links the external libraries
/// (SpecValidator, LifecycleLib, MembershipLib, ResourceLib) automatically.
///
///   forge script script/DeployRegistry.s.sol --rpc-url $RPC --broadcast --private-key $PK
contract DeployRegistry is Script {
    function run() external {
        vm.startBroadcast();
        SwarmRegistry reg = new SwarmRegistry(new bytes32[](0), new address[](0));
        vm.stopBroadcast();

        console2.log("SwarmRegistry", address(reg));
        string memory json = "deployment";
        vm.serializeUint(json, "chainId", block.chainid);
        vm.serializeAddress(json, "SwarmRegistry", address(reg));
        string memory out = vm.serializeString(json, "clockMode", reg.CLOCK_MODE());
        vm.writeJson(out, string.concat("deployments/", vm.toString(block.chainid), ".json"));
    }
}
