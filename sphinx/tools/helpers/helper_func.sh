#!/bin/bash




CC_SPHINX_DEST_DIR=""
LOG_FILE=""


# Function to read a value from an INI file
# Usage: read_ini <file> <section> <key>
read_ini() {
    local file="$1"
    local section="$2"
    local key="$3"
    
    awk -F '=' -v section="$section" -v key="$key" '
        # Strip leading/trailing whitespace
        function trim(s) {
            sub(/^[ \t]+/, "", s)
            sub(/[ \t]+$/, "", s)
            return s
        }
        # Detect section headers like [section_name]
        /^[[:space:]]*\[.*\][[:space:]]*$/ {
            current = $0
            sub(/^[[:space:]]*\[/, "", current)
            sub(/\][[:space:]]*$/, "", current)
            next
        }
        # Skip comments and blank lines
        /^[[:space:]]*[#;]/ { next }
        /^[[:space:]]*$/  { next }
        # Match key in the desired section
        current == section {
            k = trim($1)
            if (k == key) {
                # Re-join in case the value contains "="
                sub(/^[^=]*=/, "", $0)
                print trim($0)
                exit
            }
        }
    ' "$file"
}
## Add verbosity to the output
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}


main () {
    local cc_log_file
    
    CC_SPHINX_SRC_DIR=$(read_ini "$CONFIG_FILE" "cc_gen_pdf_paths" "CC_SPHINX_SRC_DIR")
    cc_log_file=$(read_ini "$CONFIG_FILE" "cc_gen_pdf_paths" "CC_LOG_FILE")
    LOG_FILE="$(dirname "${CC_SPHINX_SRC_DIR}")/../$cc_log_file"

}

main