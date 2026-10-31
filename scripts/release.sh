#!/bin/bash
# Builds and drafts a ChargeGuard release from this Mac, the same way .github/workflows/release.yml does on
# GitHub's machines. Use it whenever GitHub Actions isn't available.
#
#   scripts/release.sh             test, build, tag vX.Y.Z, push the tag and draft the GitHub release
#   scripts/release.sh --dry-run   test and build only; print the git and gh commands instead of running them
#   scripts/release.sh --yes       don't ask before pushing the tag and creating the release
#
# The version is MARKETING_VERSION in project.yml. The build goes to build/release/, never to
# build/ChargeGuard.app, so a development install of the helper from build/ keeps working. Releases are
# ad-hoc signed (IDENTITY=-), so no certificate or personal detail ends up in the app. The release is a
# draft: test the DMG, then publish with `gh release edit vX.Y.Z --draft=false` or on GitHub.
set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --yes | -y) ASSUME_YES=1 ;;
        -h | --help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "Unknown option: $arg (see --help)" >&2; exit 2 ;;
    esac
done

say() { printf '\n==> %s\n' "$*"; }
fail() { printf 'Error: %s\n' "$*" >&2; exit 1; }
# Outward actions (tag push, release) only print in a dry run.
run() {
    if (( DRY_RUN )); then
        printf '    (dry run, not run) %s\n' "$*"
    else
        "$@"
    fi
}

[[ "$(uname -s)" == "Darwin" ]] || fail "Releases are built on macOS."
command -v gh >/dev/null || fail "GitHub CLI is missing: brew install gh"
command -v xcodegen >/dev/null || fail "XcodeGen is missing: brew install xcodegen"
gh auth status >/dev/null 2>&1 || fail "GitHub CLI isn't signed in: gh auth login"

VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\(.*\)" *$/\1/p' project.yml | head -n 1)"
[[ -n "$VERSION" ]] || fail "No MARKETING_VERSION in project.yml."
TAG="v$VERSION"
BUILD_DIR="build/release"
DMG="$BUILD_DIR/ChargeGuard.dmg"
COMMIT="$(git rev-parse HEAD)"

# A release has to match a commit that is on GitHub.
if [[ -n "$(git status --porcelain)" ]]; then
    (( DRY_RUN )) || fail "Commit or stash your changes first: a release must match a commit."
    echo "Warning: uncommitted changes (allowed in a dry run only)."
fi
git fetch --quiet --tags origin
if [[ -z "$(git branch -r --contains HEAD)" ]]; then
    (( DRY_RUN )) || fail "Push your commits first: $(git rev-parse --short HEAD) isn't on GitHub yet."
    echo "Warning: HEAD isn't on GitHub yet (allowed in a dry run only)."
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    [[ "$(git rev-list -n 1 "$TAG")" == "$COMMIT" ]] \
        || fail "Tag $TAG already points at another commit. Bump MARKETING_VERSION in project.yml."
fi
if gh release view "$TAG" >/dev/null 2>&1; then
    fail "GitHub already has a release $TAG. Bump MARKETING_VERSION in project.yml."
fi

say "ChargeGuard $VERSION ($TAG) from commit $(git rev-parse --short HEAD)$( (( DRY_RUN )) && echo ', dry run')"

say "Unit tests"
make test

say "Building the ad-hoc signed app and DMG in $BUILD_DIR"
rm -rf "$BUILD_DIR"
make dmg BUILD="$BUILD_DIR" IDENTITY=- TEAM=

say "Checking the build"
codesign --verify --deep --strict "$BUILD_DIR/ChargeGuard.app"
signature="$(codesign -dv "$BUILD_DIR/ChargeGuard.app" 2>&1)"
grep -q '^Signature=adhoc' <<<"$signature" || fail "The app isn't ad-hoc signed; refusing to release it."
grep -q '^TeamIdentifier=not set' <<<"$signature" || fail "The app carries a Team ID; refusing to release it."
built="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILD_DIR/ChargeGuard.app/Contents/Info.plist")"
[[ "$built" == "$VERSION" ]] || fail "The app says version $built but project.yml says $VERSION."
(cd "$BUILD_DIR" && shasum -a 256 ChargeGuard.dmg > ChargeGuard.dmg.sha256)
echo "Ad-hoc signed, no Team ID, version $built."
cat "$BUILD_DIR/ChargeGuard.dmg.sha256"

if (( ! DRY_RUN && ! ASSUME_YES )); then
    answer=""
    read -r -p "Push tag $TAG and create a draft release on GitHub? [y/N] " answer || true
    if [[ ! "$answer" =~ ^[Yy]$ ]]; then
        echo "Stopped before anything left this Mac. The build is in $BUILD_DIR."
        exit 0
    fi
fi

say "Tagging $TAG and pushing the tag"
if ! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    run git tag -a "$TAG" -m "ChargeGuard $VERSION"
fi
run git push origin "refs/tags/$TAG"

say "Drafting the GitHub release"
run gh release create "$TAG" "$DMG" "$DMG.sha256" \
    --draft --verify-tag \
    --title "ChargeGuard $VERSION" \
    --notes-file .github/release-notes.md \
    --generate-notes

if (( DRY_RUN )); then
    say "Dry run finished. The DMG is in $BUILD_DIR; nothing was tagged, pushed or released."
else
    say "Draft release $TAG created. Download the DMG from it, test it, then publish:"
    echo "    gh release edit $TAG --draft=false"
fi
