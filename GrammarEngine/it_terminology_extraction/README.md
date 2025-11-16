# IT Terminology Wordlist Extraction

Comprehensive documentation for the IT terminology wordlist generation system used by the Gnau grammar checker.

## Quick Start

Regenerate the wordlist from project root:
```bash
make update-terminology
```

Or manually:
```bash
cd GrammarEngine/it_terminology_extraction/scripts
./regenerate_wordlist.sh
```

## Directory Structure

```
it_terminology_extraction/
├── source/              # Manually curated source files (✓ in git)
│   ├── protocols.txt              # IANA protocol names
│   ├── services.txt               # IANA service names
│   ├── security_terms.txt         # RFC 4949 security glossary
│   ├── linux_syscalls.txt         # Linux kernel syscalls (377)
│   ├── linux_bpf.txt              # BPF/eBPF subsystem (173)
│   ├── linux_filesystems.txt      # Linux filesystems (90)
│   ├── nist_terms.txt             # NIST CSRC Glossary (6,391)
│   ├── mdn_glossary.txt           # MDN web tech glossary
│   ├── stackoverflow_survey.txt   # Stack Overflow developer survey
│   ├── stackoverflow_tags.txt     # Stack Overflow top tags
│   ├── cncf_technologies.txt      # CNCF Landscape projects
│   └── languages.txt              # GitHub Linguist languages
│
├── scripts/             # Build scripts (✓ in git)
│   ├── regenerate_wordlist.sh     # Main regeneration script
│   └── split_hyphens.sh           # Intelligent hyphen splitter
│
├── downloads/           # Downloaded raw files (✗ not in git)
│   └── ...              # Large source files, regenerated on demand
│
├── build/               # Build artifacts (✗ not in git)
│   └── ...              # Temporary intermediate files
│
└── IT_SOURCES.md        # Detailed source documentation
```

## Output

Generated in `GrammarEngine/wordlists/` directory:
- **it_terminology.txt** - 10,041 unique IT terms

## Current Statistics (v2.2)

- **Total Sources**: 12 authoritative sources
- **Final Unique Terms**: 10,041

### Breakdown by Source

| Source | Terms | % of Final |
|--------|-------|------------|
| NIST CSRC Glossary | 6,174 | 61.5% |
| CNCF Landscape (split) | 3,067 | 30.5% |
| GitHub Linguist (split) | 1,564 | 15.6% |
| IANA Services | 739 | 7.4% |
| Linux System Calls | 377 | 3.8% |
| Linux BPF/eBPF | 173 | 1.7% |
| Others | ~500 | ~5% |

*Note: Percentages exceed 100% due to overlap before deduplication*

## Key Features

### 1. Intelligent Hyphen Splitting

Differentiates between:
- **Vendor-product names** → Split: `apache-kafka` → `apache` + `kafka`
- **Technical compounds** → Keep: `api-gateway`, `just-in-time`, `server-side`

80+ valid hyphenated technical terms preserved in `scripts/split_hyphens.sh`.

### 2. Comprehensive Coverage

- **Programming**: Languages, frameworks, tools from GitHub Linguist + CNCF
- **Networking**: IANA protocols and services
- **Security**: RFC 4949 + NIST CSRC Glossary (cryptography, authentication, compliance)
- **Linux Kernel**: Syscalls, BPF/eBPF, filesystems from official kernel sources
- **Web Tech**: MDN Glossary
- **Industry**: Stack Overflow survey data

### 3. 100% Reproducible

All extractions are programmatic with documented commands. No manual curation.

## Processing Pipeline

```
source/*.txt → split_hyphens.sh → build/*_split.txt
                                          ↓
                                   combine & filter
                                          ↓
                          sort | dedupe | lowercase
                                          ↓
                              it_terminology.txt
```

**Filters applied:**
1. Lowercase conversion
2. Character validation: `[a-z0-9_-]` only
3. Length: 2-40 characters
4. Common English word removal (a, an, the, is, etc.)
5. Deduplication

## License Compliance

All sources are from public domain or permissively licensed data:

| Source | License |
|--------|---------|
| IANA (Protocols & Services) | Public Domain |
| RFC 4949 | Public Domain |
| NIST CSRC Glossary | Public Domain (US Gov) |
| GitHub Linguist | MIT |
| CNCF Landscape | CC-BY-4.0 |
| Stack Overflow | ODbL / CC-BY-SA 4.0 |
| MDN Glossary | CC-BY-SA 2.5 |
| Linux Kernel | GPLv2 (data compilation) |

**This compilation is licensed under MIT** with proper attribution.

## Update Schedule

- **IANA registries**: Quarterly
- **Stack Overflow Survey**: Annual (May)
- **GitHub Linguist**: Quarterly
- **CNCF Landscape**: Semi-annual (June & December)
- **Linux Kernel**: Quarterly (syscalls, BPF features)
- **NIST CSRC**: Semi-annual
- **RFC/MDN glossaries**: Semi-annual

**Last Updated**: 2025-11-16
**Next Scheduled Update**: 2026-02-16

## Version History

### v2.1 (2025-11-16)
- Added 6,391 NIST cybersecurity/privacy terms
- Total: 10,193 terms (up from 4,529)

### v2.0 (2025-11-16)
- Added 377 Linux syscalls, 173 BPF terms, 90 filesystems
- Implemented intelligent hyphen splitting
- Removed manual curation
- Total: 4,529 terms (up from 3,915)

### v1.0 (2025-11-15)
- Initial release with 10 sources
- 3,915 terms with manual curation

## Contributing

To suggest additions or corrections:

1. Open an issue at: https://github.com/PhilipSchmid/gnau/issues
2. Provide the term(s) with justification
3. Reference a reliable source (IANA, RFC, official docs, etc.)
4. Terms reviewed and added in next scheduled update

## Detailed Documentation

For complete extraction methodology, source URLs, and command-line examples, see:
- **IT_SOURCES.md** (in this directory) - Full technical documentation
