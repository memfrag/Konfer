#!/bin/bash
# Copyright © 2026 Martin Johannesson. All rights reserved.
set -euo pipefail

# -----------------------------------------------------------------------------
# Package a converted Pianissimo for a GitHub release, and optionally publish
# it.
#
# Prerequisites:
#   - ./scripts/pianissimo-coreml/convert.sh has been run
#   - gh auth login (for --publish)
#
# Usage:
#   ./scripts/pianissimo-coreml/package.sh --release 1 [--publish]
#
# Writes build/release/pianissimo-sv-120s.zip with a manifest and the release
# notes, and prints the size and SHA-256 that PianissimoModelStore pins.
# --publish creates the release pianissimo-sv-120s-<release> on GitHub. It is
# never marked latest: build-and-notarize.sh reads the latest release as the
# app's last version.
# -----------------------------------------------------------------------------

GITHUB_REPO="memfrag/Konfer"
ASSET="pianissimo-sv-120s.zip"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPILED="$SCRIPT_DIR/build/compiled"
STAGING="$SCRIPT_DIR/build/release/staging"
ARCHIVE="$SCRIPT_DIR/build/release/$ASSET"

RELEASE=""
PUBLISH=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) RELEASE="$2"; shift 2 ;;
        --publish) PUBLISH=1; shift ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done
[[ -n "$RELEASE" ]] || { echo "--release <n> is required" >&2; exit 1; }
[[ -d "$COMPILED" ]] || { echo "Nothing to package: run convert.sh first" >&2; exit 1; }
TAG="pianissimo-sv-120s-$RELEASE"

echo "==> Staging"
rm -rf "$STAGING" "$ARCHIVE"
mkdir -p "$STAGING"
cp -R "$COMPILED"/. "$STAGING"/
cp "$SCRIPT_DIR/RELEASE_NOTES.md" "$STAGING/README.md"

# Every file's size and SHA-256, so a copy can be checked against the release.
(cd "$STAGING" && find . -type f ! -name manifest.json | sed 's|^\./||' | sort | while read -r file; do
    printf '%s\t%s\t%s\n' "$(stat -f %z "$file")" "$(shasum -a 256 "$file" | cut -d' ' -f1)" "$file"
done) | python3 -c '
import json, sys
files = [dict(path=p, size=int(s), sha256=h) for s, h, p in (l.rstrip("\n").split("\t") for l in sys.stdin)]
json.dump({"release": sys.argv[1], "files": files}, open(sys.argv[2], "w"), indent=2)
' "$TAG" "$STAGING/manifest.json"

echo "==> Zipping"
# Sorted, with fixed timestamps and no extra attributes, so the same build
# always zips to the same bytes, and so to the same SHA-256.
find "$STAGING" -exec touch -h -t 202601010000 {} +
(cd "$STAGING" && find . -type f | sed 's|^\./||' | LC_ALL=C sort | zip -q -X -@ "$ARCHIVE")

SIZE=$(stat -f %z "$ARCHIVE")
SHA256=$(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)
echo "    $ARCHIVE"
echo "    tag:    $TAG"
echo "    size:   $SIZE"
echo "    sha256: $SHA256"

if [[ "$PUBLISH" -eq 1 ]]; then
    echo "==> Publishing $TAG to $GITHUB_REPO"
    gh release create "$TAG" "$ARCHIVE" \
        --repo "$GITHUB_REPO" \
        --title "Pianissimo CoreML, 120 s window ($RELEASE)" \
        --notes-file "$SCRIPT_DIR/RELEASE_NOTES.md" \
        --latest=false
    echo "    https://github.com/$GITHUB_REPO/releases/download/$TAG/$ASSET"
fi
