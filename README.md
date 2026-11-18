# phoenix-local — the standard local AWS environment

The single, versioned definition of the local AWS stack every Phoenix agent and
repo tests against, built on **[Floci](https://floci.io/floci/)** (a free,
open-source AWS emulator). It covers the services Phoenix actually uses —
**Organizations, Control Tower, Service Catalog, IAM, S3, DynamoDB,
CloudFormation, CodePipeline, CodeBuild, Lambda, Step Functions** — which is the
whole of Layer 0 (account vending) plus the Layer 2/3 data plane.

## The operating model

**`main` is the adopted standard. Anything not in `main` is not yet adopted.**

- Every Phoenix concern is its own repo with a protected `main`:
  `phoenix-aws-org` (Layer 0), `phoenix-aws` (Layers 2/3, incl. networking),
  `phoenix-backstage` (the front door), and **this** repo (the local env).
- Agents **branch → PR → merge to `main`**. Direct pushes to `main` are off.
- **Build is local, not CI.** Each agent pulls and runs Floci on their own
  machine (`make up` / `make seed` / `terraform apply -var floci=true`) — that
  is the inner loop. CI never builds or applies.
- **CI's only job is the downstream-breakage gate** — `terraform plan` /
  `terraform test` (mock providers) proving a change doesn't break any flow.
  The `floci-smoke` here is manual-only (re-verify the pin on demand).
- Changing the **shared standard** (this repo) is how agents coordinate so one
  agent's change can't break another's local downstream — review it on the PR.
- The **pin** in [`.env.example`](.env.example) (`FLOCI_VERSION`) *is* the
  standard — an unpinned or drifting version is not.

## Standardise the definition, isolate the instance

Floci starts in ~24 ms / ~13 MiB, so **each agent runs its own ephemeral
instance** from this one definition — same contract, no shared-state contention:

```bash
cp .env.example .env            # then set FLOCI_VERSION to the current stable
make up    PROJECT=phoenix-$USER   # your own container + state (unique project)
make seed                          # apply the Layer 0 baseline into it
make reset PROJECT=phoenix-$USER   # wipe when done
```

Host clients use `http://localhost:4566`; the containers Floci spawns for
Lambda/CodeBuild use `http://floci:4566`.

## Pointing Terraform at Floci

Each Phoenix root gates a `floci` variable so the **same** root targets real AWS
(`assume_role`) or local Floci (`endpoints` + skip flags + dummy creds) — see
[`providers-floci.tf.example`](providers-floci.tf.example). `make seed` sets
`TF_VAR_floci=1`.

## Make targets

| Target | What |
|---|---|
| `make up` | start this agent's Floci and wait for it |
| `make seed` | apply the Layer 0 baseline (org + landing zone + OUs + SCP + registry) |
| `make down` | stop (keep the data volume) |
| `make reset` | wipe container + volume |
| `make logs` / `make sh` | follow logs / shell in |
| `make verify-backstage` | seed Floci, build Backstage, verify catalog/orchestrator startup, and run downstream tests across all four repos |

## Backstage integration verification

Keep the four repositories as siblings named `backstage`, `AWS`,
`AWS-organization`, and `phoenix-local`, then run:

```bash
make verify-backstage PROJECT=phoenix-integration-$USER
```

The project name scopes both Docker Compose stacks so cleanup never targets an
unrelated developer environment. Override repository locations with
`PHOENIX_BACKSTAGE_DIR`, `PHOENIX_AWS_DIR`, `PHOENIX_AWS_ORG_DIR`, and
`PHOENIX_LOCAL_DIR`. Set `KEEP_STACK=1` to retain containers after verification.

The check proves local integration only: Backstage starts in explicit `floci`
mode, reads the seeded account registry, loads the catalog/templates, and runs
the orchestration/provider gates. It does not execute Terraform from Backstage
and does not choose a workflow runner location.

## Status / open items

- **`FLOCI_VERSION` is pinned to `nightly`** — proven by the `floci-smoke` CI to
  apply Organizations + Control Tower landing zone + DynamoDB cleanly. `2.4.0`
  fails the landing-zone read-back (fix is in main, not yet in a stable tag).
  **Re-pin to the first stable release** that includes PRs #7298/#7403.
- The **`floci` provider gate** in each root is finalised on the `floci-harness`
  branch (first PR against this standard).
- Emulated ≠ identical: IAM enforcement, OIDC *federation* semantics, and true
  account isolation still only prove out on real AWS — the first live apply
  remains the final fidelity check.
