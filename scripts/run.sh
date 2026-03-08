#!/usr/bin/env bash
# run.sh - Local SBOM pipeline runner
#
# Processes apps through the full SBOM pipeline locally:
# fetch SBOM, build augmented SBOM, dedup check, upload, cleanup.
#
# Usage:
#   ./scripts/run.sh <app>                  # Single app
#   ./scripts/run.sh --all                  # All apps
#   ./scripts/run.sh --type docker          # Filter by source type
#   ./scripts/run.sh --app redis,trivy      # Specific apps
#   ./scripts/run.sh <app> --dry-run        # No upload
#   ./scripts/run.sh --all --parallel 5     # Parallel execution
#
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/sbomify-api.sh
source "${SCRIPT_DIR}/lib/sbomify-api.sh"

# Add fnm-managed node to PATH (needed for cdxgen in lockfile sources)
if [[ -d "${HOME}/.local/share/fnm" ]]; then
    export PATH="${HOME}/.local/share/fnm:${PATH}"
    eval "$(fnm env 2>/dev/null)" 2>/dev/null || true
fi

# Add local JDK and Maven to PATH if present (needed for Maven/Gradle lockfile sources)
if [[ -d "${HOME}/.local/jdk/bin" ]]; then
    export JAVA_HOME="${HOME}/.local/jdk"
    export PATH="${JAVA_HOME}/bin:${PATH}"
fi
if [[ -d "${HOME}/.local/maven/bin" ]]; then
    export PATH="${HOME}/.local/maven/bin:${PATH}"
fi

# =============================================================================
# Constants
# =============================================================================

MAX_PARALLEL=5

# =============================================================================
# Argument Parsing
# =============================================================================

RUN_ALL=false
FILTER_TYPE=""
FILTER_APPS=""
SINGLE_APP=""
PARALLEL_COUNT=""

print_run_usage() {
    cat >&2 <<EOF
Usage: $(basename "$0") [options] [app]

Run the full SBOM pipeline for one or all apps.

Arguments:
  app                 Single app to process

Options:
  --all               Process all apps
  --type TYPE         Only process apps of this source type (docker, chainguard, github_release, lockfile)
  --app APP[,APP]     Process specific apps (comma-separated)
  --parallel N        Max parallel jobs (default: ${MAX_PARALLEL})
  -n, --dry-run       Skip upload step
  -v, --verbose       Enable debug output
  -h, --help          Show this help message

Examples:
  $(basename "$0") trivy                    # Single app
  $(basename "$0") trivy --dry-run          # Dry run
  $(basename "$0") --all                    # All apps
  $(basename "$0") --all --parallel 5       # Parallel execution
  $(basename "$0") --type docker            # Only docker apps
  $(basename "$0") --app redis,trivy        # Specific apps
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_run_usage
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
            --all)
                RUN_ALL=true
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
            --parallel)
                [[ $# -lt 2 ]] && die "--parallel requires an argument"
                PARALLEL_COUNT="$2"
                shift 2
                ;;
            -*)
                die "Unknown option: $1. Use --help for usage."
                ;;
            *)
                # Positional argument = single app
                if [[ -n "$SINGLE_APP" ]]; then
                    die "Only one app argument allowed. Use --app for multiple apps."
                fi
                SINGLE_APP="$1"
                shift
                ;;
        esac
    done

    if [[ -n "$PARALLEL_COUNT" ]]; then
        MAX_PARALLEL="$PARALLEL_COUNT"
    fi

    # Validate we have something to do
    if [[ -z "$SINGLE_APP" && "$RUN_ALL" != true && -z "$FILTER_TYPE" && -z "$FILTER_APPS" ]]; then
        die "Specify an app, --all, --type, or --app. Use --help for usage."
    fi
}

# =============================================================================
# PURL Builder
# =============================================================================

# Build Package URL for a given app, mirroring sbom-builder.yml lines 117-138
build_purl() {
    local app="$1"
    local source_type version image registry repo

    source_type=$(get_source_type "$app")
    version=$(get_latest_version "$app")

    case "$source_type" in
        docker)
            image=$(get_config "$app" ".source.image")
            echo "pkg:docker/${image}@${version}"
            ;;
        chainguard)
            image=$(get_config "$app" ".source.image")
            registry=$(get_config "$app" ".source.registry")
            echo "pkg:oci/${registry}/${image}@${version}"
            ;;
        github_release|lockfile)
            repo=$(get_config "$app" ".source.repo")
            echo "pkg:github/${repo}@${version}"
            ;;
        *)
            log_warn "Unknown source type for PURL: $source_type"
            echo ""
            ;;
    esac
}

# Build PURL base (without version) for digest-based components
build_purl_base() {
    local app="$1"
    local source_type image registry repo

    source_type=$(get_source_type "$app")

    case "$source_type" in
        docker)
            image=$(get_config "$app" ".source.image")
            echo "pkg:docker/${image}"
            ;;
        chainguard)
            image=$(get_config "$app" ".source.image")
            registry=$(get_config "$app" ".source.registry")
            echo "pkg:oci/${registry}/${image}"
            ;;
        github_release|lockfile)
            repo=$(get_config "$app" ".source.repo")
            echo "pkg:github/${repo}"
            ;;
        *)
            echo ""
            ;;
    esac
}

# =============================================================================
# Per-App Pipeline
# =============================================================================

process_app() {
    local app="$1"

    validate_app_dir "$app"

    local source_type version component_id component_name sbom_format
    source_type=$(get_source_type "$app")
    version=$(get_latest_version "$app")
    component_id=$(get_sbomify_component_id "$app")
    component_name=$(get_config "$app" ".sbomify.component_name" "")
    sbom_format=$(get_config "$app" ".format" "cyclonedx")

    log_info "=== Processing: $app v${version} (${source_type}) ==="

    # -------------------------------------------------------------------------
    # Step 1: Fetch SBOM in a temp working directory
    # -------------------------------------------------------------------------
    local work_dir
    work_dir=$(create_temp_dir "run-${app}")
    log_debug "Working directory: $work_dir"

    (
        cd "$work_dir"
        "${SCRIPT_DIR}/fetch-sbom.sh" "$app"
    )

    # -------------------------------------------------------------------------
    # Step 2: Read image digest (docker/chainguard only)
    # -------------------------------------------------------------------------
    local image_digest="" component_purl component_version
    component_version="$version"

    if [[ "$source_type" == "docker" || "$source_type" == "chainguard" ]]; then
        if [[ ! -f "${work_dir}/image-digest.txt" ]]; then
            log_error "image-digest.txt not found for $app"
            return 1
        fi
        image_digest=$(<"${work_dir}/image-digest.txt")
        component_version="$image_digest"
        local purl_base
        purl_base=$(build_purl_base "$app")
        component_purl="${purl_base}@${image_digest}"
        log_info "Image digest: $image_digest"
    else
        component_purl=$(build_purl "$app")
    fi

    # -------------------------------------------------------------------------
    # Step 3: Build augmented SBOM via sbomify-action
    # -------------------------------------------------------------------------
    if [[ -z "$component_id" ]]; then
        log_warn "No component_id configured for $app, skipping SBOM build/upload"
        return 0
    fi

    local sbomify_env=(
        "TOKEN=${SBOMIFY_TOKEN:-}"
        "COMPONENT_ID=${component_id}"
        "COMPONENT_NAME=${component_name}"
        "COMPONENT_VERSION=${component_version}"
        "COMPONENT_PURL=${component_purl}"
        "OUTPUT_FILE=${work_dir}/sbom-output.json"
        "AUGMENT=true"
        "ENRICH=false"
        "UPLOAD=false"
    )

    if [[ "$source_type" == "lockfile" ]]; then
        # Determine lockfile path
        local lockfile_path clone
        clone=$(get_config "$app" ".source.clone" "false")
        lockfile_path=$(get_config "$app" ".source.lockfile" "")

        if [[ "$clone" == "true" ]]; then
            sbomify_env+=("LOCK_FILE=${work_dir}/repo/${lockfile_path}")
        else
            sbomify_env+=("LOCK_FILE=${work_dir}/$(basename "$lockfile_path")")
        fi
    else
        sbomify_env+=("SBOM_FILE=${work_dir}/sbom.json")
    fi

    # Sanitize invalid SPDX license expressions before augmentation
    if [[ "$sbom_format" == "spdx" && -f "${work_dir}/sbom.json" ]]; then
        python3 -c "
import json, sys, re
with open(sys.argv[1]) as f:
    data = json.load(f)
changed = 0
for pkg in data.get('packages', []):
    for field in ('licenseDeclared', 'licenseConcluded'):
        val = pkg.get(field, '')
        if val and val not in ('NOASSERTION', 'NONE'):
            # Replace invalid license expressions with NOASSERTION
            if re.search(r'[^A-Za-z0-9_.+\-\s()\/]', val) or '(the ' in val.lower() or '(tests ' in val.lower():
                pkg[field] = 'NOASSERTION'
                changed += 1
if changed:
    with open(sys.argv[1], 'w') as f:
        json.dump(data, f)
    print(f'Sanitized {changed} invalid license expression(s)', file=sys.stderr)
" "${work_dir}/sbom.json" 2>&1 | while read -r line; do log_info "$line"; done
    fi

    log_info "Building augmented SBOM..."
    ( cd "$work_dir" && env "${sbomify_env[@]}" uvx --from sbomify-action sbomify-action )

    # -------------------------------------------------------------------------
    # Step 3b: Strip file-level data from SPDX SBOMs
    # -------------------------------------------------------------------------
    # Docker/chainguard SPDX SBOMs include per-file entries that can be 10MB+.
    # The sbomify API has a body size limit, so we strip files and file-level
    # relationships to keep the upload under the limit while preserving all
    # package-level data.
    if [[ "$sbom_format" == "spdx" && -f "${work_dir}/sbom-output.json" ]]; then
        local original_size stripped_size
        original_size=$(stat -c%s "${work_dir}/sbom-output.json")
        if [[ $original_size -gt 2000000 ]]; then
            log_info "Stripping file-level data from SPDX SBOM ($(( original_size / 1024 / 1024 ))MB)..."
            python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
data['files'] = []
data['relationships'] = [r for r in data.get('relationships', [])
    if not r.get('spdxElementId', '').startswith('SPDXRef-File')
    and not r.get('relatedSpdxElement', '').startswith('SPDXRef-File')]
with open(sys.argv[1], 'w') as f:
    json.dump(data, f)
" "${work_dir}/sbom-output.json"
            stripped_size=$(stat -c%s "${work_dir}/sbom-output.json")
            log_info "Stripped: $(( original_size / 1024 ))KB -> $(( stripped_size / 1024 ))KB"
        fi
    fi

    # -------------------------------------------------------------------------
    # Step 4: Dedup check
    # -------------------------------------------------------------------------
    local should_upload=true

    if ! is_dry_run; then
        if [[ "$source_type" == "docker" || "$source_type" == "chainguard" ]]; then
            # Check sbomify for existing digest
            if sbomify_digest_exists "$component_id" "$image_digest"; then
                log_info "Digest already exists on sbomify, skipping upload"
                should_upload=false
            else
                log_info "New digest, will upload"
            fi
        else
            # TEA check for github_release/lockfile
            local purl tei result
            purl=$(build_purl "$app")
            if [[ -n "$purl" ]]; then
                tei="urn:tei:purl:library.sbomify.com:${purl}"
                log_debug "TEI: $tei"
                result=$(uvx --from 'libtea[cli]' tea-cli inspect "$tei" --json 2>/dev/null || true)
                if [[ -n "$result" && "$result" != "{}" && "$result" != "null" ]]; then
                    log_info "Version already published on TEA, skipping upload"
                    should_upload=false
                else
                    log_info "Version not found on TEA, will upload"
                fi
            fi
        fi
    fi

    # -------------------------------------------------------------------------
    # Step 5: Upload (if new + not dry-run)
    # -------------------------------------------------------------------------
    if is_dry_run; then
        log_info "[DRY RUN] Would upload SBOM for $app"
    elif [[ "$should_upload" == true ]]; then
        # Build product release array
        local product_id bundle_product_id product_release=""
        product_id=$(get_config "$app" ".sbomify.product_id" "")
        bundle_product_id=$(get_config "$app" ".sbomify.bundle_product_id" "")

        if [[ -n "$product_id" && -n "$version" ]]; then
            product_release="\"${product_id}:${version}\""
            if [[ -n "$bundle_product_id" ]]; then
                product_release="${product_release},\"${bundle_product_id}:${version}\""
            fi
            product_release="[${product_release}]"
        fi

        log_info "Uploading SBOM..."
        local upload_env=(
            "TOKEN=${SBOMIFY_TOKEN:-}"
            "COMPONENT_ID=${component_id}"
            "COMPONENT_NAME=${component_name}"
            "COMPONENT_VERSION=${component_version}"
            "COMPONENT_PURL=${component_purl}"
            "SBOM_FILE=${work_dir}/sbom-output.json"
            "OUTPUT_FILE=${work_dir}/sbom-final.json"
            "AUGMENT=false"
            "ENRICH=false"
            "UPLOAD=true"
        )
        if [[ -n "$product_release" ]]; then
            upload_env+=("PRODUCT_RELEASE=${product_release}")
        fi

        ( cd "$work_dir" && env "${upload_env[@]}" uvx --from sbomify-action sbomify-action )
        log_info "Upload complete for $app"
    else
        log_info "Skipping upload for $app (already exists)"
    fi

    # -------------------------------------------------------------------------
    # Step 6: Cleanup (docker/chainguard only)
    # -------------------------------------------------------------------------
    if ! is_dry_run && [[ "$source_type" == "docker" || "$source_type" == "chainguard" ]]; then
        if [[ "$should_upload" == true ]]; then
            log_info "Cleaning up old SBOMs..."
            sbomify_cleanup_old_sboms "$component_id" "$image_digest"

            local product_id_cleanup
            product_id_cleanup=$(get_config "$app" ".sbomify.product_id" "")
            if [[ -n "$product_id_cleanup" ]]; then
                sbomify_cleanup_versioned_releases "$product_id_cleanup"
            fi
        fi
    fi

    log_info "=== Done: $app ==="
}

# =============================================================================
# Tool Checks
# =============================================================================

check_tools() {
    local apps=("$@")

    require_cmd "yq" "Install with: brew install yq"
    require_cmd "jq" "Install with: brew install jq"

    # Check uvx (needed for sbomify-action and tea-cli)
    if ! command -v uvx &>/dev/null; then
        die "Required command 'uvx' not found. Install with: pip install uv"
    fi

    # Check source-type-specific tools
    local needs_crane=false needs_cosign=false needs_lockfile_gen=false
    for app in "${apps[@]}"; do
        local src_type
        src_type=$(get_source_type "$app")
        case "$src_type" in
            docker) needs_crane=true ;;
            chainguard) needs_cosign=true ;;
            lockfile) needs_lockfile_gen=true ;;
        esac
    done

    if [[ "$needs_crane" == true ]]; then
        require_cmd "crane" "Install with: go install github.com/google/go-containerregistry/cmd/crane@latest"
    fi
    if [[ "$needs_cosign" == true ]]; then
        require_cmd "cosign" "Install from: https://github.com/sigstore/cosign"
    fi
    if [[ "$needs_lockfile_gen" == true ]]; then
        if ! command -v cdxgen &>/dev/null && ! command -v trivy &>/dev/null && ! command -v syft &>/dev/null; then
            die "Lockfile sources require cdxgen, trivy, or syft. Install cdxgen with: npm install -g @cyclonedx/cdxgen"
        fi
    fi

    # Validate SBOMIFY_TOKEN for non-dry-run
    if ! is_dry_run && [[ -z "${SBOMIFY_TOKEN:-}" ]]; then
        die "SBOMIFY_TOKEN is required for upload. Set it or use --dry-run."
    fi
}

# =============================================================================
# App List Builder
# =============================================================================

build_app_list() {
    local apps=()

    if [[ -n "$SINGLE_APP" ]]; then
        apps=("$SINGLE_APP")
    elif [[ -n "$FILTER_APPS" ]]; then
        IFS=',' read -ra apps <<< "$FILTER_APPS"
    else
        for config in "${APPS_DIR}"/*/config.yaml; do
            local app_dir app
            app_dir="$(dirname "$config")"
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

    # Validate all apps exist
    for app in "${apps[@]}"; do
        validate_app_dir "$app"
    done

    if [[ ${#apps[@]} -eq 0 ]]; then
        die "No apps found matching filters."
    fi

    echo "${apps[@]}"
}

# =============================================================================
# Main
# =============================================================================

main() {
    parse_args "$@"

    # Build app list
    local app_list
    app_list=$(build_app_list)
    local apps=()
    read -ra apps <<< "$app_list"

    # Check required tools
    check_tools "${apps[@]}"

    local total=${#apps[@]}
    log_info "Processing ${total} app(s)..."

    if [[ $total -eq 1 ]]; then
        # Single app — run directly
        process_app "${apps[0]}"
    else
        # Multiple apps — run in parallel
        local running=0
        local pids=()
        local failed=0

        for app in "${apps[@]}"; do
            (
                # Clear inherited EXIT trap so child doesn't remove parent's temp dir
                trap - EXIT
                _SBOM_TEMP_DIRS=()
                process_app "$app"
            ) &
            pids+=($!)
            running=$(( running + 1 ))

            if [[ $running -ge $MAX_PARALLEL ]]; then
                wait -n 2>/dev/null || failed=$(( failed + 1 ))
                running=$(( running - 1 ))
            fi
        done

        # Wait for remaining jobs
        for pid in "${pids[@]}"; do
            wait "$pid" 2>/dev/null || failed=$(( failed + 1 ))
        done

        if [[ $failed -gt 0 ]]; then
            log_warn "${failed} app(s) failed"
            exit 1
        fi
    fi

    log_info "All done."
}

main "$@"
