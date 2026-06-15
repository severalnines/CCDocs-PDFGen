#!/usr/bin/env bash

## Convert MkDocs `!!! warning` (case-insenstive)admonitions:

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
import sys, pprint, json
from pathlib import Path

sys.path.insert(0, os.environ['BIN_DIR'])
import helper

src_dir  = Path(os.environ['CC_SPHINX_SRC_DIR'])
log_file = Path(os.environ['CC_LOG_FILE'])


HEADER_RE = re.compile(r'^(\s*)!!! warning(?:\t*"")?\t*$', re.IGNORECASE | re.MULTILINE)

# get all warning with title enclosed in double quotes, e.g. !!! warning "This is a warning"
HEADER_RE_WITH_TITLE = re.compile(r'^(\s*)!!![ \t]+warning[ \t]+"([^"]+)"[ \t]*\r?$', re.IGNORECASE | re.MULTILINE)

INFO_PATTERNS = [HEADER_RE, HEADER_RE_WITH_TITLE]

def convert_warning_content(lines):
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
        result.append(dedented.rstrip())

    while result and not result[0]:
        result.pop(0)
    while result and not result[-1]:
        result.pop()
    return result


def convert_warning_block_with_title(title, block_lines):
    result = [f':::{{warning}} {title}', '']
    res_ext = convert_warning_content(block_lines)

    result.extend(res_ext)
    result.append(':::')
    result.append('')
    return result

def process_file(md_file):
    content = md_file.read_text()
    lines = content.split('\n')
    result = []
    i = 0
    changed = False
    
    while i < len(lines):
        line = lines[i]

        m = HEADER_RE.match(line.rstrip())
        h_re_wtm = HEADER_RE_WITH_TITLE.match(line.rstrip())
        
        if m or h_re_wtm:

            if m:
                header_indent = m.group(1)
            else:
                header_indent = h_re_wtm.group(1)
                
            indent_len = len(header_indent)
        
            # Collect all indented/blank lines belonging to this block
            block_lines = []
            j = i + 1

            while j < len(lines) and  (lines[j].startswith(' ' * (indent_len + 4)) or lines[j].strip() == ''):
                block_lines.append(lines[j])
                j += 1

            title = "Warning!"
            
            if h_re_wtm:
                title = h_re_wtm.group(2)

            result.extend(convert_warning_block_with_title(title, block_lines))
            
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

helper.log(f'Warning admonition conversion complete. Converted {converted_files} file(s).', log_file)
PYEOF

exit $?
