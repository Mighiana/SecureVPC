#!/usr/bin/env bash
# Read-only verification of a deployed SecureVPC stack.
#
# Uses `terraform output` plus read-only AWS CLI describe/get calls. It never
# prints credentials, and the AWS account ID is masked in its output, so the
# result is safe to paste into a README or screenshot.
# JMESPath queries use literal backticks (SC2016); ok()/bad() always return 0 (SC2015).
# shellcheck disable=SC2015,SC2016
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="$ROOT/terraform"

command -v aws >/dev/null || { echo "aws CLI is required" >&2; exit 1; }
command -v jq  >/dev/null || { echo "jq is required" >&2; exit 1; }

out() { terraform -chdir="$TF_DIR" output -raw "$1"; }
mask() { sed -E 's/[0-9]{12}/************/g'; }

REGION="$(out region)"
VPC_ID="$(out vpc_id)"
PUB_SUBNET="$(out public_subnet_id)"
PRIV_SUBNET="$(out private_subnet_id)"
BASTION_ID="$(out bastion_instance_id)"
WEB_ID="$(out web_instance_id)"
LOG_GROUP="$(out flow_log_group_name)"
export AWS_REGION="$REGION"

PASS=0; FAIL=0
ok()   { printf '  [PASS] %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }
section() { printf '\n## %s\n' "$*"; }

section "VPC"
aws ec2 describe-vpcs --vpc-ids "$VPC_ID" \
  --query 'Vpcs[0].{VpcId:VpcId,Cidr:CidrBlock,State:State}' --output table

section "Subnets"
aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
  --query 'Subnets[].{Name:Tags[?Key==`Name`]|[0].Value,SubnetId:SubnetId,Cidr:CidrBlock,AZ:AvailabilityZone,AutoPublicIP:MapPublicIpOnLaunch}' \
  --output table

section "Routing"
PUB_DEFAULT=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$PUB_SUBNET" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].GatewayId | [0]" --output text)
PRIV_DEFAULT=$(aws ec2 describe-route-tables --filters "Name=association.subnet-id,Values=$PRIV_SUBNET" \
  --query "RouteTables[0].Routes[?DestinationCidrBlock=='0.0.0.0/0'].NatGatewayId | [0]" --output text)
[[ "$PUB_DEFAULT" == igw-* ]]  && ok "public subnet 0.0.0.0/0 -> $PUB_DEFAULT"  || bad "public subnet default route is '$PUB_DEFAULT' (expected igw-*)"
[[ "$PRIV_DEFAULT" == nat-* ]] && ok "private subnet 0.0.0.0/0 -> $PRIV_DEFAULT" || bad "private subnet default route is '$PRIV_DEFAULT' (expected nat-*)"

NAT_STATE=$(aws ec2 describe-nat-gateways --nat-gateway-ids "$(out nat_gateway_id)" --query 'NatGateways[0].State' --output text)
[[ "$NAT_STATE" == "available" ]] && ok "NAT Gateway state: available" || bad "NAT Gateway state: $NAT_STATE"

section "Instances"
aws ec2 describe-instances --instance-ids "$BASTION_ID" "$WEB_ID" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,Id:InstanceId,State:State.Name,Subnet:SubnetId,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress,IMDS:MetadataOptions.HttpTokens}' \
  --output table

WEB_PUBLIC=$(aws ec2 describe-instances --instance-ids "$WEB_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
[[ "$WEB_PUBLIC" == "None" ]] && ok "web server has no public IP" || bad "web server has public IP $WEB_PUBLIC"

section "Security groups"
BASTION_SG=$(terraform -chdir="$TF_DIR" output -json security_group_ids | jq -r .bastion)
WEB_SG=$(terraform -chdir="$TF_DIR" output -json security_group_ids | jq -r .web)
aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$BASTION_SG,$WEB_SG" \
  --query 'SecurityGroupRules[].{Group:GroupId,Egress:IsEgress,Proto:IpProtocol,From:FromPort,To:ToPort,Cidr:CidrIpv4,SourceSG:ReferencedGroupInfo.GroupId}' \
  --output table

OPEN_SSH=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$BASTION_SG,$WEB_SG" \
  --query "length(SecurityGroupRules[?IsEgress==\`false\` && CidrIpv4=='0.0.0.0/0'])" --output text)
[[ "$OPEN_SSH" == "0" ]] && ok "no security group ingress from 0.0.0.0/0" || bad "$OPEN_SSH ingress rule(s) open to 0.0.0.0/0"

WEB_CIDR_INGRESS=$(aws ec2 describe-security-group-rules --filters "Name=group-id,Values=$WEB_SG" \
  --query "length(SecurityGroupRules[?IsEgress==\`false\` && CidrIpv4!=null])" --output text)
[[ "$WEB_CIDR_INGRESS" == "0" ]] && ok "web SG ingress only references the bastion SG" || bad "web SG has CIDR-based ingress"

section "Network ACLs"
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=$VPC_ID" "Name=default,Values=false" \
  --query 'NetworkAcls[].Entries[?RuleNumber<`32767`].{Egress:Egress,Rule:RuleNumber,Action:RuleAction,Cidr:CidrBlock,From:PortRange.From,To:PortRange.To}' \
  --output table

section "VPC Flow Logs"
aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC_ID" \
  --query 'FlowLogs[].{Id:FlowLogId,Status:FlowLogStatus,Traffic:TrafficType,DestType:LogDestinationType,Delivery:DeliverLogsStatus}' \
  --output table | mask

FL_STATUS=$(aws ec2 describe-flow-logs --filter "Name=resource-id,Values=$VPC_ID" "Name=log-destination-type,Values=cloud-watch-logs" \
  --query 'FlowLogs[0].DeliverLogsStatus' --output text)
[[ "$FL_STATUS" == "SUCCESS" ]] && ok "flow logs delivering to CloudWatch" || bad "flow log delivery status: $FL_STATUS"

section "CloudWatch Logs"
STREAMS=$(aws logs describe-log-streams --log-group-name "$LOG_GROUP" --query 'length(logStreams)' --output text)
[[ "$STREAMS" -gt 0 ]] && ok "$STREAMS log stream(s) in $LOG_GROUP" || bad "no log streams yet in $LOG_GROUP (records appear a few minutes after traffic)"

echo "  Most recent REJECT records (last 30 min, max 10):"
aws logs filter-log-events --log-group-name "$LOG_GROUP" \
  --start-time $(( ($(date +%s) - 1800) * 1000 )) --filter-pattern '"REJECT"' --max-items 10 \
  --query 'events[].message' --output text 2>/dev/null | tr '\t' '\n' | mask | sed 's/^/    /' || true

printf '\nResult: %d passed, %d failed\n' "$PASS" "$FAIL"
[[ "$FAIL" -eq 0 ]]
