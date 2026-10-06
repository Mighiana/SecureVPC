#!/usr/bin/env bash
# Static checks. Needs no AWS credentials and creates nothing.
#   terraform fmt / validate / test (mocked provider), tflint, checkov, shellcheck
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"

step() { printf '\n==> %s\n' "$*"; }

step "terraform fmt -check"
terraform -chdir="$TF_DIR" fmt -recursive -check -diff

# Two root modules: the faithful reconstruction and the advanced profile.
for root in "$TF_DIR" "$TF_DIR/advanced"; do
  rel="${root#"$ROOT"/}"

  step "terraform init (no backend): $rel"
  terraform -chdir="$root" init -backend=false -input=false >/dev/null

  step "terraform validate: $rel"
  terraform -chdir="$root" validate

  step "terraform test (mock provider, offline): $rel"
  terraform -chdir="$root" test
done

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

if command -v shellcheck >/dev/null 2>&1; then
  step "shellcheck"
  shellcheck "$ROOT"/scripts/*.sh "$ROOT"/terraform/modules/compute/templates/bastion.sh
else
  echo "shellcheck not installed - skipping (pip install shellcheck-py)"
fi

step "all checks passed"
