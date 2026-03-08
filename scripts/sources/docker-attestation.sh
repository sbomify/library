#!/usr/bin/env bash
# docker-attestation.sh - Extract SBOM from Docker image OCI attestation
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

app="$1"
version=$(get_latest_version "$app")
registry=$(get_config "$app" ".source.registry" "docker.io")
image=$(get_config "$app" ".source.image")
platform="linux/amd64"
image_ref="${registry}/${image}:${version}"

log_info "Extracting SBOM: $image_ref"

# Get the image index (multi-arch manifest list)
index=$(crane manifest "$image_ref")

# Find the platform-specific image digest
IFS='/' read -r plat_os plat_arch <<< "$platform"
image_digest=$(echo "$index" | jq -r --arg os "$plat_os" --arg arch "$plat_arch" '
    .manifests[] |
    select(.platform.os == $os and .platform.architecture == $arch) |
    select(.annotations["vnd.docker.reference.type"] == null) |
    .digest
' | head -1)

[[ -z "$image_digest" || "$image_digest" == "null" ]] && \
    die "No image found for platform $platform"

log_debug "Image digest: $image_digest"
echo "$image_digest" > image-digest.txt

# Find the attestation manifest that references this image
sbom_digest=$(echo "$index" | jq -r --arg ref "$image_digest" '
    .manifests[] |
    select(
        .annotations["vnd.docker.reference.type"] == "attestation-manifest" and
        .annotations["vnd.docker.reference.digest"] == $ref
    ) | .digest
' | head -1)

[[ -z "$sbom_digest" || "$sbom_digest" == "null" ]] && die "No SBOM attestation found"

base_ref="${image_ref%:*}"
att_manifest=$(crane manifest "${base_ref}@${sbom_digest}")

sbom_layer=$(echo "$att_manifest" | jq -r '
    .layers[] |
    select(
        (.annotations["in-toto.io/predicate-type"] |
         (contains("spdx") or contains("cyclonedx"))) // false
    ) | .digest
' | head -1)

[[ -z "$sbom_layer" || "$sbom_layer" == "null" ]] && die "No SBOM layer found"

crane blob "${base_ref}@${sbom_layer}" | \
    jq -r 'if .predicate then .predicate else . end' > sbom.json
