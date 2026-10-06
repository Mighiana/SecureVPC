TF_DIR := terraform
TF     := terraform -chdir=$(TF_DIR)
ADV    := terraform -chdir=$(TF_DIR)/advanced

.PHONY: help bootstrap init fmt check test plan apply output verify destroy cost-check demo \
        adv-init adv-test adv-plan adv-apply adv-output adv-verify adv-destroy reachability

help: ## List targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-13s %s\n", $$1, $$2}'

bootstrap: ## Install pinned, checksum-verified dev tools into ~/.local/bin
	./scripts/bootstrap.sh

init: ## terraform init
	$(TF) init

fmt: ## Format all Terraform files
	$(TF) fmt -recursive

check: ## fmt-check, validate, test, tflint, checkov, shellcheck (no AWS credentials needed)
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

demo: ## Free local demo: apply + verify + destroy the baseline on LocalStack (Docker, no AWS account)
	./scripts/localstack-demo.sh

# --- Advanced profile (2026 extension; expensive while running, see README) ---

adv-init: ## Advanced profile: terraform init
	$(ADV) init

adv-test: ## Advanced profile: offline terraform test
	$(ADV) test

adv-plan: ## Advanced profile: plan into terraform/advanced/tfplan
	$(ADV) plan -out=tfplan

adv-apply: ## Advanced profile: apply the saved plan
	$(ADV) apply tfplan

adv-output: ## Advanced profile: show outputs
	$(ADV) output

adv-verify: ## Advanced profile: read-only checks against the deployed stack
	./scripts/verify-advanced.sh

reachability: ## Advanced profile: Reachability Analyzer checks (~USD 0.10 per analysis)
	./scripts/reachability.sh $(or $(REGION),us-east-1)

adv-destroy: ## Advanced profile: tear everything down
	$(ADV) destroy
