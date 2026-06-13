#!/usr/bin/env bash

## Convert MkDocs `!!! quote ""` admonitions:

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

log "Starting !!! quote admonition conversion under '$CC_SPHINX_SRC_DIR'..."

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

# Opening line of a MkDocs quote admonition with an EMPTY title:  !!! quote ""
HEADER_RE = re.compile(r'^(\s*)!!!\s+quote\s+""\s*\r?$', re.IGNORECASE | re.MULTILINE)


def extract_label(lines, header_idx):
    """Derive the admonition title from the **bold** phrase on the nearest
    non-blank line ABOVE the block, e.g.

        4.  In the **Deploy Valkey Cluster** wizard, configure ...
                    ^^^^^^^^^^^^^^^^^^^^^^   ->  "Deploy Valkey Cluster"

    Falls back to "Note" when no bold phrase is found.
    """
    k = header_idx - 1
    while k >= 0 and lines[k].strip() == '':
        k -= 1
    if k >= 0:
        m = re.search(r'\*\*(.+?)\*\*', lines[k])
        if m:
            return m.group(1).strip()
    return 'Note'


def convert_quote_block(label, block_lines, header_indent):
    """Flatten a `!!! quote ""` block that uses `=== "..."` tabs into a MyST
    admonition. Each tab title becomes a bold paragraph and its list is
    de-indented to the left margin (deeper nesting is preserved). The whole
    block is emitted at column 0:

        ::::{admonition} <label>
        :class: note

        **(1) Cluster details**

        - **Name**: ...
        ...
        ::::
        <!-- end list -->
    """
    indent_len = len(header_indent)
    tab_re = re.compile(r'^ {%d}=== "(.+?)"\s*\r?$' % (indent_len + 4))
    content_base = indent_len + 8  # list items sit two levels below the !!! marker

    out = [f'::::{{admonition}} {label}', ':class: note', '']

    for line in block_lines:
        tab = tab_re.match(line)
        if tab:
            # start of a new section: blank-separate, then the (bold) title
            if out[-1] != '':
                out.append('')
            out.append(tab.group(1).strip())
            out.append('')
        elif line.strip() == '':
            if out[-1] != '':
                out.append('')
        else:
            # de-indent the section body, preserving any deeper nesting
            if len(line) >= content_base and line[:content_base].isspace():
                dedented = line[content_base:]
            else:
                dedented = line.lstrip(' ')
            out.append(dedented.rstrip())

    while out and out[-1] == '':
        out.pop()
    out.append('::::')
    out.append('<!-- end list -->')
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
        indent_len = len(header_indent)

        # Collect all indented/blank lines belonging to this block
        block_lines = []
        j = i + 1
        while j < len(lines) and (lines[j].startswith(' ' * (indent_len + 4))
                                  or lines[j].strip() == ''):
            block_lines.append(lines[j])
            j += 1

        has_tabs = any(re.match(r'^ {%d}=== "' % (indent_len + 4), l) for l in block_lines)
        if has_tabs:
            label = extract_label(lines, i)
            result.extend(convert_quote_block(label, block_lines, header_indent))
            i = j
            changed = True
        else:
            # Not a tabbed quote block -> leave it untouched.
            result.append(line)
            i += 1

    if changed:
        md_file.write_text('\n'.join(result))

    return changed


converted_files = 0
for md_file in sorted(src_dir.rglob('*.md')):

    if not HEADER_RE.search(md_file.read_text()):
        continue
    helper.log(f'  Processing: {md_file}', log_file)
    if process_file(md_file):
        helper.log(f'  Converted: {md_file}', log_file)
        converted_files += 1

helper.log(f'Quote admonition conversion complete. Converted {converted_files} file(s).', log_file)
PYEOF

exit $?
