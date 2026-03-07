#!/usr/bin/env bash
# sbomify-api.sh - Shared utilities for sbomify API calls
#
# Usage: source this file in other scripts (after common.sh)
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/sbomify-api.sh"
#
# Requires: SBOMIFY_TOKEN, curl, jq

set -euo pipefail

SBOMIFY_API="${SBOMIFY_API_URL:-https://app.sbomify.com}"

# Check if a component already has an SBOM with this digest as version
# Usage: sbomify_digest_exists <component_id> <digest>
# Returns: 0 if exists, 1 if not
sbomify_digest_exists() {
    local component_id="$1" digest="$2"

    local sboms
    sboms=$(curl -fsSL -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
        "${SBOMIFY_API}/api/v1/components/${component_id}/sboms")
    echo "$sboms" | jq -e --arg d "$digest" \
        '.items[] | select(.sbom.version == $d)' > /dev/null 2>&1
}

# Remove old SBOMs for a component (keep only current digest)
# Usage: sbomify_cleanup_old_sboms <component_id> <current_digest>
sbomify_cleanup_old_sboms() {
    local component_id="$1" current_digest="$2"

    local sboms old_ids
    sboms=$(curl -fsSL -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
        "${SBOMIFY_API}/api/v1/components/${component_id}/sboms")
    old_ids=$(echo "$sboms" | jq -r --arg d "$current_digest" \
        '.items[] | select(.sbom.version != $d) | .sbom.id')

    for sbom_id in $old_ids; do
        log_info "Removing old SBOM ${sbom_id} from component ${component_id}"
        curl -fsSL -X DELETE -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
            "${SBOMIFY_API}/api/v1/sboms/sbom/${sbom_id}" || true
    done
}

# Remove versioned releases from a product (keep only "latest")
# Usage: sbomify_cleanup_versioned_releases <product_id>
sbomify_cleanup_versioned_releases() {
    local product_id="$1"

    local releases release_ids
    releases=$(curl -fsSL -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
        "${SBOMIFY_API}/api/v1/releases?product_id=${product_id}")
    release_ids=$(echo "$releases" | jq -r \
        '.items[] | select(.is_latest != true) | .id')

    for release_id in $release_ids; do
        log_info "Removing versioned release ${release_id} from product ${product_id}"
        curl -fsSL -X DELETE -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
            "${SBOMIFY_API}/api/v1/releases/${release_id}" || true
    done
}
