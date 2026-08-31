#!/usr/bin/env bash
# Package the addon into build/addons/addon_lib/tree_sitter_gd/
#
# build/ mirrors a Godot project root, so the zip CI makes from it extracts
# straight over a project and merges into addons/addon_lib/tree_sitter_gd/.
#
# Everything inside the tree_sitter_gd/ source folder is copied recursively, so
# adding new .gd files (or any addon assets) there needs no change to this script.
# LICENSE and README live at the repo root (for GitHub) and are copied in too.
# Compiled libraries are pulled from bin/.
#
# Version comes from `git describe` (exact tag = clean release, -N-g<hash>
# suffix = built past the tag); version.cfg is only a fallback and the PACKAGED
# version.cfg gets stamped with the resolved version. A pre-existing build/ is
# removed first.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ADDON_SRC="tree_sitter_gd"   # source folder that maps 1:1 to addons/addon_lib/tree_sitter_gd/

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
if [[ -z "$VERSION" ]]; then
    # fallback (packaging from a tarball etc.): read from version.cfg
    VERSION="$(sed -n 's/^[[:space:]]*version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p' "$ADDON_SRC/version.cfg" | head -n1)"
fi
if [[ -z "$VERSION" ]]; then
    echo "package.sh: could not determine version (git describe failed, version.cfg fallback empty)" >&2
    exit 1
fi

DEST="build/addons/addon_lib/tree_sitter_gd"

# --- clean & recreate ---
rm -rf build
mkdir -p "$DEST/bin"

# --- addon source (recursive: everything in the folder ships) ---
cp -R "$ADDON_SRC/." "$DEST/"
find "$DEST" -name '.DS_Store' -delete

# --- stamp the version into the packaged version.cfg (source stays untouched) ---
sed -i.bak 's/^[[:space:]]*version[[:space:]]*=.*/version="'"$VERSION"'"/' "$DEST/version.cfg"
rm -f "$DEST/version.cfg.bak"

# --- repo-root docs ---
for f in LICENSE README.md; do
    if [[ -f "$f" ]]; then
        cp "$f" "$DEST/"
    else
        echo "package.sh: warning — '$f' not found, skipping" >&2
    fi
done

# --- compiled libraries (skip cruft) ---
if compgen -G "bin/*" > /dev/null; then
    # Godot only loads the runtime libraries (.dylib/.so/.dll). MSVC also emits
    # import-lib (.lib) and exports (.exp) files alongside the Windows .dll —
    # those are link-time only and don't belong in the shipped addon.
    find bin -type f \
        ! -name '.DS_Store' \
        ! -name '*.os' \
        ! -name '*.exp' \
        ! -name '*.lib' \
        -exec cp {} "$DEST/bin/" \;
else
    echo "package.sh: warning — bin/ is empty; did you build first?" >&2
fi

echo "Packaged tree-sitter-gd v${VERSION} -> ${DEST}"
