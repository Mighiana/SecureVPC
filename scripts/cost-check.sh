#!/usr/bin/env bash
# Lists billable SecureVPC resources still present in a region, by tag.
# Run after `terraform destroy` to confirm nothing was left behind.
#   ./scripts/cost-check.sh us-east-1
set -euo pipefail

REGION="${1:-${AWS_REGION:-us-east-1}}"
export AWS_REGION="$REGION"
TAG="Name=tag:Project,Values=SecureVPC"

echo "Region: $REGION"
echo "Running/stopped EC2 instances:"
aws ec2 describe-instances --filters "$TAG" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text
echo "NAT Gateways (billed hourly):"
aws ec2 describe-nat-gateways --filter "$TAG" "Name=state,Values=pending,available" \
  --query 'NatGateways[].[NatGatewayId,State]' --output text
echo "Network Firewalls (advanced profile, ~USD 0.395/hour per AZ):"
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=SecureVPC \
  --resource-type-filters network-firewall:firewall --query 'ResourceTagMappingList[].ResourceARN' --output text
echo "Load balancers and interface VPC endpoints (advanced profile):"
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=SecureVPC \
  --resource-type-filters elasticloadbalancing:loadbalancer ec2:vpc-endpoint --query 'ResourceTagMappingList[].ResourceARN' --output text
echo "Elastic IPs:"
aws ec2 describe-addresses --filters "$TAG" --query 'Addresses[].[AllocationId,PublicIp]' --output text
echo "VPCs:"
aws ec2 describe-vpcs --filters "$TAG" --query 'Vpcs[].VpcId' --output text
# Tag-based, so renamed deployments (project_name) and a retained S3 archive are still found.
echo "Log groups and S3 buckets:"
aws resourcegroupstaggingapi get-resources --tag-filters Key=Project,Values=SecureVPC \
  --resource-type-filters logs:log-group s3 --query 'ResourceTagMappingList[].ResourceARN' --output text
echo "(Empty sections = nothing left. KMS keys show as PendingDeletion for 7 days and are not billed in that state.)"
