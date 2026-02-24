# Migration Instructions — BringID Widget (v2 → v3)

## Overview

The widget is a Next.js embeddable iframe that handles identity verification and Semaphore ZK proof generation. It communicates with the parent website via postMessage, manages OAuth and ZK-TLS flows, and calls backend APIs (verifier, task-manager, indexer).

## Required Changes

### 1. Contract Addresses

Update any hardcoded or configured contract addresses:

```diff
- REGISTRY_ADDRESS=0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe
+ REGISTRY_ADDRESS=0x17a22f130d4e1c4ba5C20a679a5a29F227083A62
```

### 2. Scope Formula — `appId` Included (CRITICAL)

**File:** Proof generation utilities

The scope for Semaphore proofs now includes `appId`:

```diff
- scope = keccak256(abi.encode(callerAddress, context))
+ scope = keccak256(abi.encode(appId, callerAddress, context))
```

In JavaScript:

```diff
  import { ethers } from 'ethers'

  const scope = ethers.keccak256(
    ethers.AbiCoder.defaultAbiCoder().encode(
-     ['address', 'uint256'],
-     [callerAddress, context]
+     ['uint256', 'address', 'uint256'],
+     [appId, callerAddress, context]
    )
  )
```

Where:
- `appId` — the app ID registered on the CredentialRegistry
- `callerAddress` — the on-chain caller (`msg.sender`), typically the relayer or consuming contract
- `context` — application-defined context value (e.g., 0)

Proofs generated with the old scope formula will fail with `ScopeMismatch()` or `InvalidProof()`.

### 3. Verifier API — `chain_id` in Attestation (CRITICAL)

**File:** `src/app/content/api/verifier/index.tsx`

The verifier response now includes `chain_id` in the attestation:

```diff
  const {
    attestation: {
      registry,
+     chain_id,
      credential_group_id,
      credential_id,
      app_id,
      semaphore_identity_commitment,
      issued_at
    },
    signature
  } = response
```

The `chain_id` must be included when constructing task-manager requests or any calldata that encodes the `Attestation` struct.

**Request changes** — add `chain_id` if the widget sends it explicitly:

```diff
  // POST /verify (ZK-TLS)
  {
    tlsn_presentation: string,
    registry: string,
+   chain_id: string,
    credential_group_id: string,
    app_id: string,
    semaphore_identity_commitment: string
  }
```

### 4. Task Manager API — `chain_id` Field

**File:** `src/app/content/api/task-manager/index.tsx`

Add `chain_id` to the task-manager verification request:

```diff
  {
    registry: string,
+   chain_id: string,
    credential_group_id: string,
    credential_id: string,
    app_id: string,
    identity_commitment: string,
    verifier_signature: string,
+   issued_at: string
  }
```

### 5. Indexer API — New Semaphore Group IDs

Per-app Semaphore group IDs have changed because the contract was redeployed. The widget must fetch fresh Semaphore group IDs from:

- The registry's `appSemaphoreGroups(credentialGroupId, appId)` mapping, or
- The new `getAppSemaphoreGroupIds(appId)` view function, or
- The task-manager/verifier response after registration

Old group IDs from the previous deployment are invalid.

### 6. Error Handling — Custom Errors

If the widget displays user-facing error messages based on contract revert reasons, update from string matching to custom error names:

```diff
- if (error.includes('BID::not registered')) { ... }
- if (error.includes('BID::already registered')) { ... }
- if (error.includes('BID::attestation expired')) { ... }
+ // Custom error selectors:
+ // NotRegistered()
+ // AlreadyRegistered()
+ // AttestationExpired()
+ // WrongChain()
+ // DuplicateCredentialGroup()
```

### 7. Verification Status / Task Data Model

**File:** `src/app/content/store/` (Redux reducers)

If the Redux store includes `chainId` in verification data:

```diff
  interface TVerification {
    status: 'pending' | 'completed' | 'failed'
    scheduledTime: number
    credentialGroupId: string
    appId: string
+   chainId: string
    batchId?: string | null
    txHash?: string
    fetched: boolean
    taskId: string
  }
```

### 8. Re-registration Flow

Existing credentials registered on the old contract (`0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe`) are not accessible from the new contract. Users will need to go through the full verification and registration flow again.

The widget should handle the case where a user who previously verified now needs to re-verify. Clear any cached verification status from the old contract.

## No Changes Required

- OAuth popup communication protocol (AUTH_SUCCESS / AUTH_ERROR)
- ZK-TLS extension communication protocol
- Theme support, URL parameters
- Plausible analytics events
- General postMessage architecture
- Semaphore identity derivation formula (unchanged — uses `keccak256(abi.encodePacked(masterKey, appId, credentialGroupId))`)
- Credential group IDs (unchanged from v2)
- Proof struct fields (`credential_group_id`, `app_id`, `semaphore_proof` — unchanged)
- `PROOFS_REQUEST` / `PROOFS_RESPONSE` message format (unchanged from v2)
