#!/usr/bin/env bash
# Reachability Analyzer checks for the advanced profile.
# Creates temporary Network Insights paths, runs one analysis per path
# (AWS charges about USD 0.10 per analysis), compares the verdict with the
# intended design, then deletes the paths. Needs a deployed advanced stack.
#
#   ./scripts/reachability.sh [region]
set -euo pipefail

REGION="${1:-us-east-1}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF=(terraform -chdir="$ROOT/terraform/advanced")
AWS=(aws --region "$REGION")

VPC=$("${TF[@]}" output -raw vpc_id)
IGW=$("${TF[@]}" output -raw igw_id)
ASG=$("${TF[@]}" output -raw asg_name)
EGRESS=$("${TF[@]}" output -json nat_public_ips)

INSTANCE=$("${AWS[@]}" autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)
SSM_ENI=$("${AWS[@]}" ec2 describe-vpc-endpoints \
  --filters "Name=vpc-id,Values=$VPC" "Name=service-name,Values=com.amazonaws.$REGION.ssm" \
  --query 'VpcEndpoints[0].NetworkInterfaceIds[0]' --output text)

if [[ "$INSTANCE" == "None" || -z "$INSTANCE" ]]; then
  echo "No app instance found in $ASG" >&2
  exit 1
fi

PATHS=()
# shellcheck disable=SC2329  # invoked by the EXIT trap
cleanup() {
  for p in "${PATHS[@]}"; do
    "${AWS[@]}" ec2 delete-network-insights-path --network-insights-path-id "$p" >/dev/null 2>&1 || true
  done
}
trap cleanup EXIT

FAILED=0

# check NAME SOURCE DESTINATION PORT EXPECTED(True|False)
check() {
  local name=$1 src=$2 dst=$3 port=$4 expected=$5 path analysis status found
  path=$("${AWS[@]}" ec2 create-network-insights-path --source "$src" --destination "$dst" \
    --protocol tcp --destination-port "$port" \
    --tag-specifications "ResourceType=network-insights-path,Tags=[{Key=Project,Value=SecureVPC},{Key=Name,Value=$name}]" \
    --query 'NetworkInsightsPath.NetworkInsightsPathId' --output text)
  PATHS+=("$path")

  analysis=$("${AWS[@]}" ec2 start-network-insights-analysis --network-insights-path-id "$path" \
    --query 'NetworkInsightsAnalysis.NetworkInsightsAnalysisId' --output text)

  status=running
  while [[ "$status" == "running" ]]; do
    sleep 5
    read -r status found < <("${AWS[@]}" ec2 describe-network-insights-analyses \
      --network-insights-analysis-ids "$analysis" \
      --query 'NetworkInsightsAnalyses[0].[Status,NetworkPathFound]' --output text)
  done

  if [[ "$status" != "succeeded" ]]; then
    printf '%-34s ERROR    analysis %s (%s)\n' "$name" "$status" "$analysis"
    FAILED=1
  elif [[ "$found" == "$expected" ]]; then
    printf '%-34s OK       reachable=%s\n' "$name" "$found"
  else
    printf '%-34s MISMATCH reachable=%s expected=%s (analysis %s)\n' "$name" "$found" "$expected" "$analysis"
    FAILED=1
  fi
}

[[ "$EGRESS" == "{}" ]] && egress_expected=False || egress_expected=True

echo "Reachability Analyzer, $REGION, instance $INSTANCE"
check internet-ssh-to-app          "$IGW"      "$INSTANCE" 22  False
check internet-dataport-to-app     "$IGW"      "$INSTANCE" 5432 False
check internet-https-to-endpoint   "$IGW"      "$SSM_ENI"  443 False
check app-https-to-ssm-endpoint    "$INSTANCE" "$SSM_ENI"  443 True
check app-https-to-internet        "$INSTANCE" "$IGW"      443 "$egress_expected"

exit "$FAILED"
