#!/usr/bin/env bash
# Adds a file to this tag's GitHub Release, waiting (up to 45 minutes) for
# the Build workflow to create it. Usage: upload_to_release.sh FILE
set -euo pipefail
for _ in $(seq 90); do
  if gh release view "$GITHUB_REF_NAME" --repo "$GITHUB_REPOSITORY" >/dev/null 2>&1; then
    gh release upload "$GITHUB_REF_NAME" "$1" --repo "$GITHUB_REPOSITORY" --clobber
    exit 0
  fi
  sleep 30
done
echo "::error::No release for $GITHUB_REF_NAME after 45 minutes; $1 is in this run's artifacts."
exit 1
