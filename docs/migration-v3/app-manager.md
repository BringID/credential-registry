# Migration Instructions — BringID App Manager Dashboard (v2 → v3)

## Overview

The App Manager is a Next.js web dashboard for third-party app developers to self-manage their BringID integration. App admins connect their wallet and manage their app's settings, custom scoring, and lifecycle via direct contract calls. See `docs/app-manager-specs.md` for the full spec.

## Required Changes

### 1. Contract Addresses

Update all hardcoded or configured contract addresses:

```diff
- REGISTRY_ADDRESS=0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe
+ REGISTRY_ADDRESS=0x17a22f130d4e1c4ba5C20a679a5a29F227083A62

- DEFAULT_SCORER_ADDRESS=0x6a0b5ba649C7667A0C4Cd7FE8a83484AEE6C5345
+ DEFAULT_SCORER_ADDRESS=0x6791B588dAdeb4323bc1C3d987130bC13cBe3625

- SCORER_FACTORY_ADDRESS=0x05321FAAD6315a04d5024Ee5b175AB1C62a3fd44
+ SCORER_FACTORY_ADDRESS=0x016bC46169533a8d3284c5D8DD590C91783C8C06
```

Contract ABIs have changed — re-extract from `out/CredentialRegistry.sol/CredentialRegistry.json` and `out/DefaultScorer.sol/DefaultScorer.json` after building the v3 contracts.

### 2. App ID Generation — Hash-Based, Non-Sequential (CRITICAL)

**Affects:** My Apps list, app enumeration, Register App page

App IDs are no longer sequential auto-increment integers. They are now derived from a hash:

```diff
- appId = nextAppId++                                              // v2: sequential 1, 2, 3, …
+ appId = uint256(keccak256(abi.encodePacked(chainId, sender, nonce)))  // v3: hash-based
```

The `nextAppId` storage variable still exists but it is now a **nonce counter** used as an input to the hash, not the next app ID itself. You cannot enumerate apps by iterating `1..nextAppId`.

**Impact on "My Apps" list:** The enumeration strategy from the specs (using `nextAppId()` to bound iteration) no longer works. You **must** rely on event indexing to discover app IDs:

```diff
  // Old: iterate 1..nextAppId and check admin
- for (let id = 1; id < nextAppId; id++) {
-   const app = await registry.read.apps([id])
-   if (app.admin === connectedAddress) myApps.push(id)
- }

  // New: index AppRegistered + AppAdminTransferred events
+ const created = await publicClient.getLogs({
+   address: REGISTRY_ADDRESS,
+   event: parseAbiItem('event AppRegistered(uint256 indexed appId, address indexed admin, uint256 recoveryTimelock)'),
+   args: { admin: connectedAddress },
+   fromBlock: DEPLOY_BLOCK,
+ })
+ const received = await publicClient.getLogs({
+   address: REGISTRY_ADDRESS,
+   event: parseAbiItem('event AppAdminTransferred(uint256 indexed appId, address indexed oldAdmin, address indexed newAdmin)'),
+   args: { newAdmin: connectedAddress },
+   fromBlock: DEPLOY_BLOCK,
+ })
```

The `registerApp()` return value is still the assigned `appId` — capture it from the transaction receipt.

### 3. Admin Transfer — Two-Step Process (CRITICAL)

**Affects:** App Detail / Settings page (Admin Transfer section)

`setAppAdmin()` has been replaced with a two-step transfer pattern:

```diff
- function setAppAdmin(uint256 appId, address newAdmin) external;
+ function transferAppAdmin(uint256 appId, address newAdmin) external;  // Step 1: initiate
+ function acceptAppAdmin(uint256 appId) external;                      // Step 2: accept
```

**UI changes required:**

- **Initiating admin (current admin):** Call `transferAppAdmin(appId, newAdmin)`. The warning "This is irreversible" is no longer accurate — the transfer is pending until accepted.
- **Accepting admin (new admin):** Add a new UI section for pending incoming transfers. Query `pendingAppAdmin(appId)` to check if the connected wallet has pending transfers to accept.
- **New event:** `AppAdminTransferInitiated(appId, currentAdmin, newAdmin)` fires on `transferAppAdmin()`. The existing `AppAdminTransferred(appId, oldAdmin, newAdmin)` fires on `acceptAppAdmin()`.

```diff
  // Old: single transaction
- await registry.write.setAppAdmin([appId, newAdmin])

  // New: two-step
+ // Current admin initiates:
+ await registry.write.transferAppAdmin([appId, newAdmin])
+ // New admin accepts:
+ await registry.write.acceptAppAdmin([appId])
```

**Event indexing update** — add `AppAdminTransferInitiated` to track pending transfers:

```diff
  // Events to index
  AppRegistered(appId, admin, recoveryTimelock)
+ AppAdminTransferInitiated(appId, currentAdmin, newAdmin)   // NEW: pending transfers
  AppAdminTransferred(appId, oldAdmin, newAdmin)
  AppStatusChanged(appId, status)
  AppScorerSet(appId, scorer)
  AppRecoveryTimelockSet(appId, timelock)
```

### 4. Event Names — `AppStatusChanged` Replaces Separate Events

**Affects:** My Apps list, App Detail page, event indexing

The separate `AppSuspended` and `AppActivated` events have been replaced with a single `AppStatusChanged` event carrying an `AppStatus` enum:

```diff
- event AppSuspended(uint256 indexed appId);
- event AppActivated(uint256 indexed appId);
+ event AppStatusChanged(uint256 indexed appId, ICredentialRegistry.AppStatus status);
```

`AppStatus` enum values: `UNDEFINED (0)`, `ACTIVE (1)`, `SUSPENDED (2)`.

Update event indexing:

```diff
- const suspended = await publicClient.getLogs({
-   event: parseAbiItem('event AppSuspended(uint256 indexed appId)'),
- })
- const activated = await publicClient.getLogs({
-   event: parseAbiItem('event AppActivated(uint256 indexed appId)'),
- })

+ const statusChanges = await publicClient.getLogs({
+   event: parseAbiItem('event AppStatusChanged(uint256 indexed appId, uint8 status)'),
+   fromBlock: DEPLOY_BLOCK,
+ })
+ // status === 1 → ACTIVE, status === 2 → SUSPENDED
```

### 5. Scorer Validation — ERC165 On-Chain Check

**Affects:** App Detail / Scorer Configuration section, Deploy Custom Scorer page

`setAppScorer()` now validates the scorer contract on-chain via `ERC165Checker.supportsInterface()`. If the scorer does not implement the `IScorer` interface ID, the transaction reverts with `InvalidScorerContract()`.

The specs recommended a client-side `getAllScores()` try-call before submitting. This is still useful for UX (prevents wasting gas), but the contract now enforces validation regardless:

```diff
  // Client-side validation (unchanged, still recommended for UX)
  try {
    await scorer.read.getAllScores()
  } catch {
    showError('This address does not implement the IScorer interface.')
    return
  }

  // Contract-side validation (NEW in v3 — will revert if scorer is invalid)
  await registry.write.setAppScorer([appId, scorerAddress])
+ // Reverts with InvalidScorerContract() if scorer doesn't support IScorer interface
```

**Custom scorer deployment** — scorers deployed via `ScorerFactory.create()` already implement `IERC165` and will pass validation. If app admins deploy custom scorer contracts manually, they **must** implement `supportsInterface()`:

```solidity
import {IScorer} from "@bringid/contracts/interfaces/IScorer.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract MyScorer is IScorer {
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IScorer).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
    // ... getScore, getScores, getAllScores implementations
}
```

### 6. Error Handling — Custom Errors Replace Strings

**Affects:** All pages with contract interactions

All `"BID::..."` error strings have been replaced with typed custom errors. Update error parsing throughout the dashboard:

```diff
- if (error.message.includes('BID::app not active')) {
-   showError('This app is currently suspended.')
- }

+ // Decode custom error from revert data
+ import { decodeErrorResult } from 'viem'
+ const decoded = decodeErrorResult({ abi: registryAbi, data: error.data })
+ switch (decoded.errorName) {
+   case 'AppNotActive':
+     showError('This app is currently suspended.')
+     break
+   case 'NotAppAdmin':
+     showError('You are not the admin of this app.')
+     break
+   case 'AppNotSuspended':
+     showError('This app is already active.')
+     break
+ }
```

App management error mapping:

| Old (string) | New (custom error) | User Message |
|---|---|---|
| _(string match)_ | `NotAppAdmin()` | You are not the admin of this app. |
| _(string match)_ | `AppNotActive()` | This app is currently suspended. |
| _(string match)_ | `AppNotSuspended()` | This app is already active. |
| _(new)_ | `InvalidAdminAddress()` | Invalid admin address (cannot be zero). |
| _(new)_ | `NotPendingAdmin()` | You are not the pending admin for this app. |
| _(new)_ | `InvalidScorerContract()` | This address does not implement the IScorer interface. |
| _(new)_ | `InvalidScorerAddress()` | Invalid scorer address (cannot be zero). |

### 7. New Feature — Merkle Tree Duration Configuration

**Affects:** App Detail / Settings page (new section)

v3 adds per-app Merkle tree duration configuration. App admins can override the registry-level default:

```typescript
// Read current per-app override (0 = using registry default)
const appDuration = await registry.read.appMerkleTreeDuration([appId])

// Read registry default
const defaultDuration = await registry.read.defaultMerkleTreeDuration()

// Set per-app override (admin-only)
await registry.write.setAppMerkleTreeDuration([appId, durationInSeconds])

// Clear override (revert to registry default)
await registry.write.setAppMerkleTreeDuration([appId, 0n])
```

The dashboard should add a "Merkle Tree Duration" section to the App Detail page:
- Show current effective duration (per-app override if set, otherwise registry default)
- Input field for seconds with human-readable preview
- Note: setting to 0 reverts to the registry default
- Note: updating propagates to all existing Semaphore groups for the app

New event to index: `AppMerkleTreeDurationSet(uint256 indexed appId, uint256 merkleTreeDuration)`.

### 8. New View Function — `getAppSemaphoreGroupIds`

**Affects:** App Detail page (optional enhancement)

v3 adds a view function to retrieve all Semaphore group IDs for an app:

```typescript
const groupIds = await registry.read.getAppSemaphoreGroupIds([appId])
```

This can be used to show how many credential groups have active Semaphore groups for the app, or for debugging purposes.

### 9. Re-registration

All apps must be re-registered on the new contract. Existing app IDs from the previous deployment (`0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe`) are not valid on the new contract.

The dashboard should:
- Clear any cached/stored app IDs from the old contract
- Re-index events starting from the new contract's deployment block
- Prompt returning users to re-register their apps

## No Changes Required

- Wallet connection flow (wagmi + viem + ConnectKit/RainbowKit)
- Chain configuration (Base mainnet 8453 + Base Sepolia 84532)
- `registerApp(recoveryTimelock)` function signature (unchanged)
- `suspendApp(appId)` / `activateApp(appId)` function signatures (unchanged)
- `setAppRecoveryTimelock(appId, timelock)` function signature (unchanged)
- `ScorerFactory.create()` flow (unchanged)
- `DefaultScorer` read functions (`getScore`, `getScores`, `getAllScores`)
- Score Explorer page (credential group IDs and structure unchanged)
- General architecture (no backend, direct contract calls, event-based indexing)
