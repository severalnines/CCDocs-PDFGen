#!/usr/bin/env bash

## Convert MkDocs `!!! Note` / `!!! Note ""` admonitions:
##   - Blocks with `===` tab headers → MyST `::::{tab-set}` / `:::{tab-item}`
##   - Plain note blocks             → MyST `:::{note}` ... `:::`

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

log "Starting !!! Note admonition conversion under '$CC_SPHINX_SRC_DIR'..."

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

# Matches `!!! Note`, `!!! note`, `!!! Note ""`, `    !!! Note`, etc.
# Does NOT match `!!! Notes` or `!!! Note "Some title"`.
HEADER_RE = re.compile(r'^(\s*)!!! note(?:\s*"")?\s*$', re.IGNORECASE)


def convert_tab_content(lines):
    """Convert indented MkDocs list items to MyST list items."""
    result = []
    base_indent = 8
    for line in lines:
        if not line.strip():
            continue
        stripped = line.lstrip(' ')
        indent = len(line) - len(stripped)
        if stripped.startswith('* '):
            item_text = stripped[2:].rstrip()
            level = max(0, (indent - base_indent) // 4)
            result.append('  ' * level + '- ' + item_text)
        else:
            result.append(stripped.rstrip())
    return result


def convert_note_tabset(block_lines):
    """Convert !!! Note "" with === tabs into ::::{tab-set} / :::{tab-item}."""
    result = ['::::{tab-set}', '']
    current_tab_name = None
    current_tab_lines = []

    for line in block_lines:
        tab_match = re.match(r'^ {4}=== "([^"]+)"', line)
        if tab_match:
            if current_tab_name is not None:
                result.append(f':::{{tab-item}} {current_tab_name}')
                result.extend(convert_tab_content(current_tab_lines))
                result.append(':::')
                result.append('')
            current_tab_name = tab_match.group(1)
            current_tab_lines = []
        elif current_tab_name is not None:
            current_tab_lines.append(line)

    if current_tab_name is not None:
        result.append(f':::{{tab-item}} {current_tab_name}')
        result.extend(convert_tab_content(current_tab_lines))
        result.append(':::')
        result.append('')

    result.append('::::')
    return result


def convert_plain_note(header_indent, block_lines):
    """Convert a plain !!! Note block into :::{note} Note ... :::."""
    indent_len = len(header_indent)
    content_indent = indent_len + 4
    body = []
    for line in block_lines:
        if line.strip() == '':
            body.append('')
        elif line.startswith(' ' * content_indent):
            body.append(line[indent_len:].rstrip())
        else:
            body.append(line[indent_len:].rstrip())

    while body and body[0] == '':
        body.pop(0)
    while body and body[-1] == '':
        body.pop()

    return [f'{header_indent}:::{{note}} Note'] + body + [f'{header_indent}:::']


def process_file(md_file):
    content = md_file.read_text()
    lines = content.split('\n')
    result = []
    i = 0
    changed = False

    while i < len(lines):
        line = lines[i]

        m = HEADER_RE.match(line.rstrip())
        if m:
            header_indent = m.group(1)
            indent_len = len(header_indent)

            # Collect all indented/blank lines belonging to this block
            block_lines = []
            j = i + 1
            while j < len(lines) and (lines[j].startswith(' ' * (indent_len + 4)) or lines[j].strip() == ''):
                block_lines.append(lines[j])
                j += 1

            has_tabs = any(re.match(r'^' + ' ' * (indent_len + 4) + r'=== "', l) for l in block_lines)

            if has_tabs:
                result.extend(convert_note_tabset(block_lines))
            else:
                result.extend(convert_plain_note(header_indent, block_lines))

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

    if not re.search(r'^\s*!!! note(?:\s*"")?\s*$', md_file.read_text(), re.IGNORECASE | re.MULTILINE):
        continue
    helper.log(f'  Processing: {md_file}', log_file)
    if process_file(md_file):
        helper.log(f'  Converted: {md_file}', log_file)
        converted_files += 1

helper.log(f'Note admonition conversion complete. Converted {converted_files} file(s).', log_file)
PYEOF

exit $?
