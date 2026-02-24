# Task: Test the TLSN Verifier `/verify/oauth` endpoint

Write and run a Node.js script (using ethers v6 which is already installed in this repo) to test the verifier's `/verify/oauth` endpoint running at `http://localhost:3000`.

## What the endpoint does

It accepts an OAuth credential message + signature, validates it, and returns a signed attestation. The server is running in **dev mode**, which means signer validation is skipped — but the signature must still be a valid ECDSA signature over the correct message hash.

## How to construct the request

### 1. Create a signer (any random wallet works in dev mode)

```js
const { ethers } = require("ethers");
const wallet = ethers.Wallet.createRandom();
```

### 2. Build the OAuth message

```js
const message = {
  domain: "github.com",
  userId: "testuser123",
  score: "30",       // must be >= credential group's min score (uint256 as string)
  timestamp: "1700000000"  // uint256 as string
};
```

### 3. Sign the message

The signature must be over `keccak256(abi.encode(string, string, uint256, uint256))`:

```js
const encoded = ethers.AbiCoder.defaultAbiCoder().encode(
  ["string", "string", "uint256", "uint256"],
  [message.domain, message.userId, message.score, message.timestamp]
);
const hash = ethers.keccak256(encoded);
const signature = await wallet.signMessage(ethers.getBytes(hash));
```

### 4. Send the request

```js
const body = {
  message: message,
  signature: signature,
  registry: "0x17a22f130d4e1c4ba5C20a679a5a29F227083A62",
  chain_id: "84532",          // Base Sepolia
  credential_group_id: "5",   // github.com, min score 30
  app_id: "1",
  semaphore_identity_commitment: "12345"
};

const res = await fetch("http://localhost:3000/verify/oauth", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify(body)
});
```

### 5. Validate the response

The response should be:

```json
{
  "attestation": {
    "registry": "0x17a22f130d4e1c4ba5c20a679a5a29f227083a62",
    "chain_id": 84532,
    "credential_group_id": "...",
    "credential_id": "0x...",
    "app_id": "1",
    "semaphore_identity_commitment": "12345",
    "issued_at": 1740268800
  },
  "verifier_hash": "0x...",
  "signature": "0x..."
}
```

Verify:
- `attestation.chain_id` is `84532` (number, not string)
- `attestation.registry` is the address you sent
- `attestation.credential_group_id` is `"5"`
- `attestation.app_id` is `"1"`
- `attestation.semaphore_identity_commitment` is `"12345"`
- `attestation.issued_at` is a recent unix timestamp (number)
- `verifier_hash` matches `keccak256(abi.encode(registry, chainId, credentialGroupId, credentialId, appId, semaphoreIdentityCommitment, issuedAt))` with Solidity types `(address, uint256, uint256, bytes32, uint256, uint256, uint256)`
- `signature` recovers to verifier address `0x3c50f7055D804b51e506Bc1EA7D082cB1548376C`

### 6. Test error cases

Also test these should fail:
- **Missing `chain_id`** → should return 422
- **Invalid `chain_id: "1"`** → should return 400 with "unsupported chain_id"
- **Wrong domain** (e.g. `domain: "x.com"` with `credential_group_id: "5"` which expects `github.com`) → should return 400

## Available credential groups for testing

| ID | Domain | Min Score |
|----|--------|-----------|
| 1 | farcaster.xyz | 10 |
| 4 | github.com | 10 |
| 5 | github.com | 30 |
| 7 | x.com | 10 |
| 10 | zkpassport.id | 100 |
| 11 | self.xyz | 100 |

## Important notes

- Run the script from `/home/claude/credential-registry` (that's where `ethers` is installed)
- All uint256 values in the request body are **strings**
- `chain_id` in the request is a **string**, but in the response `attestation.chain_id` is a **number**
- The script should print clear pass/fail results for each check
