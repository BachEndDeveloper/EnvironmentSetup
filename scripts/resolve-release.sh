#!/usr/bin/env bash
# Resolve the release a checkout should run. See RELEASES.md.
#
# Usage: resolve-release.sh <git-checkout> <ref>
#   <ref> = "latest"  -> the highest stable release tag (vMAJOR.MINOR.PATCH, no pre-release suffix)
#   <ref> = anything else (for example v0.6.0) -> printed unchanged: an explicit hold-back pin
#
# Prints the resolved tag on stdout. Exits non-zero, with a message on stderr, when "latest" is
# requested but the checkout has no release tag. Tags must already be fetched; this script never
# touches the network and never changes the checkout.
set -euo pipefail

dir="${1:?usage: resolve-release.sh <git-checkout> <ref>}"
ref="${2:?usage: resolve-release.sh <git-checkout> <ref>}"

if [[ "$ref" != "latest" ]]; then
	printf '%s\n' "$ref"
	exit 0
fi

tag="$(git -C "$dir" tag --list 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 || true)"
if [[ -z "$tag" ]]; then
	echo "no release tag (vX.Y.Z) found in $dir - nothing has been released yet" >&2
	exit 1
fi
printf '%s\n' "$tag"
