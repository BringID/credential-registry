// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {CredentialRegistry} from "../contracts/registry/CredentialRegistry.sol";
import {ICredentialRegistry} from "@bringid/contracts/interfaces/ICredentialRegistry.sol";
import {DefaultScorer} from "@bringid/contracts/scoring/DefaultScorer.sol";
import {Script, console} from "forge-std/Script.sol";

/// @notice Adds Reddit (zkTLS) credential groups to an existing CredentialRegistry.
///
///  ID | Credential | Group  | Family | Duration | Score
///  ---|------------|--------|--------|----------|------
///  16 | Reddit     | Low    |   4    | 30 days  |   2
///  17 | Reddit     | Medium |   4    | 60 days  |   5
///  18 | Reddit     | High   |   4    | 90 days  |  10
///
/// Usage:
///   PRIVATE_KEY=<key> CREDENTIAL_REGISTRY_ADDRESS=0x17a22f130d4e1c4ba5C20a679a5a29F227083A62 \
///     forge script script/AddRedditGroups.s.sol:AddRedditGroups \
///     --rpc-url <rpc> --broadcast
contract AddRedditGroups is Script {
    function run() public {
        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        CredentialRegistry registry = CredentialRegistry(vm.envAddress("CREDENTIAL_REGISTRY_ADDRESS"));
        DefaultScorer scorer = DefaultScorer(registry.defaultScorer());

        // --- Reddit credential groups (family 4) ---
        uint256[] memory ids = new uint256[](3);
        uint256[] memory durations = new uint256[](3);
        uint256[] memory families = new uint256[](3);
        uint256[] memory scores = new uint256[](3);

        // Reddit Low — 30 days, score 2
        ids[0] = 16;
        durations[0] = 30 days;
        families[0] = 4;
        scores[0] = 2;

        // Reddit Medium — 60 days, score 5
        ids[1] = 17;
        durations[1] = 60 days;
        families[1] = 4;
        scores[1] = 5;

        // Reddit High — 90 days, score 10
        ids[2] = 18;
        durations[2] = 90 days;
        families[2] = 4;
        scores[2] = 10;

        // Create credential groups that don't already exist
        for (uint256 i = 0; i < ids.length; i++) {
            (ICredentialRegistry.CredentialGroupStatus status,,) = registry.credentialGroups(ids[i]);
            if (status == ICredentialRegistry.CredentialGroupStatus.UNDEFINED) {
                registry.createCredentialGroup(ids[i], durations[i], families[i]);
                console.log("Created group %d", ids[i]);
            } else {
                console.log("Group %d already exists, skipping", ids[i]);
            }
        }

        // Set scores on the DefaultScorer
        scorer.setScores(ids, scores);

        vm.stopBroadcast();

        // --- verification logging ---
        for (uint256 i = 0; i < ids.length; i++) {
            (ICredentialRegistry.CredentialGroupStatus status,,) = registry.credentialGroups(ids[i]);
            uint256 score = scorer.getScore(ids[i]);
            console.log("Group %d: status=%d, score=%d", ids[i], uint256(status), score);
        }
    }
}
