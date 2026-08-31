#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Archive, notarize, DMG, sign for Sparkle, publish GitHub release,
# and update appcast.xml.
#
# Prerequisites:
#   - xcrun notarytool store-credentials 'notary' (one-time setup)
#   - gh auth login
#   - Sparkle EdDSA keys in keychain (run: ./Sparkle-tools/bin/generate_keys)
#
# Usage:
#   ./scripts/build-and-notarize.sh [--version 1.2.0] [--title "Konfer 1.2.0"]
#
# Both values are prompted for when omitted and a terminal is attached, and
# required as arguments when one is not, so the same script serves a release cut
# by hand and one cut by a machine.
# -----------------------------------------------------------------------------

# --- Constants ---
SCHEME="Konfer (Release)"
APP_NAME="Konfer"
KEYCHAIN_PROFILE="notary"
SPARKLE_VERSION="2.9.1"
GITHUB_REPO="memfrag/Konfer"

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
SPARKLE_TOOLS_DIR="$PROJECT_DIR/Sparkle-tools"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
EXPORT_OPTIONS="$SCRIPT_DIR/ExportOptions.plist"
PBXPROJ="$PROJECT_DIR/$APP_NAME.xcodeproj/project.pbxproj"

# --- Helpers ---
error() {
    echo "ERROR: $1" >&2
    exit 1
}

usage() {
    cat <<USAGE
Usage: $(basename "$0") [options]

  --version <x.y.z>   Version to release. Prompted for when omitted.
  --title <text>      GitHub release title. Defaults to "$APP_NAME <version>".
  -h, --help          This.

With no arguments and a terminal attached, both are prompted for as before.
USAGE
}

# --- Arguments ---
VERSION_ARG=""
TITLE_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        --version) [ $# -ge 2 ] || error "--version needs a value."; VERSION_ARG="$2"; shift 2 ;;
        --version=*) VERSION_ARG="${1#*=}"; shift ;;
        --title) [ $# -ge 2 ] || error "--title needs a value."; TITLE_ARG="$2"; shift 2 ;;
        --title=*) TITLE_ARG="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; error "Unknown option: $1" ;;
    esac
done

# Whether there is anyone to ask.
if [ -t 0 ]; then INTERACTIVE=true; else INTERACTIVE=false; fi

# --- Preflight ---
# Everything the run needs but would not miss until the end. Notarization is
# forty minutes of archiving away from the start, and finding out there is no
# credential for it then is the whole reason this section exists.
echo "==> Checking prerequisites..."

xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1 \
    || error "No notarytool credentials for profile '$KEYCHAIN_PROFILE'. Run:
    xcrun notarytool store-credentials '$KEYCHAIN_PROFILE' --apple-id <id> --team-id <team>"

gh auth status >/dev/null 2>&1 \
    || error "gh is not authenticated. Run: gh auth login"

security find-generic-password -s "https://sparkle-project.org" >/dev/null 2>&1 \
    || error "No Sparkle EdDSA key in the keychain. Run: ./Sparkle-tools/bin/generate_keys"

echo "    Notarization, GitHub and Sparkle signing are all set up."

# --- Clean and create build directory ---
echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# --- Download Sparkle tools if needed ---
if [ ! -x "$SPARKLE_TOOLS_DIR/bin/sign_update" ]; then
    echo "==> Downloading Sparkle tools $SPARKLE_VERSION..."
    curl -sL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" -o "$BUILD_DIR/Sparkle.tar.xz"
    mkdir -p "$SPARKLE_TOOLS_DIR"
    tar -xf "$BUILD_DIR/Sparkle.tar.xz" -C "$SPARKLE_TOOLS_DIR"
    rm "$BUILD_DIR/Sparkle.tar.xz"
    echo "    Sparkle tools installed at $SPARKLE_TOOLS_DIR"
fi

# --- Version checking ---
echo "==> Checking version..."
CURRENT_VERSION=$(grep 'MARKETING_VERSION' "$PBXPROJ" | head -1 | sed 's/.*= *//;s/ *;.*//' || true)
[ -n "$CURRENT_VERSION" ] || error "Could not read MARKETING_VERSION from project.pbxproj."
echo "    Current version: $CURRENT_VERSION"

LATEST_TAG=$(gh release view --repo "$GITHUB_REPO" --json tagName -q '.tagName' 2>/dev/null || true)
if [ -n "$LATEST_TAG" ]; then
    echo "    Latest release: $LATEST_TAG"
fi

NEED_NEW_VERSION=false
if [ -n "$LATEST_TAG" ] && [ "$CURRENT_VERSION" = "$LATEST_TAG" ]; then
    NEED_NEW_VERSION=true
    echo "    Current version matches the latest release, so it has to go up."
fi

if [ -n "$VERSION_ARG" ]; then
    VERSION="$VERSION_ARG"
elif [ "$INTERACTIVE" = true ]; then
    if [ "$NEED_NEW_VERSION" = true ]; then
        read -rp "    Enter new version: " VERSION
        [ -n "$VERSION" ] || error "Version cannot be empty."
    else
        read -rp "    Enter version to release [$CURRENT_VERSION]: " VERSION
        VERSION="${VERSION:-$CURRENT_VERSION}"
    fi
elif [ "$NEED_NEW_VERSION" = true ]; then
    # Reusing the released version would be wrong, and there is nobody to ask.
    error "$CURRENT_VERSION is already released. Pass --version <x.y.z>."
else
    VERSION="$CURRENT_VERSION"
    echo "    No --version given; releasing $VERSION."
fi

case "$VERSION" in
    ""|*[![:alnum:].+-]*) error "Version '$VERSION' should look like 1.2.0." ;;
esac

# Cheaper to refuse now than after notarization, which is where the clash would
# otherwise surface.
if git rev-parse -q --verify "refs/tags/$VERSION" >/dev/null; then
    error "Tag $VERSION already exists."
fi

if [ "$VERSION" != "$CURRENT_VERSION" ]; then
    echo "==> Updating version to $VERSION..."
    sed -i '' "s/MARKETING_VERSION = [^;]*/MARKETING_VERSION = $VERSION/" "$PBXPROJ" || error "Failed to update MARKETING_VERSION in project.pbxproj"
    sed -i '' "s/CURRENT_PROJECT_VERSION = [^;]*/CURRENT_PROJECT_VERSION = $VERSION/" "$PBXPROJ" || error "Failed to update CURRENT_PROJECT_VERSION in project.pbxproj"
    cd "$PROJECT_DIR"
    git add "$PBXPROJ"
    git commit -m "Bump version to $VERSION"
    git push origin HEAD
    echo "    Version updated and pushed."
fi

TAG="$VERSION"

# --- Archive ---
echo "==> Archiving..."
if ! xcodebuild archive \
    -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    -arch arm64 \
    ENABLE_HARDENED_RUNTIME=YES \
    2>&1 | tee "$BUILD_DIR/archive.log" | tail -5 || [ ! -d "$ARCHIVE_PATH" ]; then
    echo "--- Last 30 lines of archive.log ---"
    tail -30 "$BUILD_DIR/archive.log"
    error "Archive failed. See $BUILD_DIR/archive.log for details."
fi
echo "    Archive created."

# --- Export ---
echo "==> Exporting..."
APP_PATH="$EXPORT_DIR/$APP_NAME.app"
if ! xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$EXPORT_OPTIONS" \
    2>&1 | tee "$BUILD_DIR/export.log" | tail -5 || [ ! -d "$APP_PATH" ]; then
    echo "--- Last 30 lines of export.log ---"
    tail -30 "$BUILD_DIR/export.log"
    error "Export failed. See $BUILD_DIR/export.log for details."
fi
echo "    Export complete."

# --- Read version from exported app ---
EXPORTED_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
echo "    Exported app version: $EXPORTED_VERSION"
if [ "$EXPORTED_VERSION" != "$VERSION" ]; then
    error "Exported app is version $EXPORTED_VERSION, expected $VERSION. The bump did not reach the build settings."
fi

# --- Create DMG ---
echo "==> Creating DMG..."
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"
DMG_STAGING="$BUILD_DIR/dmg-staging"
mkdir -p "$DMG_STAGING"
cp -a "$APP_PATH" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH" || error "Failed to create DMG."
rm -rf "$DMG_STAGING"
echo "    DMG created: $DMG_PATH"

# --- Verify codesign ---
echo "==> Verifying codesign..."
codesign --verify --deep --strict "$APP_PATH" || error "Codesign verification failed."
echo "    Codesign verified."

# --- Notarize ---
echo "==> Submitting for notarization..."
xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait || error "Notarization failed."
echo "    Notarization complete."

# --- Staple ---
echo "==> Stapling..."
xcrun stapler staple "$DMG_PATH" || error "Stapling failed."
echo "    Stapled."

# --- Sign for Sparkle ---
# generate_appcast signs the entry itself further down; this call is here to
# fail on missing EdDSA keys before a GitHub release has been published.
echo "==> Checking Sparkle signing key..."
"$SPARKLE_TOOLS_DIR/bin/sign_update" "$DMG_PATH" || error "Sparkle signing failed."

# --- Release title ---
if [ -n "$TITLE_ARG" ]; then
    RELEASE_TITLE="$TITLE_ARG"
elif [ "$INTERACTIVE" = true ]; then
    read -rp "==> Enter release title [$APP_NAME $VERSION]: " RELEASE_TITLE
fi
RELEASE_TITLE="${RELEASE_TITLE:-$APP_NAME $VERSION}"

# --- Create GitHub release ---
echo "==> Creating GitHub release..."
cd "$PROJECT_DIR"
git tag "$TAG" || error "Failed to create tag $TAG."
git push origin "$TAG" || error "Failed to push tag $TAG."
gh release create "$TAG" "$DMG_PATH" \
    --repo "$GITHUB_REPO" \
    --title "$RELEASE_TITLE" \
    --generate-notes || error "Failed to create GitHub release."
echo "    Release created: $TAG"

# --- Generate appcast ---
echo "==> Generating appcast..."
APPCAST_DIR="$BUILD_DIR/appcast-assets"
mkdir -p "$APPCAST_DIR"

if [ -f "$PROJECT_DIR/appcast.xml" ]; then
    cp "$PROJECT_DIR/appcast.xml" "$APPCAST_DIR/"
fi

cp "$DMG_PATH" "$APPCAST_DIR/"

"$SPARKLE_TOOLS_DIR/bin/generate_appcast" \
    --download-url-prefix "https://github.com/$GITHUB_REPO/releases/download/$TAG/" \
    -o "$APPCAST_DIR/appcast.xml" \
    "$APPCAST_DIR" || error "Failed to generate appcast."

cp "$APPCAST_DIR/appcast.xml" "$PROJECT_DIR/appcast.xml"
cd "$PROJECT_DIR"
git add appcast.xml
git commit -m "Update appcast for $VERSION"
git push origin HEAD
echo "    Appcast updated and pushed."

echo ""
echo "==> Done! Released $APP_NAME $VERSION"
