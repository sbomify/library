#!/usr/bin/env bash
# docker-attestation.sh - Extract SBOMs from Docker image OCI attestations
#
# This script extracts SBOM attestations that are embedded in Docker images
# using BuildKit's provenance and SBOM attestation features.
#
# Usage: ./docker-attestation.sh <app-name>

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

This script supports extracting SBOM attestations from Docker images that
were built with BuildKit's SBOM attestation feature enabled.

Config options in config.yaml:
  source.type: docker
  source.image: Image name (e.g., 'library/nginx' or 'myorg/myapp')
  source.registry: Registry URL (default: docker.io)
  source.platform: Target platform (default: linux/amd64)
  source.use_digest: If true, use digest instead of tag (default: false)"
}

# Get the full image reference for a given app and version
get_image_ref() {
    local app="$1"
    local version="$2"
    
    local registry image
    registry="$(get_config "$app" ".source.registry" "$DEFAULT_REGISTRY")"
    image="$(get_config "$app" ".source.image")"
    
    # Normalize registry
    if [[ "$registry" == "docker.io" ]]; then
        # Docker Hub uses index.docker.io for API calls
        registry="index.docker.io"
    fi
    
    echo "${registry}/${image}:${version}"
}

# Check if required Docker tools are available
check_docker_tools() {
    # We need at least one of these tools
    local has_tool=false
    
    if command -v docker &> /dev/null; then
        log_debug "Found docker CLI"
        has_tool=true
    fi
    
    if command -v crane &> /dev/null; then
        log_debug "Found crane CLI"
        has_tool=true
    fi
    
    if command -v oras &> /dev/null; then
        log_debug "Found oras CLI"
        has_tool=true
    fi
    
    if [[ "$has_tool" != "true" ]]; then
        die "No Docker tools found. Install one of: docker, crane, or oras"
    fi
}

# Extract SBOM using docker buildx imagetools
extract_with_docker() {
    local image_ref="$1"
    local format="$2"
    local platform="$3"
    
    log_info "Extracting SBOM using docker buildx imagetools..."
    log_debug "Image: $image_ref, Platform: $platform"
    
    # First, try to get the SBOM attestation directly
    local sbom_output
    
    # docker buildx imagetools inspect can extract attestations
    if sbom_output=$(docker buildx imagetools inspect "$image_ref" \
        --format '{{ json .SBOM }}' 2>/dev/null); then
        
        if [[ -n "$sbom_output" && "$sbom_output" != "null" ]]; then
            log_debug "Got SBOM from imagetools inspect"
            echo "$sbom_output"
            return 0
        fi
    fi
    
    # Try alternative: inspect with provenance
    log_debug "Trying provenance inspection..."
    
    # Get the manifest and look for attestation layers
    local manifest
    manifest=$(docker buildx imagetools inspect "$image_ref" --raw 2>/dev/null) || true
    
    if [[ -n "$manifest" ]]; then
        # Check if it's a manifest list or single manifest
        local media_type
        media_type=$(echo "$manifest" | jq -r '.mediaType // empty')
        
        log_debug "Manifest media type: $media_type"
        
        # Look for SBOM in attestation manifests
        if echo "$manifest" | jq -e '.manifests' > /dev/null 2>&1; then
            # It's a manifest list, find the attestation manifest
            local sbom_digest
            sbom_digest=$(echo "$manifest" | jq -r '
                .manifests[] | 
                select(.annotations["vnd.docker.reference.type"] == "attestation-manifest") |
                select(.annotations["vnd.docker.reference.digest"] != null) |
                .digest
            ' | head -1)
            
            if [[ -n "$sbom_digest" && "$sbom_digest" != "null" ]]; then
                log_debug "Found attestation manifest: $sbom_digest"
                
                # Extract the base image reference (without tag)
                local base_ref="${image_ref%:*}"
                
                # Get the attestation manifest
                local att_manifest
                att_manifest=$(docker buildx imagetools inspect "${base_ref}@${sbom_digest}" --raw 2>/dev/null) || true
                
                if [[ -n "$att_manifest" ]]; then
                    # Find and extract SBOM layer
                    local sbom_layer_digest
                    sbom_layer_digest=$(echo "$att_manifest" | jq -r '
                        .layers[] |
                        select(.annotations["in-toto.io/predicate-type"] | 
                               contains("spdx") or contains("cyclonedx")) |
                        .digest
                    ' | head -1)
                    
                    if [[ -n "$sbom_layer_digest" && "$sbom_layer_digest" != "null" ]]; then
                        log_debug "Found SBOM layer: $sbom_layer_digest"
                        # Would need to fetch the blob here
                        # For now, this is a placeholder for the full implementation
                    fi
                fi
            fi
        fi
    fi
    
    return 1
}

# Extract SBOM using crane (from google/go-containerregistry)
extract_with_crane() {
    local image_ref="$1"
    local format="$2"
    local platform="$3"
    
    log_info "Extracting SBOM using crane..."
    log_debug "Image: $image_ref, Platform: $platform"
    
    # Get the manifest
    local manifest
    manifest=$(crane manifest "$image_ref" --platform "$platform" 2>/dev/null) || {
        log_debug "Failed to get manifest for platform $platform, trying without platform..."
        manifest=$(crane manifest "$image_ref" 2>/dev/null) || return 1
    }
    
    # Check for attestations in manifest list
    if echo "$manifest" | jq -e '.manifests' > /dev/null 2>&1; then
        # Find attestation manifest for SBOM
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
            log_debug "Found SBOM attestation digest: $sbom_digest"
            
            local base_ref="${image_ref%:*}"
            local att_manifest
            att_manifest=$(crane manifest "${base_ref}@${sbom_digest}" 2>/dev/null) || return 1
            
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
                
                # Fetch the blob
                local blob
                blob=$(crane blob "${base_ref}@${sbom_layer}" 2>/dev/null) || return 1
                
                # The blob is an in-toto statement, extract the predicate (the actual SBOM)
                if echo "$blob" | jq -e '.predicate' > /dev/null 2>&1; then
                    echo "$blob" | jq '.predicate'
                    return 0
                else
                    # Might be the raw SBOM
                    echo "$blob"
                    return 0
                fi
            fi
        fi
    fi
    
    return 1
}

# Extract SBOM using oras
extract_with_oras() {
    local image_ref="$1"
    local format="$2"
    local platform="$3"
    
    log_info "Extracting SBOM using oras..."
    log_debug "Image: $image_ref, Platform: $platform"
    
    local temp_dir
    temp_dir=$(create_temp_dir "sbom-oras")
    
    # Try to discover referrers (OCI 1.1 referrers API)
    local referrers
    referrers=$(oras discover "$image_ref" --format json 2>/dev/null) || {
        log_debug "No referrers found via discover"
        return 1
    }
    
    # Look for SBOM artifacts
    local sbom_ref
    sbom_ref=$(echo "$referrers" | jq -r '
        .manifests[] |
        select(.artifactType | contains("sbom") or contains("spdx") or contains("cyclonedx")) |
        .digest
    ' | head -1)
    
    if [[ -n "$sbom_ref" && "$sbom_ref" != "null" ]]; then
        log_debug "Found SBOM referrer: $sbom_ref"
        
        local base_ref="${image_ref%:*}"
        
        # Pull the SBOM artifact
        if oras pull "${base_ref}@${sbom_ref}" -o "$temp_dir" 2>/dev/null; then
            # Find the SBOM file
            local sbom_file
            sbom_file=$(find "$temp_dir" -name "*.json" -o -name "*.spdx" -o -name "*.cdx" | head -1)
            
            if [[ -n "$sbom_file" && -f "$sbom_file" ]]; then
                cat "$sbom_file"
                return 0
            fi
        fi
    fi
    
    return 1
}

# Main extraction function - tries multiple methods
extract_sbom() {
    local app="$1"
    local version="$2"
    
    local image_ref format platform
    image_ref=$(get_image_ref "$app" "$version")
    format=$(get_sbom_format "$app")
    platform=$(get_config "$app" ".source.platform" "linux/amd64")
    
    log_info "Extracting SBOM for: $image_ref"
    log_info "Expected format: $format"
    
    local sbom=""
    
    # Try each extraction method in order of preference
    if command -v crane &> /dev/null; then
        sbom=$(extract_with_crane "$image_ref" "$format" "$platform") && {
            log_info "Successfully extracted SBOM using crane"
            echo "$sbom"
            return 0
        }
    fi
    
    if command -v docker &> /dev/null; then
        sbom=$(extract_with_docker "$image_ref" "$format" "$platform") && {
            log_info "Successfully extracted SBOM using docker"
            echo "$sbom"
            return 0
        }
    fi
    
    if command -v oras &> /dev/null; then
        sbom=$(extract_with_oras "$image_ref" "$format" "$platform") && {
            log_info "Successfully extracted SBOM using oras"
            echo "$sbom"
            return 0
        }
    fi
    
    die "Failed to extract SBOM from $image_ref using any available method"
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
    check_docker_tools
    validate_app_dir "$app"
    
    # Get version and verify source type
    local version source_type
    version=$(get_latest_version "$app")
    source_type=$(get_source_type "$app")
    
    if [[ "$source_type" != "docker" ]]; then
        die "App '$app' is not configured for Docker extraction (source.type=$source_type)"
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

