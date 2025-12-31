#!/usr/bin/env bash
# fetch-sbom.sh - Main entry point for SBOM extraction
#
# This script reads an app's configuration and routes to the appropriate
# source handler to fetch or generate the SBOM.
#
# Usage: ./fetch-sbom.sh <app-name> [options]
#
# The SBOM is output to stdout in JSON format.
#
# Note: Each version only needs to be processed once. Once uploaded to
# sbomify, the SBOM is permanently stored there. Bumping LATEST to a new
# version triggers processing; re-running the same version is unnecessary.

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

# Source handlers directory
SOURCES_DIR="${SCRIPT_DIR}/sources"

# =============================================================================
# Functions
# =============================================================================

show_help() {
    cat >&2 <<EOF
Usage: $(basename "$0") <app-name> [options]

Fetch or generate SBOM for a specified app.

This script reads the app's config.yaml and LATEST version, then routes
to the appropriate source handler to fetch or generate the SBOM.

Supported source types:
  docker          Extract from Docker image OCI attestations
  github_release  Download from GitHub release assets
  lockfile        Generate from project lockfiles
  chainguard      Download from Chainguard image attestations (via cosign)

Options:
  -h, --help      Show this help message
  -n, --dry-run   Run in dry-run mode (no actual fetching)
  -v, --verbose   Enable verbose/debug output
  -o, --output    Output file (default: stdout)
  --validate      Validate the SBOM after fetching
  --version VER   Override the version (instead of reading LATEST)

Environment Variables:
  LOG_LEVEL       Set logging level (DEBUG, INFO, WARN, ERROR). Default: INFO
  DRY_RUN         Set to 'true' for dry-run mode. Default: false
  SBOMIFY_TOKEN   API token for sbomify upload (if using upload feature)

Examples:
  $(basename "$0") nginx
  $(basename "$0") redis --dry-run
  $(basename "$0") python -o sbom.json
  $(basename "$0") node --version 20.10.0
EOF
}

# Route to the appropriate source handler
route_to_handler() {
    local app="$1"
    local source_type="$2"
    local output_file="$3"

    local handler_script=""

    case "$source_type" in
        docker)
            handler_script="${SOURCES_DIR}/docker-attestation.sh"
            ;;
        github_release)
            handler_script="${SOURCES_DIR}/github-release.sh"
            ;;
        lockfile)
            handler_script="${SOURCES_DIR}/lockfile-generator.sh"
            ;;
        chainguard)
            handler_script="${SOURCES_DIR}/chainguard.sh"
            ;;
        *)
            die "Unknown source type: $source_type"
            ;;
    esac

    if [[ ! -f "$handler_script" ]]; then
        die "Handler script not found: $handler_script"
    fi

    if [[ ! -x "$handler_script" ]]; then
        log_warn "Handler script not executable, using bash to run it"
        bash "$handler_script" "$app" "$output_file"
    else
        "$handler_script" "$app" "$output_file"
    fi
}

# List all available apps
list_apps() {
    log_info "Available apps:"
    
    local app_dirs
    app_dirs=$(find "$APPS_DIR" -mindepth 1 -maxdepth 1 -type d -not -name ".*" | sort)
    
    if [[ -z "$app_dirs" ]]; then
        log_warn "No apps found in $APPS_DIR"
        return
    fi
    
    while IFS= read -r app_dir; do
        local app_name
        app_name=$(basename "$app_dir")
        
        if [[ -f "${app_dir}/config.yaml" && -f "${app_dir}/LATEST" ]]; then
            local version source_type
            version=$(tr -d '[:space:]' < "${app_dir}/LATEST")
            source_type=$(yq -r '.source.type // "unknown"' "${app_dir}/config.yaml")
            echo "  ${app_name} (v${version}, source: ${source_type})"
        else
            echo "  ${app_name} (incomplete configuration)"
        fi
    done <<< "$app_dirs"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local output_file=""
    local override_version=""
    local do_validate=false
    local list_only=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                export DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            -o|--output)
                output_file="$2"
                shift 2
                ;;
            --version)
                override_version="$2"
                shift 2
                ;;
            --validate)
                do_validate=true
                shift
                ;;
            --list)
                list_only=true
                shift
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                break
                ;;
        esac
    done
    
    # Check required tools
    check_required_tools
    
    # Handle --list
    if [[ "$list_only" == "true" ]]; then
        list_apps
        exit 0
    fi
    
    # Require app name
    if [[ $# -lt 1 ]]; then
        show_help
        exit 1
    fi
    
    local app="$1"
    
    # Handle template specially
    if [[ "$app" == ".template" ]]; then
        die "Cannot process .template - it's a template, not a real app"
    fi
    
    # Validate app exists
    validate_app_dir "$app"
    
    # Get version (from LATEST or override)
    local version
    if [[ -n "$override_version" ]]; then
        version="$override_version"
        log_info "Using override version: $version"
    else
        version=$(get_latest_version "$app")
    fi
    
    # Get source type
    local source_type
    source_type=$(get_source_type "$app")
    
    log_info "========================================"
    log_info "SBOM Fetch"
    log_info "========================================"
    log_info "App:     $app"
    log_info "Version: $version"
    log_info "Source:  $source_type"
    log_info "========================================"
    
    # Determine output file
    local sbom_file
    if [[ -n "$output_file" ]]; then
        sbom_file="$output_file"
    else
        sbom_file="$(create_temp_dir)/sbom.json"
    fi

    # Fetch SBOM directly to file
    route_to_handler "$app" "$source_type" "$sbom_file"

    # Validate if requested
    if [[ "$do_validate" == "true" ]]; then
        local format
        format=$(get_sbom_format "$app")
        validate_sbom "$(cat "$sbom_file")" "$format"
        log_info "SBOM validation passed"
    fi

    # Output to stdout if no output file was specified
    if [[ -z "$output_file" ]]; then
        cat "$sbom_file"
    fi
    
    log_info "Done!"
}

# Run main
main "$@"

