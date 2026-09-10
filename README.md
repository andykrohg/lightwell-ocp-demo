# Lightwell Demo — From Vulnerable to Verified

A reusable, customer-facing demo that showcases the integration between
**Lightwell Network**, **Red Hat Trusted Profile Analyzer (TPA)**, and
**Red Hat Advanced Cluster Security (ACS)** as part of the
Red Hat Advanced Developer Suite.

The demo deploys a Java microservice in two variants — one built with a
vulnerable open-source dependency, and one rebuilt with the Lightwell Network
remediated version — then uses a live exploit, automated VEX reconciliation,
and SBOM tracking to demonstrate a complete secure supply chain.

## The CVE

The demo centers on **CVE-2022-40152** — a denial-of-service vulnerability in
**woodstox-core 6.0.3**. A tiny crafted XML document (~1 KB) with deeply nested
DTD element declarations triggers unbounded recursion in the parser, crashing
the service with a StackOverflowError. The Lightwell-remediated version
(`6.0.3.rhlw-00001`) adds a recursion depth limit of 500, eliminating the
attack vector.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    OpenShift Cluster                             │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐  │
│  │ catalog-app  │  │ catalog-app  │  │     demo-hub         │  │
│  │ (vulnerable) │  │ (remediated) │  │ (links to native UIs)│  │
│  └──────┬───────┘  └──────┬───────┘  └──────────────────────┘  │
│         │                 │                                     │
│  ┌──────┴─────────────────┴───────────────────────────────┐    │
│  │              Tekton Pipeline                            │    │
│  │  git-clone → maven-build ─┬─ upload-sbom → vex-reconcile│    │
│  │                           └─ buildah ─┐                │    │
│  │                           acs-check ──┤→ deploy        │    │
│  │                           acs-scan ───┘                │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────┐  ┌─────────────────────────────────┐   │
│  │        ACS         │  │  Trusted Profile Analyzer (TPA) │   │
│  │  CVE monitoring    │  │  SBOM & vulnerability tracking  │   │
│  │  VEX reconciliation│  │  VEX advisory storage           │   │
│  └────────────────────┘  └─────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Demo Flow

| Act | What Happens | Command |
|-----|-------------|---------|
| **1 — The Problem** | Build with vulnerable woodstox-core → ACS flags CVE-2022-40152; live exploit crashes the service | `make pipeline-vulnerable` |
| **2 — The Fix** | Rebuild with Lightwell `.rhlw` version → vex-reconcile creates ACS exception; same exploit is rejected cleanly | `make pipeline-remediated` |
| **3 — Lock the Door** | Enable ACS enforcement → vulnerable build blocked by policy (no VEX exception) | `make pipeline-enforce` |

## Prerequisites

### Cluster Operators

- **Red Hat OpenShift Pipelines** (Tekton) — v1.14+ (`tekton.dev/v1` API)
- **Red Hat Advanced Cluster Security** — Central deployed, API token generated
- **Red Hat Trusted Profile Analyzer** — deployed with OIDC client credentials available

### CLI Tools

- `oc` — logged into the target cluster
- `tkn` — Tekton CLI
- `jq` — used by setup script

### Configuration

All cluster-specific values (TPA URLs, ACS endpoints, OCP console) are
auto-detected via `oc`. Just copy the example env file and add your ACS token:

```bash
cp demo.env.example demo.env
# Edit demo.env — set ROX_API_TOKEN
```

> **Note:** The Lightwell demo repository at `packages.redhat.com` is publicly
> accessible — no Lightwell credentials are required.

## Quick Start

```bash
# 0. Log into the cluster
oc login ...

# 1. Install TPA (if not already deployed)
./scripts/install-tpa.sh

# 2. One-time cluster setup (auto-detects TPA/ACS/OCP URLs)
make setup

# 3. Open the demo hub for the guided walkthrough
make status   # shows the demo-hub route URL

# 4. Follow the demo hub — run pipelines as prompted
make pipeline-vulnerable
make pipeline-remediated
make pipeline-enforce

# 5. Reset for next run
make reset
```

## Project Structure

```
lightwell-ocp-demo/
├── catalog-app/          Spring Boot product catalog (dual Maven profiles)
│   ├── pom.xml           vulnerable (default) + remediated profiles
│   ├── Containerfile     Multi-stage build for local dev
│   └── src/              REST API: /api/products, /api/health, /api/dependencies
├── demo-hub/             Static landing page with links to native UIs
│   ├── index.html        Narrative + deep links to TPA/ACS/OCP
│   └── Containerfile     UBI9 nginx, URLs injected via envsubst
├── tekton/               Tekton CI pipeline
│   ├── pipeline.yaml     git-clone → build → upload-sbom → scan → deploy
│   ├── tasks/            Custom tasks: upload-sbom, vex-reconcile, acs-image-check/scan
│   └── pipelinerun-*.yaml  Pre-configured runs for each variant
├── acs-policies/         ACS policy definitions (imported during setup)
├── manifests/
│   ├── base/             Kustomize base (catalog-app, dashboard)
│   ├── overlays/         Per-variant overlays (vulnerable, remediated, dashboard)
│   └── tpa/              TPA prerequisites + CR (used by install-tpa.sh)
├── scripts/              setup.sh, reset.sh, exploit-demo.sh
├── demo.env.example      Environment config template (only ROX_API_TOKEN required)
└── Makefile              Build and deploy targets
```

## Make Targets

```
make help                    Show all targets
make setup                   One-time cluster setup (requires demo.env with ROX_API_TOKEN)
make reset                   Reset demo state
make pipeline-vulnerable     Trigger vulnerable pipeline on cluster
make pipeline-remediated     Trigger remediated pipeline on cluster
make pipeline-enforce        Trigger vulnerable build with ACS enforcement (should fail)
make pipeline-logs           Follow latest pipeline logs
make status                  Show deployment status
make build-vulnerable        Build catalog-app locally with vulnerable profile
make build-remediated        Build catalog-app locally with remediated profile
make hub-build               Build demo hub container image
```

## How the Demo Uses Each Product

**Lightwell Network** — The `remediated` Maven profile in `catalog-app/pom.xml`
overrides `woodstox-core` to version `6.0.3.rhlw-00001` from the Lightwell
public demo repository at `packages.redhat.com`. This is the same upstream
version with a backported security patch (recursion depth limit), SLSA L3
provenance, and Sigstore signatures. Lightwell also publishes VEX data
declaring this package as `not_affected` for CVE-2022-40152. No credentials
required.

**Trusted Profile Analyzer** — The pipeline uploads a CycloneDX SBOM (generated
by the `cyclonedx-maven-plugin`) to TPA after each build. TPA ingests Red Hat
CSAF advisories and Lightwell VEX data, providing SBOM tracking and advisory
visibility across both build variants.

**VEX Reconciliation** — The `vex-reconcile` pipeline task queries TPA's
`/api/v3/vulnerability/analyze` endpoint to find CVEs with resolving VEX
statuses (`not_affected`, `fixed`). It then automatically creates false-positive
exceptions in ACS for those CVEs, scoped to the pipeline's image. This bridges
TPA's advisory intelligence with ACS's policy enforcement.

**Advanced Cluster Security** — A CVE watch policy flags CVE-2022-40152 across
deployments. In soft-fail mode (default), violations are logged but builds
proceed. With `SOFT_FAIL=false` (`make pipeline-enforce`), the ACS image check
blocks builds with unresolved CVE violations — but the remediated build passes
because vex-reconcile already created the exception.

## Notes

- Both pipelines use `--soft-fail` on ACS checks so they deploy despite
  violations — this lets you show both variants side by side.
- The demo hub page auto-templates console URLs at container startup via
  `envsubst` — configured in the Kustomize overlay ConfigMap.
