#!/usr/bin/env bash
# github-release.sh - Download SBOMs from GitHub release assets
#
# This script downloads SBOM files from GitHub releases using curl.
#
# Usage: ./github-release.sh <app-name>

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# =============================================================================
# Functions
# =============================================================================

show_help() {
    print_usage "$(basename "$0")" "Download SBOMs from GitHub release assets.

Config options in config.yaml:
  source.type: github_release
  source.repo: GitHub repository (e.g., 'owner/repo')
  source.asset: Asset filename (e.g., 'bom.json')
  source.tag_prefix: Version tag prefix (default: '')
  source.tag_suffix: Version tag suffix (default: '')"
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

# Download SBOM from GitHub release
download_sbom() {
    local app="$1"
    local version="$2"

    local repo asset tag
    repo=$(get_config "$app" ".source.repo")
    asset=$(get_config "$app" ".source.asset")
    tag=$(get_tag_name "$app" "$version")

    local url="https://github.com/${repo}/releases/download/${tag}/${asset}"

    log_info "Downloading SBOM from GitHub release"
    log_info "  URL: $url"

    if is_dry_run; then
        log_info "[DRY RUN] Would download: $url"
        # Return a valid placeholder SBOM for dry-run validation
        echo '{"bomFormat":"CycloneDX","specVersion":"1.4","version":1,"components":[]}'
        return 0
    fi

    local sbom
    sbom=$(curl -fsSL "$url") || {
        die "Failed to download SBOM from $url"
    }

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
        die "App '$app' is not configured for GitHub release (source.type=$source_type)"
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
