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


# Extract the value and assign to a variable
CC_SPHINX_SRC_DIR=$(read_ini "$CONFIG_FILE" "cc_gen_pdf_paths" "CC_SPHINX_SRC_DIR")
CC_LOG_FILE=$(read_ini "$CONFIG_FILE" "cc_gen_pdf_paths" "CC_LOG_FILE")

echo "$0: Starting gif ${CC_SPHINX_SRC_DIR}/images/cc-watchlist-animations.gif conversion from '$CC_SPHINX_SRC_DIR/images' ..."| tee -a "$CC_LOG_FILE"
convert "${CC_SPHINX_SRC_DIR}/images/cc-watchlist-animations.gif[0]" ${CC_SPHINX_SRC_DIR}/images/cc-watchlist-animations.png
find "$CC_SPHINX_SRC_DIR" -name "*.md" -type f -exec \
    sed -i 's|images/cc-watchlist-animations\.gif|images/cc-watchlist-animations.png|g' {} +

echo "Done. Recursively replaced occurrences under '$CC_SPHINX_SRC_DIR'."

exit 0