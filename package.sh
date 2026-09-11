#!/usr/bin/env bash
# Per-repo config for package.sh. The body below the marker is stamped from
# package.template.sh in the sh-templates submodule -- edit the template, not
# the body.
ADDON_SRC="tree_sitter_gd"
ADDON_DEST="addons/addon_lib"
VERSION_FILE="version.cfg"
RELEASE_NAME="tree-sitter-gd"
# ---- end config ----
# Stage the addon in build/$ADDON_DEST/$ADDON_SRC/, then create its release zip
# in dist/.
#
# build/ mirrors a Godot project root, so the zip extracts straight over a project
# and merges into $ADDON_DEST/$ADDON_SRC/. dist/ contains the finished distributable.
#
# Everything inside the $ADDON_SRC source folder is copied recursively, so
# adding new files (or any addon assets) there needs no change to this script.
# LICENSE and README live at the repo root (for GitHub) and are copied in too.
# Compiled libraries are pulled from bin/, preserving subdirectory structure so
# macOS .framework bundles survive intact.
#
# Version comes from `git describe` (exact tag = clean release, -N-g<hash>
# suffix = built past the tag); the version file is only a fallback and the
# PACKAGED copy gets stamped with the resolved version, the source stays
# untouched. Pre-existing build/ and dist/ directories are removed first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

if [[ -z "${RELEASE_NAME:-}" ]]; then
    echo "package.sh: RELEASE_NAME must be set in the config block" >&2
    exit 1
fi
if ! command -v zip >/dev/null 2>&1; then
    echo "package.sh: 'zip' not found; install it to create the release archive" >&2
    exit 1
fi
if [[ ! -d "$ADDON_SRC" ]]; then
    echo "package.sh: addon source folder '$ADDON_SRC/' not found" >&2
    exit 1
fi

# --- version: git describe (exact tag = clean release, suffix = mistagged) ---
VERSION=""
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    VERSION="$(git describe --tags --always 2>/dev/null || true)"
    VERSION="${VERSION#v}"   # tags are v-prefixed, addon versions are not
fi
if [[ -z "$VERSION" && -n "$VERSION_FILE" && -f "$ADDON_SRC/$VERSION_FILE" ]]; then
    # fallback (packaging from a tarball etc.): read from the version file
    VERSION="$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ADDON_SRC/$VERSION_FILE" | head -n1)"
fi
if [[ -z "$VERSION" ]]; then
    echo "package.sh: could not determine version (git describe failed, version file fallback empty)" >&2
    exit 1
fi

# Absolute: the bin copy below runs in a subshell cd'd into bin/, so a relative
# DEST would silently resolve against the wrong directory there.
DEST="$ROOT/build/$ADDON_DEST/$ADDON_SRC"

# --- clean & recreate ---
rm -rf build dist
mkdir -p "$DEST/bin"

# --- addon source (recursive: everything in the folder ships) ---
cp -R "$ADDON_SRC/." "$DEST/"
find "$DEST" -name '.DS_Store' -delete

# --- stamp the version into the packaged copy (source stays untouched) ---
if [[ -n "$VERSION_FILE" && -f "$DEST/$VERSION_FILE" ]]; then
    sed -i.bak 's/^[[:space:]]*version[[:space:]]*=.*/version="'"$VERSION"'"/' "$DEST/$VERSION_FILE"
    rm -f "$DEST/$VERSION_FILE.bak"
fi

# --- repo-root docs ---
for f in LICENSE README.md; do
    if [[ -f "$f" ]]; then
        cp "$f" "$DEST/"
    else
        echo "package.sh: warning: '$f' not found, skipping" >&2
    fi
done

# --- compiled libraries (skip cruft) ---
if compgen -G "bin/*" > /dev/null; then
    # Godot only loads the runtime libraries (.dylib/.so/.dll, or the binary inside a
    # .framework bundle). MSVC also emits import-lib (.lib) and exports (.exp) files
    # alongside the Windows .dll; those are link-time only and don't belong in the
    # shipped addon. Paths under bin/ are preserved so .framework bundles keep their
    # required layout; flat bins are unaffected (dirname is ".").
    (cd bin && find . -type f \
        ! -name '.DS_Store' \
        ! -name '*.os' \
        ! -name '*.exp' \
        ! -name '*.lib' \
        -exec sh -c 'mkdir -p "$0/$(dirname "$1")" && cp "$1" "$0/$1"' "$DEST/bin" {} \;)
else
    echo "package.sh: warning: bin/ is empty; did you build first?" >&2
fi

# --- canonical release archive ---
ARCHIVE="$ROOT/dist/${RELEASE_NAME}-v${VERSION}.zip"
mkdir -p "$ROOT/dist"
(cd "$ROOT/build" && zip -qr "$ARCHIVE" .)

echo "Packaged $(basename "$ROOT") v${VERSION} -> ${ARCHIVE}"
