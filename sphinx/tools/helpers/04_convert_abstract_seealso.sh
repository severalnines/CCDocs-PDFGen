#!/usr/bin/env bash

## Convert `!!! abstract "See also"` and `??? abstract "See also"` MkDocs admonitions
## into MyST `:::{admonition} See also` blocks with the `dropdown` class.

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

log "Starting abstract \"See also\" admonition conversion under '$CC_SPHINX_SRC_DIR'..."

export CC_SPHINX_SRC_DIR
export CC_LOG_FILE
export BIN_DIR="$(dirname "$0")/../bin"

python3 << 'PYEOF'
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, os.environ['BIN_DIR'])
import helper

src_dir  = Path(os.environ['CC_SPHINX_SRC_DIR'])
log_file = Path(os.environ['CC_LOG_FILE'])

# Matches `!!! abstract "See also"`, `!!!+ abstract "See also"`,
# `??? abstract "See also"`, `???+ abstract "See also"`, and variants
# with mixed case like `Abstract "See Also"`.
HEADER_RE = re.compile(r'^(?:!!!|\?\?\?)\+?\s+abstract\s+"See also"\s*$', re.IGNORECASE)


def convert_block_content(block_lines):
    """
    Strip the 4-space MkDocs indent from each content line and normalize
    bullet markers (`*` -> `-`). Drops blank lines at start/end.
    """
    out = []
    for line in block_lines:
        # Remove the 4-space base indent (keep any deeper indent intact)
        if line.startswith('    '):
            stripped = line[4:]
        elif line.strip() == '':
            stripped = ''
        else:
            stripped = line

        # Normalize `*` bullet to `-` bullet, preserving leading spaces
        m = re.match(r'^(\s*)\*\s+(.*)$', stripped)
        if m:
            stripped = f'{m.group(1)}- {m.group(2)}'

        out.append(stripped.rstrip())

    # trim leading/trailing blank lines
    while out and out[0] == '':
        out.pop(0)
    while out and out[-1] == '':
        out.pop()

    return out


def process_file(md_file):
    content = md_file.read_text()
    lines = content.split('\n')
    result = []
    i = 0
    changed = False

    while i < len(lines):
        line = lines[i]

        if HEADER_RE.match(line.rstrip()):
            # Collect all indented/blank lines belonging to this block
            block_lines = []
            j = i + 1
            while j < len(lines) and (lines[j].startswith('    ') or lines[j].strip() == ''):
                block_lines.append(lines[j])
                j += 1

            # Emit the MyST admonition
            result.append(':::{admonition} See also')
            result.append(':class: dropdown')
            result.extend(convert_block_content(block_lines))
            result.append(':::')
            i = j
            changed = True
        else:
            result.append(line)
            i += 1

    if changed:
        md_file.write_text('\n'.join(result))

    return changed


converted_files = 0
for md_file in sorted(src_dir.rglob('*.md')):
    text = md_file.read_text()
    if not re.search(r'(?:!!!|\?\?\?)\+?\s+abstract\s+"See also"', text, re.IGNORECASE):
        continue
    helper.log(f'  Processing: {md_file}', log_file)
    if process_file(md_file):
        helper.log(f'  Converted: {md_file}', log_file)
        converted_files += 1

helper.log(f'Abstract "See also" admonition conversion complete. Converted {converted_files} file(s).', log_file)
PYEOF

exit $?
