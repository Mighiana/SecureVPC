TF_DIR := terraform
TF     := terraform -chdir=$(TF_DIR)

.PHONY: help init fmt check test plan apply output verify destroy cost-check

help: ## List targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-12s %s\n", $$1, $$2}'

init: ## terraform init
	$(TF) init

fmt: ## Format all Terraform files
	$(TF) fmt -recursive

check: ## fmt-check, validate, test, tflint, checkov (no AWS credentials needed)
	./scripts/check.sh

test: ## Offline terraform test with the mocked AWS provider
	$(TF) test

plan: ## Plan into terraform/tfplan
	$(TF) plan -out=tfplan

apply: ## Apply the saved plan
	$(TF) apply tfplan

output: ## Show outputs
	$(TF) output

verify: ## Read-only checks against the deployed stack
	./scripts/verify.sh

destroy: ## Tear everything down
	$(TF) destroy

cost-check: ## Confirm no billable SecureVPC resources remain (REGION=us-east-1)
	./scripts/cost-check.sh $(or $(REGION),us-east-1)
