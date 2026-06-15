#!/usr/bin/env bash

## Convert MkDocs `!!! tip` / `??? tip` admonitions (case-insensitive, optional
## `+`, with or without a title) into MyST. `tip` is a NATIVE Sphinx admonition,
## so a title-less block maps to the built-in `:::{tip}` (proper green styling in
## HTML and PDF). `???` (collapsible) adds `:class: dropdown`. A custom title can
## only be carried by a generic `:::{admonition} <title>` + `:class: tip`.

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

log "Starting !!!/??? tip admonition conversion under '$CC_SPHINX_SRC_DIR'..."

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

# Match `!!! tip`, `??? tip` (+ optional `+`), case-insensitively, with an
# OPTIONAL greedy-captured title.
#   group(1) = leading indentation
#   group(2) = marker  (!!! or ???)   -> ??? means collapsible (dropdown)
#   group(3) = title text (None / "" -> no title; use native {tip})
HEADER_RE = re.compile(
    r'^(\s*)(!!!|\?\?\?)\+?[ \t]+tip(?:[ \t]+"(.*)")?[ \t]*\r?$',
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


def process_file(md_file):
    content = md_file.read_text()
    lines = content.split('\n')
    result = []
    i = 0
    changed = False

    while i < len(lines):
        line = lines[i]
        m = HEADER_RE.match(line)

        if not m:
            result.append(line)
            i += 1
            continue

        header_indent = m.group(1)
        is_dropdown = m.group(2) == '???'
        title = (m.group(3) or '').strip()
        content_base = len(header_indent) + 4

        # Collect all indented/blank lines belonging to this block
        block_lines = []
        j = i + 1
        while j < len(lines) and (lines[j].startswith(' ' * content_base)
                                  or lines[j].strip() == ''):
            block_lines.append(lines[j])
            j += 1

        # A custom title needs a generic admonition (typed `{tip}` takes no
        # title argument); otherwise use the native `{tip}` directive.
        if title:
            cls = 'tip dropdown' if is_dropdown else 'tip'
            emit = [f':::{{admonition}} {title}', f':class: {cls}', '']
        else:
            emit = [':::{tip}']
            if is_dropdown:
                emit.append(':class: dropdown')
            emit.append('')

        emit += convert_block_content(block_lines, content_base)
        emit += [':::']

        # Re-apply the block's own indentation
        for e in emit:
            result.append(f'{header_indent}{e}' if e else '')

        i = j
        changed = True

    if changed:
        md_file.write_text('\n'.join(result))

    return changed


converted_files = 0
for md_file in sorted(src_dir.rglob('*.md')):
    text = md_file.read_text()
    if not HEADER_RE.search(text):
        continue
    helper.log(f'  Processing: {md_file}', log_file)
    if process_file(md_file):
        helper.log(f'  Converted: {md_file}', log_file)
        converted_files += 1

helper.log(f'Tip admonition conversion complete. Converted {converted_files} file(s).', log_file)
PYEOF

exit $?
