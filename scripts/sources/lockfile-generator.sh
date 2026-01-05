#!/usr/bin/env bash
# lockfile-generator.sh - Download lockfile or clone repo for SBOM generation
#
# This script downloads lockfiles or clones repos from GitHub.
# SBOM generation is handled by the sbomify GitHub Action.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../lib/common.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

app="$1"
version=$(get_latest_version "$app")
repo=$(get_config "$app" ".source.repo")
lockfile=$(get_config "$app" ".source.lockfile")
tag_prefix=$(get_config "$app" ".source.tag_prefix" "")
tag_suffix=$(get_config "$app" ".source.tag_suffix" "")
clone=$(get_config "$app" ".source.clone" "false")
tag="${tag_prefix}${version}${tag_suffix}"

if [[ "$clone" == "true" ]]; then
    # Shallow clone the repository
    repo_url="https://github.com/${repo}.git"
    log_info "Shallow cloning: $repo_url (tag: $tag)"
    git clone --depth 1 --branch "$tag" "$repo_url" repo
    log_info "Cloned: repo/"

    # Run post-clone commands if configured
    while IFS= read -r cmd; do
        if [[ -n "$cmd" ]]; then
            log_info "Running post-clone command: $cmd"
            (cd repo && bash -c "$cmd")
        fi
    done < <(get_config_array "$app" ".source.post_clone_commands")
else
    # Download just the lockfile
    url="https://raw.githubusercontent.com/${repo}/${tag}/${lockfile}"
    log_info "Downloading lockfile: $url"
    lockfile_name=$(basename "$lockfile")
    curl -fsSL -o "${lockfile_name}" "$url"
    log_info "Downloaded: ${lockfile_name}"
fi
