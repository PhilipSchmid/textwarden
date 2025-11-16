#!/usr/bin/env python3
"""
Extract terms from NIST CSRC Glossary JSON export.

Source: https://csrc.nist.gov/csrc/media/glossary/glossary-export.zip
License: Public Domain (US Government work)

This script extracts individual technical terms while avoiding:
- Concatenated organization names
- HTML/XML markup
- Mathematical notation
- Overly long compound phrases
"""

import json
import re
from pathlib import Path
from typing import Set

def is_valid_term(word: str) -> bool:
    """Check if a word is a valid technical term."""
    # Must be 2-40 characters
    if len(word) < 2 or len(word) > 40:
        return False

    # Must contain only alphanumeric, hyphens, underscores
    if not re.match(r'^[a-z0-9][a-z0-9_-]*$', word):
        return False

    # Filter out pure numbers
    if word.isdigit():
        return False

    # Filter out common English words (basic set)
    common_words = {
        'a', 'an', 'the', 'is', 'are', 'was', 'were', 'be', 'been', 'being',
        'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would', 'should',
        'could', 'may', 'might', 'can', 'of', 'in', 'on', 'at', 'to', 'for',
        'with', 'from', 'by', 'as', 'or', 'and', 'but', 'if', 'then', 'else',
        'when', 'while', 'this', 'that', 'any', 'all', 'some', 'each', 'every',
        'which', 'what', 'who', 'whom', 'whose', 'where', 'why', 'how'
    }
    if word in common_words:
        return False

    return True

def extract_from_nist(json_path: Path) -> Set[str]:
    """Extract technical terms from NIST glossary JSON."""
    with open(json_path, 'r', encoding='utf-8-sig') as f:
        data = json.load(f)

    terms = set()

    for entry in data.get('parentTerms', []):
        term_text = entry.get('term', '')

        # Skip entries with HTML/XML/math markup
        if '<' in term_text or '>' in term_text or '{' in term_text or '}' in term_text:
            continue

        # Skip entries starting with special characters
        if term_text and term_text[0] in '([{':
            continue

        # Clean and lowercase
        cleaned = term_text.lower()

        # Remove punctuation except hyphens/underscores
        cleaned = re.sub(r'[^\w\s-]', ' ', cleaned)

        # Split into words
        words = cleaned.split()

        # Only process if reasonable number of words (avoid long organization names)
        if len(words) <= 4:
            for word in words:
                # Clean up individual word
                word = word.strip().strip('-_')
                if word and is_valid_term(word):
                    terms.add(word)

        # Also extract abbreviations/synonyms
        for abbr in entry.get('abbrSyn', []):
            abbr_text = abbr.get('text', '').lower()
            # Only single-word abbreviations
            if abbr_text and ' ' not in abbr_text and is_valid_term(abbr_text):
                terms.add(abbr_text)

    return terms

def main():
    script_dir = Path(__file__).parent
    extract_dir = script_dir.parent
    downloads_dir = extract_dir / 'downloads'
    source_dir = extract_dir / 'source'

    print("=== NIST CSRC Glossary Extraction ===")
    print()

    # Check for NIST JSON
    nist_json = downloads_dir / 'glossary-export.json'
    if not nist_json.exists():
        print(f"Error: NIST JSON not found: {nist_json}")
        print("Download from: https://csrc.nist.gov/csrc/media/glossary/glossary-export.zip")
        return 1

    # Extract terms
    print("Extracting terms from NIST glossary...")
    terms = extract_from_nist(nist_json)

    # Sort
    sorted_terms = sorted(terms)

    # Write output
    output_file = source_dir / 'nist_terms.txt'
    with open(output_file, 'w') as f:
        f.write("# NIST CSRC Glossary Terms\n")
        f.write("# Source: NIST Computer Security Resource Center Glossary\n")
        f.write("# URL: https://csrc.nist.gov/glossary\n")
        f.write("# Download: https://csrc.nist.gov/csrc/media/glossary/glossary-export.zip\n")
        f.write("# License: Public Domain (US Government work)\n")
        f.write(f"# Extraction date: {Path.cwd()}\n")
        f.write("#\n")
        f.write("# Methodology:\n")
        f.write("# 1. Downloaded ZIP containing glossary-export.json\n")
        f.write("# 2. Extracted individual technical words from terms and abbreviations\n")
        f.write("# 3. Filtered multi-word organization names (>4 words)\n")
        f.write("# 4. Removed HTML/XML markup and mathematical notation\n")
        f.write("# 5. Filtered common English words\n")
        f.write("#\n")
        f.write(f"# Total terms: {len(sorted_terms)}\n")
        f.write("#\n")
        f.write("# DO NOT EDIT - Regenerate with: scripts/extract_nist_terms.py\n")
        f.write("\n")
        for term in sorted_terms:
            f.write(f"{term}\n")

    print(f"Extracted {len(sorted_terms)} terms")
    print(f"Output: {output_file}")
    print()
    print("Sample terms:")
    for term in sorted_terms[:30]:
        print(f"  - {term}")

    return 0

if __name__ == '__main__':
    exit(main())
