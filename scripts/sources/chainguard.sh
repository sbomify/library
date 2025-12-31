#!/usr/bin/env bash
# chainguard.sh - Download SBOM from Chainguard image via cosign
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

app="$1"
version=$(get_latest_version "$app")
registry=$(get_config "$app" ".source.registry" "cgr.dev/chainguard")
image=$(get_config "$app" ".source.image")
platform=$(get_config "$app" ".source.platform" "linux/amd64")
image_ref="${registry}/${image}:${version}"

log_info "Downloading attestation: $image_ref"
cosign download attestation \
    --platform "$platform" \
    --predicate-type="https://spdx.dev/Document" \
    "$image_ref" 2>/dev/null | \
    jq -r '.payload | @base64d | fromjson | .predicate' > sbom.json
