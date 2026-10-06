#!/usr/bin/env bash
# Install the pinned dev toolchain into ~/.local/bin (versions match CI).
# Release binaries/plugins are verified against pinned SHA-256 checksums
# before they are installed. Idempotent: re-running skips what is present.
set -euo pipefail

TERRAFORM_VERSION=1.9.8
TERRAFORM_SHA256=186e0145f5e5f2eb97cbd785bc78f21bae4ef15119349f6ad4fa535b83b10df8
TFLINT_VERSION=0.53.0
TFLINT_SHA256=bb0a3a6043ea1bcd221fc95d49bac831bb511eb31946ca6a4050983e9e584578
TFLINT_AWS_VERSION=0.34.0
TFLINT_AWS_SHA256=ce08b73b4173967e8999da5794ec055abad0cf2ed3ad26097144c72e18452959
CHECKOV_VERSION=3.3.23
SHELLCHECK_PY_VERSION=0.11.0.1

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *) echo "bootstrap.sh pins linux_amd64 checksums only; install the tools manually on $(uname -sm)." >&2; exit 1 ;;
esac

BIN="$HOME/.local/bin"
mkdir -p "$BIN"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch_verified() { # url sha256 dest
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum -c --quiet -
}

if ! "$BIN/terraform" version 2>/dev/null | grep -q "v$TERRAFORM_VERSION"; then
  fetch_verified "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    "$TERRAFORM_SHA256" "$TMP/terraform.zip"
  unzip -o -q "$TMP/terraform.zip" terraform -d "$BIN"
fi

if ! "$BIN/tflint" --version 2>/dev/null | grep -q "$TFLINT_VERSION"; then
  fetch_verified "https://github.com/terraform-linters/tflint/releases/download/v${TFLINT_VERSION}/tflint_linux_amd64.zip" \
    "$TFLINT_SHA256" "$TMP/tflint.zip"
  unzip -o -q "$TMP/tflint.zip" tflint -d "$BIN"
fi

# Installed directly so `tflint --init` doesn't depend on the GitHub API (rate limits).
PLUGIN_DIR="$HOME/.tflint.d/plugins/github.com/terraform-linters/tflint-ruleset-aws/$TFLINT_AWS_VERSION"
if [ ! -x "$PLUGIN_DIR/tflint-ruleset-aws" ]; then
  fetch_verified "https://github.com/terraform-linters/tflint-ruleset-aws/releases/download/v${TFLINT_AWS_VERSION}/tflint-ruleset-aws_linux_amd64.zip" \
    "$TFLINT_AWS_SHA256" "$TMP/tflint-ruleset-aws.zip"
  mkdir -p "$PLUGIN_DIR"
  unzip -o -q "$TMP/tflint-ruleset-aws.zip" -d "$PLUGIN_DIR"
fi

python3 -m pip install --user -q "checkov==$CHECKOV_VERSION" "shellcheck-py==$SHELLCHECK_PY_VERSION"

case ":$PATH:" in *":$BIN:"*) ;; *) echo "Add $BIN to PATH." ;; esac
"$BIN/terraform" version | sed -n 1p
"$BIN/tflint" --version | sed -n 1p
"$BIN/checkov" --version
"$BIN/shellcheck" --version | sed -n 2p
