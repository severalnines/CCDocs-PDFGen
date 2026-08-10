#!/usr/bin/env bash

## Convert MkDocs content tabs (=== "Title") into MyST {tab-set}/{tab-item}:

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

log "Starting content tab (=== \"...\") conversion under '$CC_SPHINX_SRC_DIR'..."

export CC_SPHINX_SRC_DIR
export CC_LOG_FILE
export BIN_DIR="$(dirname "$0")/../bin"

python3 << 'PYEOF'
import os
import re
import sys, pprint, json
from pathlib import Path

sys.path.insert(0, os.environ['BIN_DIR'])
import helper

src_dir  = Path(os.environ['CC_SPHINX_SRC_DIR'])
log_file = Path(os.environ['CC_LOG_FILE'])


# A content-tab marker:  === "Title"   (captures the indentation and the title)
TAB_RE = re.compile(r'^(\s*)=== "([^"]+)"\s*\r?$', re.MULTILINE)

def dedent_block(lines, base):
    """Strip `base` leading spaces from each content line, preserving any deeper
    nesting (e.g. fenced-code continuation lines) and blank lines. Trims the
    surrounding blank lines.
    """
    out = []
    for line in lines:
        if not line.strip():
            out.append('')
        elif len(line) >= base and line[:base].isspace():
            out.append(line[base:].rstrip())
        else:
            out.append(line.lstrip(' ').rstrip())

    while out and not out[0]:
        out.pop(0)
    while out and not out[-1]:
        out.pop()
    return out


def convert_tab_group(items):
    """items: list of (title, dedented_content_lines).

    Returns the MyST representation:

        ::::{tab-set}

        :::{tab-item} <title>

        <content>
        :::

        ::::
    """
    out = ['::::{tab-set}', '']
    for title, content in items:
        out.append(f':::{{tab-item}} {title}')
        out.append('')
        out.extend(content)
        out.append(':::')
        out.append('')
    out.append('::::')
    out.append('')
    return out


def process_file(md_file):
    content = md_file.read_text()
    lines = content.split('\n')
    result = []
    i = 0
    changed = False

    while i < len(lines):
        m = TAB_RE.match(lines[i].rstrip())
        if not m:
            result.append(lines[i])
            i += 1
            continue

        # Start of a content-tab GROUP. All tabs in one group share this indent.
        base_len = len(m.group(1))
        content_indent = base_len + 4

        items = []
        while i < len(lines):
            tm = TAB_RE.match(lines[i].rstrip())
            if not tm or len(tm.group(1)) != base_len:
                break  # no more sibling tabs -> group ends

            title = tm.group(2).strip()

            # Collect this tab's body: blank lines or lines indented at least
            # content_indent, stopping at the next sibling tab or any out-dented line.
            block = []
            j = i + 1
            while j < len(lines):
                nxt = TAB_RE.match(lines[j].rstrip())
                if nxt and len(nxt.group(1)) == base_len:
                    break
                if lines[j].strip() == '' or lines[j].startswith(' ' * content_indent):
                    block.append(lines[j])
                    j += 1
                else:
                    break

            items.append((title, dedent_block(block, content_indent)))
            i = j

        result.extend(convert_tab_group(items))
        changed = True

    if changed:
        md_file.write_text('\n'.join(result))

    return changed


converted_files = 0
for md_file in sorted(src_dir.rglob('*.md')):
    text = md_file.read_text()
    if not TAB_RE.search(text):
        continue
    helper.log(f'  Processing: {md_file}', log_file)
    if process_file(md_file):
        helper.log(f'  Converted: {md_file}', log_file)
        converted_files += 1

helper.log(f'Content tab conversion complete. Converted {converted_files} file(s).', log_file)
PYEOF

exit $?
