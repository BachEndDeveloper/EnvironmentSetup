#!/usr/bin/env bash
# Retry GitHub SSH authentication failures over HTTPS, using local Git credentials.
# Other failures (notably host-key verification) must not bypass SSH's checks.
set -euo pipefail
umask 077
[[ "$#" == 2 ]] || { echo 'Usage: git-clone-with-https-fallback.sh repository directory' >&2; exit 1; }
repo="$1"
destination="$2"
errors="$(mktemp)"
trap 'rm -f -- "$errors"' EXIT
status=0
git clone "$repo" "$destination" 2>"$errors" || status=$?
cat "$errors" >&2
[[ "$status" != 0 ]] || exit 0
https=""
if [[ "$repo" =~ ^git@github\.com:([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$ ]]; then
	https="https://github.com/${BASH_REMATCH[1]}"
elif [[ "$repo" =~ ^ssh://git@github\.com/([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$ ]]; then
	https="https://github.com/${BASH_REMATCH[1]}"
fi
if [[ -n "$https" ]] && grep -Eqi 'Permission denied \(publickey[^)]*\)|Authentication failed|sign_and_send_pubkey: signing failed|No supported authentication methods available' "$errors"; then
	echo 'SSH authentication failed; retrying the same repository over HTTPS (no embedded credentials).' >&2
	GIT_TERMINAL_PROMPT=0 git clone "$https" "$destination"
else
	exit "$status"
fi
