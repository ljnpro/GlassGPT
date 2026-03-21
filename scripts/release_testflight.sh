#!/usr/bin/env bash
set -euo pipefail

export PYTHONDONTWRITEBYTECODE="${PYTHONDONTWRITEBYTECODE:-1}"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.local/publish.env"
VERSIONS_XCCONFIG_PATH="${VERSIONS_XCCONFIG_PATH:-$ROOT_DIR/ios/GlassGPT/Config/Versions.xcconfig}"
PROJECT_PATH="${XCODE_PROJECT_PATH:-$ROOT_DIR/ios/GlassGPT.xcodeproj}"
SCHEME="${XCODE_SCHEME:-GlassGPT}"
BUILD_DIR="${LOCAL_BUILD_DIR:-$ROOT_DIR/.local/build}"
EXPORT_OPTIONS="${EXPORT_OPTIONS_PLIST:-$ROOT_DIR/.local/export-options-app-store.plist}"
REMOTE="${GITHUB_REMOTE:-origin}"
REMOTE_REPO="${GITHUB_REPO_URL:-}"

function usage() {
  cat <<'EOF'
Usage:
  ./scripts/release_testflight.sh <marketing_version> <build_number> [--branch <name>] [--commit-message "<message>"] [--preserve-main-as <name>] [--force-main-with-lease] [--skip-main-promotion] [--preflight-only]

Examples:
  ./scripts/release_testflight.sh 4.10.0 20185 --branch codex/stable-4.10
EOF
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

VERSION="$1"
BUILD_NUMBER="$2"
shift 2

TARGET_BRANCH=""
COMMIT_MESSAGE="Release $VERSION ($BUILD_NUMBER)"
PRESERVE_MAIN_AS=""
FORCE_MAIN_WITH_LEASE=0
PROMOTE_MAIN=1
PREFLIGHT_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      TARGET_BRANCH="${2:-}"
      shift 2
      ;;
    --commit-message)
      COMMIT_MESSAGE="${2:-}"
      shift 2
      ;;
    --preserve-main-as)
      PRESERVE_MAIN_AS="${2:-}"
      shift 2
      ;;
    --force-main-with-lease)
      FORCE_MAIN_WITH_LEASE=1
      shift
      ;;
    --skip-main-promotion)
      PROMOTE_MAIN=0
      shift
      ;;
    --preflight-only)
      PREFLIGHT_ONLY=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

function remote_branch_sha() {
  local branch_name="$1"
  git -C "$ROOT_DIR" ls-remote --heads "$REMOTE" "$branch_name" | awk '{print $1}' | tail -1
}

function ensure_commit_present() {
  local commit_sha="$1"

  if [[ -z "$commit_sha" ]]; then
    return 0
  fi

  if git -C "$ROOT_DIR" cat-file -e "${commit_sha}^{commit}" 2>/dev/null; then
    return 0
  fi

  git -C "$ROOT_DIR" fetch "$REMOTE" main >/dev/null 2>&1
  git -C "$ROOT_DIR" cat-file -e "${commit_sha}^{commit}" 2>/dev/null
}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing env file: $ENV_FILE" >&2
  exit 1
fi

source "$ENV_FILE"

if [[ -z "$TARGET_BRANCH" ]]; then
  TARGET_BRANCH="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
fi

case "$TARGET_BRANCH" in
  main|codex/stable-4.1|codex/stable-4.2|codex/stable-4.3|codex/stable-4.4|codex/stable-4.5|codex/stable-4.6|codex/stable-4.7|codex/stable-4.8|codex/stable-4.9|codex/stable-4.10)
    ;;
  *)
    echo "Release target branch must be a stable branch or main. Got: $TARGET_BRANCH" >&2
    exit 1
    ;;
esac

CURRENT_BRANCH="$(git -C "$ROOT_DIR" rev-parse --abbrev-ref HEAD)"
if [[ "$CURRENT_BRANCH" != "HEAD" && "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
  echo "Run the release wrapper from the target branch. Current: $CURRENT_BRANCH, target: $TARGET_BRANCH" >&2
  exit 1
fi

if [[ -n "$PRESERVE_MAIN_AS" ]]; then
  if ! git check-ref-format --branch "$PRESERVE_MAIN_AS" >/dev/null 2>&1; then
    echo "Invalid preserve-main branch: $PRESERVE_MAIN_AS" >&2
    exit 1
  fi
  if [[ "$PRESERVE_MAIN_AS" == "main" || "$PRESERVE_MAIN_AS" == "$TARGET_BRANCH" ]]; then
    echo "preserve-main branch must differ from main and the target branch." >&2
    exit 1
  fi
fi

if (( FORCE_MAIN_WITH_LEASE == 1 )) && (( PROMOTE_MAIN == 0 )); then
  echo "--force-main-with-lease cannot be combined with --skip-main-promotion." >&2
  exit 1
fi

if [[ ! -f "$VERSIONS_XCCONFIG_PATH" ]]; then
  echo "Missing version config: $VERSIONS_XCCONFIG_PATH" >&2
  exit 1
fi

if [[ ! -f "$EXPORT_OPTIONS" ]]; then
  echo "Missing export options plist: $EXPORT_OPTIONS" >&2
  exit 1
fi

if [[ ! -d "$BUILD_DIR" ]]; then
  mkdir -p "$BUILD_DIR"
fi

REMOTE_MAIN_SHA=""
if [[ "${PUSH_RELEASE:-1}" == "1" && "$PROMOTE_MAIN" == "1" ]]; then
  REMOTE_MAIN_SHA="$(remote_branch_sha main)"
  if [[ -n "$REMOTE_MAIN_SHA" ]]; then
    if ! ensure_commit_present "$REMOTE_MAIN_SHA"; then
      echo "Could not fetch the current remote main commit ($REMOTE_MAIN_SHA)." >&2
      exit 1
    fi

    if ! git -C "$ROOT_DIR" merge-base --is-ancestor "$REMOTE_MAIN_SHA" HEAD; then
      if (( FORCE_MAIN_WITH_LEASE == 0 )); then
        echo "Remote main does not fast-forward to HEAD. Use --force-main-with-lease and --preserve-main-as before promoting main." >&2
        exit 1
      fi

      if [[ -z "$PRESERVE_MAIN_AS" ]]; then
        echo "Non-fast-forward main promotion requires --preserve-main-as to retain the current remote main tip." >&2
        exit 1
      fi
    fi
  fi
fi

if (( PREFLIGHT_ONLY == 1 )); then
  echo "Release preflight checks passed."
  exit 0
fi

echo "==> Running release-readiness gate"
export RELEASE_EXPECT_MARKETING_VERSION="$VERSION"
export RELEASE_EXPECT_BUILD_NUMBER="$BUILD_NUMBER"
export RELEASE_REQUIRE_CLEAN_WORKTREE=1
./scripts/ci.sh release-readiness

echo "==> Running full CI gates"
./scripts/ci.sh

python3 - "$VERSIONS_XCCONFIG_PATH" "$VERSION" "$BUILD_NUMBER" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
version = sys.argv[2]
build = sys.argv[3]
text = path.read_text()
text, build_count = re.subn(
    r"(?m)^(\s*CURRENT_PROJECT_VERSION\s*=\s*).+$",
    rf"\g<1>{build}",
    text
)
text, version_count = re.subn(
    r"(?m)^(\s*MARKETING_VERSION\s*=\s*).+$",
    rf"\g<1>{version}",
    text
)
if build_count != 1 or version_count != 1:
    sys.exit("Failed to update version values in Versions.xcconfig")
path.write_text(text)
PY

if ! rg -q "^MARKETING_VERSION = ${VERSION}$" "$VERSIONS_XCCONFIG_PATH"; then
  echo "Failed to set MARKETING_VERSION to $VERSION." >&2
  exit 1
fi

if ! rg -q "^CURRENT_PROJECT_VERSION = ${BUILD_NUMBER}$" "$VERSIONS_XCCONFIG_PATH"; then
  echo "Failed to set CURRENT_PROJECT_VERSION to $BUILD_NUMBER." >&2
  exit 1
fi

ARCHIVE_PATH="$BUILD_DIR/GlassGPT-$VERSION.xcarchive"
EXPORT_PATH="$BUILD_DIR/export-$VERSION"
ARCHIVE_LOG="$BUILD_DIR/archive-$VERSION.log"
EXPORT_LOG="$BUILD_DIR/export-$VERSION.log"
UPLOAD_LOG="$BUILD_DIR/upload-$VERSION.log"
IPA_PATH="$EXPORT_PATH/GlassGPT.ipa"
RELEASE_TAG="v$VERSION"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

KEY_PATH="${ASC_API_KEY_PATH:-}"
if [[ -z "$KEY_PATH" || ! -f "$KEY_PATH" ]]; then
  KEY_PATH="${ASC_API_KEY_FALLBACK_PATH:-}"
fi

if [[ -z "$KEY_PATH" || ! -f "$KEY_PATH" ]]; then
  echo "Could not find App Store Connect API key (.p8)." >&2
  exit 1
fi

echo "==> Archiving"
xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$ARCHIVE_PATH" \
  clean archive \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_API_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" | tee "$ARCHIVE_LOG"

echo "==> Exporting"
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_API_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID" | tee "$EXPORT_LOG"

if [[ ! -f "$IPA_PATH" ]]; then
  echo "Missing IPA at $IPA_PATH" >&2
  exit 1
fi

echo "==> Verifying IPA metadata"
python3 - "$IPA_PATH" "$VERSION" "$BUILD_NUMBER" <<'PY'
import plistlib
import sys
import zipfile

ipa_path = sys.argv[1]
expected_version = sys.argv[2]
expected_build = sys.argv[3]
with zipfile.ZipFile(ipa_path) as zf:
    info = plistlib.loads(zf.read("Payload/GlassGPT.app/Info.plist"))
actual_version = info["CFBundleShortVersionString"]
actual_build = info["CFBundleVersion"]
if actual_version != expected_version or actual_build != expected_build:
    raise SystemExit(f"IPA metadata mismatch. expected {expected_version} ({expected_build}), found {actual_version} ({actual_build})")
print(f"Verified IPA version: {actual_version} ({actual_build})")
PY

echo "==> Uploading to TestFlight"
UPLOAD_OUTPUT="$(
  xcrun altool \
    --upload-app \
    --type ios \
    --file "$IPA_PATH" \
    --apiKey "$ASC_API_KEY_ID" \
    --apiIssuer "$ASC_ISSUER_ID" \
    2>&1 | tee "$UPLOAD_LOG"
)"
DELIVERY_UUID="$(printf '%s\n' "$UPLOAD_OUTPUT" | awk -F'Delivery UUID: ' '/Delivery UUID:/ {print $2}' | tail -1)"

if [[ -z "$DELIVERY_UUID" && -f "$UPLOAD_LOG" ]]; then
  DELIVERY_UUID="$(awk -F'Delivery UUID: ' '/Delivery UUID:/ {print $2}' "$UPLOAD_LOG" | tail -1)"
fi

if [[ -z "$DELIVERY_UUID" ]]; then
  DELIVERY_UUID="unknown"
fi

if [[ -n "$(git -C "$ROOT_DIR" status --short "$VERSIONS_XCCONFIG_PATH")" ]]; then
  echo "==> Committing release metadata"
  git -C "$ROOT_DIR" add "$VERSIONS_XCCONFIG_PATH"
  git -C "$ROOT_DIR" commit -m "$COMMIT_MESSAGE"
fi

if ! git -C "$ROOT_DIR" rev-parse --verify "$RELEASE_TAG" >/dev/null 2>&1; then
  echo "==> Tagging"
  git -C "$ROOT_DIR" tag -a "$RELEASE_TAG" -m "Release $VERSION ($BUILD_NUMBER)"
else
  current_tag_commit="$(git -C "$ROOT_DIR" rev-parse "$RELEASE_TAG" 2>/dev/null || true)"
  head_commit="$(git -C "$ROOT_DIR" rev-parse HEAD 2>/dev/null)"
  if [[ "$current_tag_commit" != "$head_commit" ]]; then
    echo "Tag $RELEASE_TAG already exists and does not point to HEAD. Remove or override before release." >&2
    exit 1
  fi
fi

if [[ "${PUSH_RELEASE:-1}" == "1" ]]; then
  verify_refs=("$TARGET_BRANCH" main "refs/tags/$RELEASE_TAG")
  if [[ -n "$PRESERVE_MAIN_AS" ]]; then
    verify_refs+=("$PRESERVE_MAIN_AS")
  fi

  echo "==> Pushing branch and release tag"
  git -C "$ROOT_DIR" push "$REMOTE" "HEAD:$TARGET_BRANCH"
  git -C "$ROOT_DIR" push "$REMOTE" "$RELEASE_TAG"

  if [[ "$PROMOTE_MAIN" == "1" ]]; then
    if [[ -n "$PRESERVE_MAIN_AS" && -n "$REMOTE_MAIN_SHA" ]]; then
      echo "==> Preserving current main on $PRESERVE_MAIN_AS"
      git -C "$ROOT_DIR" push "$REMOTE" "${REMOTE_MAIN_SHA}:refs/heads/$PRESERVE_MAIN_AS"
    fi

    echo "==> Promoting main"
    if (( FORCE_MAIN_WITH_LEASE == 1 )) && [[ -n "$REMOTE_MAIN_SHA" ]]; then
      git -C "$ROOT_DIR" push --force-with-lease="main:$REMOTE_MAIN_SHA" "$REMOTE" "HEAD:main"
    else
      git -C "$ROOT_DIR" push "$REMOTE" "HEAD:main"
    fi
  else
    echo "==> Skipping main promotion"
  fi

  echo "==> Verifying remote refs"
  git -C "$ROOT_DIR" ls-remote --heads --tags "$REMOTE" "${verify_refs[@]}"
fi

echo ""
echo "Release complete."
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Branch: $TARGET_BRANCH"
echo "Archive: $ARCHIVE_PATH"
echo "IPA: $IPA_PATH"
echo "Delivery UUID: $DELIVERY_UUID"
