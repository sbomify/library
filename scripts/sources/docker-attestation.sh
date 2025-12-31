#!/usr/bin/env bash
# docker-attestation.sh - Extract SBOMs from Docker image OCI attestations
#
# This script extracts SBOM attestations that are embedded in Docker images
# using BuildKit's provenance and SBOM attestation features.
#
# Usage: ./docker-attestation.sh <app-name> <output-file>

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# =============================================================================
# Docker-specific configuration
# =============================================================================

# Default registry
DEFAULT_REGISTRY="docker.io"

# =============================================================================
# Functions
# =============================================================================

show_help() {
    print_usage "$(basename "$0")" "Extract SBOMs from Docker image OCI attestations.

Config options in config.yaml:
  source.type: docker
  source.image: Image name (e.g., 'library/nginx' or 'myorg/myapp')
  source.registry: Registry URL (default: docker.io)
  source.platform: Target platform (default: linux/amd64)"
}

# Check if required Docker tools are available
check_docker_tools() {
    if ! command -v crane &> /dev/null; then
        die "Required command 'crane' not found."
    fi
    log_debug "Found crane"
}

# Get the full image reference for a given app and version
get_image_ref() {
    local app="$1"
    local version="$2"

    local registry image
    registry="$(get_config "$app" ".source.registry" "$DEFAULT_REGISTRY")"
    image="$(get_config "$app" ".source.image")"

    echo "${registry}/${image}:${version}"
}

# Extract SBOM using crane
extract_sbom() {
    local app="$1"
    local version="$2"
    local output_file="$3"

    local image_ref platform
    image_ref=$(get_image_ref "$app" "$version")
    platform=$(get_config "$app" ".source.platform" "linux/amd64")

    log_info "Extracting SBOM from Docker image"
    log_info "  Image: $image_ref"
    log_info "  Platform: $platform"

    # Get the manifest
    local manifest
    manifest=$(crane manifest "$image_ref" --platform "$platform" 2>/dev/null) || {
        die "Failed to get manifest for $image_ref"
    }

    # Find SBOM attestation in manifest list
    if echo "$manifest" | jq -e '.manifests' > /dev/null 2>&1; then
        local sbom_digest
        sbom_digest=$(echo "$manifest" | jq -r '
            .manifests[] |
            select(
                (.annotations["vnd.docker.reference.type"] == "attestation-manifest") or
                (.artifactType | contains("sbom") // false)
            ) |
            .digest
        ' | head -1)

        if [[ -n "$sbom_digest" && "$sbom_digest" != "null" ]]; then
            log_debug "Found SBOM attestation: $sbom_digest"

            local base_ref="${image_ref%:*}"
            local att_manifest
            att_manifest=$(crane manifest "${base_ref}@${sbom_digest}" 2>/dev/null) || {
                die "Failed to get attestation manifest"
            }

            # Get SBOM layer
            local sbom_layer
            sbom_layer=$(echo "$att_manifest" | jq -r '
                .layers[] |
                select(
                    (.annotations["in-toto.io/predicate-type"] |
                     (contains("spdx") or contains("cyclonedx"))) // false
                ) |
                .digest
            ' | head -1)

            if [[ -n "$sbom_layer" && "$sbom_layer" != "null" ]]; then
                log_debug "Fetching SBOM blob: $sbom_layer"

                crane blob "${base_ref}@${sbom_layer}" 2>/dev/null | \
                    jq -r 'if .predicate then .predicate else . end' > "$output_file" || {
                    die "Failed to extract SBOM blob"
                }

                log_info "Extracted successfully"
                return 0
            fi
        fi
    fi

    die "No SBOM attestation found in $image_ref"
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
    check_docker_tools
    validate_app_dir "$app"

    # Get version and verify source type
    local version source_type
    version=$(get_latest_version "$app")
    source_type=$(get_source_type "$app")

    if [[ "$source_type" != "docker" ]]; then
        die "App '$app' is not configured for Docker (source.type=$source_type)"
    fi

    log_info "Processing app: $app, version: $version"

    # Extract directly to output file
    extract_sbom "$app" "$version" "$output_file"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
