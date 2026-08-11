# IT Terminology Wordlist Extraction

This directory contains the source snapshots and scripts used to build TextWarden's dictionary of programming, cloud, DevOps, networking, cybersecurity, web, and Linux terminology. The Rust grammar engine embeds the generated wordlist at compile time.

## Current Output

`GrammarEngine/wordlists/it_terminology.txt` contains **10,041 sorted, unique entries**. Blank lines and comments are not counted.

The checked-in source snapshots come from 12 collections:

- IANA protocol and service registries
- RFC 4949 security terminology
- GitHub Linguist language names and aliases
- CNCF Cloud Native Landscape project and product names
- Stack Overflow survey technologies and tags
- MDN Web Docs glossary terms
- Linux system calls, BPF/eBPF terms, and filesystem names
- NIST CSRC glossary terms and abbreviations

See [IT_SOURCES.md](IT_SOURCES.md) for the recorded URLs, retrieval dates, licenses, and extraction notes.

## Regenerate the Checked-In Wordlist

Run the script from any working directory:

```bash
LC_ALL=en_US.UTF-8 GrammarEngine/it_terminology_extraction/scripts/regenerate_wordlist.sh
```

The script rebuilds `GrammarEngine/wordlists/it_terminology.txt` from the committed files under `source/`. It does not download fresh upstream data. Refreshing a source snapshot is a separate, reviewed step.

The script relies on the host `sort` order. `LC_ALL=en_US.UTF-8` reproduces the checked-in byte order; another locale can produce the same 10,041 terms in a different order.

## Files

```text
it_terminology_extraction/
├── source/                              Checked-in normalized source snapshots
│   ├── cncf_technologies.txt
│   ├── languages.txt
│   ├── linux_bpf.txt
│   ├── linux_filesystems.txt
│   ├── linux_syscalls.txt
│   ├── mdn_glossary.txt
│   ├── nist_terms.txt
│   ├── protocols.txt
│   ├── security_terms.txt
│   ├── services.txt
│   ├── stackoverflow_survey.txt
│   ├── stackoverflow_tags.txt
│   └── valid_hyphenated_compounds.txt
├── scripts/
│   ├── extract_hyphenated_compounds.py  Rebuild the preserved-compound allowlist
│   ├── extract_nist_terms.py             Extract terms from a downloaded NIST JSON export
│   ├── regenerate_wordlist.sh            Combine, filter, sort, and publish the wordlist
│   └── split_hyphens.sh                  Split product-style names while preserving compounds
├── build/                                Ignored intermediate output
├── downloads/                            Ignored upstream downloads
├── IT_SOURCES.md                         Provenance and methodology
└── README.md
```

## Processing Rules

The regeneration script:

1. Splits unapproved hyphenated entries from the GitHub Linguist and CNCF snapshots.
2. Preserves entries listed in `source/valid_hyphenated_compounds.txt`, currently 166 terms.
3. Combines those results with the other 10 source snapshots.
4. Keeps lowercase terms that match `[a-z0-9][a-z0-9_-]*` and are 2-40 characters long.
5. Removes a small built-in list of common English function words.
6. Sorts and deduplicates the final output.

For example, `apache-kafka` becomes `apache` and `kafka`, while a recognized compound such as `server-side` stays intact.

## Reproducibility Boundary

The final 10,041-entry content is reproducible from the source snapshots committed to this repository. Use `LC_ALL=en_US.UTF-8` when byte-for-byte ordering matters. The upstream refresh process is only partly automated: NIST and compound extraction have dedicated Python scripts, while other snapshots use the commands and source notes recorded in [IT_SOURCES.md](IT_SOURCES.md).

When refreshing data:

1. Record the upstream URL, revision or retrieval date, license, and extraction command.
2. Update the relevant file under `source/`.
3. Regenerate the wordlist.
4. Review the diff for accidental prose, malformed identifiers, and overly broad terms.
5. Update the counts in both documentation files.

## Licensing and Attribution

The source material uses several different terms, including CC0, MIT, Apache-2.0 or CC BY 4.0, CC BY-SA, IETF Trust terms, and Linux kernel licensing. Do not describe the combined output as uniformly MIT-licensed. Keep the attribution records in [IT_SOURCES.md](IT_SOURCES.md), and review upstream terms when importing a new snapshot.

## History

- **v2.2 (2025-11-16):** Cleaned the NIST extraction, generated the hyphenated-compound allowlist, and produced the current 10,041-entry output.
- **v2.1 (2025-11-16):** Added the first NIST CSRC glossary extraction, producing 10,193 entries.
- **v2.0 (2025-11-16):** Added Linux kernel sources and hyphen splitting, producing 4,529 entries.
- **v1.0 (2025-11-15):** Initial 3,915-entry compilation.
