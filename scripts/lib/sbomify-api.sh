#!/usr/bin/env bash
# sbomify-api.sh - Shared utilities for sbomify API calls
#
# Usage: source this file in other scripts (after common.sh)
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/sbomify-api.sh"
#
# Requires: SBOMIFY_TOKEN, curl, jq

set -euo pipefail

SBOMIFY_API="${SBOMIFY_API_URL:-https://app.sbomify.com}"

# Check if a release artifact already has this digest version
# Usage: sbomify_digest_exists <product_id> <tag_version> <component_id> <digest>
# Returns: 0 if exists, 1 if not
sbomify_digest_exists() {
    local product_id="$1" tag_version="$2" component_id="$3" digest="$4"

    # Find the release
    local releases release_id
    releases=$(curl -fsSL -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
        "${SBOMIFY_API}/api/v1/releases?product_id=${product_id}&version=${tag_version}")
    release_id=$(echo "$releases" | jq -r --arg v "$tag_version" \
        '.items[] | select(.version == $v) | .id' | head -1)

    [[ -z "$release_id" ]] && return 1  # No release → digest doesn't exist

    # Check artifacts for matching digest
    local artifacts
    artifacts=$(curl -fsSL -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
        "${SBOMIFY_API}/api/v1/releases/${release_id}/artifacts?mode=existing")
    echo "$artifacts" | jq -e --arg cid "$component_id" --arg d "$digest" \
        '.items[] | select(.component_id == $cid and .sbom_version == $d)' > /dev/null 2>&1
}

# Remove old artifacts for a component from a release (keep only current digest)
# Usage: sbomify_cleanup_old_artifacts <product_id> <tag_version> <component_id> <current_digest>
sbomify_cleanup_old_artifacts() {
    local product_id="$1" tag_version="$2" component_id="$3" current_digest="$4"

    # Find the release
    local releases release_id
    releases=$(curl -fsSL -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
        "${SBOMIFY_API}/api/v1/releases?product_id=${product_id}&version=${tag_version}")
    release_id=$(echo "$releases" | jq -r --arg v "$tag_version" \
        '.items[] | select(.version == $v) | .id' | head -1)

    [[ -z "$release_id" ]] && return 0  # No release → nothing to clean

    # Find old artifacts for this component with different digest
    local old_ids
    old_ids=$(curl -fsSL -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
        "${SBOMIFY_API}/api/v1/releases/${release_id}/artifacts?mode=existing" | \
        jq -r --arg cid "$component_id" --arg d "$current_digest" \
        '.items[] | select(.component_id == $cid and .sbom_version != $d) | .id')

    for artifact_id in $old_ids; do
        log_info "Removing old artifact ${artifact_id} from release ${release_id}"
        curl -fsSL -X DELETE -H "Authorization: Bearer ${SBOMIFY_TOKEN}" \
            "${SBOMIFY_API}/api/v1/releases/${release_id}/artifacts/${artifact_id}"
    done
}
