#!/usr/bin/env bash
# Stamp the shared gdext files into this repo.
#
#   ./render-gdext.sh           rewrite each target, report updated/unchanged
#   ./render-gdext.sh --check   verify they match; exit 1 on drift
#
# --check is what you want in a pre-tag gate: it fails if a shared file was edited
# directly instead of editing the shared template.
#
# The rendering itself lives in the pinned sh-templates submodule
# (gdext/render-target.sh). Everything here is repo-local policy: which targets
# to render.
#
# Bootstrap for a new repo: commit a package.sh containing only its config block
# (ADDON_SRC/ADDON_DEST/VERSION_FILE) and the "# ---- end config ----" marker, then
# run this once to receive the body.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT" || exit 1

RENDERER="$ROOT/sh-templates/gdext/render-target.sh"

TARGETS=(
  "package.sh"
  ".github/workflows/build.yml"
)

case "${1:-}" in
  --check|"") ;;
  -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

if [[ ! -x "$RENDERER" ]]; then
  echo "render-gdext.sh: required submodule renderer not found: $RENDERER" >&2
  echo "Initialize it with: git submodule update --init sh-templates" >&2
  exit 1
fi

# Rendering is in place: the target supplies its own config block and receives the
# result. Accumulate failure so --check can gate a preflight -- a single drifted or
# broken target must fail the whole run.
fail=0
for t in "${TARGETS[@]}"; do
  "$RENDERER" "$@" "$t" || fail=1
done

exit "$fail"
