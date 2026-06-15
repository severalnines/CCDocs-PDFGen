#!/usr/bin/env bash

## Rename the "administration-guide" section to "admin-guide" and fix all references.

BASE_PARENT_DIR="$1"
CONFIG_FILE="$2"

if [ -z "$BASE_PARENT_DIR" ]; then
    echo "ERROR: BASE_PARENT_DIR argument is required." >&2
    exit 1
fi

if [ ! -d "$BASE_PARENT_DIR" ]; then
    echo "ERROR: Directory '$BASE_PARENT_DIR' does not exist." >&2
    exit 1
fi

if [ -z "$CONFIG_FILE" ]; then
    echo "ERROR: CONFIG_FILE argument is required." >&2
    exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: File '$CONFIG_FILE' does not exist." >&2
    exit 1
fi

. "$(dirname "$0")/helper_func.sh"

CC_SPHINX_SRC_DIR=$(read_ini "$CONFIG_FILE" "cc_gen_pdf_paths" "CC_SPHINX_SRC_DIR")
CC_LOG_FILE=$(read_ini "$CONFIG_FILE" "cc_gen_pdf_paths" "CC_LOG_FILE")

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$CC_LOG_FILE"
}

log "Starting 'administration-guide' -> 'admin-guide' rename under '$CC_SPHINX_SRC_DIR'..."

SRC="$CC_SPHINX_SRC_DIR"
OLD="administration-guide"
NEW="admin-guide"

# 1) Rename the section directory (with ALL its files) and its landing page.
#    Guarded so a re-run is a harmless no-op.
if [ -d "$SRC/$OLD" ] && [ ! -e "$SRC/$NEW" ]; then
    mv "$SRC/$OLD" "$SRC/$NEW"
    log "  Renamed directory: $OLD/ -> $NEW/"
elif [ -d "$SRC/$NEW" ]; then
    log "  Directory $NEW/ already exists; skipping directory rename."
fi

if [ -f "$SRC/$OLD.md" ] && [ ! -e "$SRC/$NEW.md" ]; then
    mv "$SRC/$OLD.md" "$SRC/$NEW.md"
    log "  Renamed landing page: $OLD.md -> $NEW.md"
fi

# 2) Fix every reference to the old name across the whole doc set (toctrees,
#    relative links, etc.). Idempotent: 'admin-guide' never contains the
#    string 'administration-guide'.
ref_fixed=0
while IFS= read -r f; do
    if grep -q "$OLD" "$f"; then
        sed -i "s|$OLD|$NEW|g" "$f"
        ref_fixed=$((ref_fixed + 1))
    fi
done < <(find "$SRC" -type f -name '*.md')
log "  Updated '$OLD' references in $ref_fixed file(s)."

# 3) In the section index, make toctree entries bare (strip the leading
#    'admin-guide/' path) and drop a self-referential 'index' entry, if any.
IDX="$SRC/$NEW/index.md"
if [ -f "$IDX" ]; then
    sed -i "s|$NEW/||g" "$IDX"
    sed -i '/^[[:space:]]*index[[:space:]]*$/d' "$IDX"
    log "  Normalized toctree entries in $NEW/index.md"
fi

log "admin-guide naming convention fix complete."
exit 0
