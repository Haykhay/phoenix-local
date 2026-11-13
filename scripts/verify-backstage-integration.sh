#!/usr/bin/env bash
set -euo pipefail

local_repo=${PHOENIX_LOCAL_DIR:-$(cd "$(dirname "$0")/.." && pwd)}
phoenix_root=$(cd "$local_repo/.." && pwd)
backstage_repo=${PHOENIX_BACKSTAGE_DIR:-$phoenix_root/backstage}
aws_repo=${PHOENIX_AWS_DIR:-$phoenix_root/AWS}
aws_org_repo=${PHOENIX_AWS_ORG_DIR:-$phoenix_root/AWS-organization}

project=${PROJECT:-phoenix-integration-$USER}
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
cleanup() {
  status=$?
  if [ "$status" -ne 0 ]; then
    docker compose -p "$backstage_project" -f "$backstage_repo/docker-compose.yaml" logs --no-color backstage 2>/dev/null | tail -n 100 || true
    docker compose --env-file "$local_repo/.env.example" -p "$local_project" -f "$local_repo/docker-compose.yml" logs --no-color floci 2>/dev/null | tail -n 100 || true
  fi
  if [ "$keep_stack" != 1 ]; then
    docker compose -p "$backstage_project" -f "$backstage_repo/docker-compose.yaml" down -v >/dev/null 2>&1 || true
    docker compose --env-file "$local_repo/.env.example" -p "$local_project" -f "$local_repo/docker-compose.yml" down -v >/dev/null 2>&1 || true
  fi
  exit "$status"
}
trap cleanup EXIT INT TERM

FLOCI_PORT="$floci_port" docker compose --env-file "$local_repo/.env.example" \
  -p "$local_project" -f "$local_repo/docker-compose.yml" up -d
node "$local_repo/scripts/check-http.mjs" "http://localhost:$floci_port/" 90

AWS_ENDPOINT_URL="http://localhost:$floci_port" \
LANDING_ZONE_DIR="$aws_org_repo/landing-zone" \
REGISTRY_DIR="$aws_org_repo/registry" \
  make -C "$local_repo" seed PROJECT="$local_project"

AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=eu-west-1 \
  aws dynamodb scan --table-name phoenix-account-registry \
  --endpoint-url "http://localhost:$floci_port" --output json >/dev/null

FLOCI_ENDPOINT="http://host.docker.internal:$floci_port" BACKSTAGE_PORT="$backstage_port" \
  docker compose -p "$backstage_project" -f "$backstage_repo/docker-compose.yaml" up -d --build
node "$local_repo/scripts/check-http.mjs" "http://localhost:$backstage_port/healthcheck" 180

logs=$(docker compose -p "$backstage_project" -f "$backstage_repo/docker-compose.yaml" logs --no-color backstage)
grep -q 'Phoenix orchestrator backend initialized' <<<"$logs" || fail "Backstage orchestrator did not initialize"
grep -Eq 'aws-account-registry: projected [1-9][0-9]* account' <<<"$logs" || fail "Backstage did not project the Floci account registry"

"$backstage_repo/scripts/verify-local-config.sh"
node --test "$backstage_repo"/packages/backend/src/modules/orchestrator/*.node.test.mjs
terraform -chdir="$aws_repo/infrastructure/modules/context" test
actionlint "$aws_repo/.github/workflows/terraform.yml"

echo "Phoenix repositories verified together: Backstage + Floci + AWS organization + AWS units"
