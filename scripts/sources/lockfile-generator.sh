#!/usr/bin/env bash
# lockfile-generator.sh - Generate SBOMs from project lockfiles
#
# This script downloads lockfiles from a specific release/tag and generates
# an SBOM using tools like cdxgen or syft.
#
# Usage: ./lockfile-generator.sh <app-name> <output-file>

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# =============================================================================
# Functions
# =============================================================================

show_help() {
    print_usage "$(basename "$0")" "Generate SBOMs from project lockfiles.

Config options in config.yaml:
  source.type: lockfile
  source.repo: GitHub repository (e.g., 'owner/repo')
  source.lockfile: Path to lockfile in repo (e.g., 'package-lock.json')
  source.tag_prefix: Version tag prefix (e.g., 'v')
  source.generator: SBOM generator to use ('cdxgen', 'syft', 'auto')"
}

# Check if SBOM generators are available
check_generator_tools() {
    if command -v cdxgen &> /dev/null; then
        log_debug "Found cdxgen"
        return 0
    fi

    if command -v syft &> /dev/null; then
        log_debug "Found syft"
        return 0
    fi

    die "No SBOM generator found. Install cdxgen or syft."
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

# Generate SBOM from lockfile
generate_sbom() {
    local app="$1"
    local version="$2"
    local output_file="$3"

    local repo lockfile tag format generator
    repo=$(get_config "$app" ".source.repo")
    lockfile=$(get_config "$app" ".source.lockfile")
    tag=$(get_tag_name "$app" "$version")
    format=$(get_sbom_format "$app")
    generator=$(get_config "$app" ".source.generator" "auto")

    local url="https://raw.githubusercontent.com/${repo}/${tag}/${lockfile}"

    log_info "Generating SBOM from lockfile"
    log_info "  Repo: $repo"
    log_info "  Tag: $tag"
    log_info "  Lockfile: $lockfile"

    # Create temp directory for work
    local work_dir
    work_dir=$(create_temp_dir "sbom-gen")

    # Download lockfile
    local lockfile_name
    lockfile_name=$(basename "$lockfile")
    curl -fsSL -o "${work_dir}/${lockfile_name}" "$url" || {
        die "Failed to download lockfile from $url"
    }

    # Try to download package.json for JS projects
    case "$lockfile_name" in
        package-lock.json|yarn.lock|pnpm-lock.yaml)
            local pkg_dir
            pkg_dir=$(dirname "$lockfile")
            if [[ "$pkg_dir" == "." ]]; then
                pkg_dir=""
            else
                pkg_dir="${pkg_dir}/"
            fi
            curl -fsSL -o "${work_dir}/package.json" \
                "https://raw.githubusercontent.com/${repo}/${tag}/${pkg_dir}package.json" 2>/dev/null || true
            ;;
    esac

    # Determine output format
    local output_format
    case "$format" in
        cyclonedx) output_format="json" ;;
        spdx) output_format="spdx-json" ;;
        *) output_format="json" ;;
    esac

    # Generate SBOM
    if [[ "$generator" == "auto" || "$generator" == "cdxgen" ]] && command -v cdxgen &> /dev/null; then
        log_info "Generating with cdxgen..."
        (cd "$work_dir" && cdxgen -o "$output_file" --format "$output_format" .) || {
            die "cdxgen failed"
        }
    elif command -v syft &> /dev/null; then
        log_info "Generating with syft..."
        local syft_format
        case "$format" in
            cyclonedx) syft_format="cyclonedx-json" ;;
            spdx) syft_format="spdx-json" ;;
            *) syft_format="cyclonedx-json" ;;
        esac
        syft "dir:${work_dir}" -o "$syft_format=$output_file" || {
            die "syft failed"
        }
    else
        die "No generator available"
    fi

    log_info "Generated successfully"
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
    check_generator_tools
    validate_app_dir "$app"

    # Get version and verify source type
    local version source_type
    version=$(get_latest_version "$app")
    source_type=$(get_source_type "$app")

    if [[ "$source_type" != "lockfile" ]]; then
        die "App '$app' is not configured for lockfile (source.type=$source_type)"
    fi

    log_info "Processing app: $app, version: $version"

    # Generate directly to output file
    generate_sbom "$app" "$version" "$output_file"
}

# Run main if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
