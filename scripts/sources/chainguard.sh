#!/usr/bin/env bash
# chainguard.sh - Download SBOMs from Chainguard images via cosign attestations
#
# Chainguard images include SPDX SBOMs as signed attestations that can be
# downloaded using cosign.
#
# Usage: ./chainguard.sh <app-name> <output-file>

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# =============================================================================
# Chainguard-specific configuration
# =============================================================================

# Default registry for Chainguard images
CHAINGUARD_REGISTRY="cgr.dev/chainguard"

# SPDX predicate type for attestations
SPDX_PREDICATE_TYPE="https://spdx.dev/Document"

# =============================================================================
# Functions
# =============================================================================

show_help() {
    print_usage "$(basename "$0")" "Download SBOMs from Chainguard images via cosign attestations.

Config options in config.yaml:
  source.type: chainguard
  source.image: Image name (e.g., 'nginx', 'python', 'node')
  source.registry: Registry URL (default: cgr.dev/chainguard)
  source.platform: Target platform (default: linux/amd64)"
}

# Check if cosign is available
check_chainguard_tools() {
    if ! command -v cosign &> /dev/null; then
        die "Required command 'cosign' not found."
    fi
    log_debug "Found cosign"
}

# Get the full image reference for a given app and version
get_image_ref() {
    local app="$1"
    local version="$2"

    local registry image
    registry="$(get_config "$app" ".source.registry" "$CHAINGUARD_REGISTRY")"
    image="$(get_config "$app" ".source.image")"

    echo "${registry}/${image}:${version}"
}

# Download SBOM attestation using cosign
download_sbom() {
    local app="$1"
    local version="$2"
    local output_file="$3"

    local image_ref platform
    image_ref=$(get_image_ref "$app" "$version")
    platform=$(get_config "$app" ".source.platform" "linux/amd64")

    log_info "Downloading SBOM from Chainguard image"
    log_info "  Image: $image_ref"
    log_info "  Platform: $platform"

    # Download attestation and extract SBOM predicate
    cosign download attestation \
        --platform "$platform" \
        --predicate-type="$SPDX_PREDICATE_TYPE" \
        "$image_ref" 2>/dev/null | \
        jq -r '.payload | @base64d | fromjson | .predicate' > "$output_file" || {
        die "Failed to download SBOM attestation from $image_ref"
    }

    log_info "Downloaded to: $output_file"
}

# =============================================================================
# Main
# =============================================================================

main() {
    if ! parse_common_args "$@"; then
        show_help
        exit 0
    fi
    set -- "${REMAINING_ARGS[@]}"

    if [[ $# -lt 2 ]]; then
        show_help
        exit 1
    fi

    local app="$1"
    local output_file="$2"

    # Validate
    check_required_tools
    check_chainguard_tools
    validate_app_dir "$app"

    # Get version and verify source type
    local version source_type
    version=$(get_latest_version "$app")
    source_type=$(get_source_type "$app")

    if [[ "$source_type" != "chainguard" ]]; then
        die "App '$app' is not configured for Chainguard (source.type=$source_type)"
    fi

    log_info "Processing app: $app, version: $version"

    # Download directly to output file
    download_sbom "$app" "$version" "$output_file"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
