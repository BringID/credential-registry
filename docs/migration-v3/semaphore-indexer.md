# Migration Instructions — BringID Semaphore Indexer (v2 → v3)

## Overview

The Semaphore Indexer indexes Semaphore group members and returns Merkle proofs for identity commitments. It reads from a PostgreSQL database that mirrors on-chain Semaphore group state.

## Required Changes

### 1. Contract Addresses

Update the CredentialRegistry address used for event monitoring or group discovery:

```diff
- REGISTRY_ADDRESS=0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe
+ REGISTRY_ADDRESS=0xbF9b2556e6Dd64D60E08E3669CeF2a4293e006db
```

Semaphore address is unchanged: `0x8A1fd199516489B0Fb7153EB5f075cDAC83c693D`.

### 2. Database Re-Indexing (CRITICAL)

The contracts were redeployed, creating a new CredentialRegistry with new per-app Semaphore groups. All Semaphore group IDs from the old deployment are invalid.

After switching to the new contract:
- Drop or archive old member data from the previous deployment's Semaphore groups
- Re-index from the Semaphore contract's events starting from the new CredentialRegistry's deployment block
- The `AppSemaphoreGroupCreated(credentialGroupId, appId, semaphoreGroupId)` event on the new registry identifies which Semaphore groups to index

### 3. New View Function: `getAppSemaphoreGroupIds`

The new registry exposes `getAppSemaphoreGroupIds(uint256 appId)` which returns all Semaphore group IDs for an app. This can be used for group discovery instead of relying solely on events:

```typescript
const groupIds = await registry.getAppSemaphoreGroupIds(appId)
```

### 4. Event Monitoring — Updated Event Signatures

If the indexer monitors CredentialRegistry events for group discovery, update event signatures:

**New events to monitor:**
- `DefaultMerkleTreeDurationSet(uint256 indexed duration)` — registry-level Merkle tree duration changes
- `AppMerkleTreeDurationSet(uint256 indexed appId, uint256 merkleTreeDuration)` — per-app Merkle tree duration changes

**Removed events:**
- `CredentialGroupFamilySet` — no longer emitted (family ID immutable after creation)

**Unchanged events:**
- `AppSemaphoreGroupCreated(uint256 indexed credentialGroupId, uint256 indexed appId, uint256 semaphoreGroupId)`
- `CredentialRegistered(...)`
- `CredentialExpired(...)`
- `RecoveryExecuted(...)`

## No Changes Required

- Semaphore contract address is unchanged
- API endpoint contracts (`GET /proofs`, `POST /proofs`) remain the same
- Merkle proof generation logic (uses @semaphore-protocol/group)
- Request validation schemas
- Error handling patterns
- PostgreSQL model schema (member model structure is unchanged)
- Authentication (API key validation)
- Semaphore `MemberAdded`/`MemberRemoved` event signatures are unchanged
