#!/usr/bin/env bash

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

if ! command -v mmdc &>/dev/null; then
    log "mmdc not found. Installing @mermaid-js/mermaid-cli via npm..."
    if ! command -v npm &>/dev/null; then
        echo "ERROR: npm is not installed. Please install Node.js/npm first." >&2
        exit 1
    fi
    npm install -g @mermaid-js/mermaid-cli
    if ! command -v mmdc &>/dev/null; then
        echo "ERROR: mmdc installation failed." >&2
        exit 1
    fi
    log "mmdc installed successfully."
fi

TMP_DIR="/tmp/mermaid"
IMAGES_DIR="${CC_SPHINX_SRC_DIR%/}/images"
mkdir -p "$TMP_DIR"

PUPPETEER_CFG="${TMP_DIR}/puppeteer-config.json"
echo '{"args":["--no-sandbox","--disable-setuid-sandbox"]}' > "$PUPPETEER_CFG"

log "Starting Mermaid conversion under '$CC_SPHINX_SRC_DIR'..."

export CC_SPHINX_SRC_DIR
export IMAGES_DIR
export TMP_DIR
export PUPPETEER_CFG
export CC_LOG_FILE
export BIN_DIR="$(dirname "$0")/../bin"

python3 << 'PYEOF'
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, os.environ['BIN_DIR'])
import helper

src_dir       = Path(os.environ['CC_SPHINX_SRC_DIR'])
images_dir    = Path(os.environ['IMAGES_DIR'])
tmp_dir       = Path(os.environ['TMP_DIR'])
puppeteer_cfg = os.environ['PUPPETEER_CFG']
log_file      = Path(os.environ['CC_LOG_FILE'])

MERMAID_BLOCK = re.compile(r'```mermaid\s*\n(.*?)\n\s*```', re.DOTALL)

converted = 0
failed = 0

for md_file in sorted(src_dir.rglob('*.md')):
    content = md_file.read_text()
    blocks = MERMAID_BLOCK.findall(content)

    if not blocks:
        continue

    helper.log(f"  Processing: {md_file}", log_file)
    base_name = md_file.stem
    succeeded = {}

    # Phase 1 & 2: extract each block, run mmdc, move PNG to images/
    for i, block_content in enumerate(blocks, 1):
        mmd_file = tmp_dir / f"{base_name}_{i}.mmd"
        img_tmp  = tmp_dir / f"{base_name}_{i}.png"
        img_dest = images_dir / f"{base_name}_{i}.png"

        mmd_file.write_text(block_content)

        helper.log(f"    [Block {i}] converting -> {img_dest.name}", log_file)
        result = subprocess.run(
            ['mmdc', '-i', str(mmd_file), '-o', str(img_tmp),
             '--puppeteerConfigFile', puppeteer_cfg],
            stderr=open(log_file, 'a')
        )

        if result.returncode == 0:
            shutil.move(str(img_tmp), str(img_dest))
            succeeded[i] = img_dest
            converted += 1
            helper.log(f"    [Block {i}] OK -> {img_dest}", log_file)
        else:
            helper.log(f"    [Block {i}] WARN: mmdc failed — original block kept.", log_file, error=True)
            failed += 1

    # Phase 3: replace successful blocks with image references
    counter = [0]
    def replace_block(m):
        counter[0] += 1
        idx = counter[0]
        if idx not in succeeded:
            return m.group(0)
        img_dest = succeeded[idx]
        rel_path = os.path.relpath(img_dest, md_file.parent)
        return f"![{base_name} flow diagram {idx}]({rel_path})"

    new_content = MERMAID_BLOCK.sub(replace_block, content)
    md_file.write_text(new_content)

helper.log(f"Mermaid conversion complete. Converted: {converted} block(s), Failed: {failed} block(s).", log_file)
PYEOF

exit $?