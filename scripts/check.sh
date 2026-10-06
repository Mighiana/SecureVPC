#!/usr/bin/env bash
# Static checks. Needs no AWS credentials and creates nothing.
#   terraform fmt / validate / test (mocked provider), tflint, checkov
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"

step() { printf '\n==> %s\n' "$*"; }

step "terraform fmt -check"
terraform -chdir="$TF_DIR" fmt -recursive -check -diff

step "terraform init (no backend)"
terraform -chdir="$TF_DIR" init -backend=false -input=false >/dev/null

step "terraform validate"
terraform -chdir="$TF_DIR" validate

step "terraform test (mock provider, offline)"
terraform -chdir="$TF_DIR" test

if command -v tflint >/dev/null 2>&1; then
  step "tflint"
  tflint --init --config="$ROOT/.tflint.hcl" >/dev/null
  tflint --chdir="$TF_DIR" --config="$ROOT/.tflint.hcl" --recursive
else
  echo "tflint not installed - skipping (https://github.com/terraform-linters/tflint)"
fi

if command -v checkov >/dev/null 2>&1; then
  step "checkov"
  checkov -d "$TF_DIR" --framework terraform --compact --quiet
else
  echo "checkov not installed - skipping (pip install checkov)"
fi

step "all checks passed"
