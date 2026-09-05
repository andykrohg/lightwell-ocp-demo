# Lightwell Demo — From Vulnerable to Verified

A reusable, customer-facing demo that showcases the integration between
**Lightwell Network**, **Red Hat Trusted Profile Analyzer (TPA)**, and
**Red Hat Advanced Cluster Security (ACS)** as part of the
Red Hat Advanced Developer Suite.

The demo deploys a Java microservice in two variants — one built with standard
Maven Central dependencies containing known critical CVEs, and one rebuilt with
Lightwell Network remediated dependencies — then uses VEX-aware scanning,
SBOM tracking, and image signing to demonstrate a complete secure supply chain.

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
│  │  git-clone → maven-build ─┬─ vex-check                 │    │
│  │                           ├─ upload-sbom               │    │
│  │                           └─ buildah → cosign-sign ─┐  │    │
│  │                                       acs-check ────┤→ deploy│
│  │                                       acs-scan ─────┘  │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────┐  ┌─────────────────────────────────┐   │
│  │        ACS         │  │  Trusted Profile Analyzer (TPA) │   │
│  │  Signature policy  │  │  SBOM & vulnerability tracking  │   │
│  │  CVE monitoring    │  │  VEX advisory storage           │   │
│  └────────────────────┘  └─────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Demo Narrative

| Act | What Happens |
|-----|-------------|
| **1 — The Problem** | Build with standard Maven Central deps → pipeline vex-check shows all CVEs unresolved; TPA tracks the SBOM; ACS flags violations |
| **2 — The Fix** | Rebuild with Lightwell Network `.rhlw` deps + VEX data → pipeline vex-check suppresses patched CVEs; exploit demo proves functional fix |
| **3 — Lock the Door** | Enable VEX enforcement (`REQUIRE_VEX=true`) → vulnerable build fails at vex-check (zero VEX suppressions); remediated build passes |

## Prerequisites

### Cluster Operators

- **Red Hat OpenShift Pipelines** (Tekton) — v1.14+ (`tekton.dev/v1` API)
- **Red Hat Advanced Cluster Security** — Central deployed, API token generated
- **Red Hat Trusted Profile Analyzer** — deployed with OIDC client credentials available

### CLI Tools

- `oc` — logged into the target cluster
- `tkn` — Tekton CLI
- `podman` — container builds
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

# 3. Run the guided demo
make demo

# 4. Reset for next run
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
│   ├── index.html        Narrative + dependency table + deep links to TPA/ACS/OCP
│   └── Containerfile     UBI9 nginx, URLs injected via envsubst
├── vex/                  VEX (Vulnerability Exploitability eXchange) data
│   ├── lightwell-remediated.openvex.json   OpenVEX for pipeline vex-check
│   └── lightwell-remediated.json           CSAF VEX for TPA advisory upload
├── tekton/               Tekton CI pipeline
│   ├── pipeline.yaml     git-clone → build → vex-check → sign → scan → deploy
│   ├── tasks/            Custom tasks: vex-check, upload-sbom, acs-image-check/scan, cosign-sign
│   └── pipelinerun-*.yaml  Pre-configured runs for each variant
├── acs-policies/         ACS policy definitions (imported during setup)
├── manifests/
│   ├── base/             Kustomize base (catalog-app, dashboard)
│   ├── overlays/         Per-variant overlays (vulnerable, remediated, dashboard)
│   └── tpa/              TPA prerequisites + CR (used by install-tpa.sh)
├── scripts/              setup.sh, demo.sh (guided), reset.sh, exploit-demo.sh
├── demo.env.example      Environment config template (only ROX_API_TOKEN required)
└── Makefile              Build and deploy targets
```

## Key Dependencies (the Demo's Subject)

| Dependency | Vulnerable | Remediated | CVEs |
|-----------|-----------|------------|------|
| woodstox-core | 6.0.3 | 6.0.3.rhlw-00001 | CVE-2022-40152, CVE-2022-40156 |
| json-path | 2.7.0 | 2.7.0.rhlw-00001 | CVE-2023-51074, CVE-2023-1370 |
| org.json | 20220320 | 20220320.0.0.rhlw-00003 | CVE-2022-45688, CVE-2023-5072 |
| spring-core | 5.3.18 | 5.3.18.rhlw-00003 | CVE-2025-41249, CVE-2026-41848 |

## Container Images

| Image | Purpose |
|-------|---------|
| `quay.io/andy_krohg/lightwell-demo-catalog:vulnerable-latest` | Catalog app with vulnerable deps |
| `quay.io/andy_krohg/lightwell-demo-catalog:remediated-latest` | Catalog app with Lightwell deps |
| `quay.io/andy_krohg/lightwell-demo-hub:latest` | Static demo hub page |

## Make Targets

```
make help                    Show all targets
make setup                   One-time cluster setup (requires demo.env with ROX_API_TOKEN)
make demo                    Run guided interactive demo
make reset                   Reset demo state
make catalog-build-vulnerable  Build vulnerable catalog image
make catalog-build-remediated  Build remediated catalog image
make hub-build               Build demo hub image
make pipeline-vulnerable     Trigger vulnerable pipeline on cluster
make pipeline-remediated     Trigger remediated pipeline on cluster
make pipeline-logs           Follow latest pipeline logs
make status                  Show deployment status
```

## How the Demo Uses Each Product

**Lightwell Network** — The `remediated` Maven profile in `catalog-app/pom.xml`
pulls dependencies from the Lightwell Network public demo repository at
`packages.redhat.com` with `.rhlw-NNNNN` version suffixes. These are the same
upstream versions with backported security patches, SLSA L3 provenance, and
Sigstore signatures. Lightwell also publishes VEX data declaring these packages
as `not_affected` for the original CVEs. No credentials required for the demo
repository.

**VEX Check** — The pipeline includes a VEX-aware vulnerability scan step that
evaluates the SBOM against known CVE databases, then applies Lightwell's VEX
data to suppress findings for patched dependencies. For the vulnerable build,
all CVEs remain. For the remediated build, the Lightwell-covered CVEs are
suppressed. The `REQUIRE_VEX` pipeline parameter enables enforcement — when set
to `true`, builds where VEX suppresses zero vulnerabilities are blocked,
ensuring only builds with verified remediation data can proceed. This is the
pipeline step that correctly differentiates the two builds in Act 3.

**Trusted Profile Analyzer** — The pipeline uploads a CycloneDX SBOM (generated
by the `cyclonedx-maven-plugin`) to TPA after each build. Lightwell's CSAF VEX
document is uploaded during setup. TPA provides SBOM tracking and advisory
visibility. Note: TPA does not apply VEX data to its own CVE analysis, so both
SBOMs show the same CVE counts — the VEX suppression difference is only visible
in the pipeline vex-check logs.

**Advanced Cluster Security** — CVE watch policies (inform-only) flag known
vulnerabilities across deployments. A signature verification policy ensures only
cosign-signed images from the trusted pipeline can deploy. ACS provides runtime
monitoring and risk scoring for both deployment variants. Note: ACS CVE policies
cannot distinguish the two builds (both flag the same vulnerabilities), so
enforcement in the demo is handled by the pipeline vex-check, not ACS.

## Notes

- Both pipelines use `--soft-fail` on ACS checks so they deploy despite
  violations — ACS CVE policies flag both builds equally, so soft-fail lets
  you show both variants side by side.
- The `cosign-sign` task requires Red Hat Trusted Artifact Signer (RHTAS). If
  not configured, signing will fail but won't block the rest of the demo.
- The demo hub page auto-templates console URLs at container startup via
  `envsubst` — configure them in the Kustomize overlay ConfigMap.
