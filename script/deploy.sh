#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# BringID Credential Registry — Deployment Script
#
# Usage:
#   ./script/deploy.sh sepolia                    # Deploy to Base Sepolia
#   ./script/deploy.sh mainnet                    # Deploy to Base Mainnet
#   ./script/deploy.sh sepolia --dry-run          # Simulate without broadcasting
#   ./script/deploy.sh sepolia --skip-credential-groups --skip-apps
#
# Flags:
#   --skip-credential-groups  Skip credential group creation and score setting
#   --skip-apps               Skip app registration
#   --skip-scorer-factory     Skip ScorerFactory deployment
#   --dry-run                 Simulate without broadcasting (no --broadcast flag)
#   --prebuilt                Skip compilation; use pre-built artifacts from out/
#                             (build on VPS with `make build-deploy-artifacts`, commit
#                             deploy-artifacts.tar.gz, then extract locally before deploying)
#
# Required env vars (in .env):
#   PRIVATE_KEY       — Deployer private key (hex, without 0x prefix)
#   ALCHEMY_API_KEY   — Alchemy API key for RPC
#
# Optional env vars:
#   BASESCAN_API_KEY  — Enables --verify on all forge script calls
# ──────────────────────────────────────────────────────────────────────────────

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Parse arguments ──────────────────────────────────────────────────────────
NETWORK=""
SKIP_CREDENTIAL_GROUPS=false
SKIP_APPS=false
SKIP_SCORER_FACTORY=false
DRY_RUN=false
PREBUILT=false

for arg in "$@"; do
  case "$arg" in
    sepolia|mainnet)
      NETWORK="$arg"
      ;;
    --skip-credential-groups)
      SKIP_CREDENTIAL_GROUPS=true
      ;;
    --skip-apps)
      SKIP_APPS=true
      ;;
    --skip-scorer-factory)
      SKIP_SCORER_FACTORY=true
      ;;
    --dry-run)
      DRY_RUN=true
      ;;
    --prebuilt)
      PREBUILT=true
      ;;
    *)
      echo -e "${RED}Unknown argument: $arg${NC}"
      echo "Usage: ./script/deploy.sh <sepolia|mainnet> [--skip-credential-groups] [--skip-apps] [--skip-scorer-factory] [--dry-run] [--prebuilt]"
      exit 1
      ;;
  esac
done

if [[ -z "$NETWORK" ]]; then
  echo -e "${RED}Error: Network argument required${NC}"
  echo "Usage: ./script/deploy.sh <sepolia|mainnet> [--skip-credential-groups] [--skip-apps] [--skip-scorer-factory] [--dry-run] [--prebuilt]"
  exit 1
fi

# ── Network configuration ────────────────────────────────────────────────────
SEMAPHORE_ADDRESS="0x8A1fd199516489B0Fb7153EB5f075cDAC83c693D"

if [[ "$NETWORK" == "sepolia" ]]; then
  CHAIN_ID=84532
  TRUSTED_VERIFIER="0x3c50f7055D804b51e506Bc1EA7D082cB1548376C"
  EXPLORER_URL="https://sepolia.basescan.org"
  NETWORK_LABEL="Base Sepolia"
else
  CHAIN_ID=8453
  TRUSTED_VERIFIER="0x9186aA65288bFfa67fB58255AeeaFfc4515535d9"
  EXPLORER_URL="https://basescan.org"
  NETWORK_LABEL="Base Mainnet"
fi

# ── Load .env ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ ! -f "$PROJECT_DIR/.env" ]]; then
  echo -e "${RED}Error: .env file not found at $PROJECT_DIR/.env${NC}"
  echo "Copy .env.example to .env and fill in the values:"
  echo "  cp .env.example .env"
  exit 1
fi

set -a
source "$PROJECT_DIR/.env"
set +a

# ── Validate required env vars ───────────────────────────────────────────────
missing_vars=()
[[ -z "${PRIVATE_KEY:-}" ]] && missing_vars+=("PRIVATE_KEY")
[[ -z "${ALCHEMY_API_KEY:-}" ]] && missing_vars+=("ALCHEMY_API_KEY")

if [[ ${#missing_vars[@]} -gt 0 ]]; then
  echo -e "${RED}Error: Missing required environment variables:${NC}"
  for var in "${missing_vars[@]}"; do
    echo "  - $var"
  done
  exit 1
fi

# Normalize PRIVATE_KEY to include 0x prefix (forge's vm.envUint requires it)
if [[ "$PRIVATE_KEY" != 0x* ]]; then
  export PRIVATE_KEY="0x$PRIVATE_KEY"
fi

# ── Construct RPC URL ─────────────────────────────────────────────────────────
if [[ "$NETWORK" == "sepolia" ]]; then
  RPC_URL="https://base-sepolia.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
else
  RPC_URL="https://base-mainnet.g.alchemy.com/v2/${ALCHEMY_API_KEY}"
fi

# ── Build verification flags ─────────────────────────────────────────────────
VERIFY_FLAGS=""
if [[ -n "${BASESCAN_API_KEY:-}" ]]; then
  VERIFY_FLAGS="--verify --etherscan-api-key $BASESCAN_API_KEY"
  echo -e "${GREEN}BaseScan verification enabled${NC}"
else
  echo -e "${YELLOW}BaseScan verification disabled (no BASESCAN_API_KEY)${NC}"
fi

# ── Build broadcast flag ─────────────────────────────────────────────────────
BROADCAST_FLAG="--broadcast"
if [[ "$DRY_RUN" == true ]]; then
  BROADCAST_FLAG=""
  VERIFY_FLAGS=""  # --verify requires --broadcast
  echo -e "${YELLOW}DRY RUN mode — no transactions will be broadcast${NC}"
fi

# ── Prebuilt artifacts ───────────────────────────────────────────────────────
SKIP_COMPILATION_FLAG=""
if [[ "$PREBUILT" == true ]]; then
  TARBALL="$PROJECT_DIR/deploy-artifacts.tar.gz"
  if [[ ! -f "$TARBALL" ]]; then
    echo -e "${RED}Error: --prebuilt requires deploy-artifacts.tar.gz in project root${NC}"
    echo "Build on VPS first:  make build-deploy-artifacts"
    exit 1
  fi
  echo -e "${CYAN}Extracting pre-built artifacts from deploy-artifacts.tar.gz${NC}"
  tar -xzf "$TARBALL" -C "$PROJECT_DIR"
  SKIP_COMPILATION_FLAG="--skip-compilation"
  echo -e "${GREEN}✓ Pre-built artifacts extracted${NC}"
fi

# ── Foundry profile for forge script calls ───────────────────────────────────
# Use default profile (via_ir=true) so forge script deploys the same optimized
# bytecode that Step 1 compiles. This ensures deployed contracts match the
# verified source on BaseScan without needing a separate verify-contract step.
# When --prebuilt is used, compilation is skipped entirely so the profile only
# affects non-compilation aspects of forge script.
FORGE_PROFILE="default"

# ── Pre-flight checks ────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Pre-flight checks${NC}"
echo "─────────────────────────────────────────"

# Check required tools
for cmd in forge cast jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo -e "${RED}Error: '$cmd' is not installed${NC}"
    exit 1
  fi
  echo -e "  ${GREEN}✓${NC} $cmd found"
done

# Check RPC is reachable and returns expected chain ID
echo -n "  Checking RPC connectivity... "
ACTUAL_CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null || true)
if [[ -z "$ACTUAL_CHAIN_ID" ]]; then
  echo -e "${RED}FAILED${NC}"
  echo -e "${RED}Error: Cannot reach RPC at $RPC_URL${NC}"
  exit 1
fi
if [[ "$ACTUAL_CHAIN_ID" != "$CHAIN_ID" ]]; then
  echo -e "${RED}FAILED${NC}"
  echo -e "${RED}Error: Expected chain ID $CHAIN_ID but got $ACTUAL_CHAIN_ID${NC}"
  exit 1
fi
echo -e "${GREEN}✓${NC} chain ID $CHAIN_ID"

# Check deployer balance
DEPLOYER_ADDRESS=$(cast wallet address --private-key "0x$PRIVATE_KEY" 2>/dev/null || cast wallet address --private-key "$PRIVATE_KEY" 2>/dev/null || true)
if [[ -z "$DEPLOYER_ADDRESS" ]]; then
  echo -e "${RED}Error: Could not derive deployer address from PRIVATE_KEY${NC}"
  exit 1
fi
echo -e "  Deployer: ${CYAN}$DEPLOYER_ADDRESS${NC}"

BALANCE_WEI=$(cast balance "$DEPLOYER_ADDRESS" --rpc-url "$RPC_URL" 2>/dev/null || true)
if [[ -z "$BALANCE_WEI" || "$BALANCE_WEI" == "0" ]]; then
  echo -e "${RED}Error: Deployer has zero ETH balance on $NETWORK_LABEL${NC}"
  exit 1
fi
BALANCE_ETH=$(cast from-wei "$BALANCE_WEI" 2>/dev/null || echo "$BALANCE_WEI wei")
echo -e "  Balance:  ${GREEN}$BALANCE_ETH ETH${NC}"

# ── Confirmation prompt ──────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Deployment Summary${NC}"
echo "─────────────────────────────────────────"
echo -e "  Network:           ${CYAN}$NETWORK_LABEL${NC} (chain ID $CHAIN_ID)"
echo -e "  Deployer:          ${CYAN}$DEPLOYER_ADDRESS${NC}"
echo -e "  Semaphore:         ${CYAN}$SEMAPHORE_ADDRESS${NC}"
echo -e "  Trusted Verifier:  ${CYAN}$TRUSTED_VERIFIER${NC}"
echo -e "  Explorer:          ${CYAN}$EXPLORER_URL${NC}"
echo ""
echo -e "  Steps:"
[[ "$PREBUILT" == false ]] && echo -e "    1. Compile contracts (via_ir=true)" || echo -e "    1. ${GREEN}[PREBUILT]${NC} Using pre-built via_ir=true artifacts"
echo -e "    2. Deploy CredentialRegistry + DefaultScorer"
[[ "$SKIP_CREDENTIAL_GROUPS" == false ]] && echo -e "    3. Create credential groups + set scores" || echo -e "    3. ${YELLOW}[SKIP]${NC} Create credential groups + set scores"
[[ "$SKIP_APPS" == false ]] && echo -e "    4. Register apps" || echo -e "    4. ${YELLOW}[SKIP]${NC} Register apps"
[[ "$SKIP_SCORER_FACTORY" == false ]] && echo -e "    5. Deploy ScorerFactory" || echo -e "    5. ${YELLOW}[SKIP]${NC} Deploy ScorerFactory"
[[ "$DRY_RUN" == true ]] && echo -e "\n  ${YELLOW}⚠  DRY RUN — no transactions will be broadcast${NC}"

echo ""
if [[ "$NETWORK" == "mainnet" ]]; then
  echo -e "${RED}${BOLD}⚠  WARNING: You are deploying to BASE MAINNET with real funds!${NC}"
  echo ""
fi

read -r -p "Proceed with deployment? (y/N) " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "Deployment cancelled."
  exit 0
fi

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Step 1: Compile contracts
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$PREBUILT" == true ]]; then
  echo -e "${GREEN}Step 1/5: Using pre-built artifacts (--prebuilt)${NC}"
else
  echo -e "${BOLD}Step 1/5: Compiling contracts (via_ir=true)${NC}"
  echo -e "${YELLOW}Note: via_ir compilation may be slow and use significant memory${NC}"
  echo "─────────────────────────────────────────"

  FOUNDRY_PROFILE=default forge build --skip test --skip script

  echo -e "${GREEN}✓ Compilation successful${NC}"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Step 2: Deploy CredentialRegistry (+ DefaultScorer via constructor)
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}Step 2/5: Deploying CredentialRegistry${NC}"
echo "─────────────────────────────────────────"

SEMAPHORE_ADDRESS="$SEMAPHORE_ADDRESS" \
TRUSTED_VERIFIER="$TRUSTED_VERIFIER" \
FOUNDRY_PROFILE="$FORGE_PROFILE" \
  forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$RPC_URL" \
  $BROADCAST_FLAG \
  $VERIFY_FLAGS \
  $SKIP_COMPILATION_FLAG \
  -v

echo ""

# Extract addresses from broadcast JSON
REGISTRY_ADDRESS=""
DEFAULT_SCORER_ADDRESS=""

BROADCAST_FILE="$PROJECT_DIR/broadcast/Deploy.s.sol/$CHAIN_ID/run-latest.json"

if [[ "$DRY_RUN" == true ]]; then
  # In dry-run mode, try to extract from dry-run broadcast
  BROADCAST_FILE="$PROJECT_DIR/broadcast/Deploy.s.sol/$CHAIN_ID/dry-run/run-latest.json"
fi

if [[ -f "$BROADCAST_FILE" ]]; then
  # Extract CredentialRegistry address — it's a CREATE transaction
  REGISTRY_ADDRESS=$(jq -r '.transactions[] | select(.transactionType == "CREATE" and .contractName == "CredentialRegistry") | .contractAddress' "$BROADCAST_FILE" | head -1)

  # Extract DefaultScorer address from additionalContracts (deployed by CredentialRegistry constructor)
  DEFAULT_SCORER_ADDRESS=$(jq -r '.transactions[] | select(.contractName == "CredentialRegistry") | .additionalContracts[]? | select(.contractName == "DefaultScorer") | .address' "$BROADCAST_FILE" | head -1)

  # Fallback: query on-chain if not found in broadcast JSON (won't work in dry-run)
  if [[ (-z "$DEFAULT_SCORER_ADDRESS" || "$DEFAULT_SCORER_ADDRESS" == "null") && -n "$REGISTRY_ADDRESS" && "$REGISTRY_ADDRESS" != "null" && "$DRY_RUN" == false ]]; then
    DEFAULT_SCORER_ADDRESS=$(cast call "$REGISTRY_ADDRESS" "defaultScorer()(address)" --rpc-url "$RPC_URL" 2>/dev/null || true)
  fi
fi

# Fallback: try to parse from forge script console output if broadcast JSON extraction failed
if [[ -z "$REGISTRY_ADDRESS" || "$REGISTRY_ADDRESS" == "null" ]]; then
  echo -e "${YELLOW}Warning: Could not extract addresses from broadcast JSON${NC}"
  echo -e "${YELLOW}Please enter the deployed addresses manually:${NC}"
  read -r -p "  CredentialRegistry address: " REGISTRY_ADDRESS
  read -r -p "  DefaultScorer address: " DEFAULT_SCORER_ADDRESS
fi

if [[ -z "$REGISTRY_ADDRESS" || "$REGISTRY_ADDRESS" == "null" ]]; then
  echo -e "${RED}Error: Could not determine CredentialRegistry address${NC}"
  exit 1
fi

echo -e "${GREEN}✓ CredentialRegistry deployed: ${CYAN}$REGISTRY_ADDRESS${NC}"
echo -e "${GREEN}✓ DefaultScorer deployed:      ${CYAN}$DEFAULT_SCORER_ADDRESS${NC}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Step 3: Create credential groups + set scores
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$SKIP_CREDENTIAL_GROUPS" == true ]]; then
  echo -e "${YELLOW}Step 3/5: Skipping credential groups (--skip-credential-groups)${NC}"
elif [[ "$DRY_RUN" == true ]]; then
  echo -e "${YELLOW}Step 3/5: Skipping credential groups (dry-run — registry not deployed on-chain)${NC}"
else
  echo -e "${BOLD}Step 3/5: Creating credential groups + setting scores${NC}"
  echo "─────────────────────────────────────────"

  CREDENTIAL_REGISTRY_ADDRESS="$REGISTRY_ADDRESS" \
  FOUNDRY_PROFILE="$FORGE_PROFILE" \
    forge script script/CredentialGroups.s.sol:DeployCredentialGroups \
    --rpc-url "$RPC_URL" \
    $BROADCAST_FLAG \
    $VERIFY_FLAGS \
    $SKIP_COMPILATION_FLAG \
    -v

  echo -e "${GREEN}✓ Credential groups created and scores set${NC}"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Step 4: Register apps
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$SKIP_APPS" == true ]]; then
  echo -e "${YELLOW}Step 4/5: Skipping app registration (--skip-apps)${NC}"
elif [[ "$DRY_RUN" == true ]]; then
  echo -e "${YELLOW}Step 4/5: Skipping app registration (dry-run — registry not deployed on-chain)${NC}"
else
  echo -e "${BOLD}Step 4/5: Registering apps${NC}"
  echo -e "${YELLOW}⚠  Warning: App registration is NOT idempotent. Running this again will create duplicate apps.${NC}"
  echo "─────────────────────────────────────────"

  CREDENTIAL_REGISTRY_ADDRESS="$REGISTRY_ADDRESS" \
  FOUNDRY_PROFILE="$FORGE_PROFILE" \
    forge script script/RegisterApps.s.sol:RegisterApps \
    --rpc-url "$RPC_URL" \
    $BROADCAST_FLAG \
    $VERIFY_FLAGS \
    $SKIP_COMPILATION_FLAG \
    -v

  echo -e "${GREEN}✓ Apps registered${NC}"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Step 5: Deploy ScorerFactory
# ══════════════════════════════════════════════════════════════════════════════
if [[ "$SKIP_SCORER_FACTORY" == true ]]; then
  echo -e "${YELLOW}Step 5/5: Skipping ScorerFactory (--skip-scorer-factory)${NC}"
else
  echo -e "${BOLD}Step 5/5: Deploying ScorerFactory${NC}"
  echo "─────────────────────────────────────────"

  FOUNDRY_PROFILE="$FORGE_PROFILE" \
    forge script script/DeployScorerFactory.s.sol:DeployScorerFactory \
    --rpc-url "$RPC_URL" \
    $BROADCAST_FLAG \
    $VERIFY_FLAGS \
    $SKIP_COMPILATION_FLAG \
    -v

  echo -e "${GREEN}✓ ScorerFactory deployed${NC}"
fi
echo ""

# ── Extract ScorerFactory address ─────────────────────────────────────────────
SCORER_FACTORY_ADDRESS=""
if [[ "$SKIP_SCORER_FACTORY" == false ]]; then
  SF_BROADCAST="$PROJECT_DIR/broadcast/DeployScorerFactory.s.sol/$CHAIN_ID/run-latest.json"
  if [[ "$DRY_RUN" == true ]]; then
    SF_BROADCAST="$PROJECT_DIR/broadcast/DeployScorerFactory.s.sol/$CHAIN_ID/dry-run/run-latest.json"
  fi
  if [[ -f "$SF_BROADCAST" ]]; then
    SCORER_FACTORY_ADDRESS=$(jq -r '.transactions[] | select(.transactionType == "CREATE" and .contractName == "ScorerFactory") | .contractAddress' "$SF_BROADCAST" | head -1)
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════════
echo -e "${BOLD}═══════════════════════════════════════════${NC}"
echo -e "${BOLD}  Deployment Complete — $NETWORK_LABEL${NC}"
echo -e "${BOLD}═══════════════════════════════════════════${NC}"
echo ""
echo -e "  ${BOLD}Deployed Contracts${NC}"
echo -e "  ─────────────────────────────────────────"
echo -e "  Semaphore:            ${CYAN}$SEMAPHORE_ADDRESS${NC}"
echo -e "  CredentialRegistry:   ${CYAN}$REGISTRY_ADDRESS${NC}"
echo -e "  DefaultScorer:        ${CYAN}${DEFAULT_SCORER_ADDRESS:-N/A}${NC}"
[[ -n "$SCORER_FACTORY_ADDRESS" && "$SCORER_FACTORY_ADDRESS" != "null" ]] && \
  echo -e "  ScorerFactory:        ${CYAN}$SCORER_FACTORY_ADDRESS${NC}"
echo ""
echo -e "  ${BOLD}Explorer Links${NC}"
echo -e "  ─────────────────────────────────────────"
echo -e "  Registry:       ${CYAN}$EXPLORER_URL/address/$REGISTRY_ADDRESS${NC}"
[[ -n "${DEFAULT_SCORER_ADDRESS:-}" && "$DEFAULT_SCORER_ADDRESS" != "null" ]] && \
  echo -e "  DefaultScorer:  ${CYAN}$EXPLORER_URL/address/$DEFAULT_SCORER_ADDRESS${NC}"
[[ -n "$SCORER_FACTORY_ADDRESS" && "$SCORER_FACTORY_ADDRESS" != "null" ]] && \
  echo -e "  ScorerFactory:  ${CYAN}$EXPLORER_URL/address/$SCORER_FACTORY_ADDRESS${NC}"
echo ""
echo -e "  ${BOLD}Verification Commands${NC}"
echo -e "  ─────────────────────────────────────────"
echo -e "  cast call $REGISTRY_ADDRESS \"defaultScorer()(address)\" --rpc-url $RPC_URL"
[[ -n "${DEFAULT_SCORER_ADDRESS:-}" && "$DEFAULT_SCORER_ADDRESS" != "null" ]] && \
  echo -e "  cast call $DEFAULT_SCORER_ADDRESS \"getScore(uint256)(uint256)\" 1 --rpc-url $RPC_URL"
echo -e "  cast call $REGISTRY_ADDRESS \"nextAppId()(uint256)\" --rpc-url $RPC_URL"
echo ""
