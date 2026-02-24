# Migration Instructions — BringID Relayer (v2 → v3)

## Overview

The Relayer executes blockchain operations via a relayer wallet with transaction tracking and retries. It receives pre-encoded calldata from the task-manager and sends transactions.

## Required Changes

### 1. Contract Addresses

**File:** Environment variables or config files

```diff
- REGISTRY_ADDRESS=0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe
+ REGISTRY_ADDRESS=0x17a22f130d4e1c4ba5C20a679a5a29F227083A62
```

Semaphore address is unchanged: `0x8A1fd199516489B0Fb7153EB5f075cDAC83c693D`.

### 2. Contract Error Handling — Custom Errors Replace Strings (CRITICAL)

**File:** `src/utils/error-parser.js`

All `"BID::..."` error strings have been replaced with typed custom errors. Update the error parser to decode custom error selectors instead of matching strings:

```diff
  // Old: string-based error matching
- 'BID::already registered': 'ALREADY_REGISTERED',
- 'BID::not registered': 'NOT_REGISTERED',
- 'BID::app not active': 'APP_NOT_ACTIVE',
- 'BID::attestation expired': 'ATTESTATION_EXPIRED',
- 'BID::credential group not active': 'CREDENTIAL_GROUP_NOT_ACTIVE',
- 'BID::recovery pending': 'RECOVERY_PENDING',
- 'BID::not expired': 'NOT_EXPIRED',

  // New: custom error selectors (import from Errors.sol ABI)
+ AlreadyRegistered(): 'ALREADY_REGISTERED',
+ NotRegistered(): 'NOT_REGISTERED',
+ AppNotActive(): 'APP_NOT_ACTIVE',
+ AttestationExpired(): 'ATTESTATION_EXPIRED',
+ CredentialGroupInactive(): 'CREDENTIAL_GROUP_NOT_ACTIVE',
+ RecoveryPending(): 'RECOVERY_PENDING',
+ NotYetExpired(): 'NOT_EXPIRED',
```

New errors to handle:

| Custom Error | Code |
|---|---|
| `WrongChain()` | `WRONG_CHAIN` |
| `InvalidCommitment()` | `INVALID_COMMITMENT` |
| `DuplicateCredentialGroup()` | `DUPLICATE_CREDENTIAL_GROUP` |
| `InvalidScorerContract()` | `INVALID_SCORER_CONTRACT` |
| `ScopeMismatch()` | `SCOPE_MISMATCH` |
| `FutureAttestation()` | `FUTURE_ATTESTATION` |
| `AppIdMismatch()` | `APP_ID_MISMATCH` |

To decode custom errors, use the contract ABI:

```javascript
const iface = new ethers.Interface(registryAbi)
try {
  const decoded = iface.parseError(revertData)
  // decoded.name === 'AlreadyRegistered', 'NotRegistered', etc.
} catch {
  // Unknown error
}
```

### 3. Error-to-Warn Configuration

**File:** `configs/error-to-warn.json`

Update error codes to match new custom error names:

```diff
  {
-   "ALREADY_REGISTERED": { "warn": true },
-   "ATTESTATION_EXPIRED": { "warn": true }
+   "AlreadyRegistered": { "warn": true },
+   "AttestationExpired": { "warn": true }
  }
```

### 4. Simulation ABI Update

If the relayer simulates transactions before sending, update the ABI for proof functions. All proof functions now take `appId` as the first parameter:

```diff
- 'function submitProofs(uint256 context, (uint256 credentialGroupId, uint256 appId, ...) [] proofs) returns (uint256)'
+ 'function submitProofs(uint256 appId, uint256 context, (uint256 credentialGroupId, uint256 appId, ...) [] proofs) returns (uint256)'
```

### 5. Re-registration

All apps must be re-registered on the new contract. The relayer itself does not need to re-register, but app IDs used in calldata will differ. Ensure the task-manager provides updated app IDs.

## No Changes Required

- The relayer receives pre-encoded calldata (`data` field) from the task-manager, so most ABI changes in calldata construction are handled by the task-manager
- Operation lifecycle and status tracking
- Transaction retry logic and gas management
- Nonce queue management
- MongoDB models and schemas
- API endpoints (`/operations/execute`, `/operations/:id/status`)
- General infrastructure (Express, MongoDB, cron)
