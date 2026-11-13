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
- Agents **branch → PR → CI → merge to `main`**. Direct pushes to `main` are off.
- Everyone **develops Floci and Backstage against this standard**; when a change
  lands in a repo's `main`, others `git pull` and build on it.
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
