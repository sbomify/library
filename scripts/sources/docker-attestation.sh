#!/usr/bin/env bash
# docker-attestation.sh - Extract SBOM from Docker image OCI attestation
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

app="$1"
version=$(get_latest_version "$app")
registry=$(get_config "$app" ".source.registry" "docker.io")
image=$(get_config "$app" ".source.image")
platform=$(get_config "$app" ".source.platform" "linux/amd64")
image_ref="${registry}/${image}:${version}"

log_info "Extracting SBOM: $image_ref"

manifest=$(crane manifest "$image_ref" --platform "$platform")

sbom_digest=$(echo "$manifest" | jq -r '
    .manifests[] |
    select(
        (.annotations["vnd.docker.reference.type"] == "attestation-manifest") or
        (.artifactType | contains("sbom") // false)
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
