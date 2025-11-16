#!/bin/bash
# Hyphenated Term Processor
#
# This script processes hyphenated terms and splits them into individual words,
# EXCEPT for valid hyphenated technical terms which are kept as-is.
#
# Usage: ./split_hyphens.sh <input_file> <output_file>
#
# Valid technical compounds are loaded from:
#   source/valid_hyphenated_compounds.txt
#
# To regenerate the valid compounds list:
#   scripts/extract_hyphenated_compounds.py

set -e

# Find the source directory (relative to script location)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")/source"
VALID_COMPOUNDS="$SOURCE_DIR/valid_hyphenated_compounds.txt"

if [ ! -f "$VALID_COMPOUNDS" ]; then
    echo "Error: Valid compounds file not found: $VALID_COMPOUNDS"
    echo "Run: scripts/extract_hyphenated_compounds.py"
    exit 1
fi

input_file="$1"
output_file="$2"

if [ -z "$input_file" ] || [ -z "$output_file" ]; then
    echo "Usage: $0 <input_file> <output_file>"
    exit 1
fi

# Load valid hyphenated compounds (skip comments)
PATTERN_FILE=$(mktemp)
grep -v '^#' "$VALID_COMPOUNDS" | grep -v '^$' > "$PATTERN_FILE"

num_valid=$(wc -l < "$PATTERN_FILE")

# Process the file:
# 1. For each line with a hyphen
# 2. Check if it's in our valid list
# 3. If yes, keep it as-is
# 4. If no, split it into individual words
while IFS= read -r term; do
    if [[ "$term" == *-* ]]; then
        # Check if this term is in our valid list
        if grep -Fxq "$term" "$PATTERN_FILE"; then
            # Keep valid hyphenated term
            echo "$term"
        else
            # Split into individual words
            echo "$term" | tr '-' '\n'
        fi
    else
        # No hyphen, keep as-is
        echo "$term"
    fi
done < "$input_file" > "$output_file"

rm "$PATTERN_FILE"

echo "Processed $(wc -l < "$input_file") input terms"
echo "Generated $(wc -l < "$output_file") output terms (after splitting hyphens)"
