#!/usr/bin/env bash
# Read-only verification of a deployed advanced-profile stack.
# Uses `terraform output` plus describe/get calls only; masks the account ID.
# JMESPath queries use literal backticks (SC2016); ok()/bad() always return 0 (SC2015).
# shellcheck disable=SC2015,SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform/advanced"

command -v aws >/dev/null || { echo "aws CLI is required" >&2; exit 1; }
command -v jq  >/dev/null || { echo "jq is required" >&2; exit 1; }

out()  { terraform -chdir="$TF_DIR" output -raw "$1"; }
json() { terraform -chdir="$TF_DIR" output -json "$1"; }
mask() { sed -E 's/[0-9]{12}/************/g'; }

export AWS_REGION; AWS_REGION="$(out region)"
VPC_ID="$(out vpc_id)"
ASG="$(out asg_name)"
WEB_URL="$(out web_url)"
ALB_ARN="$(out alb_arn)"
FIREWALL="$(json network_firewall)"

PASS=0; FAIL=0
ok()   { printf '  [PASS] %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }
section() { printf '\n## %s\n' "$*"; }

section "Subnet tiers"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'sort_by(Subnets,&CidrBlock)[].{Tier:Tags[?Key==`Tier`]|[0].Value,Cidr:CidrBlock,AZ:AvailabilityZone,AutoPublicIP:MapPublicIpOnLaunch}' \
  --output table

section "Routing"
for id in $(json subnet_ids | jq -r '.data[], .endpoints[]'); do
  r=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$id" \
    --query "length(RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'])" --output text)
  [[ "$r" == "0" ]] && ok "isolated subnet $id has no default route" || bad "isolated subnet $id has a default route"
done
if [[ "$FIREWALL" != "null" ]]; then
  for id in $(json subnet_ids | jq -r '.public[]'); do
    t=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$id" \
      --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'] | [0].[GatewayId, VpcEndpointId] | [?@ != null] | [0]" --output text)
    [[ "$t" == vpce-* ]] && ok "public subnet $id 0.0.0.0/0 -> firewall endpoint $t" || bad "public subnet $id default route is '$t' (expected vpce-*)"
  done
  name=$(jq -r .name <<<"$FIREWALL")
  st=$(aws network-firewall describe-firewall --firewall-name "$name" --query 'FirewallStatus.Status' --output text)
  [[ "$st" == "READY" ]] && ok "Network Firewall $name is READY" || bad "Network Firewall status: $st"
fi

section "App instances (no public IP, no SSH)"
IDS=$(aws autoscaling describe-auto-scaling-groups --auto-scaling-group-names "$ASG" \
  --query 'AutoScalingGroups[0].Instances[].InstanceId' --output text)
for i in $IDS; do
  pub=$(aws ec2 describe-instances --instance-ids "$i" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
  [[ "$pub" == "None" ]] && ok "$i has no public IP" || bad "$i has public IP $pub"
done
SSH=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[].GroupId' --output text | tr '\t' ',')" \
  --query 'length(SecurityGroupRules[?IsEgress==`false` && FromPort<=`22` && ToPort>=`22`])' --output text)
[[ "$SSH" == "0" ]] && ok "no security group in the VPC allows TCP/22" || bad "$SSH ingress rule(s) allow TCP/22"

section "Session Manager"
ONLINE=$(aws ssm describe-instance-information --filters "Key=tag:aws:autoscaling:groupName,Values=$ASG" \
  --query 'length(InstanceInformationList[?PingStatus==`Online`])' --output text)
[[ "$ONLINE" -gt 0 ]] && ok "$ONLINE instance(s) online in SSM (reached via VPC endpoints)" || bad "no instances online in SSM"

section "Web tier"
WAF=$(aws wafv2 get-web-acl-for-resource --resource-arn "$ALB_ARN" --query 'WebACL.Name' --output text)
[[ "$WAF" == "$(out web_acl_name)" ]] && ok "WAF $WAF is associated with the ALB" || bad "ALB WAF association: $WAF"
BODY=$(curl -s --max-time 10 "$WEB_URL" || true)
[[ "$BODY" == *"Secure Web Server"* ]] && ok "$WEB_URL returns Secure Web Server" || bad "$WEB_URL did not return the expected page"

section "Logging"
FL=$(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC_ID" \
  --query 'FlowLogs[].{Dest:LogDestinationType,Status:DeliverLogsStatus}' --output text)
echo "$FL" | mask | sed 's/^/    /'
if [[ -z "$FL" ]]; then bad "no flow logs found for $VPC_ID"
else [[ "$FL" != *FAILED* ]] && ok "flow log delivery has no failures" || bad "a flow log is failing to deliver"; fi
for lg in $(json log_groups | jq -r '.[] | select(. != null)'); do
  n=$(aws logs describe-log-streams --log-group-name "$lg" --max-items 1 --query 'length(logStreams)' --output text 2>/dev/null || echo 0)
  [[ "$n" != "0" ]] && ok "log streams present in $lg" || bad "no log streams yet in $lg (traffic-dependent)"
done

printf '\nResult: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
