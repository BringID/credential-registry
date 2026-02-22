// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {CredentialRegistry} from "../contracts/registry/CredentialRegistry.sol";
import {ICredentialRegistry} from "@bringid/contracts/interfaces/ICredentialRegistry.sol";
import {Script, console} from "forge-std/Script.sol";

contract RegisterApps is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));
        CredentialRegistry registry;
        if (vm.envAddress("CREDENTIAL_REGISTRY_ADDRESS") != address(0)) {
            registry = CredentialRegistry(vm.envAddress("CREDENTIAL_REGISTRY_ADDRESS"));
        } else {
            revert("CREDENTIAL_REGISTRY_ADDRESS should be provided");
        }

        uint256 appId = registry.registerApp(0);
        vm.stopBroadcast();

        console.log("Registered app ID:", appId);
        console.log("On registry:", address(registry));
    }
}
