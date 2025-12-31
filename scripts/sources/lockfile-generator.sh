#!/usr/bin/env bash
# lockfile-generator.sh - Generate SBOMs from project lockfiles
#
# This script downloads lockfiles from a specific release/tag and generates
# an SBOM using tools like cdxgen or syft.
#
# Usage: ./lockfile-generator.sh <app-name>

set -euo pipefail

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

# =============================================================================
# Lockfile-specific configuration
# =============================================================================

# Get lockfile type from filename
get_lockfile_type() {
    local filename="$1"
    case "$filename" in
        package-lock.json) echo "npm" ;;
        yarn.lock) echo "yarn" ;;
        pnpm-lock.yaml) echo "pnpm" ;;
        Gemfile.lock) echo "bundler" ;;
        requirements.txt) echo "pip" ;;
        Pipfile.lock) echo "pipenv" ;;
        poetry.lock) echo "poetry" ;;
        Cargo.lock) echo "cargo" ;;
        go.sum) echo "go" ;;
        composer.lock) echo "composer" ;;
        pubspec.lock) echo "dart" ;;
        gradle.lockfile) echo "gradle" ;;
        pom.xml) echo "maven" ;;
        *) echo "unknown" ;;
    esac
}

# =============================================================================
# Functions
# =============================================================================

show_help() {
    print_usage "$(basename "$0")" "Generate SBOMs from project lockfiles.

This script downloads lockfiles from a repository and generates SBOMs
using cdxgen, syft, or other SBOM generators.

Config options in config.yaml:
  source.type: lockfile
  source.repo: GitHub repository (e.g., 'owner/repo')
  source.lockfile: Path to lockfile in repo (e.g., 'package-lock.json')
  source.tag_prefix: Version tag prefix (e.g., 'v')
  source.generator: SBOM generator to use ('cdxgen', 'syft', 'auto')
  source.extra_files: Additional files needed for generation (array)"
}

# Check if SBOM generators are available
check_generator_tools() {
    local has_generator=false
    
    if command -v cdxgen &> /dev/null; then
        log_debug "Found cdxgen"
        has_generator=true
    fi
    
    if command -v syft &> /dev/null; then
        log_debug "Found syft"
        has_generator=true
    fi
    
    if [[ "$has_generator" != "true" ]]; then
        die "No SBOM generator found. Install one of: cdxgen (npm install -g @cyclonedx/cdxgen), syft"
    fi
}

# Get the best available generator
get_available_generator() {
    local preferred="$1"
    
    case "$preferred" in
        cdxgen)
            if command -v cdxgen &> /dev/null; then
                echo "cdxgen"
                return
            fi
            ;;
        syft)
            if command -v syft &> /dev/null; then
                echo "syft"
                return
            fi
            ;;
        auto|"")
            # Prefer cdxgen for better CycloneDX output
            if command -v cdxgen &> /dev/null; then
                echo "cdxgen"
                return
            fi
            if command -v syft &> /dev/null; then
                echo "syft"
                return
            fi
            ;;
    esac
    
    die "Preferred generator '$preferred' not available"
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

# Download a file from GitHub at a specific ref
download_file() {
    local repo="$1"
    local ref="$2"
    local file_path="$3"
    local output_path="$4"
    
    local url="https://raw.githubusercontent.com/${repo}/${ref}/${file_path}"
    
    log_debug "Downloading: $url"
    
    if is_dry_run; then
        log_info "[DRY RUN] Would download: $url"
        return 0
    fi
    
    local http_code
    http_code=$(curl -sL -w "%{http_code}" -o "$output_path" "$url")
    
    if [[ "$http_code" != "200" ]]; then
        die "Failed to download $file_path from $repo@$ref (HTTP $http_code)"
    fi
    
    log_debug "Downloaded to: $output_path"
}

# Download lockfile and any extra files
download_project_files() {
    local app="$1"
    local version="$2"
    local temp_dir="$3"
    
    local repo tag lockfile
    repo=$(get_config "$app" ".source.repo")
    tag=$(get_tag_name "$app" "$version")
    lockfile=$(get_config "$app" ".source.lockfile")
    
    log_info "Downloading project files from $repo@$tag"
    
    # Download main lockfile
    local lockfile_name
    lockfile_name=$(basename "$lockfile")
    download_file "$repo" "$tag" "$lockfile" "${temp_dir}/${lockfile_name}"
    
    # Download extra files if specified
    local extra_files
    extra_files=$(get_config "$app" ".source.extra_files" "[]")
    
    if [[ "$extra_files" != "[]" && "$extra_files" != "null" ]]; then
        # Parse JSON array of extra files
        local files
        files=$(echo "$extra_files" | yq -r '.[]' 2>/dev/null) || files=""
        
        while IFS= read -r file; do
            if [[ -n "$file" ]]; then
                local file_name
                file_name=$(basename "$file")
                log_debug "Downloading extra file: $file"
                download_file "$repo" "$tag" "$file" "${temp_dir}/${file_name}" || {
                    log_warn "Failed to download optional file: $file"
                }
            fi
        done <<< "$files"
    fi
    
    # Also try to download package.json if we have a JS lockfile
    case "$lockfile_name" in
        package-lock.json|yarn.lock|pnpm-lock.yaml)
            local package_dir
            package_dir=$(dirname "$lockfile")
            if [[ "$package_dir" == "." ]]; then
                package_dir=""
            else
                package_dir="${package_dir}/"
            fi
            download_file "$repo" "$tag" "${package_dir}package.json" "${temp_dir}/package.json" 2>/dev/null || {
                log_debug "No package.json found (optional)"
            }
            ;;
    esac
}

# Generate SBOM using cdxgen
generate_with_cdxgen() {
    local work_dir="$1"
    local format="$2"
    local lockfile_type="$3"
    
    log_info "Generating SBOM with cdxgen..."
    
    local output_format
    case "$format" in
        cyclonedx)
            output_format="json"
            ;;
        spdx)
            output_format="spdx-json"
            ;;
        *)
            output_format="json"
            ;;
    esac
    
    if is_dry_run; then
        log_info "[DRY RUN] Would run: cdxgen -o - --format $output_format $work_dir"
        echo '{"bomFormat": "CycloneDX", "dryRun": true}'
        return 0
    fi
    
    # Run cdxgen
    local sbom
    sbom=$(cd "$work_dir" && cdxgen -o - --format "$output_format" . 2>/dev/null) || {
        die "cdxgen failed to generate SBOM"
    }
    
    echo "$sbom"
}

# Generate SBOM using syft
generate_with_syft() {
    local work_dir="$1"
    local format="$2"
    local lockfile_type="$3"
    
    log_info "Generating SBOM with syft..."
    
    local output_format
    case "$format" in
        cyclonedx)
            output_format="cyclonedx-json"
            ;;
        spdx)
            output_format="spdx-json"
            ;;
        *)
            output_format="cyclonedx-json"
            ;;
    esac
    
    if is_dry_run; then
        log_info "[DRY RUN] Would run: syft dir:$work_dir -o $output_format"
        echo '{"bomFormat": "CycloneDX", "dryRun": true}'
        return 0
    fi
    
    # Run syft
    local sbom
    sbom=$(syft "dir:${work_dir}" -o "$output_format" 2>/dev/null) || {
        die "syft failed to generate SBOM"
    }
    
    echo "$sbom"
}

# Main generation function
generate_sbom() {
    local app="$1"
    local version="$2"
    
    local format lockfile generator
    format=$(get_sbom_format "$app")
    lockfile=$(get_config "$app" ".source.lockfile")
    generator=$(get_config "$app" ".source.generator" "auto")
    
    log_info "Generating SBOM for $app v$version"
    log_info "  Lockfile: $lockfile"
    log_info "  Format: $format"
    
    # Create temp directory for work
    local temp_dir
    temp_dir=$(create_temp_dir "sbom-gen")
    
    # Download files
    download_project_files "$app" "$version" "$temp_dir"
    
    # Determine lockfile type
    local lockfile_name lockfile_type
    lockfile_name=$(basename "$lockfile")
    lockfile_type=$(get_lockfile_type "$lockfile_name")
    
    log_debug "Detected lockfile type: $lockfile_type"
    
    # Get available generator
    local selected_generator
    selected_generator=$(get_available_generator "$generator")
    
    log_info "Using generator: $selected_generator"
    
    # Generate SBOM
    local sbom
    case "$selected_generator" in
        cdxgen)
            sbom=$(generate_with_cdxgen "$temp_dir" "$format" "$lockfile_type")
            ;;
        syft)
            sbom=$(generate_with_syft "$temp_dir" "$format" "$lockfile_type")
            ;;
        *)
            die "Unknown generator: $selected_generator"
            ;;
    esac
    
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
    check_generator_tools
    validate_app_dir "$app"
    
    # Get version and verify source type
    local version source_type
    version=$(get_latest_version "$app")
    source_type=$(get_source_type "$app")
    
    if [[ "$source_type" != "lockfile" ]]; then
        die "App '$app' is not configured for lockfile generation (source.type=$source_type)"
    fi
    
    log_info "Processing app: $app, version: $version"
    
    # Generate and output
    local sbom
    sbom=$(generate_sbom "$app" "$version")
    
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

