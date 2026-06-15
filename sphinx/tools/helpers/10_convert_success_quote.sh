#!/usr/bin/env bash

## Convert MkDocs `!!! success` / `??? success` admonitions.
##  * EMPTY-title (e.g. `!!! success ""`) blocks are used as styled "next steps"
##    link lists. A RUN of consecutive ones is MERGED into a single native
##    `:::{seealso}` block (proper styling in HTML & PDF, no extra extension).
##  * A success block WITH a real title becomes `:::{admonition} <title>` with
##    `:class: tip` (a genuine positive callout).

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

log "Starting !!!/??? success admonition conversion under '$CC_SPHINX_SRC_DIR'..."

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

# Empty/no-title success:  `!!! success`  or  `!!! success ""`  (+ `???`, `+`).
# group(1) = leading indentation.
EMPTY_RE = re.compile(
    r'^(\s*)(?:!!!|\?\?\?)\+?[ \t]+success(?:[ \t]+"")?[ \t]*\r?$',
    re.IGNORECASE | re.MULTILINE,
)

# Success WITH a (non-empty) title:  `!!! success "All done!"`.
# group(1) = indentation, group(2) = title text (greedy, so embedded quotes survive).
TITLED_RE = re.compile(
    r'^(\s*)(?:!!!|\?\?\?)\+?[ \t]+success[ \t]+"(.+)"[ \t]*\r?$',
    re.IGNORECASE | re.MULTILINE,
)


def convert_block_content(block_lines, base):
    """Strip the `base`-space MkDocs indent from each content line (keeping any
    deeper indent), normalize bullet markers (`*` -> `-`), and drop blank lines
    at the start/end."""
    out = []
    for line in block_lines:
        if line.strip() == '':
            out.append('')
            continue
        if len(line) >= base and line[:base].isspace():
            stripped = line[base:]
        else:
            stripped = line.lstrip(' ')

        m = re.match(r'^(\s*)\*\s+(.*)$', stripped)
        if m:
            stripped = f'{m.group(1)}- {m.group(2)}'

        out.append(stripped.rstrip())

    while out and out[0] == '':
        out.pop(0)
    while out and out[-1] == '':
        out.pop()
    return out


def collect_block(lines, start, content_base):
    """Collect the indented/blank lines of the block opened at `start`.
    Returns (block_lines, next_index)."""
    block = []
    j = start + 1
    while j < len(lines) and (lines[j].startswith(' ' * content_base)
                              or lines[j].strip() == ''):
        block.append(lines[j])
        j += 1
    return block, j


def process_file(md_file):
    content = md_file.read_text()
    lines = content.split('\n')
    result = []
    i = 0
    changed = False

    while i < len(lines):
        line = lines[i]
        em = EMPTY_RE.match(line)
        tm = None if em else TITLED_RE.match(line)

        if em:
            header_indent = em.group(1)
            content_base = len(header_indent) + 4

            # Merge a RUN of consecutive empty-title success blocks (same indent)
            # into a single {seealso} with their bodies concatenated.
            merged = []
            while i < len(lines):
                m2 = EMPTY_RE.match(lines[i])
                if not (m2 and m2.group(1) == header_indent):
                    break
                block, i = collect_block(lines, i, content_base)
                merged.extend(convert_block_content(block, content_base))

            emit = [':::{seealso}', ''] + merged + [':::']
            for e in emit:
                result.append(f'{header_indent}{e}' if e else '')
            changed = True

        elif tm:
            header_indent = tm.group(1)
            title = tm.group(2).strip()
            content_base = len(header_indent) + 4

            block, i = collect_block(lines, i, content_base)
            emit = [f':::{{admonition}} {title}', ':class: tip', '']
            emit += convert_block_content(block, content_base)
            emit += [':::']
            for e in emit:
                result.append(f'{header_indent}{e}' if e else '')
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
    if not (EMPTY_RE.search(text) or TITLED_RE.search(text)):
        continue
    helper.log(f'  Processing: {md_file}', log_file)
    if process_file(md_file):
        helper.log(f'  Converted: {md_file}', log_file)
        converted_files += 1

helper.log(f'Success admonition conversion complete. Converted {converted_files} file(s).', log_file)
PYEOF

exit $?
