# sbomify SBOM Library

A collection of Software Bill of Materials (SBOMs) for popular open-source projects, automatically extracted and uploaded to [sbomify](https://sbomify.com) for public browsing.

## Overview

This repository manages SBOM extraction from multiple sources:

- **Docker OCI Attestations** - Extract SBOMs embedded in Docker images via BuildKit attestations
- **Chainguard Images** - Download signed SBOM attestations from Chainguard images via cosign
- **GitHub Releases** - Download SBOMs published as release assets
- **Lockfile Generation** - Generate SBOMs from project dependency lockfiles

Each app has its own folder with version tracking. When you bump the `version` in `config.yaml`, only that app's SBOM is rebuilt and uploaded - not the entire repository.

**Note:** Each version only needs to be processed once. Once an SBOM is uploaded to sbomify, it is permanently stored there. There is no need to re-process the same version.

## Projects

| Project | Component | Source | Job | sbomify |
|---------|-----------|--------|-----|---------|
| [Caddy](https://github.com/caddyserver/caddy) | Caddy | GitHub Release | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-caddy.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-caddy.yml) | [![sbomify](https://sbomify.com/assets/images/logo/badge.svg)](https://library.sbomify.com/product/caddy/) |
| [Dependency Track](https://github.com/DependencyTrack/dependency-track) | API Server | GitHub Release | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-dependency-track.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-dependency-track.yml) | [![sbomify](https://sbomify.com/assets/images/logo/badge.svg)](https://library.sbomify.com/product/dependency-track/) |
| [Dependency Track](https://github.com/DependencyTrack/frontend) | Frontend | GitHub Release | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-dependency-track-frontend.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-dependency-track-frontend.yml) | [![sbomify](https://sbomify.com/assets/images/logo/badge.svg)](https://library.sbomify.com/product/dependency-track/) |
| [OSV Scanner](https://github.com/google/osv-scanner) | OSV Scanner | Lockfile | [![SBOM](https://github.com/sbomify/library/actions/workflows/sbom-osv-scanner.yml/badge.svg)](https://github.com/sbomify/library/actions/workflows/sbom-osv-scanner.yml) | [![sbomify](https://sbomify.com/assets/images/logo/badge.svg)](https://library.sbomify.com/product/osv-scanner/) |

## Directory Structure

```
.
├── .github/
│   └── workflows/
│       ├── sbom-builder.yml          # Reusable workflow (main logic)
│       ├── _sbom-template.yml        # Template for new app workflows
│       └── sbom-<app-name>.yml       # Per-app workflow
├── apps/
│   └── <app-name>/                   # Example app
│       └── config.yaml               # App configuration (includes version)
├── scripts/
│   ├── fetch-sbom.sh                 # Main entry point
│   ├── lib/
│   │   └── common.sh                 # Shared utilities
│   └── sources/
│       ├── docker-attestation.sh     # Docker extraction
│       ├── github-release.sh         # GitHub release download
│       └── lockfile-generator.sh     # Lockfile-based generation
└── README.md
```

## Quick Start

### Adding a New App

1. **Create the app folder:**
   ```bash
   mkdir -p apps/myapp
   ```

2. **Create `apps/myapp/config.yaml`:**
   ```yaml
   name: myapp
   version: "1.0.0"  # Must be valid semver
   format: cyclonedx  # or spdx

   source:
     type: docker  # or github_release, lockfile, chainguard
     image: "library/myapp"
     registry: "docker.io"

   sbomify:
     component_id: "your-component-id"
     component_name: "My App"
   ```

   Valid version formats: `1.2.3`, `1.2.3-rc1`, `1.2.3-alpha.1+build`. **Note:** `latest` is not allowed.

3. **Create the workflow file:**
   ```bash
   cp .github/workflows/_sbom-template.yml .github/workflows/sbom-myapp.yml
   # Edit the file and replace 'example-app' with 'myapp'
   ```

4. **Commit and push:**
   ```bash
   git add apps/myapp .github/workflows/sbom-myapp.yml
   git commit -m "Add myapp SBOM"
   git push
   ```

### Bumping a Version

Simply update the `version` field in `config.yaml`:

```yaml
# apps/nginx/config.yaml
name: nginx
version: "1.26.0"  # Update this line
...
```

```bash
git add apps/nginx/config.yaml
git commit -m "Bump nginx to 1.26.0"
git push
```

The GitHub Action will automatically rebuild and upload only the nginx SBOM.

## Configuration Reference

### App Configuration (`config.yaml`)

```yaml
# Required: App name (should match folder name)
name: nginx

# Required: Version (must be valid semver)
version: "1.25.4"

# Required: SBOM format
format: cyclonedx  # cyclonedx | spdx

# Required: Source configuration
source:
  type: docker  # docker | github_release | lockfile | chainguard

  # ... source-specific options (see below)

# Required for upload: sbomify configuration
sbomify:
  component_id: "abc123-def456"
  component_name: "Nginx"
```

### Source Types

#### Docker OCI Attestations

Extract SBOMs from Docker image attestations (requires images built with BuildKit SBOM support):

```yaml
source:
  type: docker
  image: "library/nginx"          # Image name (required)
  registry: "docker.io"           # Registry (default: docker.io)
  platform: "linux/amd64"         # Platform (default: linux/amd64)
```

#### Chainguard Images

Download signed SBOM attestations from Chainguard images using cosign:

```yaml
source:
  type: chainguard
  image: "nginx"                  # Chainguard image name (required)
  registry: "cgr.dev/chainguard"  # Registry (default: cgr.dev/chainguard)
  platform: "linux/amd64"         # Platform (default: linux/amd64)
```

Note: Chainguard images use SPDX format by default. Set `format: spdx` in your config.

#### GitHub Release

Download SBOMs from GitHub release assets:

```yaml
source:
  type: github_release
  repo: "owner/repo"              # GitHub repository (required)
  asset: "bom.json"               # Asset filename (required, supports ${version})
  tag_prefix: "v"                 # Tag prefix (default: "")
  tag_suffix: ""                  # Tag suffix (default: "")
```

The `asset` field supports `${version}` substitution for projects that include the version in the asset filename:

```yaml
source:
  type: github_release
  repo: "caddyserver/caddy"
  asset: "caddy_${version}_linux_amd64.sbom"  # Becomes caddy_2.10.1_linux_amd64.sbom
  tag_prefix: "v"
```

#### Lockfile Generation

Generate SBOMs from project lockfiles:

```yaml
source:
  type: lockfile
  repo: "owner/repo"              # GitHub repository (required)
  lockfile: "package-lock.json"   # Path to lockfile (required)
  tag_prefix: "v"                 # Tag prefix
  generator: "auto"               # cdxgen | syft | auto
  extra_files:                    # Additional files to download
    - "package.json"
```

## Local Development

### Prerequisites

- **bash** 4.0+
- **jq** - JSON processor
- **yq** - YAML processor

For Docker sources:
- **docker** with buildx, or
- **crane** (from go-containerregistry), or
- **oras**

For Chainguard sources:
- **cosign** (from sigstore)

For lockfile generation:
- **cdxgen** (`npm install -g @cyclonedx/cdxgen`), or
- **syft**

### Running Locally

```bash
# List available apps
./scripts/fetch-sbom.sh --list

# Fetch SBOM for an app
./scripts/fetch-sbom.sh nginx

# Fetch with verbose output
./scripts/fetch-sbom.sh nginx --verbose

# Dry-run mode (no actual fetching)
./scripts/fetch-sbom.sh nginx --dry-run

# Output to file
./scripts/fetch-sbom.sh nginx --output sbom.json

# Override version
./scripts/fetch-sbom.sh nginx --version 1.24.0
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LOG_LEVEL` | Logging level: DEBUG, INFO, WARN, ERROR | `INFO` |
| `DRY_RUN` | Run in dry-run mode | `false` |
| `SBOMIFY_TOKEN` | sbomify API token for upload | - |
| `GH_TOKEN` | GitHub token for API access | - |

## GitHub Actions

### Secrets

Configure these secrets in your repository:

| Secret | Description | Required |
|--------|-------------|----------|
| `SBOMIFY_TOKEN` | sbomify API token for uploading SBOMs | For upload |

### Manual Trigger

Each app workflow can be manually triggered from the Actions tab with optional dry-run mode.

### Workflow Structure

- **Per-app workflows** (`sbom-<app-name>.yml`) - Thin wrappers that trigger on config.yaml changes
- **Reusable workflow** (`sbom-builder.yml`) - Contains all the build logic
- **Template** (`_sbom-template.yml`) - Copy this to create new app workflows

This design ensures:
1. Only the changed app is rebuilt (via path filters on config.yaml)
2. Build logic is centralized and maintainable
3. New apps just need a simple workflow file

## Contributing

1. Fork the repository
2. Add your app following the Quick Start guide
3. Test locally with `./scripts/fetch-sbom.sh <app-name>`
4. Submit a pull request

## License

See [LICENSE](LICENSE) for details.
