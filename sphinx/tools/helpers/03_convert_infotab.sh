#!/usr/bin/env bash

## Convert empty info blocks with tabbed content (Empty Notes or Message) in Mkdocs

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

log "Starting !!! info tab conversion under '$CC_SPHINX_SRC_DIR'..."

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

# Matches a TAB-SET container: an info admonition with an explicit EMPTY title,
#   !!! info ""
# Only this exact form is treated as a transparent wrapper for tabbed content.
INFO_TABSET_RE = re.compile(r'^!!![ \t]+info[ \t]+""[ \t]*\r?$',
                            re.IGNORECASE | re.MULTILINE)

# Matches a DEFAULT-title info admonition with NO quotes at all, e.g.
#   !!! info   /   !!! Info
# MkDocs renders these with the auto-title "Info" -> treat as a real callout.
INFO_DEFAULT_RE = re.compile(r'^!!![ \t]+info[ \t]*\r?$',
                             re.IGNORECASE | re.MULTILINE)

# Matches a TITLED info admonition, capturing the title text, e.g.:
#   !!! info "Some Title"
# These are treated as real callouts (-> {admonition} with :class: info).
INFO_RE_WITH_TITLE = re.compile(r'^!!![ \t]+info[ \t]+"([^"]+)"[ \t]*\r?$',
                                re.IGNORECASE | re.MULTILINE)

# All info-admonition opener patterns, used for quick file-level pre-checks.
INFO_PATTERNS = (INFO_TABSET_RE, INFO_DEFAULT_RE, INFO_RE_WITH_TITLE)


def convert_badge(text):
    text = re.sub(r'\^==Enterprise==\^', '{bdg-primary}`Enterprise`', text)
    text = re.sub(r'\^==Advanced==\^',   '{bdg-secondary}`Advanced`', text)
    return text


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
            item_text = convert_badge(stripped[2:].rstrip())
            level = max(0, (indent - base_indent) // 4)
            result.append('  ' * level + '- ' + item_text)
    return result


def convert_info_block(block_lines):
    """
    Convert collected indented block lines (from !!! info "") into
    a MyST ::::{tab-set} / :::{tab-item} structure.
    """
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

    # flush last tab
    if current_tab_name is not None:
        result.append(f':::{{tab-item}} {current_tab_name}')
        result.extend(convert_tab_content(current_tab_lines))
        result.append(':::')
        result.append('')

    result.append('::::')
    return result


def collect_block_lines(lines, start):
    """Collect the indented/blank lines that belong to an admonition opened at `start`.

    Returns (block_lines, next_index) where next_index is the first line that is
    no longer part of the block.
    """
    block_lines = []
    j = start + 1
    while j < len(lines) and (lines[j].startswith('    ') or lines[j].strip() == ''):
        block_lines.append(lines[j])
        j += 1
    return block_lines, j


def convert_titled_content(lines):
    """De-indent a titled admonition body (4-space base) and convert badges.

    Preserves deeper nesting and blank lines; trims surrounding blank lines.
    """
    base_indent = 4
    result = []
    for line in lines:
        if not line.strip():
            result.append('')
            continue
        if len(line) >= base_indent and line[:base_indent].isspace():
            dedented = line[base_indent:]
        else:
            dedented = line.lstrip(' ')
        result.append(convert_badge(dedented.rstrip()))
    while result and not result[0]:
        result.pop(0)
    while result and not result[-1]:
        result.pop()
    return result


def convert_info_block_with_title(title, block_lines):
    """Convert a TITLED MkDocs info admonition (!!! info "Some Title") into a
    MyST {admonition} directive that preserves the title and keeps info styling:

        :::{admonition} Some Title
        :class: info

        body content...
        :::
    """
    result = [f':::{{admonition}} {title}', ':class: info', '']
    result.extend(convert_titled_content(block_lines))
    result.append(':::')
    result.append('')
    return result


def process_file(md_file):
    content = md_file.read_text()
    if not any(p.search(content) for p in INFO_PATTERNS):
        return False

    lines = content.split('\n')
    result = []
    i = 0
    changed = False

    while i < len(lines):
        line = lines[i]
        stripped = line.rstrip()
        title_match = INFO_RE_WITH_TITLE.match(stripped)

        if INFO_TABSET_RE.match(stripped):
            # !!! info ""  ->  tab-set wrapper (only when it actually holds === tabs)
            block_lines, j = collect_block_lines(lines, i)
            has_tabs = any(re.match(r'^ {4}=== "', l) for l in block_lines)
            if has_tabs:
                result.extend(convert_info_block(block_lines))
                i = j
                changed = True
            else:
                result.append(line)
                i += 1
        elif title_match:
            # !!! info "Some Title"  ->  {admonition} Some Title :class: info
            block_lines, j = collect_block_lines(lines, i)
            result.extend(convert_info_block_with_title(title_match.group(1), block_lines))
            i = j
            changed = True
        elif INFO_DEFAULT_RE.match(stripped):
            # !!! info / !!! Info (no quotes)  ->  {admonition} Info :class: info,
            # unless it happens to hold tabs, in which case treat it as a tab-set.
            block_lines, j = collect_block_lines(lines, i)
            if any(re.match(r'^ {4}=== "', l) for l in block_lines):
                result.extend(convert_info_block(block_lines))
            else:
                result.extend(convert_info_block_with_title('Info', block_lines))
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
    if not any(p.search(text) for p in INFO_PATTERNS):
        continue
    helper.log(f'  Processing: {md_file}', log_file)
    if process_file(md_file):
        helper.log(f'  Converted: {md_file}', log_file)
        converted_files += 1

helper.log(f'Info tab conversion complete. Converted {converted_files} file(s).', log_file)
PYEOF

exit $?
