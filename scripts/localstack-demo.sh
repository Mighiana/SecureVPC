#!/usr/bin/env bash
# Free local demo of the baseline profile on LocalStack (an AWS emulator in Docker).
#
# No AWS account or real credentials: LocalStack accepts the dummy "test" keys.
# The demo shows that the Terraform applies, wires the resources together as
# designed and destroys cleanly. It does NOT boot real instances or move packets,
# so it is not an AWS deployment.
#
# Works on a copy in .localstack/work (git-ignored), so it never touches
# terraform/ state. KEEP=1 leaves the stack and container running.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.localstack/work"
OVERRIDES="$ROOT/demo/localstack/overrides"
IMAGE="localstack/localstack:3.8"
NAME="securevpc-localstack"
PORT="${LOCALSTACK_PORT:-4566}"
KEEP="${KEEP:-0}"

for c in docker terraform aws jq ssh-keygen curl; do
  command -v "$c" >/dev/null || { echo "$c is required" >&2; exit 1; }
done
REAL_AWS="$(command -v aws)"

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# shellcheck disable=SC2317,SC2329  # invoked by the EXIT trap (code differs by ShellCheck version)
cleanup() {
  [[ "$KEEP" == "1" ]] || docker rm -f "$NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

step "Start LocalStack ($IMAGE) on 127.0.0.1:$PORT"
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" -p "127.0.0.1:$PORT:4566" \
  -e SERVICES=ec2,ssm,logs,iam,kms,s3,sts,cloudwatch -e EAGER_SERVICE_LOADING=1 \
  "$IMAGE" >/dev/null
for _ in $(seq 90); do
  if curl -sf "http://127.0.0.1:$PORT/_localstack/health" 2>/dev/null \
    | jq -e '.services.ec2 | test("running|available")' >/dev/null 2>&1; then
    break
  fi
  sleep 2
done

step "Copy the baseline root module into .localstack/work and point it at LocalStack"
rm -rf "$WORK"
mkdir -p "$WORK/bin"
tar --exclude=.terraform --exclude='*.tfstate*' --exclude='*.tfvars' --exclude=advanced --exclude=tests \
  -cf - -C "$ROOT/terraform" . | tar -xf - -C "$WORK"
sed "s#localhost:4566#localhost:$PORT#" "$OVERRIDES/root.tf.tmpl" >"$WORK/localstack_override.tf"
for m in flow_logs security compute; do
  cp "$OVERRIDES/$m.tf.tmpl" "$WORK/modules/$m/localstack_override.tf"
done

# Throwaway key pair: only the public half goes into Terraform.
ssh-keygen -q -t ed25519 -N '' -C securevpc-demo -f "$WORK/demo_key"
cat >"$WORK/terraform.tfvars" <<VARS
aws_region     = "us-east-1"
environment    = "demo"
admin_cidrs    = ["203.0.113.10/32"] # documentation range (RFC 5737)
ssh_public_key = "$(cat "$WORK/demo_key.pub")"
VARS

# aws CLI shim so scripts/verify.sh talks to LocalStack unchanged.
cat >"$WORK/bin/aws" <<SHIM
#!/usr/bin/env bash
export AWS_DEFAULT_REGION="\${AWS_REGION:-us-east-1}"
exec "$REAL_AWS" --endpoint-url "http://127.0.0.1:$PORT" "\$@"
SHIM
chmod +x "$WORK/bin/aws"
export AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1

step "terraform init"
terraform -chdir="$WORK" init -input=false -no-color >/dev/null
echo "ok"

step "terraform apply"
terraform -chdir="$WORK" apply -auto-approve -input=false -no-color \
  | grep --line-buffered -E 'Creation complete|Apply complete' | sed -u -E 's/ \[id=[^]]*\]//'

step "terraform plan again (expect no drift)"
terraform -chdir="$WORK" plan -detailed-exitcode -input=false -no-color | grep -E 'No changes|Plan:'

step "Key outputs"
for o in vpc_id public_subnet_id private_subnet_id nat_gateway_id bastion_instance_id web_private_ip web_public_ip flow_log_group_name; do
  printf '  %-20s %s\n' "$o" "$(terraform -chdir="$WORK" output -raw "$o")"
done

step "scripts/verify.sh (read-only checks, LocalStack mode)"
VERIFY_RC=0
PATH="$WORK/bin:$PATH" TF_DIR="$WORK" LOCALSTACK=1 "$ROOT/scripts/verify.sh" || VERIFY_RC=$?

if [[ "$KEEP" == "1" ]]; then
  step "KEEP=1: stack left running (destroy with: terraform -chdir=$WORK destroy)"
else
  step "terraform destroy"
  terraform -chdir="$WORK" destroy -auto-approve -input=false -no-color | grep -E 'Destroy complete'
fi

exit "$VERIFY_RC"
