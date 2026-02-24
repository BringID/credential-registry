# Migration Instructions — TLSN Verifier (v2 → v3)

## Overview

The TLSN Verifier validates TLSN presentations (ZK-TLS proofs), OAuth tokens, zkPassport proofs, and other verification methods. It derives a `credentialId` from the verified identity, constructs an `Attestation` struct, signs it with the trusted verifier private key, and returns the signed attestation to the caller (widget).

The verifier is directly responsible for attestation construction and signing — **every attestation field change is a critical update**.

## Required Changes

### 1. Attestation Struct — `chainId` Field (CRITICAL)

The `Attestation` struct has a new `chainId` field at position 2. This is the **most critical change** — it alters the ABI encoding and therefore the hash that gets signed.

```diff
  struct Attestation {
      address registry;
+     uint256 chainId;
      uint256 credentialGroupId;
      bytes32 credentialId;
      uint256 appId;
      uint256 semaphoreIdentityCommitment;
      uint256 issuedAt;
  }
```

The contract enforces `attestation.chainId == block.chainid` and reverts with `WrongChain()` on mismatch.

### 2. Attestation Hashing — Updated Encoding (CRITICAL)

The attestation hash used for ECDSA signing must include `chainId`:

```diff
  // Old: 6 fields
  const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
-   ['address', 'uint256', 'bytes32', 'uint256', 'uint256', 'uint256'],
-   [registry, credentialGroupId, credentialId, appId, commitment, issuedAt]
+   ['address', 'uint256', 'uint256', 'bytes32', 'uint256', 'uint256', 'uint256'],
+   [registry, chainId, credentialGroupId, credentialId, appId, commitment, issuedAt]
  )

  const hash = ethers.keccak256(encoded)
  const signature = await signer.signMessage(ethers.getBytes(hash))
```

The contract verifies using:
```solidity
signer = keccak256(abi.encode(attestation_)).toEthSignedMessageHash().recover(v, r, s);
```

If `chainId` is missing or in the wrong position, the recovered signer will not match the trusted verifier and the contract will revert with `UntrustedVerifier()`.

### 3. Contract Address — `registry` Field

Update the `registry` field in all attestations to the new contract address:

```diff
- registry: '0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe'
+ registry: '0x17a22f130d4e1c4ba5C20a679a5a29F227083A62'
```

The contract enforces `attestation.registry == address(this)` and reverts with `WrongRegistryAddress()` on mismatch.

### 4. Chain ID Values

The verifier must set the correct `chainId` based on the target chain:

| Chain | Chain ID |
|---|---|
| Base Mainnet | `8453` |
| Base Sepolia | `84532` |

The verifier should either:
- Accept `chain_id` from the request and validate it against a known allowlist, or
- Determine the chain ID from its own configuration based on the deployment environment

### 5. API Response — `chain_id` Field

Add `chain_id` to the attestation response:

```diff
  {
    attestation: {
      registry: string,
+     chain_id: string,
      credential_group_id: string,
      credential_id: string,
      app_id: string,
      semaphore_identity_commitment: string,
      issued_at: string
    },
    signature: string
  }
```

### 6. API Request — `chain_id` Field

If the verifier needs the chain ID from the caller (e.g., to support multiple chains), add it to all verification endpoints:

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

  // POST /verify/oauth
  {
    message: { ... },
    signature: string,
    registry: string,
+   chain_id: string,
    credential_group_id: string,
    app_id: string,
    semaphore_identity_commitment: string
  }
```

Validate that the provided `chain_id` is one of the supported values (`8453` or `84532`).

### 7. Error Responses — New Contract Errors

If the verifier simulates attestation verification on-chain before responding, update error handling for new custom errors:

| Old (string) | New (custom error) |
|---|---|
| `"BID::credential group inactive"` | `CredentialGroupInactive()` |
| `"BID::app not active"` | `AppNotActive()` |
| `"BID::wrong registry address"` | `WrongRegistryAddress()` |
| `"BID::attestation expired"` | `AttestationExpired()` |
| `"BID::untrusted verifier"` | `UntrustedVerifier()` |
| _(new)_ | `WrongChain()` |
| _(new)_ | `FutureAttestation()` |

### 8. Attestation Validation Checks

The contract now performs an additional check that was not present before:

- **`FutureAttestation()`** — `attestation.issuedAt > block.timestamp` is rejected. The verifier must ensure `issuedAt` is not ahead of the on-chain block timestamp. Use `Math.floor(Date.now() / 1000)` and do not add any forward offset.
- **`WrongChain()`** — `attestation.chainId != block.chainid` is rejected.

### 9. Environment Variables

Update or add:

```diff
- REGISTRY_ADDRESS=0xfd600B14Dc5A145ec9293Fd5768ae10Ccc1E91Fe
+ REGISTRY_ADDRESS=0x17a22f130d4e1c4ba5C20a679a5a29F227083A62
```

Ensure `CHAIN_ID` or equivalent config is available if the verifier serves multiple chains.

## Example — Full Attestation Construction (JavaScript)

```javascript
import { ethers } from 'ethers'

const chainId = 84532 // Base Sepolia
const attestation = {
  registry: '0x17a22f130d4e1c4ba5C20a679a5a29F227083A62',
  chainId,
  credentialGroupId,
  credentialId,
  appId,
  semaphoreIdentityCommitment: commitment,
  issuedAt: Math.floor(Date.now() / 1000)
}

// ABI-encode (must match Solidity's abi.encode order exactly)
const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
  ['address', 'uint256', 'uint256', 'bytes32', 'uint256', 'uint256', 'uint256'],
  [
    attestation.registry,
    attestation.chainId,
    attestation.credentialGroupId,
    attestation.credentialId,
    attestation.appId,
    attestation.semaphoreIdentityCommitment,
    attestation.issuedAt
  ]
)

// Sign as EthSignedMessage (matches toEthSignedMessageHash on-chain)
const hash = ethers.keccak256(encoded)
const signature = await verifierWallet.signMessage(ethers.getBytes(hash))
```

## No Changes Required

- TLSN presentation validation logic
- OAuth token validation logic
- `credentialId` derivation from verified identity
- Semaphore identity commitment handling
- Verifier private key management
- Rate limiting and access control
- Credential group ID values (unchanged from v2)
