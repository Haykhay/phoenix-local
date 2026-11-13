#!/usr/bin/env bash
# Seed the shared Layer 0 baseline into a running Floci so every agent starts
# from the same governed org (Organizations + Control Tower landing zone + OUs +
# SCP + core accounts, and the registry table). Points Terraform at Floci.
#
# Usage: make seed   (or LANDING_ZONE_DIR=/path REGISTRY_DIR=/path ./seed/seed.sh)
set -euo pipefail

: "${LANDING_ZONE_DIR:=../AWS-organization/landing-zone}"
: "${REGISTRY_DIR:=../AWS-organization/registry}"
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
export AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-west-1}"

apply() {
  local dir="$1"
  echo "== seeding: $dir =="
  terraform -chdir="$dir" init -backend=false -input=false >/dev/null
  # TF_VAR_floci=1 selects the Floci-friendly provider (endpoints + skip flags)
  # in the root. See providers-floci.tf — finalised on the floci-harness branch.
  TF_VAR_floci=1 terraform -chdir="$dir" apply -auto-approve -input=false
}

apply "$LANDING_ZONE_DIR"
apply "$REGISTRY_DIR"
echo "seeded Layer 0 into Floci at $AWS_ENDPOINT_URL"
