#!/usr/bin/env bash
# lockfile-generator.sh - Generate SBOM from lockfile
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../lib/common.sh"

app="$1"
version=$(get_latest_version "$app")
repo=$(get_config "$app" ".source.repo")
lockfile=$(get_config "$app" ".source.lockfile")
tag_prefix=$(get_config "$app" ".source.tag_prefix" "")
tag_suffix=$(get_config "$app" ".source.tag_suffix" "")
tag="${tag_prefix}${version}${tag_suffix}"

url="https://raw.githubusercontent.com/${repo}/${tag}/${lockfile}"
log_info "Downloading lockfile: $url"

work_dir=$(mktemp -d)
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

lockfile_name=$(basename "$lockfile")
curl -fsSL -o "${work_dir}/${lockfile_name}" "$url"

# Try to get package.json for JS projects
case "$lockfile_name" in
    package-lock.json|yarn.lock|pnpm-lock.yaml)
        pkg_dir=$(dirname "$lockfile")
        [[ "$pkg_dir" == "." ]] && pkg_dir=""
        curl -fsSL -o "${work_dir}/package.json" \
            "https://raw.githubusercontent.com/${repo}/${tag}/${pkg_dir}package.json" 2>/dev/null || true
        ;;
esac

# Generate with cdxgen or syft
if command -v cdxgen &> /dev/null; then
    log_info "Generating with cdxgen..."
    (cd "$work_dir" && cdxgen -o sbom.json .)
    mv "${work_dir}/sbom.json" sbom.json
elif command -v syft &> /dev/null; then
    log_info "Generating with syft..."
    syft "dir:${work_dir}" -o cyclonedx-json=sbom.json
else
    die "No SBOM generator found. Install cdxgen or syft."
fi
