#!/usr/bin/env bash
# github-release.sh - Download SBOMs from GitHub release assets
#
# This script downloads SBOM files that are attached as assets to GitHub releases.
# Many projects now include SBOMs as part of their release artifacts.
#
# Usage: ./github-release.sh <app-name>

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# =============================================================================
# GitHub-specific configuration
# =============================================================================

# Common SBOM file patterns
DEFAULT_SBOM_PATTERNS=(
    "*.sbom.json"
    "*sbom*.json"
    "*.cdx.json"
    "*.spdx.json"
    "*cyclonedx*.json"
    "*spdx*.json"
    "bom.json"
)

# =============================================================================
# Functions
# =============================================================================

show_help() {
    print_usage "$(basename "$0")" "Download SBOMs from GitHub release assets.

This script downloads SBOM files that projects publish as part of their
GitHub releases.

Config options in config.yaml:
  source.type: github_release
  source.repo: GitHub repository (e.g., 'owner/repo')
  source.asset_pattern: Glob pattern for SBOM asset (e.g., '*sbom*.json')
  source.tag_prefix: Version tag prefix (e.g., 'v' for 'v1.0.0' tags)
  source.tag_suffix: Version tag suffix if any"
}

# Check if GitHub CLI is available
check_github_tools() {
    if ! command -v gh &> /dev/null; then
        # Fall back to curl if gh is not available
        if ! command -v curl &> /dev/null; then
            die "Neither 'gh' CLI nor 'curl' is available. Install one of them."
        fi
        log_debug "Using curl for GitHub API (gh not found)"
        return 1
    fi
    
    # Check if gh is authenticated
    if ! gh auth status &> /dev/null; then
        log_warn "GitHub CLI not authenticated. Some private repos may not work."
    fi
    
    log_debug "Using GitHub CLI for downloads"
    return 0
}

# Build the tag name from version
get_tag_name() {
    local app="$1"
    local version="$2"
    
    local prefix suffix
    prefix=$(get_config "$app" ".source.tag_prefix" "")
    suffix=$(get_config "$app" ".source.tag_suffix" "")
    
    echo "${prefix}${version}${suffix}"
}

# Get the SBOM asset pattern
get_asset_pattern() {
    local app="$1"
    local format="$2"
    
    # Try to get from config first
    local pattern
    pattern=$(get_config "$app" ".source.asset_pattern" "")
    
    if [[ -n "$pattern" ]]; then
        echo "$pattern"
        return
    fi
    
    # Default patterns based on format
    case "$format" in
        cyclonedx)
            echo "*.cdx.json"
            ;;
        spdx)
            echo "*.spdx.json"
            ;;
        *)
            echo "*sbom*.json"
            ;;
    esac
}

# List release assets and find SBOM
find_sbom_asset() {
    local repo="$1"
    local tag="$2"
    local pattern="$3"
    
    log_debug "Looking for SBOM asset matching: $pattern"
    
    # Use gh CLI to list assets
    local assets
    assets=$(gh release view "$tag" --repo "$repo" --json assets -q '.assets[].name' 2>/dev/null) || {
        die "Failed to list assets for release $tag in $repo"
    }
    
    if [[ -z "$assets" ]]; then
        die "No assets found in release $tag"
    fi
    
    log_debug "Found assets: $assets"
    
    # Find matching asset
    local matching_asset=""
    while IFS= read -r asset; do
        # Simple glob matching using bash pattern matching
        # Convert glob to regex-like pattern
        local regex_pattern="${pattern//\*/.*}"
        regex_pattern="${regex_pattern//\?/.}"
        
        if [[ "$asset" =~ $regex_pattern ]]; then
            matching_asset="$asset"
            log_debug "Found matching asset: $asset"
            break
        fi
    done <<< "$assets"
    
    # If no match with specific pattern, try common patterns
    if [[ -z "$matching_asset" ]]; then
        log_debug "No match for pattern '$pattern', trying common patterns..."
        
        for common_pattern in "${DEFAULT_SBOM_PATTERNS[@]}"; do
            local regex_pattern="${common_pattern//\*/.*}"
            regex_pattern="${regex_pattern//\?/.}"
            
            while IFS= read -r asset; do
                if [[ "$asset" =~ $regex_pattern ]]; then
                    matching_asset="$asset"
                    log_info "Found SBOM asset using common pattern: $asset"
                    break 2
                fi
            done <<< "$assets"
        done
    fi
    
    if [[ -z "$matching_asset" ]]; then
        die "No SBOM asset found matching pattern '$pattern' in release $tag"
    fi
    
    echo "$matching_asset"
}

# Download asset using gh CLI
download_with_gh() {
    local repo="$1"
    local tag="$2"
    local asset="$3"
    
    log_info "Downloading asset '$asset' from $repo@$tag..."
    
    local temp_dir
    temp_dir=$(create_temp_dir "sbom-gh")
    
    if is_dry_run; then
        log_info "[DRY RUN] Would download: gh release download $tag --repo $repo --pattern $asset"
        echo '{"dryRun": true}'
        return 0
    fi
    
    # Download to temp directory
    gh release download "$tag" \
        --repo "$repo" \
        --pattern "$asset" \
        --dir "$temp_dir" || {
        die "Failed to download asset '$asset' from release $tag"
    }
    
    # Read and output the file
    local downloaded_file="${temp_dir}/${asset}"
    if [[ ! -f "$downloaded_file" ]]; then
        # gh might download with different name, find it
        downloaded_file=$(find "$temp_dir" -type f -name "*.json" | head -1)
    fi
    
    if [[ ! -f "$downloaded_file" ]]; then
        die "Downloaded file not found in $temp_dir"
    fi
    
    cat "$downloaded_file"
}

# Download asset using curl (fallback)
download_with_curl() {
    local repo="$1"
    local tag="$2"
    local asset="$3"
    
    log_info "Downloading asset '$asset' from $repo@$tag using curl..."
    
    # Construct download URL
    local download_url="https://github.com/${repo}/releases/download/${tag}/${asset}"
    
    if is_dry_run; then
        log_info "[DRY RUN] Would download: $download_url"
        echo '{"dryRun": true}'
        return 0
    fi
    
    local response
    response=$(curl -sL -w "\n%{http_code}" "$download_url") || {
        die "Failed to download from $download_url"
    }
    
    # Split response and status code
    local http_code
    http_code=$(echo "$response" | tail -1)
    local content
    content=$(echo "$response" | sed '$d')
    
    if [[ "$http_code" != "200" ]]; then
        die "Failed to download asset: HTTP $http_code"
    fi
    
    echo "$content"
}

# Main download function
download_sbom() {
    local app="$1"
    local version="$2"
    
    local repo tag format pattern
    repo=$(get_config "$app" ".source.repo")
    tag=$(get_tag_name "$app" "$version")
    format=$(get_sbom_format "$app")
    pattern=$(get_asset_pattern "$app" "$format")
    
    log_info "Downloading SBOM from GitHub release"
    log_info "  Repository: $repo"
    log_info "  Tag: $tag"
    log_info "  Pattern: $pattern"
    
    # Check which tool to use
    local use_gh=true
    check_github_tools || use_gh=false
    
    # Find the SBOM asset
    local asset
    if [[ "$use_gh" == "true" ]]; then
        asset=$(find_sbom_asset "$repo" "$tag" "$pattern")
    else
        # With curl, we need to know the exact filename
        # Try the pattern as-is first
        asset="${pattern//\*/sbom}"  # Replace wildcards with 'sbom'
        log_warn "Using curl without gh CLI - asset name guessed as: $asset"
    fi
    
    # Download the asset
    local sbom
    if [[ "$use_gh" == "true" ]]; then
        sbom=$(download_with_gh "$repo" "$tag" "$asset")
    else
        sbom=$(download_with_curl "$repo" "$tag" "$asset")
    fi
    
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
    validate_app_dir "$app"
    
    # Get version and verify source type
    local version source_type
    version=$(get_latest_version "$app")
    source_type=$(get_source_type "$app")
    
    if [[ "$source_type" != "github_release" ]]; then
        die "App '$app' is not configured for GitHub release download (source.type=$source_type)"
    fi
    
    log_info "Processing app: $app, version: $version"
    
    # Download and output
    local sbom
    sbom=$(download_sbom "$app" "$version")
    
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

