#!/usr/bin/env bash
# lockfile-generator.sh - Download lockfile for SBOM generation
#
# This script only downloads the lockfile from GitHub.
# SBOM generation is handled by the sbomify GitHub Action.
# shellcheck source-path=SCRIPTDIR

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

lockfile_name=$(basename "$lockfile")
curl -fsSL -o "${lockfile_name}" "$url"

log_info "Downloaded: ${lockfile_name}"
