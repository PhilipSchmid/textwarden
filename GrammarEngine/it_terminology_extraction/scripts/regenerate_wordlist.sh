#!/bin/bash
# IT Terminology Wordlist Regeneration Script
# This script regenerates the it_terminology.txt file from all sources
# with improved hyphen handling
#
# Usage: ./scripts/regenerate_wordlist.sh
#   or:  make update-terminology (from project root)

set -e  # Exit on error

# Determine absolute path to the extraction directory (parent of scripts/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXTRACT_DIR="$(dirname "$SCRIPT_DIR")"
SOURCE_DIR="$EXTRACT_DIR/source"
BUILD_DIR="$EXTRACT_DIR/build"
OUTPUT_DIR="$(dirname "$EXTRACT_DIR")/wordlists"  # GrammarEngine/wordlists directory

echo "=== IT Terminology Wordlist Regeneration ==="
echo "Extraction directory: $EXTRACT_DIR"
echo "Source directory: $SOURCE_DIR"
echo "Build directory: $BUILD_DIR"
echo "Output directory: $OUTPUT_DIR"
echo

# Clean build directory
rm -rf "$BUILD_DIR"/*
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

cd "$BUILD_DIR"

# Step 1: Process sources with hyphen splitting
echo "[1/7] Processing CNCF Landscape (splitting vendor-product hyphens)..."
if [ -f "$SOURCE_DIR/cncf_technologies.txt" ]; then
    "$SCRIPT_DIR/split_hyphens.sh" "$SOURCE_DIR/cncf_technologies.txt" cncf_technologies_split.txt
else
    echo "Warning: cncf_technologies.txt not found, skipping"
    touch cncf_technologies_split.txt
fi
echo

echo "[2/7] Processing GitHub Linguist (splitting hyphens)..."
if [ -f "$SOURCE_DIR/languages.txt" ]; then
    "$SCRIPT_DIR/split_hyphens.sh" "$SOURCE_DIR/languages.txt" languages_split.txt
else
    echo "Warning: languages.txt not found, skipping"
    touch languages_split.txt
fi
echo

# Step 2: Extract clean terms from Linux kernel files (no hyphens to split)
echo "[3/7] Extracting Linux syscalls..."
if [ -f "$SOURCE_DIR/linux_syscalls.txt" ]; then
    grep -v '^#' "$SOURCE_DIR/linux_syscalls.txt" | grep -v '^$' > syscalls_clean.txt
else
    echo "Warning: linux_syscalls.txt not found"
    touch syscalls_clean.txt
fi
echo "Extracted $(wc -l < syscalls_clean.txt) syscalls"
echo

echo "[4/7] Extracting Linux BPF terms..."
if [ -f "$SOURCE_DIR/linux_bpf.txt" ]; then
    grep -v '^#' "$SOURCE_DIR/linux_bpf.txt" | grep -v '^$' > bpf_clean.txt
else
    echo "Warning: linux_bpf.txt not found"
    touch bpf_clean.txt
fi
echo "Extracted $(wc -l < bpf_clean.txt) BPF terms"
echo

echo "[5/7] Extracting Linux filesystems..."
if [ -f "$SOURCE_DIR/linux_filesystems.txt" ]; then
    grep -v '^#' "$SOURCE_DIR/linux_filesystems.txt" | grep -v '^$' > filesystems_clean.txt
else
    echo "Warning: linux_filesystems.txt not found"
    touch filesystems_clean.txt
fi
echo "Extracted $(wc -l < filesystems_clean.txt) filesystem names"
echo

echo "[6/7] Extracting NIST CSRC Glossary terms..."
if [ -f "$SOURCE_DIR/nist_terms.txt" ]; then
    grep -v '^#' "$SOURCE_DIR/nist_terms.txt" | grep -v '^$' > nist_clean.txt
else
    echo "Warning: nist_terms.txt not found"
    touch nist_clean.txt
fi
echo "Extracted $(wc -l < nist_clean.txt) NIST cybersecurity terms"
echo

# Step 3: Combine all sources
echo "[7/7] Combining all sources..."
cat \
    "$SOURCE_DIR/protocols.txt" \
    "$SOURCE_DIR/services.txt" \
    "$SOURCE_DIR/security_terms.txt" \
    languages_split.txt \
    cncf_technologies_split.txt \
    "$SOURCE_DIR/stackoverflow_survey.txt" \
    "$SOURCE_DIR/stackoverflow_tags.txt" \
    "$SOURCE_DIR/mdn_glossary.txt" \
    syscalls_clean.txt \
    bpf_clean.txt \
    filesystems_clean.txt \
    nist_clean.txt \
    2>/dev/null | \
    sort -u | \
    grep -E '^[a-z0-9][a-z0-9_-]*$' | \
    awk 'length($0) > 1 && length($0) <= 40' | \
    grep -vE '^(a|an|the|is|are|was|were|be|been|being|have|has|had|do|does|did|will|would|should|could|may|might|can|of|in|on|at|to|for|with|from|by|as|or|and|but|if|then|else|when|while|this|that|any|all|some|each|every|which|what|who|whom|whose|where|why|how)$' \
    > it_terminology_final.txt

# Step 4: Copy to output directory
cp it_terminology_final.txt "$OUTPUT_DIR/it_terminology.txt"

echo
echo "=== Generation Complete ==="
echo "Final term count: $(wc -l < "$OUTPUT_DIR/it_terminology.txt")"
echo "Output file: $OUTPUT_DIR/it_terminology.txt"
echo
echo "Note: Intermediate build files are in: $BUILD_DIR"
