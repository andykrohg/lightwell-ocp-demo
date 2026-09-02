# Lightwell Demo — From Vulnerable to Verified

A reusable, customer-facing demo that showcases the integration between
**Lightwell Network**, **Red Hat Trusted Profile Analyzer (TPA)**, and
**Red Hat Advanced Cluster Security (ACS)** as part of the
Red Hat Advanced Developer Suite.

The demo deploys a Java microservice in two variants — one built with standard
Maven Central dependencies containing known critical CVEs, and one rebuilt with
Lightwell Network remediated dependencies — then walks through the security
posture of each using the native TPA, ACS, and OpenShift consoles.

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
│  │  git-clone → maven-build → buildah → cosign-sign ─┐    │    │
│  │                  │                   acs-check ────┤→ deploy │
│  │                  └─ upload-sbom      acs-scan ─────┘    │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                 │
│  ┌────────────────────┐  ┌─────────────────────────────────┐   │
│  │        ACS         │  │  Trusted Profile Analyzer (TPA) │   │
│  │  Policy violations │  │  SBOM & vulnerability analysis  │   │
│  │  Image scanning    │  │                                 │   │
│  │  Risk scoring      │  │                                 │   │
│  └────────────────────┘  └─────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Demo Narrative

| Act | What Happens |
|-----|-------------|
| **1 — The Problem** | Build with standard Maven Central deps → TPA shows CVEs in woodstox, json-path, org.json, and spring-core; ACS fires policy violations |
| **2 — The Solution** | Rebuild with Lightwell Network `.rhlw` deps → same versions, same API, backported patches |
| **3 — Verified** | TPA shows 0 critical CVEs, ACS policies pass, image signed, SBOM tracked |

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

### Credentials

```bash
export ROX_API_TOKEN="..."
export ROX_CENTRAL_ENDPOINT="central-acs.apps.mycluster.com"
export TPA_URL="https://tpa.apps.mycluster.com"
export TPA_CLIENT_ID="walker"
export TPA_CLIENT_SECRET="..."
export TPA_OIDC_ISSUER="https://sso.apps.mycluster.com/realms/trustify"
```

> **Note:** The Lightwell demo repository at `packages.redhat.com` is publicly
> accessible — no Lightwell credentials are required.

## Quick Start

```bash
# 1. One-time cluster setup
make setup

# 2. Run the guided demo
make demo

# 3. Reset for next run
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
├── tekton/               Tekton CI pipeline
│   ├── pipeline.yaml     git-clone → build → sign → scan → deploy
│   ├── tasks/            Custom tasks: upload-sbom, acs-image-check/scan, cosign-sign
│   └── pipelinerun-*.yaml  Pre-configured runs for each variant
├── acs-policies/         ACS policy definitions (imported during setup)
├── manifests/            Kustomize base + overlays for each deployment
├── scripts/              setup.sh, demo.sh (guided), reset.sh
└── Makefile              Build and deploy targets
```

## Key Dependencies (the Demo's Subject)

| Dependency | Vulnerable | Remediated | CVEs |
|-----------|-----------|------------|------|
| woodstox-core | 6.0.3 | 6.0.3.rhlw-00001 | CVE-2022-40152, CVE-2022-40156 |
| json-path | 2.7.0 | 2.7.0.rhlw-00001 | CVE-2023-51074, CVE-2023-1370 |
| org.json | 20220320 | 20220320.0.0.rhlw-00003 | CVE-2022-45688, CVE-2023-5072 |
| spring-core | 5.3.18 | 5.3.18.rhlw-00003 | CVE-2022-22968, CVE-2023-20861 |

## Container Images

| Image | Purpose |
|-------|---------|
| `quay.io/andy_krohg/lightwell-demo-catalog:vulnerable-latest` | Catalog app with vulnerable deps |
| `quay.io/andy_krohg/lightwell-demo-catalog:remediated-latest` | Catalog app with Lightwell deps |
| `quay.io/andy_krohg/lightwell-demo-hub:latest` | Static demo hub page |

## Make Targets

```
make help                    Show all targets
make setup                   One-time cluster setup
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
Sigstore signatures. No credentials required for the demo repository.

**Trusted Profile Analyzer** — The Tekton pipeline uploads a CycloneDX SBOM
(generated by the `cyclonedx-maven-plugin`) to TPA after each build. During the
demo, the presenter opens the TPA console to compare vulnerability counts
between the two SBOMs.

**Advanced Cluster Security** — Three custom ACS policies are imported during
setup: block critical CVEs (CVSS >= 9.0), block specific CVEs (woodstox,
json-path, org.json, spring-core), and require image signatures. The vulnerable
build triggers violations; the remediated build passes clean.

## Notes

- The vulnerable pipeline uses `--soft-fail` on ACS checks so it deploys despite
  violations — this lets you show both variants side by side.
- The `cosign-sign` task requires Red Hat Trusted Artifact Signer (RHTAS). If
  not configured, signing will fail but won't block the rest of the demo.
- The demo hub page auto-templates console URLs at container startup via
  `envsubst` — configure them in the Kustomize overlay ConfigMap.
