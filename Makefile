install:
	yarn install;

# Test commands
test:
	forge test --summary

test-all:
	forge test --via-ir --ffi --summary

test-registry:
	forge test --match-path "test/BringRegistry.t.sol" --ffi -v

test-factory:
	forge test --match-path "test/BringDropFactory.t.sol" -v

test-base:
	forge test --match-path "test/BringDropBase.t.sol" -v

test-verification:
	forge test --match-path "test/BringDropByVerification.t.sol" --ffi -v

test-score:
	forge test --match-path "test/BringDropByScore.t.sol" --ffi -v

test-zkbring:
	forge test --match-path "test/zkBring.t.sol" --ffi -v

test-idcard:
	forge test --match-path "test/IdCard.t.sol" --ffi -v

# Build deployment artifacts (via_ir=true contracts + ci scripts)
# Run on VPS, commit deploy-artifacts.tar.gz, then deploy locally with --prebuilt
build-deploy-artifacts:
	@echo "Building scripts (ci profile)..."
	FOUNDRY_PROFILE=ci forge build --skip test
	@echo "Building contracts (via_ir=true)..."
	FOUNDRY_PROFILE=default forge build --skip test --skip script
	@echo "Packaging artifacts..."
	tar -czf deploy-artifacts.tar.gz out/
	@echo "✓ deploy-artifacts.tar.gz created ($(du -h deploy-artifacts.tar.gz | cut -f1))"

# Deploy commands
deploy-local:
	forge script \
	script/Deploy.s.sol:DeployDev \
	--rpc-url http://127.0.0.1:8545 --broadcast -vvvv

deploy:
	forge script \
	--chain 84532 \
	script/Deploy.s.sol:DeployDev \
	--rpc-url $$BASE_RPC_URL \
	--broadcast --verify -vvvv

# IdCard deployment commands
deploy-idcard-local:
	forge script \
	script/DeployIdCard.s.sol:DeployIdCard \
	--rpc-url http://127.0.0.1:8545 --broadcast -vvvv

deploy-idcard:
	forge script \
	--chain 84532 \
	script/DeployIdCard.s.sol:DeployIdCard \
	--rpc-url $$BASE_RPC_URL \
	--broadcast --verify -vvvv

deploy-idcard-full-local:
	forge script \
	script/DeployIdCard.s.sol:DeployIdCardWithRegistry \
	--rpc-url http://127.0.0.1:8545 --broadcast -vvvv

deploy-idcard-full:
	forge script \
	--chain 84532 \
	script/DeployIdCard.s.sol:DeployIdCardWithRegistry \
	--rpc-url $$BASE_RPC_URL \
	--broadcast --verify -vvvv

# Register apps commands
deploy-register-apps-local:
	forge script \
	script/RegisterApps.s.sol:RegisterApps \
	--rpc-url http://127.0.0.1:8545 --broadcast -vvvv

deploy-register-apps:
	forge script \
	--chain 84532 \
	script/RegisterApps.s.sol:RegisterApps \
	--rpc-url $$BASE_RPC_URL \
	--broadcast --verify -vvvv