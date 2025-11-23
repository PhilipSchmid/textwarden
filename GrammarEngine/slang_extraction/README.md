# Slang and Abbreviations Wordlist Extraction

Documentation for the slang and abbreviations wordlists used by the TextWarden grammar checker.

## Overview

This directory contains manually curated slang and abbreviation wordlists from public educational sources and community datasets. These wordlists help TextWarden recognize informal internet language and modern slang that might otherwise be flagged as spelling errors.

## Directory Structure

```
slang_extraction/
├── SLANG_SOURCES.md     # Detailed source attribution and methodology
└── README.md            # This file

../wordlists/            # Final wordlists (✓ in git)
├── internet_abbreviations.txt  # 3,211 internet abbreviations
├── genz_slang.txt              # 274 Gen Z slang terms
└── it_terminology.txt          # 10,041 IT technical terms
```

## Wordlists

### Internet Abbreviations (3,211 terms)

Common internet abbreviations and initialisms used in digital communication.

**Examples:** btw, fyi, lol, asap, imho, afaict, brb, ttyl, imo, fwiw

**Sources:**
- Messente Blog - "Top 250+ Text Abbreviations"
- Preply Blog - "100+ Coolest Internet Abbreviations of 2025"
- SimpleTexting - "50+ most common abbreviations for text in 2024"

**License:** Public educational content

### Gen Z Slang (274 terms)

Modern slang words and phrases used in informal digital communication and social media.

**Examples:** ghosting, sus, slay, vibe, lit, flex, salty, cringe, savage, yeet

**Sources:**
- Hugging Face Dataset - "MLBtrio/genz-slang-dataset" (1,779 terms with descriptions)
- Kaggle Dataset - "Gen Z words and Phrases Dataset" (MIT License, 500 terms)
- Kaggle Dataset - "Chat / Internet Slang | Abbreviations" (3,000+ terms)
- GitHub Repository - "kaspercools/genz-dataset" (146 curated terms)

**License:** MIT License + Community datasets (publicly available)

### IT Terminology (10,041 terms)

Technical IT terms from authoritative sources covering cloud, DevOps, programming, networking, security, and system administration.

**Examples:** kubernetes, docker, nginx, api, json, http, tcp, ssh, firewall, encryption, python, javascript, chmod

**Sources:**
- NIST Cybersecurity Glossary (CSRC)
- IANA Protocol/Service Names
- Linux System Calls and Commands
- CNCF Technologies
- GitHub Linguist Programming Languages
- And more (see ../it_terminology_extraction/README.md)

**License:** Public domain / Open source terms

## Current Statistics

- **Total Wordlists**: 3
- **Internet Abbreviations**: 3,211 terms
- **Gen Z Slang**: 274 terms
- **IT Terminology**: 10,041 terms
- **Total Terms**: 13,526 unique entries

## Usage

These wordlists are directly referenced by the TextWarden grammar engine via `include_str!()` in `src/slang_dict.rs`:

```rust
WordlistCategory::InternetAbbreviations => {
    const ABBREVIATIONS: &str = include_str!("../wordlists/internet_abbreviations.txt");
    load_words_lowercase_only(ABBREVIATIONS)
}
WordlistCategory::GenZSlang => {
    const GENZ_SLANG: &str = include_str!("../wordlists/genz_slang.txt");
    load_words_lowercase_only(GENZ_SLANG)
}
WordlistCategory::ITTerminology => {
    const IT_TERMS: &str = include_str!("../wordlists/it_terminology.txt");
    load_words_lowercase_only(IT_TERMS)
}
```

## Updating Wordlists

### Manual Updates

Since these are curated wordlists, they are manually updated:

1. Edit the wordlist files directly:
   - `../wordlists/internet_abbreviations.txt`
   - `../wordlists/genz_slang.txt`
   - `../wordlists/it_terminology.txt`

2. Format: One term per line
   ```
   # Comments start with #
   term1
   term2
   ```

3. Harper's spell checker automatically matches all case variations when words are stored in lowercase

### Adding New Sources

When adding new sources:

1. Update `SLANG_SOURCES.md` with:
   - Source name and URL
   - License information
   - Number of terms contributed
   - Access date

2. Add terms to appropriate source file

3. Remove duplicates

4. Update statistics in this README

## Methodology

Terms are included if they meet these criteria:

1. Appeared in multiple independent sources
2. Listed in curated datasets (MIT or open source licensed)
3. Documented in 2024-2025 as actively used
4. Common enough to warrant spell-check recognition

## Future Wordlists

Potential expansions:
- Regional slang variations
- Gaming terminology
- Social media platform-specific terms
- Professional jargon (business, academic, etc.)

## See Also

- **SLANG_SOURCES.md** - Detailed source attribution and methodology
- **../it_terminology_extraction/** - IT terminology wordlist system
- **../wordlists/** - Generated wordlist output directory

## Last Updated

2025-11-16
