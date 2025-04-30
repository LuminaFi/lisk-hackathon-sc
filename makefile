
.PHONY: all install build clean test deploy-idrxhl deploy-idrx-transfer-manager configure-opencampus verify flatten help
-include .env

# Default RPC URL if not provided in .env
RPC_URL ?= https://rpc.sepolia-api.lisk.com

all: clean install build

help:
	@echo "Available targets:"
	@echo " install               Install dependencies"
	@echo " build                 Build the contracts"
	@echo " test                  Run the tests"
	@echo " deploy-luminafi       Deploy LuminaFi contract to OpenCampus Codex"
	@echo " deploy-luminafidao    Deploy LuminaFiDAO contract to OpenCampus Codex"
	@echo " deploy-all            Deploy both contracts in sequence"
	@echo " configure-opencampus  Configure deployed contracts on OpenCampus"
	@echo " verify                Generate flattened contracts for verification"
	@echo " flatten               Generate flattened source code"
	@echo " clean                 Clean build artifacts"
	@echo " help                  Show this help"

install:
	@echo "Installing dependencies..."
	forge install OpenZeppelin/openzeppelin-contracts@v4.9.0 --no-commit
	forge install foundry-rs/forge-std --no-commit

build:
	@echo "Building contracts..."
	forge build --optimize --optimizer-runs 200

test:
	@echo "Running tests..."
	forge test -v

# Deploy IDRXHL only
deploy-idrxhl:
	@echo "Deploying IDRXHL to Lisk Codex..."
	@if [ -z "$(PRIVATE_KEY)" ]; then echo "ERROR: PRIVATE_KEY is not set in .env file"; exit 1; fi
	@if [ -z "$(DEFAULT_ADMIN)" ]; then echo "ERROR: DEFAULT_ADMIN is not set in .env file"; exit 1; fi
	@if [ -z "$(MINTER)" ]; then echo "ERROR: MINTER is not set in .env file"; exit 1; fi
	@echo "Using RPC URL: $(RPC_URL)"
	forge create src/IDRXHL.sol:IDRXHL \
		--rpc-url "$(RPC_URL)" \
		--private-key "$(PRIVATE_KEY)" \
		--broadcast \
		--constructor-args "$(DEFAULT_ADMIN)" "$(MINTER)"
	@echo "Don't forget to set IDRXHL address in your .env file with the deployed address"

# Deploy IDRXTransferManager only
deploy-idrx-transfer-manager:
	@echo "Deploying IDRXTransferManager to Lisk Codex..."
	@if [ -z "$(PRIVATE_KEY)" ]; then echo "ERROR: PRIVATE_KEY is not set in .env file"; exit 1; fi
	@if [ -z "$(IDRX_TOKEN_ADDRESS)" ]; then echo "ERROR: IDRX_TOKEN_ADDRESS is not set in .env file"; exit 1; fi
	@echo "Using RPC URL: $(RPC_URL)"
	forge create src/IDRXTransferManager.sol:IDRXTransferManager \
		--rpc-url "$(RPC_URL)" \
		--private-key "$(PRIVATE_KEY)" \
		--broadcast \
		--constructor-args "$(IDRX_TOKEN_ADDRESS)"

clean:
	@echo "Cleaning..."
	forge clean
	rm -rf cache out flattened
