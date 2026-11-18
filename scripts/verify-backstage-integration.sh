#!/usr/bin/env bash
set -euo pipefail

local_repo=${PHOENIX_LOCAL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
phoenix_root=$(cd "$local_repo/.." && pwd)
backstage_repo=${PHOENIX_BACKSTAGE_DIR:-$phoenix_root/backstage}
aws_repo=${PHOENIX_AWS_DIR:-$phoenix_root/AWS}
aws_org_repo=${PHOENIX_AWS_ORG_DIR:-$phoenix_root/AWS-organization}

project_base=${PROJECT:-phoenix-integration-$USER}
run_id=${RUN_ID:-$(date -u +%Y%m%d%H%M%S)-$$}
project=${project_base}-${run_id}
local_project=${project}-floci
backstage_project=${project}-backstage
floci_port=${FLOCI_PORT:-4566}
backstage_port=${BACKSTAGE_PORT:-7007}

fail() { echo "$*" >&2; exit 1; }
for pair in "backstage:$backstage_repo" "aws:$aws_repo" "aws-org:$aws_org_repo" "local:$local_repo"; do
  name=${pair%%:*}; path=${pair#*:}
  [ -d "$path" ] || fail "missing repository: $name ($path)"
done
for command in docker terraform aws actionlint node; do
  command -v "$command" >/dev/null || fail "required command not found: $command"
done

printf 'local_project=%s\nbackstage_project=%s\n' "$local_project" "$backstage_project"
[ "${1:-}" = --preflight ] && exit 0

keep_stack=${KEEP_STACK:-0}
scratch=$(mktemp -d)
local_created=0
backstage_created=0
cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    docker compose -p "$backstage_project" -f "$backstage_repo/docker-compose.yaml" logs --no-color backstage 2>/dev/null | tail -n 100 || true
    docker compose --env-file "$local_repo/.env.example" -p "$local_project" -f "$local_repo/docker-compose.yml" logs --no-color floci 2>/dev/null | tail -n 100 || true
  fi
  if [ "$keep_stack" != 1 ]; then
    if [ "$backstage_created" = 1 ]; then docker compose -p "$backstage_project" -f "$backstage_repo/docker-compose.yaml" down -v >/dev/null 2>&1 || true; fi
    if [ "$local_created" = 1 ]; then docker compose --env-file "$local_repo/.env.example" -p "$local_project" -f "$local_repo/docker-compose.yml" down -v >/dev/null 2>&1 || true; fi
  fi
  rm -rf "$scratch"
  exit "$status"
}
trap cleanup EXIT INT TERM

local_created=1
FLOCI_PORT="$floci_port" docker compose --env-file "$local_repo/.env.example" \
  -p "$local_project" -f "$local_repo/docker-compose.yml" up -d
node "$local_repo/scripts/check-http.mjs" "http://localhost:$floci_port/" 90

cp -R "$aws_org_repo/landing-zone" "$scratch/landing-zone"
cp -R "$aws_org_repo/registry" "$scratch/registry"
rm -f "$scratch/landing-zone/backend.tf" "$scratch/registry/backend.tf"
rm -rf "$scratch/landing-zone/.terraform" "$scratch/registry/.terraform"
rm -f "$scratch/landing-zone/terraform.tfstate" "$scratch/landing-zone/terraform.tfstate.backup"
rm -f "$scratch/registry/terraform.tfstate" "$scratch/registry/terraform.tfstate.backup"

AWS_ENDPOINT_URL="http://localhost:$floci_port" \
TF_VAR_floci_endpoint="http://localhost:$floci_port" \
LANDING_ZONE_DIR="$scratch/landing-zone" \
REGISTRY_DIR="$scratch/registry" \
  make -C "$local_repo" seed PROJECT="$local_project"

AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-1 \
  aws dynamodb scan --table-name phoenix-account-registry \
  --endpoint-url "http://localhost:$floci_port" --output json >/dev/null

AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-1 \
  aws dynamodb put-item --table-name phoenix-account-registry \
  --endpoint-url "http://localhost:$floci_port" --item '{
    "group":{"S":"research"},"account_id":{"S":"111111111111"},
    "organisation":{"S":"acme"},"state_bucket":{"S":"acme-tfstate-111111111111"},
    "state_region":{"S":"eu-west-1"},"management_account_id":{"S":"444444444444"},
    "base_domain":{"S":"example.com"},"apps_repo":{"S":"git@github.com:acme/phoenix-apps.git"},
    "ou":{"S":"sandbox"},"status":{"S":"active"}
  }' >/dev/null

backstage_created=1
FLOCI_ENDPOINT="http://host.docker.internal:$floci_port" BACKSTAGE_PORT="$backstage_port" \
BACKSTAGE_BASE_URL="http://localhost:$backstage_port" \
  docker compose -p "$backstage_project" -f "$backstage_repo/docker-compose.yaml" up -d --build
node "$local_repo/scripts/check-http.mjs" "http://localhost:$backstage_port/.backstage/health/v1/readiness" 180
node "$local_repo/scripts/check-backstage.mjs" "http://localhost:$backstage_port"

"$backstage_repo/scripts/verify-local-config.sh"
node --test "$backstage_repo"/packages/backend/src/modules/orchestrator/*.node.test.mjs
terraform -chdir="$aws_repo/infrastructure/modules/context" test
actionlint "$aws_repo/.github/workflows/terraform.yml"

echo "Phoenix repositories verified together: Backstage + Floci + AWS organization + AWS units"
