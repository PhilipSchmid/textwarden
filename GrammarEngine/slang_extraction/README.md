# Slang and Abbreviations Wordlists

TextWarden keeps local wordlists for internet abbreviations, modern slang, and IT terminology. They reduce false spelling alerts in informal and technical writing. All entries stay on the device as part of the Rust grammar engine.

## Directory Structure

```text
slang_extraction/
├── README.md            # Maintenance notes and current counts
└── SLANG_SOURCES.md     # Source attribution and collection history

../wordlists/
├── internet_abbreviations.txt  # 3,211 entries
├── genz_slang.txt              # 274 entries
└── it_terminology.txt          # 10,041 entries
```

The IT list has its own [generation notes and scripts](../it_terminology_extraction/README.md). The abbreviation and Gen Z lists are curated manually; this directory has no regeneration script.

## Wordlists

### Internet Abbreviations

`internet_abbreviations.txt` contains 3,211 abbreviations and initialisms such as `btw`, `fyi`, `lol`, `asap`, and `afaict`. The committed file header identifies the [Chat / Internet Slang dataset on Kaggle](https://www.kaggle.com/datasets/gowrishankarp/chat-slang-abbreviations-acronyms) as its source. Other sites listed in [SLANG_SOURCES.md](SLANG_SOURCES.md) were used as references.

### Gen Z Slang

`genz_slang.txt` contains terms such as `ghosting`, `sus`, `slay`, `lowkey`, and `yeet`. Its provenance notes record several Kaggle, Hugging Face, GitHub, and web references.

The file currently has 274 non-comment entries but 262 case-insensitive unique values. Eleven normalized terms appear more than once, so a future wordlist cleanup should deduplicate the file before its count is described as unique.

### IT Terminology

`it_terminology.txt` contains 10,041 technical terms drawn from recorded sources including NIST, IANA, Linux, CNCF, GitHub Linguist, MDN, and Stack Overflow. See the [IT terminology README](../it_terminology_extraction/README.md) and [source record](../it_terminology_extraction/IT_SOURCES.md) for the actual pipeline and source-specific terms.

## Current Counts

Counts exclude blank lines and comments and were verified from the committed files on 2026-08-11.

| Wordlist | Entries | Case-insensitive unique entries |
|---|---:|---:|
| Internet abbreviations | 3,211 | 3,211 |
| Gen Z slang | 274 | 262 |
| IT terminology | 10,041 | 10,041 |
| **Total entries loaded** | **13,526** | Not measured across all three lists |

`13,526` is an entry count, not a claim that every normalized term is unique across categories.

## Runtime Loading

[`GrammarEngine/src/slang_dict.rs`](../src/slang_dict.rs) embeds the files with `include_str!()`. Its loader skips blank lines and comments, lowercases each remaining line, and adds it to Harper's dictionary.

```rust
WordlistCategory::InternetAbbreviations => {
    const ABBREVIATIONS: &str = include_str!("../wordlists/internet_abbreviations.txt");
    load_words_lowercase_only(ABBREVIATIONS)
}
```

Because the loader lowercases the entries, these lists support case-insensitive recognition. They do not validate preferred capitalization.

## Updating the Lists

For `internet_abbreviations.txt` or `genz_slang.txt`:

1. Record the source URL, license or terms, access date, and selection method in [SLANG_SOURCES.md](SLANG_SOURCES.md).
2. Keep one term per line. Comments must begin with `#`.
3. Remove blank entries and case-insensitive duplicates.
4. Recount the file and update this README.
5. Run the GrammarEngine tests before committing.

Regenerate `it_terminology.txt` with the scripts documented in the [IT terminology directory](../it_terminology_extraction/README.md), not by editing it as part of a slang refresh.

Publicly accessible articles and datasets do not automatically permit redistribution. Check the source terms before importing new material.

## See Also

- [Slang source record](SLANG_SOURCES.md)
- [IT terminology pipeline](../it_terminology_extraction/README.md)
- [Names and brands](../names_extraction/README.md)

Last source review: 2025-01-14. Counts verified: 2026-08-11.
