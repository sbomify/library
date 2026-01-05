#!/usr/bin/env bash
# github-release.sh - Download SBOM from GitHub release
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

app="$1"
version=$(get_latest_version "$app")
repo=$(get_config "$app" ".source.repo")
asset=$(get_config "$app" ".source.asset")
tag_prefix=$(get_config "$app" ".source.tag_prefix" "")
tag_suffix=$(get_config "$app" ".source.tag_suffix" "")
tag="${tag_prefix}${version}${tag_suffix}"

# Replace ${version} placeholder in asset name
asset="${asset//\$\{version\}/$version}"

url="https://github.com/${repo}/releases/download/${tag}/${asset}"
log_info "Downloading: $url"
curl -fsSL -o sbom.json "$url"
