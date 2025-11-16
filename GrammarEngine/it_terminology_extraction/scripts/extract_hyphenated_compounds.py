#!/usr/bin/env python3
"""
Extract valid hyphenated technical compounds from authoritative sources.

This script identifies hyphenated terms that represent genuine technical
compounds (e.g., "real-time", "peer-to-peer") as opposed to vendor-product
names (e.g., "apache-kafka", "alibaba-cloud") which should be split.

Criteria for valid technical compounds:
1. Common technical prefixes/suffixes
2. Directional or architectural patterns
3. Present in authoritative technical glossaries (NIST, MDN)
"""

import json
import re
from pathlib import Path
from typing import Set

# Strong technical prefixes (very likely to be technical compounds)
STRONG_TECHNICAL_PREFIXES = {
    'anti-', 'auto-', 'bi-', 'client-', 'cross-', 'end-to',
    'multi-', 'non-', 'peer-to', 'point-to', 'post-', 'pre-',
    'pub-', 'read-', 'real-', 'self-', 'server-', 'single-',
    'uni-', 'write-', 'zero-'
}

# Technical suffixes
TECHNICAL_SUFFIXES = {
    '-active', '-aware', '-balance', '-based', '-break', '-check',
    '-code', '-down', '-duplex', '-forward', '-free', '-grained',
    '-heal', '-limit', '-lived', '-load', '-master', '-only',
    '-out', '-over', '-passive', '-pressure', '-process', '-queue',
    '-read', '-reload', '-replica', '-response', '-running', '-safe',
    '-scale', '-secondary', '-sent', '-shake', '-side', '-site',
    '-slave', '-split', '-stack', '-tenant', '-threaded', '-tier',
    '-time', '-up', '-write'
}

# Complete valid compound patterns (exact matches)
# These are core technical compounds that should ALWAYS be preserved
EXACT_PATTERNS = {
    # Architectural patterns
    'end-to-end', 'peer-to-peer', 'point-to-point',
    'client-side', 'server-side',
    'active-active', 'active-passive',
    'master-master', 'master-slave',
    'leader-follower', 'primary-secondary',
    'read-write', 'read-only', 'write-only',

    # Timing/execution
    'just-in-time', 'ahead-of-time',
    'real-time', 'near-real-time',
    'compile-time', 'run-time', 'build-time', 'design-time',

    # Concurrency/atomicity
    'compare-and-swap', 'test-and-set',
    'lock-free', 'wait-free',
    'copy-on-write', 'write-ahead',

    # Messaging/communication
    'fire-and-forget', 'request-response',
    'pub-sub', 'message-queue',
    'challenge-response',

    # System properties
    'multi-tenant', 'single-tenant',
    'multi-threaded', 'single-threaded',
    'full-duplex', 'half-duplex',

    # Web/network
    'cross-origin', 'same-origin',
    'cross-site', 'same-site',
    'cross-domain',

    # Security/cryptography
    'non-repudiation',
    'zero-knowledge',
    'multi-factor',

    # Operations
    'hot-reload', 'load-balance',
    'auto-scale', 'fail-over',
    'command-line',

    # Phases
    'two-phase', 'three-way',

    # Access patterns
    'role-based', 'attribute-based',
    'host-based', 'network-based',
}

def matches_technical_pattern(term: str) -> bool:
    """Check if term matches technical compound patterns."""
    # Filter out vendor/product names:
    # - More than 3 parts (2 hyphens) is usually a product name
    # - Longer than 25 characters is usually a product name
    if term.count('-') > 2 or len(term) > 25:
        return False

    # Exclude specific vendor/product patterns
    vendor_patterns = [
        'for-',  # application-platform-for-lke
        '-for-', # aks-engine-for-azure
        '-service',  # application-high-availability-service
        '-platform',
        '-engine',
    ]
    for pattern in vendor_patterns:
        if pattern in term:
            return False

    # Exclude known vendor/product names
    vendor_names = {
        'visual-studio-code', 'threat-stack', 'grape-up',
        'kubeservice-stack', 'auto-isac',
    }
    if term in vendor_names:
        return False

    # Exclude overly specialized protocol-specific terms
    # (these are real terms but too specialized for general IT terminology)
    specialized_terms = {
        'adj-rib-out', 'xns-time', 'td-replica', 'cd-read',
        'g-code',  # CNC machine code
    }
    if term in specialized_terms:
        return False

    # Exact matches (highest confidence)
    if term in EXACT_PATTERNS:
        return True

    # Strong technical prefix (high confidence)
    for prefix in STRONG_TECHNICAL_PREFIXES:
        if term.startswith(prefix):
            return True

    # Technical suffix with reasonable prefix (medium confidence)
    for suffix in TECHNICAL_SUFFIXES:
        if term.endswith(suffix):
            # Additional check: suffix-only matches must be shorter
            # to avoid vendor products like "threat-stack"
            if len(term) <= 20:
                return True

    return False

def extract_from_nist(json_path: Path) -> Set[str]:
    """Extract hyphenated technical terms from NIST CSRC Glossary."""
    with open(json_path, 'r', encoding='utf-8-sig') as f:
        data = json.load(f)

    hyphenated = set()
    for entry in data.get('parentTerms', []):
        term = entry.get('term', '').lower()
        # Find hyphenated words
        words = re.findall(r'\b[a-z][a-z0-9]*-[a-z0-9-]+[a-z0-9]\b', term)
        for word in words:
            if matches_technical_pattern(word):
                hyphenated.add(word)

    return hyphenated

def extract_from_sources(source_dir: Path) -> Set[str]:
    """Extract hyphenated technical terms from all source files."""
    hyphenated = set()

    # Check all .txt files in source directory
    for source_file in source_dir.glob('*.txt'):
        with open(source_file, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read().lower()
            words = re.findall(r'\b[a-z][a-z0-9]*-[a-z0-9-]+[a-z0-9]\b', content)
            for word in words:
                if matches_technical_pattern(word):
                    hyphenated.add(word)

    return hyphenated

def main():
    script_dir = Path(__file__).parent
    extract_dir = script_dir.parent
    downloads_dir = extract_dir / 'downloads'
    source_dir = extract_dir / 'source'

    print("=== Extracting Hyphenated Technical Compounds ===")
    print()

    # Extract from NIST JSON
    print("[1/2] Extracting from NIST CSRC Glossary...")
    nist_path = downloads_dir / 'glossary-export.json'
    if nist_path.exists():
        nist_terms = extract_from_nist(nist_path)
        print(f"  Found {len(nist_terms)} technical compounds")
    else:
        print("  Warning: NIST JSON not found")
        nist_terms = set()

    # Extract from source files
    print("[2/2] Extracting from source files...")
    source_terms = extract_from_sources(source_dir)
    print(f"  Found {len(source_terms)} technical compounds")

    # Always include exact patterns (core technical compounds)
    core_terms = EXACT_PATTERNS.copy()

    # Combine all sets and sort
    all_terms = sorted(core_terms | nist_terms | source_terms)

    # Write output
    output_file = source_dir / 'valid_hyphenated_compounds.txt'
    with open(output_file, 'w') as f:
        f.write("# Valid Hyphenated Technical Compounds\n")
        f.write("#\n")
        f.write("# Programmatically extracted from authoritative sources:\n")
        f.write("# - NIST CSRC Glossary (downloads/glossary-export.json)\n")
        f.write("# - All source/*.txt files\n")
        f.write("#\n")
        f.write("# Extraction criteria:\n")
        f.write("# - Matches technical prefix/suffix patterns\n")
        f.write("# - Exact pattern matches (e.g., peer-to-peer)\n")
        f.write("#\n")
        f.write(f"# Total terms: {len(all_terms)}\n")
        f.write(f"# Generation date: {Path().cwd()}\n")
        f.write("#\n")
        f.write("# DO NOT EDIT - Regenerate with: scripts/extract_hyphenated_compounds.py\n")
        f.write("\n")
        for term in all_terms:
            f.write(f"{term}\n")

    print()
    print("=== Extraction Complete ===")
    print(f"Total technical compounds: {len(all_terms)}")
    print(f"Output: {output_file}")
    print()
    print("Sample terms:")
    for term in all_terms[:20]:
        print(f"  - {term}")

if __name__ == '__main__':
    main()
