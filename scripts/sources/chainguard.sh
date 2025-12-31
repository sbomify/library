#!/usr/bin/env bash
# chainguard.sh - Download SBOMs from Chainguard images via cosign attestations
#
# Chainguard images include SPDX SBOMs as signed attestations that can be
# downloaded using cosign.
#
# Usage: ./chainguard.sh <app-name>

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

# CycloneDX predicate type (if available)
CYCLONEDX_PREDICATE_TYPE="https://cyclonedx.org/bom"

# =============================================================================
# Functions
# =============================================================================

show_help() {
    print_usage "$(basename "$0")" "Download SBOMs from Chainguard images via cosign attestations.

Chainguard images include signed SBOM attestations that can be verified
and downloaded using cosign.

Config options in config.yaml:
  source.type: chainguard
  source.image: Image name (e.g., 'nginx', 'python', 'node')
  source.registry: Registry URL (default: cgr.dev/chainguard)
  source.platform: Target platform (default: linux/amd64)
  source.predicate_type: Attestation predicate type (default: https://spdx.dev/Document)"
}

# Check if cosign is available
check_chainguard_tools() {
    if ! command -v cosign &> /dev/null; then
        die "Required command 'cosign' not found. Install from: https://docs.sigstore.dev/cosign/installation/"
    fi
    log_debug "Found cosign"
    
    if ! command -v docker &> /dev/null; then
        log_warn "Docker not found - image pulling will be skipped"
    else
        log_debug "Found docker"
    fi
}

# Get the full image reference for a given app and version
get_image_ref() {
    local app="$1"
    local version="$2"
    
    local registry image
    registry="$(get_config "$app" ".source.registry" "$CHAINGUARD_REGISTRY")"
    image="$(get_config "$app" ".source.image")"
    
    # Version is required and validated as semver by common.sh
    echo "${registry}/${image}:${version}"
}

# Get the predicate type based on format
get_predicate_type() {
    local app="$1"
    local format="$2"
    
    # Check if explicitly configured
    local configured_type
    configured_type="$(get_config "$app" ".source.predicate_type" "")"
    
    if [[ -n "$configured_type" ]]; then
        echo "$configured_type"
        return
    fi
    
    # Default based on format
    case "$format" in
        spdx)
            echo "$SPDX_PREDICATE_TYPE"
            ;;
        cyclonedx)
            echo "$CYCLONEDX_PREDICATE_TYPE"
            ;;
        *)
            # Default to SPDX as Chainguard primarily uses SPDX
            echo "$SPDX_PREDICATE_TYPE"
            ;;
    esac
}

# Ensure the image is available (pull if needed)
ensure_image_available() {
    local image_ref="$1"
    
    if ! command -v docker &> /dev/null; then
        log_debug "Docker not available, skipping image pull check"
        return 0
    fi
    
    if docker image inspect "$image_ref" >/dev/null 2>&1; then
        log_debug "Image $image_ref already available locally"
    else
        log_info "Pulling image $image_ref..."
        if is_dry_run; then
            log_info "[DRY RUN] Would pull: docker pull $image_ref"
        else
            docker pull "$image_ref" || {
                log_warn "Failed to pull image, continuing anyway (cosign may still work)"
            }
        fi
    fi
}

# Download SBOM attestation using cosign
download_attestation() {
    local image_ref="$1"
    local predicate_type="$2"
    local platform="$3"
    
    log_info "Downloading SBOM attestation from $image_ref..."
    log_debug "Predicate type: $predicate_type"
    log_debug "Platform: $platform"
    
    if is_dry_run; then
        log_info "[DRY RUN] Would execute: cosign download attestation --platform $platform --predicate-type=$predicate_type $image_ref"
        echo '{"spdxVersion": "SPDX-2.3", "dryRun": true}'
        return 0
    fi
    
    local attestation
    attestation=$(cosign download attestation \
        --platform "$platform" \
        --predicate-type="$predicate_type" \
        "$image_ref" 2>/dev/null) || {
        die "Failed to download attestation from $image_ref"
    }
    
    if [[ -z "$attestation" ]]; then
        die "Empty attestation received from $image_ref"
    fi
    
    # Extract the SBOM from the attestation
    # The attestation is a DSSE envelope with base64-encoded payload
    local sbom
    sbom=$(echo "$attestation" | jq -r '.payload | @base64d | fromjson | .predicate') || {
        die "Failed to extract SBOM from attestation"
    }
    
    if [[ -z "$sbom" || "$sbom" == "null" ]]; then
        die "No SBOM predicate found in attestation"
    fi
    
    echo "$sbom"
}

# Main extraction function
extract_sbom() {
    local app="$1"
    local version="$2"
    
    local image_ref format platform predicate_type
    image_ref=$(get_image_ref "$app" "$version")
    format=$(get_sbom_format "$app")
    platform=$(get_config "$app" ".source.platform" "linux/amd64")
    predicate_type=$(get_predicate_type "$app" "$format")
    
    log_info "Extracting SBOM from Chainguard image"
    log_info "  Image: $image_ref"
    log_info "  Format: $format"
    log_info "  Platform: $platform"
    
    # Ensure image is available (optional, helps with caching)
    ensure_image_available "$image_ref"
    
    # Download and extract SBOM
    local sbom
    sbom=$(download_attestation "$image_ref" "$predicate_type" "$platform")
    
    echo "$sbom"
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

    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi
    
    local app="$1"
    
    # Validate
    check_required_tools
    check_chainguard_tools
    validate_app_dir "$app"
    
    # Get version and verify source type
    local version source_type
    version=$(get_latest_version "$app")
    source_type=$(get_source_type "$app")
    
    if [[ "$source_type" != "chainguard" ]]; then
        die "App '$app' is not configured for Chainguard extraction (source.type=$source_type)"
    fi
    
    log_info "Processing app: $app, version: $version"
    
    # Extract and output
    local sbom
    sbom=$(extract_sbom "$app" "$version")
    
    # Validate the output
    local format
    format=$(get_sbom_format "$app")
    validate_sbom "$sbom" "$format"
    
    # Output to stdout
    echo "$sbom"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

