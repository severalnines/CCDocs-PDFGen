#!/usr/bin/env bash

set -euo pipefail

DEFAULT_BUILD_VERSION="2.4.0"
BUILD_VERSION=""

usage() {
    echo "Usage: $0 [--build-version <version>]"
    echo ""
    echo "  --build-version   Version string in decimal format (e.g. 2.4.0, 2.5.6)."
    echo "                    Defaults to ${DEFAULT_BUILD_VERSION} if not specified."
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-version)
            shift
            if [[ -z "${1:-}" ]]; then
                echo "ERROR: --build-version requires a value." >&2
                usage
            fi
            if ! [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "ERROR: --build-version must be in decimal format (e.g. 2.4.0, 2.5.6)." >&2
                exit 1
            fi
            BUILD_VERSION="$1"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage
            ;;
    esac
done

BUILD_VERSION="${BUILD_VERSION:-$DEFAULT_BUILD_VERSION}"

# Resolve paths relative to this script's location:
# bin/ -> tools/ -> sphinx/
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SPHINX_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOLS_BIN_DIR="${SPHINX_DIR}/tools/bin"
CONF_PY="${SPHINX_DIR}/conf.py"

if [[ ! -f "$CONF_PY" ]]; then
    echo "ERROR: conf.py not found at '${CONF_PY}'." >&2
    exit 1
fi

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

REPO_DIR="$(cd "${SPHINX_DIR}/.." && pwd)"

log "Build version: ${BUILD_VERSION}"
log "Sphinx dir:    ${SPHINX_DIR}"
log "Repo dir:      ${REPO_DIR}"

# Step 1: Pull latest changes in the repo root
log "Step 1: Pulling latest changes in '${REPO_DIR}'..."
git -C "${REPO_DIR}" pull

# Step 2: cd into sphinx directory
log "Step 2: Switching to Sphinx directory..."
cd "${SPHINX_DIR}"

# Step 3: Generate ordered sections
log "Step 3: Generating ordered sections..."
python "${TOOLS_BIN_DIR}/gen-order-sections.py"

# Step 4: Copy docs
log "Step 4: Copying docs..."
python "${TOOLS_BIN_DIR}/copy-docs.py"

# Step 5: Generate index*.md files
log "Step 5: Generating sphinx index files..."
python "${TOOLS_BIN_DIR}/sphinx-index-gen.py"

# Step 6: Run md_to_sphinx helpers
log "Step 6: Running md_to_sphinx conversion..."
python "${TOOLS_BIN_DIR}/md_to_sphinx.py"

# Step 7: Patch release version in conf.py
log "Step 7: Setting release version to '${BUILD_VERSION}' in conf.py..."
if grep -qE '^release\s*=' "${CONF_PY}"; then
    sed -i.bak -E "s|^(release\s*=\s*)\"[^\"]*\"|\1\"${BUILD_VERSION}\"|" "${CONF_PY}"
    rm -f "${CONF_PY}.bak"
    log "  conf.py release updated."
else
    echo "ERROR: Could not find 'release = ...' line in conf.py." >&2
    exit 1
fi

# Step 8: Generate the PDF
log "Step 8: Generating PDF..."
if [[ -f "${HOME}/CCDocs-PDFGen/home_script/exports.sh" ]]; then
    # Source exports to get cc_gen_pdf and the venv
    # shellcheck disable=SC1091
    source "${HOME}/CCDocs-PDFGen/home_script/exports.sh"
    cc_gen_pdf
else
    # Fallback: run sphinx-build + latexmk directly
    log "  exports.sh not found — running sphinx-build directly..."
    CC_MAN_GEN_DIR="$(cd "${SPHINX_DIR}/../.." && pwd)"
    VENV="${CC_MAN_GEN_DIR}/venv_ccpdf_doc"
    if [[ -f "${VENV}/bin/activate" ]]; then
        # shellcheck disable=SC1091
        source "${VENV}/bin/activate"
    fi
    sphinx-build -b latex -c "${SPHINX_DIR}" "${SPHINX_DIR}/src" "${SPHINX_DIR}/build/pdf"
    cd "${SPHINX_DIR}/build/pdf"
    latexmk -xelatex clustercontrol.tex
    cd "${SPHINX_DIR}"
fi

log "Done. PDF generation complete."
