# Names and Brands Sources

This file records the stated provenance of the three proper-noun wordlists. The source datasets and intermediate extraction files are not committed, so contribution counts and processing notes are historical records rather than a reproducible manifest.

## Person Names

### US Social Security Administration Baby Names

- Source: US Social Security Administration (SSA)
- Page: https://www.ssa.gov/oact/babynames/
- Data: https://www.ssa.gov/oact/babynames/names.zip
- Mirror used for collection: https://github.com/hackerb9/ssa-baby-names
- Recorded contribution: about 100,364 names
- Access date: 2025-12-11
- Rights note: US federal government data is generally not protected by US copyright under 17 U.S.C. § 105. Check the SSA page and mirror for notices that apply to the files being downloaded.

SSA publishes baby names from Social Security card applications, with records dating back to 1880. The published national files omit names with fewer than five occurrences in a year. The collection record says `allnames.txt` was downloaded from the mirror and merged without popularity filtering.

Recorded download:

```bash
curl -s "https://raw.githubusercontent.com/hackerb9/ssa-baby-names/master/allnames.txt" \
  > ssa_all_names.txt
```

### Popular Names by Country Dataset

- Source: Popular Names by Country Dataset
- URL: https://github.com/sigpwned/popular-names-by-country-dataset
- License recorded by the source: CC0 1.0 Universal
- Recorded contribution: about 1,395 forenames from 106 countries
- Access date: 2025-12-11

The collection notes say names were extracted from the repository's country data, original casing and diacritics were kept in the wordlist, and case-insensitive duplicates were removed after merging with the SSA list.

## Last Names

### US Census Bureau Surnames via FiveThirtyEight

- Publisher: US Census Bureau / FiveThirtyEight
- Dataset: https://github.com/fivethirtyeight/data/tree/master/most-common-name
- Census source page: https://www.census.gov/topics/population/genealogy/data/2000_surnames.html
- Recorded contribution: about 151,670 surnames occurring at least 100 times in Census 2000
- Access date: 2025-12-11
- Rights note: the underlying Census data is a US federal government work. Review the FiveThirtyEight repository's terms for material added by the repository.

The collection record says the `name` column was extracted from `surnames.csv` and converted from uppercase to title case:

```bash
curl -s "https://raw.githubusercontent.com/fivethirtyeight/data/master/most-common-name/surnames.csv" \
  | tail -n +2 \
  | cut -d',' -f1 \
  | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}' \
  > last_names.txt
```

The current `last_names.txt` has 151,671 non-comment entries, one more than the recorded upstream count and the file header. The repository has no source snapshot or generation script that explains the extra entry.

## Brand and Company Names

The brand list was curated from rankings, public datasets, and company materials. The wordlist retains capitalization for human review, although the runtime loader lowercases every entry.

### Recorded Sources

| Source | URL | Recorded contribution | Terms note |
|---|---|---:|---|
| Interbrand Best Global Brands | https://interbrand.com/best-global-brands/ | About 100 | No redistribution license is recorded in this repository. |
| Brand Finance Global 500 | https://brandirectory.com/ | About 80 | No redistribution license is recorded in this repository. |
| Fortune 500 dataset | https://github.com/cmusam/fortune500 | Part of about 2,200 combined rows | Review the repository's current license before re-importing. |
| Forbes 2000 through Rdatasets | https://github.com/vincentarelbundock/Rdatasets | Part of about 2,200 combined rows | Review the repository and original dataset terms before re-importing. |
| Company style guides and press materials | Individual company sites | Capitalization reference | Trademarks and brand assets remain subject to their owners' rights. |

Examples recorded during review included `iPhone`, `macOS`, `eBay`, `GitHub`, `GitLab`, `LinkedIn`, `PayPal`, and `YouTube`. These examples document spelling in the source file; TextWarden's current dictionary loader does not validate capitalization.

## Recorded Merge Procedure

The person-name merge was documented as:

```bash
cat ssa_all_names.txt international_names.txt \
  | tr -d '\r' \
  | sed 's/[[:space:]]*$//' \
  | grep -v '^$' \
  | sort \
  | uniq -i \
  > person_names.txt
```

This command is a historical note. It is not wired into the Makefile, and the two input files are not committed.

## Current Output Counts

Counts were verified from `GrammarEngine/wordlists/` on 2026-08-11, excluding comments and blank lines.

| Output | Entries | Case-insensitive unique entries |
|---|---:|---:|
| `person_names.txt` | 100,761 | 100,761 |
| `last_names.txt` | 151,671 | 151,671 |
| `brand_names.txt` | 2,433 | 2,433 |

## Maintenance Notes

- SSA data is normally updated annually. No automatic refresh is configured here.
- Country-name and company lists should be reviewed when their upstream sources change.
- For every refresh, retain the exact input snapshot or add a generation script so the next maintainer can reproduce the output.
- Source attribution is not a substitute for license review. Public availability alone does not grant redistribution rights.

Last source review: 2025-12-11. Counts verified: 2026-08-11.
