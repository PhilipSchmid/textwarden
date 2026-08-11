# Names and Brands Wordlists

TextWarden includes first names, surnames, and brand names in its local Harper dictionary. These lists reduce false spelling alerts for proper nouns. They do not enforce official capitalization: the Rust loader converts every entry to lowercase before passing it to Harper.

## Directory Structure

```text
names_extraction/
├── README.md            # Maintenance notes and current counts
└── SOURCES.md           # Source attribution and collection history

../wordlists/
├── person_names.txt     # 100,761 international first names
├── last_names.txt       # 151,671 surnames
└── brand_names.txt      # 2,433 brand and company names
```

The checked-in wordlists are the runtime inputs. This directory does not contain a regeneration script or the original downloaded datasets.

## Wordlists

### Person Names

`person_names.txt` combines names from the [US Social Security Administration baby names data](https://www.ssa.gov/oact/babynames/) and the [Popular Names by Country Dataset](https://github.com/sigpwned/popular-names-by-country-dataset). The source record says the latter covers 106 countries.

Examples include `James`, `Maria`, `Muhammad`, `Aisha`, and `Kenji`.

### Last Names

`last_names.txt` is based on US Census 2000 surname data published through [FiveThirtyEight's most-common-name dataset](https://github.com/fivethirtyeight/data/tree/master/most-common-name). The upstream description covers surnames recorded at least 100 times.

The checked-in file contains 151,671 entries. Its header and the historical source notes say 151,670, so that one-entry difference should be reconciled before the next refresh.

### Brand Names

`brand_names.txt` combines company and product names recorded from the Fortune 500, Forbes Global 2000, Interbrand, Brand Finance, and company materials. It contains names such as `Apple`, `Microsoft`, `Coca-Cola`, and `Mercedes-Benz`.

The file retains display casing for review, but runtime matching is case-insensitive. Trademark rights remain with their owners; inclusion is not an endorsement.

## Current Counts

Counts below exclude blank lines and comments. They were verified from the committed files on 2026-08-11.

| Wordlist | Entries | Case-insensitive unique entries |
|---|---:|---:|
| First names | 100,761 | 100,761 |
| Last names | 151,671 | 151,671 |
| Brand names | 2,433 | 2,433 |
| **Total** | **254,865** | **254,865 within the three individual files** |

The total does not claim that the three categories have no terms in common.

## Runtime Loading

[`GrammarEngine/src/slang_dict.rs`](../src/slang_dict.rs) embeds each file with `include_str!()` and calls `load_words_lowercase_only`. The loader skips blank lines and lines beginning with `#`, then stores each remaining entry in lowercase.

```rust
WordlistCategory::PersonNames => {
    const PERSON_NAMES: &str = include_str!("../wordlists/person_names.txt");
    load_words_lowercase_only(PERSON_NAMES)
}
```

The brand, first-name, and last-name categories can be enabled independently through the grammar engine configuration.

## Updating the Lists

No automated update command is checked in. Treat a refresh as a source-data change:

1. Record the source URL, license or terms, access date, and extraction method in [SOURCES.md](SOURCES.md).
2. Rebuild the relevant list from the recorded source data. Keep one entry per line; comments must begin with `#`.
3. Remove blank entries and case-insensitive duplicates.
4. Recount the committed file and update this README.
5. Run the GrammarEngine tests before committing.

Do not add a source merely because it is publicly accessible. Confirm that its terms permit the intended use and redistribution.

## See Also

- [Source attribution and collection notes](SOURCES.md)
- [Slang and abbreviations](../slang_extraction/README.md)
- [IT terminology](../it_terminology_extraction/README.md)

Last source review: 2025-12-11. Counts verified: 2026-08-11.
