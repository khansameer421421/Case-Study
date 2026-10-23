#!/usr/bin/env bash
# One-time (and idempotent) deployment of the AWS foundations.
#
#   MGMT_PROFILE        profile in the management (or StackSets delegated admin) account
#   MON_PROFILE         profile in the monitoring account
#   ORG_ID              o-xxxxxxxxxx
#   TARGET_OUS          space-separated OU ids whose accounts are monitored
#   HOME_REGION         region for central resources (default us-east-1)
#   REGIONS             space-separated monitored regions
#   ALERT_EMAIL         first alert subscriber
set -euo pipefail

: "${MGMT_PROFILE:?}" "${MON_PROFILE:?}" "${ORG_ID:?}" "${TARGET_OUS:?}" "${ALERT_EMAIL:?}"
HOME_REGION="${HOME_REGION:-us-east-1}"
REGIONS="${REGIONS:-us-east-1 us-west-2 eu-west-1}"
DIR="$(cd "$(dirname "$0")/../cloudformation" && pwd)"

MON_ACCOUNT_ID=$(aws sts get-caller-identity --profile "$MON_PROFILE" --query Account --output text)
echo "Monitoring account: $MON_ACCOUNT_ID, home region: $HOME_REGION"

echo "==> 1. Central resources (monitoring account, home region)"
aws cloudformation deploy --profile "$MON_PROFILE" --region "$HOME_REGION" \
  --stack-name disk-monitoring-central \
  --template-file "$DIR/01-monitoring-account.yml" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides OrganizationId="$ORG_ID" AlertEmail="$ALERT_EMAIL"

BUCKET=$(aws cloudformation describe-stacks --profile "$MON_PROFILE" --region "$HOME_REGION" \
  --stack-name disk-monitoring-central \
  --query "Stacks[0].Outputs[?OutputKey=='ArtifactBucketName'].OutputValue" --output text)

echo "==> 2. OAM sinks (monitoring account, every monitored region)"
declare -A SINKS
for r in $REGIONS; do
  aws cloudformation deploy --profile "$MON_PROFILE" --region "$r" \
    --stack-name disk-monitoring-sink \
    --template-file "$DIR/02-monitoring-sink.yml" \
    --parameter-overrides OrganizationId="$ORG_ID"
  SINKS[$r]=$(aws cloudformation describe-stacks --profile "$MON_PROFILE" --region "$r" \
    --stack-name disk-monitoring-sink \
    --query "Stacks[0].Outputs[?OutputKey=='SinkArn'].OutputValue" --output text)
done

ensure_stackset() {  # name template params...
  local name=$1 template=$2; shift 2
  if aws cloudformation describe-stack-set --profile "$MGMT_PROFILE" --region "$HOME_REGION" \
       --stack-set-name "$name" >/dev/null 2>&1; then
    aws cloudformation update-stack-set --profile "$MGMT_PROFILE" --region "$HOME_REGION" \
      --stack-set-name "$name" --template-body "file://$template" \
      --capabilities CAPABILITY_NAMED_IAM --parameters "$@" >/dev/null
  else
    aws cloudformation create-stack-set --profile "$MGMT_PROFILE" --region "$HOME_REGION" \
      --stack-set-name "$name" --template-body "file://$template" \
      --capabilities CAPABILITY_NAMED_IAM \
      --permission-model SERVICE_MANAGED \
      --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=false \
      --parameters "$@" >/dev/null
  fi
}

echo "==> 3. Member IAM baseline StackSet (auto-deploys to new accounts in the OUs)"
ensure_stackset disk-monitoring-member-iam "$DIR/03-member-account-iam.yml" \
  ParameterKey=OrganizationId,ParameterValue="$ORG_ID" \
  ParameterKey=MonitoringAccountId,ParameterValue="$MON_ACCOUNT_ID" \
  ParameterKey=ArtifactBucketName,ParameterValue="$BUCKET" \
  ParameterKey=CentralEventBusRegion,ParameterValue="$HOME_REGION"
aws cloudformation create-stack-instances --profile "$MGMT_PROFILE" --region "$HOME_REGION" \
  --stack-set-name disk-monitoring-member-iam \
  --deployment-targets OrganizationalUnitIds="${TARGET_OUS// /,}" \
  --regions "$HOME_REGION" \
  --operation-preferences MaxConcurrentPercentage=50,FailureTolerancePercentage=10 || true

echo "==> 4. Member regional StackSet (one sink ARN per region)"
first_region=${REGIONS%% *}
ensure_stackset disk-monitoring-member-regional "$DIR/04-member-account-regional.yml" \
  ParameterKey=MonitoringAccountId,ParameterValue="$MON_ACCOUNT_ID" \
  ParameterKey=SinkArn,ParameterValue="${SINKS[$first_region]}" \
  ParameterKey=CentralEventBusRegion,ParameterValue="$HOME_REGION"
for r in $REGIONS; do
  aws cloudformation create-stack-instances --profile "$MGMT_PROFILE" --region "$HOME_REGION" \
    --stack-set-name disk-monitoring-member-regional \
    --deployment-targets OrganizationalUnitIds="${TARGET_OUS// /,}" \
    --regions "$r" \
    --parameter-overrides ParameterKey=SinkArn,ParameterValue="${SINKS[$r]}" \
    --operation-preferences MaxConcurrentPercentage=50,FailureTolerancePercentage=10 || true
done

echo "Done. Bucket: $BUCKET. Next: launch the controller with instance profile DiskMonitorControllerRole."
