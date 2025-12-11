# Names and Brands Wordlist Extraction

Documentation for the person names, last names, and brand names wordlists used by the TextWarden grammar checker.

## Overview

This directory contains manually curated wordlists for person names and brand names. These wordlists help TextWarden recognize:
- Common person names (first names/forenames) that might otherwise be flagged as spelling errors
- Common surnames (last names) from US Census data
- Brand and product names with their correct capitalization (e.g., iPhone, macOS, LinkedIn)

## Directory Structure

```
names_extraction/
├── README.md            # This file
└── SOURCES.md           # Detailed source attribution and methodology

../wordlists/            # Final wordlists (in git)
├── person_names.txt     # ~100,000 international person names (first names)
├── last_names.txt       # ~151,000 surnames from US Census
└── brand_names.txt      # ~2,400 brand/company names
```

## Wordlists

### Person Names (~100,000 terms)

Comprehensive first names (forenames) from US historical data and international sources.

**Examples:** James, Maria, Muhammad, Aisha, Chen, Dmitri, Fatima, Hans, Kenji, Olga

**Sources:**
- US Social Security Administration Baby Names (1880-present, all 100,364 names)
  - GitHub: hackerb9/ssa-baby-names (Public Domain)
  - Original: https://www.ssa.gov/oact/babynames/names.zip
  - Contains every name given to 5+ babies in the US since 1880
- Popular Names by Country Dataset (CC0 License)
  - GitHub: sigpwned/popular-names-by-country-dataset
  - ~1,400 forenames from 106 countries worldwide

**License:** Public Domain (SSA) + CC0 (International names)

### Last Names (~151,000 terms)

Comprehensive US surnames from Census Bureau data.

**Examples:** Smith, Johnson, Williams, Brown, Jones, Garcia, Miller, Davis, Rodriguez, Martinez

**Sources:**
- US Census Bureau Surnames via FiveThirtyEight (Public Domain)
  - GitHub: fivethirtyeight/data/tree/master/most-common-name
  - Contains 151,670 surnames occurring 100+ times in US Census 2000
  - Original source: US Census Bureau

**License:** Public Domain (US Government data)

### Brand Names (~2,400 terms)

Comprehensive list of brand and company names from global rankings.

**Examples:** Apple, Microsoft, Amazon, Walmart, Samsung, Toyota, Coca-Cola, Nike, Mercedes-Benz

**Sources:**
- Fortune 500 (https://github.com/cmusam/fortune500) - US largest corporations
- Forbes Global 2000 (https://github.com/vincentarelbundock/Rdatasets) - World's largest public companies
- Interbrand Best Global Brands (https://interbrand.com/best-global-brands/)
- Brand Finance Global 500 (https://brandirectory.com/)
- Official brand style guides (for special capitalization like iPhone, eBay)

**License:** Public dataset compilations + Educational use

## Current Statistics

- **Total Wordlists**: 3
- **Person Names**: ~100,761 unique first names
- **Last Names**: ~151,670 unique surnames
- **Brand Names**: ~2,433 terms
- **Total Terms**: ~254,864 unique entries

## Usage

These wordlists are referenced by the TextWarden grammar engine via `include_str!()` in `src/slang_dict.rs`:

```rust
WordlistCategory::PersonNames => {
    const PERSON_NAMES: &str = include_str!("../wordlists/person_names.txt");
    load_words_lowercase_only(PERSON_NAMES)
}
WordlistCategory::LastNames => {
    const LAST_NAMES: &str = include_str!("../wordlists/last_names.txt");
    load_words_lowercase_only(LAST_NAMES)
}
WordlistCategory::BrandNames => {
    const BRAND_NAMES: &str = include_str!("../wordlists/brand_names.txt");
    load_words_lowercase_only(BRAND_NAMES)
}
```

## Updating Wordlists

### Manual Updates

Since these are curated wordlists, they are manually updated:

1. Edit the wordlist files directly:
   - `../wordlists/person_names.txt`
   - `../wordlists/last_names.txt`
   - `../wordlists/brand_names.txt`

2. Format: One term per line
   ```
   # Comments start with #
   Name1
   Name2
   ```

3. Harper's spell checker automatically matches all case variations when words are stored in lowercase

### Adding New Sources

When adding new sources:

1. Update `SOURCES.md` with:
   - Source name and URL
   - License information
   - Number of terms contributed
   - Access date

2. Add terms to appropriate wordlist file

3. Remove duplicates (case-insensitive)

4. Update statistics in this README

## Methodology

### Person Names (First Names)

Names are included if they meet these criteria:

1. Listed in SSA database (any name given to 5+ babies in US, 1880-present)
2. Listed in popular names by country dataset (106 countries)
3. Proper noun formatting (first letter capitalized)
4. Case-insensitive deduplication applied

### Last Names (Surnames)

Surnames are included if they meet these criteria:

1. Listed in US Census Bureau database (occurring 100+ times in Census 2000)
2. Case-insensitive deduplication applied
3. No filtering for cultural/regional origin - comprehensive coverage

### Brand Names

Brands are included if they meet these criteria:

1. Listed in Interbrand Best Global Brands or Brand Finance Global 500
2. Have notable special capitalization (not just "Company Name")
3. Technology companies and consumer brands prioritized
4. Official style guide capitalization used

## See Also

- **SOURCES.md** - Detailed source attribution and methodology
- **../wordlists/** - Generated wordlist output directory
- **../slang_extraction/** - Slang and abbreviations wordlist system
- **../it_terminology_extraction/** - IT terminology wordlist system

## Last Updated

2025-12-11
