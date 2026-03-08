# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

sbomify SBOM Library — automates Software Bill of Materials (SBOM) extraction from popular open-source projects and uploads them to sbomify.com. Each app has a `config.yaml` defining its version, SBOM format, and source type.

## Architecture

**Config-driven, per-app model:** Each app in `apps/<name>/config.yaml` declares how to fetch its SBOM. A central reusable workflow (`sbom-builder.yml`) reads the config and dispatches to the appropriate source handler.

**Four SBOM source types** (each in `scripts/sources/`):
- `docker` — extract from Docker OCI attestations via `crane`
- `chainguard` — download signed attestations via `cosign`
- `github_release` — download SBOM asset from a GitHub release
- `lockfile` — download a lockfile (or clone repo) for SBOM generation

**Script structure:**
- `scripts/fetch-sbom.sh` — entry point, routes to source handler
- `scripts/lib/common.sh` — shared utilities (logging, validation, config parsing)
- `scripts/sources/*.sh` — one handler per source type

**CI/CD pattern:** Each app has a thin trigger workflow (`sbom-<app>.yml`) that calls the reusable `sbom-builder.yml`. Path-based triggers ensure only changed apps rebuild. `ci.yml` validates PRs in dry-run mode.

## Common Commands

```bash
# Run full SBOM pipeline for an app (fetch, build, dedup, upload)
./scripts/run.sh <app-name>
./scripts/run.sh <app-name> --dry-run
./scripts/run.sh --all
./scripts/run.sh --all --parallel 5
./scripts/run.sh --type docker
./scripts/run.sh --app redis,trivy

# Fetch SBOM only (no augment/upload)
./scripts/fetch-sbom.sh <app-name>

# Debug logging
LOG_LEVEL=DEBUG ./scripts/run.sh <app-name>

# Lint
shellcheck scripts/**/*.sh
yamllint .
```

> **Note:** Per-app workflow triggers (`sbom-*.yml`) are disabled (dispatch-only). Use `run.sh` for local execution. The lint workflow remains active on PRs.

## Adding a New App

1. Copy `apps/.template/` to `apps/<new-name>/`
2. Edit `config.yaml` with version, format, source config, and sbomify component ID
3. Copy `.github/workflows/_sbom-template.yml` to `.github/workflows/sbom-<new-name>.yml` and update paths/name

## Code Conventions

- **Bash:** `set -euo pipefail`, shellcheck-clean, proper quoting. Variables: `UPPER_CASE` for exports, `lower_case` for locals. Functions: `verb_noun` naming.
- **YAML:** 2-space indent, 120-char line limit (`.yamllint.yml`).
- **Versions:** Strict semver required in config.yaml — no "latest" tags.
- **App naming:** lowercase with hyphens (e.g., `osv-scanner`, `dependency-track-frontend`).

## Environment Variables

- `LOG_LEVEL` — DEBUG, INFO, WARN, ERROR (default: INFO)
- `DRY_RUN` — true/false
- `SBOMIFY_TOKEN` — API token for sbomify upload
- `GH_TOKEN` — GitHub API token

## Required Tools

bash 4.0+, jq, yq, crane, cosign (for chainguard sources), git
