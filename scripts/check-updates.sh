#!/usr/bin/env bash
# check-updates.sh - Check for upstream version updates across all apps
#
# Usage:
#   ./scripts/check-updates.sh                    # Check all apps
#   ./scripts/check-updates.sh --type docker      # Only docker apps
#   ./scripts/check-updates.sh --app redis,trivy  # Specific apps
#   ./scripts/check-updates.sh --update           # Auto-update config.yaml files
#   ./scripts/check-updates.sh --json             # JSON output for CI
#   ./scripts/check-updates.sh --dry-run --update # Preview updates
#
# Exit codes: 0=all current, 1=updates available, 2=errors
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

# =============================================================================
# Constants
# =============================================================================

MAX_PARALLEL=5

# =============================================================================
# Argument Parsing
# =============================================================================

FILTER_TYPE=""
FILTER_APPS=""
AUTO_UPDATE=false
JSON_OUTPUT=false

print_check_usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") [options]

Check for upstream version updates across all tracked apps.

Options:
  --type TYPE      Only check apps of this source type (docker, github_release, lockfile)
  --app APP[,APP]  Only check specific apps (comma-separated)
  --update         Auto-update config.yaml files with new versions
  --json           Output results as JSON
  -n, --dry-run    Preview updates without writing changes
  -v, --verbose    Enable debug output
  -h, --help       Show this help message

Examples:
  $(basename "$0")                          # Check all apps
  $(basename "$0") --type docker            # Only docker apps
  $(basename "$0") --app redis,trivy        # Specific apps
  $(basename "$0") --update --dry-run       # Preview auto-updates
  $(basename "$0") --json | jq .summary     # JSON output for CI
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_check_usage
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
            --type)
                [[ $# -lt 2 ]] && die "--type requires an argument"
                FILTER_TYPE="$2"
                shift 2
                ;;
            --app)
                [[ $# -lt 2 ]] && die "--app requires an argument"
                FILTER_APPS="$2"
                shift 2
                ;;
            --update)
                AUTO_UPDATE=true
                shift
                ;;
            --json)
                JSON_OUTPUT=true
                shift
                ;;
            *)
                die "Unknown option: $1. Use --help for usage."
                ;;
        esac
    done
}

# =============================================================================
# Version Detection Functions
# =============================================================================

# Clean a Docker annotation version to match the config's tag pattern.
# The annotation often has a distro suffix (e.g., "3.14.3-trixie") that the
# config doesn't track (e.g., "3.14.3"). This function derives the "shape"
# of the current version and extracts the matching portion.
clean_docker_version() {
    local annotation="$1"
    local current="$2"

    # If annotation matches current exactly, return as-is
    if [[ "$annotation" == "$current" ]]; then
        echo "$annotation"
        return
    fi

    # If current version contains a dash, it has an intentional suffix
    # (e.g., "25.0.2_10-jdk-noble", "26.2.0.119303-community")
    # Return the full annotation since we expect suffixed versions
    if [[ "$current" == *-* ]]; then
        echo "$annotation"
        return
    fi

    # Current has no dash — strip any dash-suffix from annotation
    # e.g., annotation "3.14.3-trixie" → "3.14.3"
    local stripped="${annotation%%-*}"

    # If the current version is a simple number like "2", match segment count
    local current_dots="${current//[^.]}"
    local stripped_dots="${stripped//[^.]}"

    if [[ ${#current_dots} -lt ${#stripped_dots} ]]; then
        # Current has fewer segments — extract matching number of segments
        local num_segments=$(( ${#current_dots} + 1 ))
        local result=""
        local i=0
        IFS='.' read -ra parts <<< "$stripped"
        for part in "${parts[@]}"; do
            if [[ $i -ge $num_segments ]]; then
                break
            fi
            if [[ -n "$result" ]]; then
                result="${result}.${part}"
            else
                result="$part"
            fi
            i=$(( i + 1 ))
        done
        echo "$result"
    else
        echo "$stripped"
    fi
}

# Get latest version from Docker Hub by reading the org.opencontainers.image.version
# annotation from the amd64 manifest entry in the image index.
get_latest_docker_version() {
    local app="$1"
    local registry image current platform
    registry=$(get_config "$app" ".source.registry" "docker.io")
    image=$(get_config "$app" ".source.image")
    platform=$(get_config "$app" ".source.platform" "linux/amd64")
    current=$(yq -r '.version' "${APPS_DIR}/${app}/config.yaml")

    local image_ref="${registry}/${image}:latest"
    log_debug "Checking Docker: $image_ref"

    # Get the manifest index for the latest tag
    local index
    index=$(crane manifest "$image_ref" 2>&1) || {
        log_warn "Failed to fetch manifest for $image_ref: $index"
        echo "ERROR"
        return
    }

    # Check if this is a manifest index (multi-arch) or a single manifest
    local media_type
    media_type=$(echo "$index" | jq -r '.mediaType // .schemaVersion' 2>/dev/null)

    local annotation=""
    IFS='/' read -r plat_os plat_arch <<< "$platform"

    case "$media_type" in
        *index*|*list*)
            # Multi-arch manifest — find the annotation on the amd64 entry
            annotation=$(echo "$index" | jq -r --arg os "$plat_os" --arg arch "$plat_arch" '
                .manifests[] |
                select(.platform.os == $os and .platform.architecture == $arch) |
                select(.annotations["vnd.docker.reference.type"] == null) |
                .annotations["org.opencontainers.image.version"] // empty
            ' 2>/dev/null | head -1)
            ;;
        *)
            # Single manifest — check config for annotation
            annotation=$(echo "$index" | jq -r '
                .annotations["org.opencontainers.image.version"] // empty
            ' 2>/dev/null)
            ;;
    esac

    if [[ -z "$annotation" ]]; then
        # Fallback: try to get annotation from image config
        local config_json
        config_json=$(crane config "${image_ref}" 2>/dev/null) || true
        if [[ -n "$config_json" ]]; then
            annotation=$(echo "$config_json" | jq -r '
                .config.Labels["org.opencontainers.image.version"] // empty
            ' 2>/dev/null)
        fi
    fi

    if [[ -z "$annotation" ]]; then
        log_warn "No version annotation found for $image_ref"
        echo "ERROR"
        return
    fi

    log_debug "Annotation for $app: $annotation (current: $current)"
    clean_docker_version "$annotation" "$current"
}

# Get latest version from GitHub releases.
# Used for both github_release and lockfile source types.
get_latest_github_version() {
    local app="$1"
    local repo tag_prefix
    repo=$(get_config "$app" ".source.repo")
    tag_prefix=$(get_config "$app" ".source.tag_prefix" "")

    log_debug "Checking GitHub: $repo"

    local tag_name=""

    if command -v gh &>/dev/null; then
        tag_name=$(gh release view --repo "$repo" --json tagName -q '.tagName' 2>&1) || {
            log_warn "gh release view failed for $repo: $tag_name"
            tag_name=""
        }
    fi

    # Fallback to curl if gh failed or isn't installed
    if [[ -z "$tag_name" ]]; then
        local api_url="https://api.github.com/repos/${repo}/releases/latest"
        local response
        response=$(curl -fsSL -H "Accept: application/vnd.github+json" \
            ${GH_TOKEN:+-H "Authorization: Bearer ${GH_TOKEN}"} \
            "$api_url" 2>&1) || {
            log_warn "Failed to fetch latest release for $repo: $response"
            echo "ERROR"
            return
        }
        tag_name=$(echo "$response" | jq -r '.tag_name // empty')
    fi

    if [[ -z "$tag_name" ]]; then
        log_warn "No release found for $repo"
        echo "ERROR"
        return
    fi

    # Strip tag prefix (e.g., "v1.2.3" → "1.2.3")
    if [[ -n "$tag_prefix" && "$tag_name" == "${tag_prefix}"* ]]; then
        tag_name="${tag_name#"$tag_prefix"}"
    fi

    echo "$tag_name"
}

# =============================================================================
# Version Comparison
# =============================================================================

# Compare two versions. Returns 0 if latest is newer than current.
version_is_newer() {
    local current="$1"
    local latest="$2"

    if [[ "$current" == "$latest" ]]; then
        return 1
    fi

    # Use sort -V (version sort) to determine order
    local sorted_first
    sorted_first=$(printf '%s\n%s\n' "$current" "$latest" | sort -V | head -1)

    # If current sorts first, then latest is newer
    [[ "$sorted_first" == "$current" ]]
}

# =============================================================================
# Per-App Check
# =============================================================================

check_single_app() {
    local app="$1"
    local result_dir="$2"

    local source_type current latest status
    source_type=$(get_source_type "$app")
    current=$(yq -r '.version' "${APPS_DIR}/${app}/config.yaml")

    case "$source_type" in
        docker)
            latest=$(get_latest_docker_version "$app")
            ;;
        github_release|lockfile)
            latest=$(get_latest_github_version "$app")
            ;;
        chainguard)
            # Rolling latest tag — nothing to compare
            echo "skipped|${app}|${current}||${source_type}" > "${result_dir}/${app}"
            return
            ;;
        *)
            log_warn "Unknown source type for $app: $source_type"
            echo "error|${app}|${current}||${source_type}" > "${result_dir}/${app}"
            return
            ;;
    esac

    if [[ "$latest" == "ERROR" ]]; then
        echo "error|${app}|${current}||${source_type}" > "${result_dir}/${app}"
        return
    fi

    if version_is_newer "$current" "$latest"; then
        status="update"
    else
        status="current"
    fi

    echo "${status}|${app}|${current}|${latest}|${source_type}" > "${result_dir}/${app}"
}

# =============================================================================
# Output Functions
# =============================================================================

print_table() {
    local result_dir="$1"

    local up_to_date=0 updates=0 skipped=0 errors=0

    for result_file in "${result_dir}"/*; do
        [[ -f "$result_file" ]] || continue
        local line
        line=$(<"$result_file")

        IFS='|' read -r status app current latest source_type <<< "$line"

        case "$status" in
            current)
                printf "  %-30s %-24s (up to date)\n" "$app" "$current"
                up_to_date=$(( up_to_date + 1 ))
                ;;
            update)
                printf "  %-30s %-24s -> %-16s (update available)\n" "$app" "$current" "$latest"
                updates=$(( updates + 1 ))
                ;;
            skipped)
                printf "  %-30s %-24s              (skipped: %s)\n" "$app" "$current" "$source_type"
                skipped=$(( skipped + 1 ))
                ;;
            error)
                printf "  %-30s %-24s              (error)\n" "$app" "$current"
                errors=$(( errors + 1 ))
                ;;
        esac
    done

    echo ""
    echo "Summary: ${up_to_date} up to date, ${updates} updates available, ${skipped} skipped, ${errors} errors"
}

print_json() {
    local result_dir="$1"

    local results=()
    local up_to_date=0 updates=0 skipped=0 errors=0

    for result_file in "${result_dir}"/*; do
        [[ -f "$result_file" ]] || continue
        local line
        line=$(<"$result_file")

        IFS='|' read -r status app current latest source_type <<< "$line"

        results+=("$(jq -n \
            --arg status "$status" \
            --arg app "$app" \
            --arg current "$current" \
            --arg latest "$latest" \
            --arg source_type "$source_type" \
            '{status: $status, app: $app, current_version: $current, latest_version: $latest, source_type: $source_type}'
        )")

        case "$status" in
            current) up_to_date=$(( up_to_date + 1 )) ;;
            update)  updates=$(( updates + 1 )) ;;
            skipped) skipped=$(( skipped + 1 )) ;;
            error)   errors=$(( errors + 1 )) ;;
        esac
    done

    # Build JSON array from results
    local json_array="["
    local first=true
    for item in "${results[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            json_array+=","
        fi
        json_array+="$item"
    done
    json_array+="]"

    jq -n \
        --argjson apps "$json_array" \
        --argjson up_to_date "$up_to_date" \
        --argjson updates "$updates" \
        --argjson skipped "$skipped" \
        --argjson errors "$errors" \
        '{
            apps: $apps,
            summary: {
                up_to_date: $up_to_date,
                updates_available: $updates,
                skipped: $skipped,
                errors: $errors
            }
        }'
}

# =============================================================================
# Auto-Update
# =============================================================================

apply_updates() {
    local result_dir="$1"
    local applied=0

    for result_file in "${result_dir}"/*; do
        [[ -f "$result_file" ]] || continue
        local line
        line=$(<"$result_file")

        IFS='|' read -r status app _ latest _ <<< "$line"

        if [[ "$status" != "update" ]]; then
            continue
        fi

        local config_file="${APPS_DIR}/${app}/config.yaml"

        if is_dry_run; then
            log_info "[DRY RUN] Would update $app to $latest in $config_file"
        else
            log_info "Updating $app to $latest"
            yq -i ".version = \"${latest}\"" "$config_file"
        fi
        applied=$(( applied + 1 ))
    done

    if [[ $applied -eq 0 ]]; then
        log_info "No updates to apply."
    else
        local verb="Applied"
        is_dry_run && verb="Would apply"
        log_info "${verb} ${applied} update(s)."
    fi
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    require_cmd "yq" "Install with: brew install yq"
    require_cmd "jq" "Install with: brew install jq"

    # Check for source-type-specific tools
    if [[ -z "$FILTER_TYPE" || "$FILTER_TYPE" == "docker" ]]; then
        require_cmd "crane" "Install with: go install github.com/google/go-containerregistry/cmd/crane@latest"
    fi

    # Build app list
    local apps=()

    if [[ -n "$FILTER_APPS" ]]; then
        IFS=',' read -ra apps <<< "$FILTER_APPS"
        # Validate each app exists
        for app in "${apps[@]}"; do
            validate_app_dir "$app"
        done
    else
        for config in "${APPS_DIR}"/*/config.yaml; do
            local app_dir
            app_dir="$(dirname "$config")"
            local app
            app="$(basename "$app_dir")"

            # Skip template
            [[ "$app" == ".template" ]] && continue

            # Apply type filter
            if [[ -n "$FILTER_TYPE" ]]; then
                local src_type
                src_type=$(yq -r '.source.type' "$config")
                [[ "$src_type" != "$FILTER_TYPE" ]] && continue
            fi

            apps+=("$app")
        done
    fi

    if [[ ${#apps[@]} -eq 0 ]]; then
        die "No apps found matching filters."
    fi

    local result_dir
    result_dir=$(create_temp_dir "check-updates")

    if [[ "$JSON_OUTPUT" != true ]]; then
        echo "Checking ${#apps[@]} apps for updates..." >&2
        echo "" >&2
    fi

    # Run checks in parallel, capped at MAX_PARALLEL
    local running=0
    local pids=()

    for app in "${apps[@]}"; do
        (
            # Clear inherited EXIT trap so child doesn't remove parent's temp dir
            trap - EXIT
            _SBOM_TEMP_DIRS=()
            check_single_app "$app" "$result_dir"
        ) &
        pids+=($!)
        running=$(( running + 1 ))

        if [[ $running -ge $MAX_PARALLEL ]]; then
            # Wait for any one job to finish
            wait -n 2>/dev/null || true
            running=$(( running - 1 ))
        fi
    done

    # Wait for all remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Output results
    if [[ "$JSON_OUTPUT" == true ]]; then
        print_json "$result_dir"
    else
        print_table "$result_dir" >&2
    fi

    # Apply updates if requested
    if [[ "$AUTO_UPDATE" == true ]]; then
        apply_updates "$result_dir"
    fi

    # Set exit code based on results
    local has_updates=false has_errors=false
    for result_file in "${result_dir}"/*; do
        [[ -f "$result_file" ]] || continue
        local status
        status=$(cut -d'|' -f1 < "$result_file")
        [[ "$status" == "update" ]] && has_updates=true
        [[ "$status" == "error" ]] && has_errors=true
    done

    if [[ "$has_errors" == true ]]; then
        exit 2
    elif [[ "$has_updates" == true ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
