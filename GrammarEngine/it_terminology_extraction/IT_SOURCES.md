# IT Terminology Sources

This file records the provenance of `GrammarEngine/wordlists/it_terminology.txt`. It describes the checked-in source snapshots, not a live mirror of each upstream project.

## Current Snapshot

- **Source retrieval date recorded in the files:** 2025-11-16
- **Wordlist generation:** v2.2
- **Final output:** 10,041 sorted, unique entries
- **Hyphenated compounds preserved:** 166
- **Upstream licensing pages reviewed:** 2026-08-11

The final content is reproducible from this repository. Set the locale to reproduce the checked-in sort order:

```bash
LC_ALL=en_US.UTF-8 GrammarEngine/it_terminology_extraction/scripts/regenerate_wordlist.sh
```

There is no `make update-terminology` target. The script above rebuilds from committed snapshots and does not fetch newer upstream data. A different locale can produce the same 10,041 terms in a different byte order because the script uses the host `sort` collation.

## Source Inventory

Counts below are non-comment, non-empty entries in each checked-in source file. They are not additive: hyphen splitting changes two inputs, filters remove malformed entries, and many terms overlap.

| Source snapshot | Checked-in entries | Recorded upstream | Terms or status |
|---|---:|---|---|
| `protocols.txt` | 146 | [IANA Protocol Numbers](https://www.iana.org/assignments/protocol-numbers/protocol-numbers.txt) | IANA protocol registry; CC0 licensing statement |
| `services.txt` | 739 | [IANA Service Names and Port Numbers](https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.csv) | IANA protocol registry; CC0 licensing statement |
| `security_terms.txt` | 98 | [RFC 4949](https://www.rfc-editor.org/rfc/rfc4949.txt) | IETF Trust copyright; distribution is unlimited |
| `languages.txt` | 1,188 | [GitHub Linguist](https://github.com/github-linguist/linguist) | MIT for repository files other than separately licensed grammars |
| `cncf_technologies.txt` | 1,687 | [CNCF Landscape](https://github.com/cncf/landscape) | `landscape.yml` is available under CC BY 4.0; logos are not imported |
| `stackoverflow_survey.txt` | 129 | [Stack Overflow Developer Survey 2024](https://survey.stackoverflow.co/2024/) | Survey results published under ODbL |
| `stackoverflow_tags.txt` | 106 | [Stack Exchange Data Explorer](https://data.stackexchange.com/stackoverflow) | Stack Exchange public data; attribution and CC BY-SA terms apply |
| `mdn_glossary.txt` | 106 | [MDN Glossary](https://developer.mozilla.org/en-US/docs/Glossary) | MDN documentation is CC BY-SA 2.5 or later unless marked otherwise |
| `linux_syscalls.txt` | 377 | [Linux source tree](https://github.com/torvalds/linux) | Names extracted from GPL-2.0 kernel source files |
| `linux_bpf.txt` | 173 | [Linux source tree](https://github.com/torvalds/linux) | BPF names extracted from kernel headers |
| `linux_filesystems.txt` | 90 | [Linux source tree](https://github.com/torvalds/linux) | Filesystem names extracted from kernel configuration and headers |
| `nist_terms.txt` | 6,174 | [NIST CSRC Glossary](https://csrc.nist.gov/glossary) | NIST public information; attribution is requested and third-party notices may still apply |

## 1. IANA Protocol Registries

### Protocol Numbers

- **Snapshot:** `source/protocols.txt`
- **Upstream:** <https://www.iana.org/assignments/protocol-numbers/protocol-numbers.txt>
- **Recorded retrieval:** 2025-11-16
- **Entries:** 146

The snapshot keeps normalized protocol identifiers such as `tcp`, `udp`, `icmp`, `esp`, `gre`, and `sctp`.

### Service Names and Port Numbers

- **Snapshot:** `source/services.txt`
- **Upstream:** <https://www.iana.org/assignments/service-names-port-numbers/service-names-port-numbers.csv>
- **Recorded retrieval:** 2025-11-16
- **Entries:** 739

The recorded extraction selected named services on ports 0-1024 plus a small set of common development, database, cache, search, and web ports. The snapshot includes identifiers such as `http`, `https`, `ssh`, `imap`, `postgresql`, and `redis`.

IANA and IETF place applicable rights in protocol registry data under the [CC0 1.0 dedication](https://www.iana.org/help/licensing-terms).

## 2. RFC 4949 Security Terms

- **Snapshot:** `source/security_terms.txt`
- **Upstream:** <https://www.rfc-editor.org/rfc/rfc4949.txt>
- **Publication:** August 2007
- **Entries:** 98

The snapshot is a small list of identifiers associated with the glossary, including `ipsec`, `kerberos`, `aes`, `rsa`, `pki`, `tls`, `x509`, and `hmac`.

RFC 4949 is Copyright © 2007 IETF Trust and says distribution is unlimited. It is not described here as public domain.

## 3. GitHub Linguist

- **Snapshot:** `source/languages.txt`
- **Upstream file:** <https://raw.githubusercontent.com/github-linguist/linguist/main/lib/linguist/languages.yml>
- **Repository:** <https://github.com/github-linguist/linguist>
- **Recorded revision:** `main` on 2025-11-16
- **Raw entries:** 1,188
- **Entries after `split_hyphens.sh`:** 1,564, with 1,222 unique values before cross-source deduplication

The snapshot contains language names and aliases normalized to lowercase, hyphenated identifiers. The Linguist repository uses the MIT license for its own files; vendored language grammars retain their upstream licenses. This extraction uses `languages.yml`, not the vendored grammar bodies.

Recorded refresh command:

```bash
curl -s -o languages.yml \
  https://raw.githubusercontent.com/github-linguist/linguist/main/lib/linguist/languages.yml

{
  yq 'keys | .[]' languages.yml | tr -d '"'
  yq '.[] | select(.aliases != null) | .aliases[]' languages.yml | tr -d '"'
} | tr '[:upper:]' '[:lower:]' \
  | tr ' ' '-' \
  | tr -d "'" \
  | grep -v '^$' \
  | sort -u > source/languages.txt
```

## 4. CNCF Cloud Native Landscape

- **Snapshot:** `source/cncf_technologies.txt`
- **Upstream file:** <https://raw.githubusercontent.com/cncf/landscape/master/landscape.yml>
- **Repository:** <https://github.com/cncf/landscape>
- **Recorded revision:** `master` on 2025-11-16
- **Raw entries:** 1,687
- **Entries after `split_hyphens.sh`:** 3,067, with 1,820 unique values before cross-source deduplication

The snapshot contains project and product names from `landscape.yml`. That file is alternatively available under CC BY 4.0 according to the repository's license section. TextWarden does not import logos or Crunchbase records.

Recorded refresh command:

```bash
curl -s -o landscape.yml \
  https://raw.githubusercontent.com/cncf/landscape/master/landscape.yml

yq '.landscape[].subcategories[].items[].name' landscape.yml \
  | tr -d '"' \
  | grep -v '(member)' \
  | grep -v '(kcsp)' \
  | grep -v '(kcntp)' \
  | tr '[:upper:]' '[:lower:]' \
  | tr ' ' '-' \
  | tr -d "'" \
  | grep -v '^$' \
  | sort -u > source/cncf_technologies.txt
```

## 5. Stack Overflow Sources

### Developer Survey 2024

- **Snapshot:** `source/stackoverflow_survey.txt`
- **Upstream:** <https://survey.stackoverflow.co/2024/>
- **Survey fielded:** May 19-June 20, 2024
- **Entries:** 129
- **License:** Open Database License (ODbL), as recorded by Stack Overflow for the survey results

The snapshot contains selected technologies reported by the survey, not respondent records or the full survey dataset.

### Stack Overflow Tags

- **Snapshot:** `source/stackoverflow_tags.txt`
- **Upstream:** <https://data.stackexchange.com/stackoverflow>
- **Recorded query date:** 2025-11-16
- **Entries:** 106

The snapshot records selected high-frequency technical tags. Stack Exchange public data and subscriber content require attribution under the applicable CC BY-SA terms.

## 6. MDN Web Docs Glossary

- **Snapshot:** `source/mdn_glossary.txt`
- **Upstream:** <https://developer.mozilla.org/en-US/docs/Glossary>
- **Recorded extraction:** 2025-11-16
- **Entries:** 106

The snapshot contains normalized web-platform terms such as `html`, `css-grid`, `javascript`, `websocket`, `webrtc`, and `webassembly`. MDN documentation is licensed under CC BY-SA 2.5 or later unless a page says otherwise. Attribute reused material to Mozilla Contributors and link the source page.

## 7. Linux Kernel Sources

The three Linux snapshots were recorded on 2025-11-16. Their counts below come from the current files, even where an older header comment states another number.

### System calls

- **Snapshot:** `source/linux_syscalls.txt`
- **Source paths:** `arch/x86/entry/syscalls/syscall_64.tbl` and `include/linux/syscalls.h`
- **Entries:** 377

### BPF/eBPF

- **Snapshot:** `source/linux_bpf.txt`
- **Source paths:** `include/linux/bpf.h` and `include/uapi/linux/bpf.h`
- **Entries:** 173

The list covers selected program, map, attach, link, and command identifiers with the `BPF_` prefix removed where appropriate.

### Filesystems

- **Snapshot:** `source/linux_filesystems.txt`
- **Source paths:** `fs/Kconfig` and `include/uapi/linux/magic.h`
- **Entries:** 90

The Linux repository is primarily GPL-2.0. Preserve the source links and notices when refreshing these derived name lists; do not infer that every file in the kernel has an identical SPDX expression.

## 8. NIST CSRC Glossary

- **Snapshot:** `source/nist_terms.txt`
- **Upstream:** <https://csrc.nist.gov/glossary>
- **Recorded extraction:** 2025-11-16
- **Entries:** 6,174
- **Extractor:** `scripts/extract_nist_terms.py`

The extractor expects `downloads/glossary-export.json`. It reads parent terms and abbreviation/synonym fields, removes markup and punctuation, rejects long or malformed tokens, and writes lowercase words to `source/nist_terms.txt`.

```bash
python3 GrammarEngine/it_terminology_extraction/scripts/extract_nist_terms.py
```

NIST says information on its sites may be distributed or copied unless marked otherwise, requests source credit, and notes that some material can carry third-party rights. Keep the NIST attribution and review any notices bundled with a future export.

## Hyphen Handling

`scripts/split_hyphens.sh` processes the Linguist and CNCF snapshots. A hyphenated entry stays intact only when it appears in `source/valid_hyphenated_compounds.txt`; every other hyphen becomes a line break.

The current allowlist has 166 entries. `scripts/extract_hyphenated_compounds.py` rebuilds it from:

- exact patterns embedded in the script;
- recognized prefix and suffix patterns in the source snapshots;
- `downloads/glossary-export.json`, when present.

Examples:

- `apache-kafka` becomes `apache` and `kafka`.
- `peer-to-peer`, `server-side`, and `zero-knowledge` remain whole.

This is a heuristic. Review both the allowlist and the final wordlist after regeneration.

## Final Filtering

`scripts/regenerate_wordlist.sh` combines all sources and applies this effective pipeline:

```text
source snapshots
  -> split Linguist and CNCF hyphens
  -> remove comments from Linux and NIST snapshots
  -> combine and sort uniquely
  -> keep [a-z0-9][a-z0-9_-]*
  -> keep lengths 2 through 40
  -> remove the script's common-word stop list
  -> GrammarEngine/wordlists/it_terminology.txt
```

Running that pipeline against the current snapshots produces 10,041 entries. With `LC_ALL=en_US.UTF-8`, their order matches the checked-in file.

## Attribution Record

```text
TextWarden IT terminology wordlist

Sources include IANA protocol registries, RFC 4949, GitHub Linguist,
CNCF Cloud Native Landscape, Stack Overflow Developer Survey 2024,
Stack Exchange Data Explorer tags, MDN Web Docs, Linux kernel source,
and the NIST CSRC Glossary.

Full source URLs, recorded retrieval dates, processing notes, and license
references: GrammarEngine/it_terminology_extraction/IT_SOURCES.md
```

This file records provenance; it is not legal advice. The inputs do not share one license, so a blanket claim that the combined wordlist is MIT-licensed would be inaccurate.

## Refresh Checklist

1. Fetch one upstream source and pin its revision or retrieval date.
2. Confirm its current reuse and attribution terms.
3. Normalize it into the corresponding `source/*.txt` file.
4. Regenerate the wordlist with `LC_ALL=en_US.UTF-8 scripts/regenerate_wordlist.sh`.
5. Review the output diff and confirm the 2-40 character filter did not hide an extraction mistake.
6. Update the counts and retrieval notes here and in `README.md`.

## Historical Outputs

- **v2.2:** 10,041 entries after NIST cleanup and generated compound handling
- **v2.1:** 10,193 entries after the first NIST import
- **v2.0:** 4,529 entries after Linux sources and hyphen splitting
- **v1.0:** 3,915 entries from the initial source set
