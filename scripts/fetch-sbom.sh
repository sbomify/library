#!/usr/bin/env bash
# fetch-sbom.sh - Fetch SBOM for an app
#
# Usage: ./fetch-sbom.sh <app-name>
# shellcheck source-path=SCRIPTDIR

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="${SCRIPT_DIR}/sources"

source "${SCRIPT_DIR}/lib/common.sh"

main() {
    if [[ $# -lt 1 ]]; then
        echo "Usage: $(basename "$0") <app-name>" >&2
        exit 1
    fi

    local app="$1"
    validate_app_dir "$app"

    local version source_type
    version=$(get_latest_version "$app")
    source_type=$(get_source_type "$app")

    log_info "Fetching SBOM: $app v$version ($source_type)"

    local handler="${SOURCES_DIR}/${source_type}.sh"
    if [[ ! -f "$handler" ]]; then
        # Try alternate names
        case "$source_type" in
            docker) handler="${SOURCES_DIR}/docker-attestation.sh" ;;
            github_release) handler="${SOURCES_DIR}/github-release.sh" ;;
            lockfile) handler="${SOURCES_DIR}/lockfile-generator.sh" ;;
            *) die "Unknown source type: $source_type" ;;
        esac
    fi

    "$handler" "$app"

    # Log appropriate output based on source type
    case "$source_type" in
        lockfile)
            local lockfile_path lockfile
            lockfile_path=$(get_config "$app" ".source.lockfile")
            lockfile=$(basename "$lockfile_path")
            log_info "Done: $lockfile"
            ;;
        *)
            log_info "Done: sbom.json"
            ;;
    esac
}

main "$@"
