#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
script="$repo_root/scripts/verify-backstage-integration.sh"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin" "$tmp/backstage" "$tmp/aws" "$tmp/aws-org" "$tmp/local"
for command in docker terraform aws actionlint node; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/$command"
  chmod +x "$tmp/bin/$command"
done

run_preflight() {
  PATH="$tmp/bin:$PATH" \
  PHOENIX_BACKSTAGE_DIR="$tmp/backstage" \
  PHOENIX_AWS_DIR="$tmp/aws" \
  PHOENIX_AWS_ORG_DIR="$tmp/aws-org" \
  PHOENIX_LOCAL_DIR="$tmp/local" \
  PROJECT="phoenix-integration-test" \
  "$script" --preflight
}

output=$(run_preflight)
grep -q '^local_project=phoenix-integration-test-floci$' <<<"$output"
grep -q '^backstage_project=phoenix-integration-test-backstage$' <<<"$output"

if PATH="$tmp/bin:$PATH" \
  PHOENIX_BACKSTAGE_DIR="$tmp/missing" \
  PHOENIX_AWS_DIR="$tmp/aws" \
  PHOENIX_AWS_ORG_DIR="$tmp/aws-org" \
  PHOENIX_LOCAL_DIR="$tmp/local" \
  "$script" --preflight >"$tmp/missing.out" 2>&1; then
  echo "expected missing repository preflight to fail" >&2
  exit 1
fi
grep -q 'missing repository:.*backstage' "$tmp/missing.out"

rm "$tmp/bin/docker"
if run_preflight >"$tmp/tool.out" 2>&1; then
  echo "expected missing docker preflight to fail" >&2
  exit 1
fi
grep -q 'required command not found: docker' "$tmp/tool.out"

echo "integration harness preflight tests passed"

make -n -C "$repo_root" verify-backstage | grep -q 'scripts/verify-backstage-integration.sh'
