#!/usr/bin/env bash
# common.sh - Shared utilities for SBOM library scripts
#
# Usage: source this file in other scripts
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

# Root directory of the repository
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APPS_DIR="${REPO_ROOT}/apps"
SCRIPTS_DIR="${REPO_ROOT}/scripts"
export REPO_ROOT APPS_DIR SCRIPTS_DIR

# Logging levels (numeric values for comparison)
# DEBUG=0, INFO=1, WARN=2, ERROR=3
LOG_LEVEL="${LOG_LEVEL:-INFO}"

# Dry run mode
DRY_RUN="${DRY_RUN:-false}"

# =============================================================================
# Logging Functions
# =============================================================================

# Convert log level name to numeric value
_log_level_value() {
    local level="$1"
    case "$level" in
        DEBUG) echo 0 ;;
        INFO)  echo 1 ;;
        WARN)  echo 2 ;;
        ERROR) echo 3 ;;
        *)     echo 1 ;;  # Default to INFO
    esac
}

_should_log() {
    local level="$1"
    local level_val current_val
    level_val=$(_log_level_value "$level")
    current_val=$(_log_level_value "$LOG_LEVEL")
    [[ $level_val -ge $current_val ]]
}

log_debug() {
    if _should_log "DEBUG"; then
        echo "[DEBUG] $*" >&2
    fi
}

log_info() {
    if _should_log "INFO"; then
        echo "[INFO] $*" >&2
    fi
}

log_warn() {
    if _should_log "WARN"; then
        echo "[WARN] $*" >&2
    fi
}

log_error() {
    if _should_log "ERROR"; then
        echo "[ERROR] $*" >&2
    fi
}

die() {
    log_error "$@"
    exit 1
}

# =============================================================================
# Validation Functions
# =============================================================================

# Check if a command exists
require_cmd() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command -v "$cmd" &> /dev/null; then
        if [[ -n "$install_hint" ]]; then
            die "Required command '$cmd' not found. $install_hint"
        else
            die "Required command '$cmd' not found."
        fi
    fi
    log_debug "Found required command: $cmd"
}

# Check all required tools are available
check_required_tools() {
    require_cmd "jq" "Install with: brew install jq"
    require_cmd "yq" "Install with: brew install yq"
}

# Validate that an app directory exists and has required files
validate_app_dir() {
    local app="$1"
    local app_dir="${APPS_DIR}/${app}"

    if [[ ! -d "$app_dir" ]]; then
        die "App directory not found: $app_dir"
    fi

    if [[ ! -f "${app_dir}/config.yaml" ]]; then
        die "config.yaml not found in: $app_dir"
    fi

    log_debug "Validated app directory: $app_dir"
}

# =============================================================================
# Config Parsing Functions
# =============================================================================

# Validate that a version string is valid semver
# Accepts: X.Y.Z, X.Y.Z-prerelease, X.Y.Z+build, X.Y.Z-prerelease+build
validate_semver() {
    local version="$1"

    # Semver regex pattern
    # Matches: MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
    local semver_regex='^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$'

    if [[ ! "$version" =~ $semver_regex ]]; then
        return 1
    fi

    return 0
}

# Read the version from an app's config.yaml
get_latest_version() {
    local app="$1"
    local config_file="${APPS_DIR}/${app}/config.yaml"

    if [[ ! -f "$config_file" ]]; then
        die "Config file not found: $config_file"
    fi

    # Ensure yq is available before attempting to read the config
    if ! command -v yq >/dev/null 2>&1; then
        die "'yq' command not found. It is required to read: $config_file. Please install 'yq' and try again."
    fi

    # Read version from config.yaml
    local version
    version="$(yq -r '.version // ""' "$config_file" | tr -d '[:space:]')"

    if [[ -z "$version" ]]; then
        die "Version not specified in: $config_file"
    fi

    # Validate semver format
    if ! validate_semver "$version"; then
        die "Invalid version '$version' in $config_file. Must be valid semver (e.g., 1.2.3, 1.2.3-rc1, 1.2.3+build)"
    fi

    echo "$version"
}

# Get a value from app config.yaml
# Usage: get_config <app> <path> [default]
# If default is provided (even empty string), it's used when value is missing
get_config() {
    local app="$1"
    local path="$2"
    local has_default=false
    local default=""

    if [[ $# -ge 3 ]]; then
        has_default=true
        default="$3"
    fi

    local config_file="${APPS_DIR}/${app}/config.yaml"

    if [[ ! -f "$config_file" ]]; then
        if [[ "$has_default" == "true" ]]; then
            echo "$default"
            return
        fi
        die "Config file not found: $config_file"
    fi

    local value
    value="$(yq -r "$path // \"\"" "$config_file")"

    if [[ -z "$value" || "$value" == "null" ]]; then
        if [[ "$has_default" == "true" ]]; then
            echo "$default"
            return
        fi
        die "Config value not found: $path in $config_file"
    fi

    echo "$value"
}

# Get the source type for an app (docker, github_release, lockfile)
get_source_type() {
    local app="$1"
    get_config "$app" ".source.type"
}

# Get the SBOM format for an app (cyclonedx, spdx)
get_sbom_format() {
    local app="$1"
    get_config "$app" ".format" "cyclonedx"
}

# Get the sbomify component ID for an app
get_sbomify_component_id() {
    local app="$1"
    get_config "$app" ".sbomify.component_id"
}

# Get array values from app config.yaml
# Usage: get_config_array <app> <path>
# Outputs each array element on a separate line
get_config_array() {
    local app="$1"
    local path="$2"
    local config_file="${APPS_DIR}/${app}/config.yaml"

    if [[ ! -f "$config_file" ]]; then
        return 0  # No config file, return empty
    fi

    yq -r "${path}[]? // empty" "$config_file"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Global variable to track temp directories for cleanup
_SBOM_TEMP_DIRS=()

# Cleanup function for temp directories
_cleanup_temp_dirs() {
    if [[ ${#_SBOM_TEMP_DIRS[@]} -gt 0 ]]; then
        for dir in "${_SBOM_TEMP_DIRS[@]}"; do
            if [[ -d "$dir" ]]; then
                rm -rf "$dir"
            fi
        done
    fi
}

# Register cleanup on exit (only once)
trap _cleanup_temp_dirs EXIT

# Create a temporary directory that will be cleaned up on exit
create_temp_dir() {
    local prefix="${1:-sbom}"
    local temp_dir
    temp_dir="$(mktemp -d -t "${prefix}.XXXXXX")"

    # Add to cleanup list
    _SBOM_TEMP_DIRS+=("$temp_dir")

    echo "$temp_dir"
}

# Check if running in dry-run mode
is_dry_run() {
    [[ "$DRY_RUN" == "true" ]]
}

# Run a command, or just print it if in dry-run mode
run_cmd() {
    if is_dry_run; then
        log_info "[DRY RUN] Would execute: $*"
    else
        log_debug "Executing: $*"
        "$@"
    fi
}

# Validate JSON output
validate_json() {
    local input="$1"

    if ! echo "$input" | jq empty 2>/dev/null; then
        die "Invalid JSON output"
    fi

    log_debug "JSON validation passed"
}

# Validate SBOM format (basic check)
validate_sbom() {
    local sbom="$1"
    local format="$2"

    # Check it's valid JSON first
    validate_json "$sbom"

    case "$format" in
        cyclonedx)
            # Check for bomFormat field
            if ! echo "$sbom" | jq -e '.bomFormat == "CycloneDX"' > /dev/null 2>&1; then
                die "Invalid CycloneDX SBOM: missing or incorrect bomFormat"
            fi
            ;;
        spdx)
            # Check for spdxVersion field
            if ! echo "$sbom" | jq -e '.spdxVersion' > /dev/null 2>&1; then
                die "Invalid SPDX SBOM: missing spdxVersion"
            fi
            ;;
        *)
            log_warn "Unknown SBOM format: $format, skipping validation"
            ;;
    esac

    log_debug "SBOM validation passed for format: $format"
}

# Print usage for scripts that source this file
print_usage() {
    local script_name="$1"
    local description="$2"

    cat >&2 <<EOF
Usage: $script_name <app-name> [options]

$description

Options:
  -h, --help     Show this help message
  -n, --dry-run  Run in dry-run mode (no actual changes)
  -v, --verbose  Enable verbose/debug output

Environment Variables:
  LOG_LEVEL    Set logging level (DEBUG, INFO, WARN, ERROR). Default: INFO
  DRY_RUN      Set to 'true' for dry-run mode. Default: false

Examples:
  $script_name nginx
  $script_name redis --dry-run
  LOG_LEVEL=DEBUG $script_name python
EOF
}

# Global array to hold remaining arguments after parsing (used by callers)
declare -a REMAINING_ARGS
export REMAINING_ARGS

# Parse common command-line arguments
# Sets REMAINING_ARGS array with unparsed arguments
# Returns 1 if help was requested, 0 otherwise
parse_common_args() {
    REMAINING_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                return 1  # Signal to caller to show help
                ;;
            -n|--dry-run)
                export DRY_RUN="true"
                shift
                ;;
            -v|--verbose)
                export LOG_LEVEL="DEBUG"
                shift
                ;;
            *)
                # Store remaining args in array
                REMAINING_ARGS=("$@")
                return 0
                ;;
        esac
    done
}

# =============================================================================
# Initialization
# =============================================================================

# Ensure we're running in bash
if [[ -z "${BASH_VERSION:-}" ]]; then
    echo "Error: This script requires bash" >&2
    exit 1
fi

log_debug "common.sh loaded from: ${BASH_SOURCE[0]}"
log_debug "Repository root: $REPO_ROOT"
