# Names and Brands Sources

Detailed documentation of data sources for the person names, last names, and brand names wordlists.

## Person Names Sources

### 1. US Social Security Administration Baby Names

**Source:** US Social Security Administration (SSA)
**URL:** https://www.ssa.gov/oact/babynames/
**Data URL:** https://www.ssa.gov/oact/babynames/names.zip
**GitHub Mirror:** https://github.com/hackerb9/ssa-baby-names
**License:** Public Domain (US Government work)
**Terms Contributed:** ~100,364 (all names)
**Access Date:** 2025-12-11

**Description:**
The SSA records baby names from Social Security card applications dating back to 1880. This is the most comprehensive historical record of given names in the United States. The dataset contains over 100,000 unique names - every name given to 5 or more babies in any year since 1880. Names are sorted by popularity (number of babies given each name in any single year).

**Processing:**
- Downloaded full `allnames.txt` from hackerb9/ssa-baby-names repository
- Used complete dataset (100,364 names) for comprehensive coverage
- Names are already in proper case (e.g., "James", "Mary")

**Data Format:**
```
Linda
James
Michael
Robert
...
```

### 2. Popular Names by Country Dataset

**Source:** Popular Names by Country Dataset
**URL:** https://github.com/sigpwned/popular-names-by-country-dataset
**License:** CC0 1.0 Universal (Public Domain Dedication)
**Terms Contributed:** ~1,395 forenames
**Access Date:** 2025-12-11

**Description:**
A curated dataset of popular forenames from 106 countries worldwide, compiled from official government statistics and authoritative sources. Includes names from:
- Europe (Western, Eastern, Nordic, Mediterranean)
- Americas (North, Central, South)
- Asia (East, South, Southeast, Central, West)
- Africa (North, Sub-Saharan)
- Oceania (Australia, New Zealand, Pacific Islands)

**Processing:**
- Downloaded raw forenames list
- Preserved original capitalization and diacritical marks
- Merged with SSA names
- Case-insensitive deduplication applied

**Data Format:**
```
Aada
Aadhya
Aarav
...
```

## Last Names Sources

### 1. US Census Bureau Surnames (via FiveThirtyEight)

**Source:** US Census Bureau / FiveThirtyEight
**URL:** https://github.com/fivethirtyeight/data/tree/master/most-common-name
**Original Source:** US Census Bureau
**License:** Public Domain (US Government work)
**Terms Contributed:** ~151,670 surnames
**Access Date:** 2025-12-11

**Description:**
The US Census Bureau compiled surnames from Census 2000 data. This dataset includes every surname occurring 100 or more times, providing comprehensive coverage of American surnames. The data was published by FiveThirtyEight as part of their "most common name" analysis.

**Processing:**
- Downloaded `surnames.csv` from FiveThirtyEight repository
- Extracted the `name` column (surnames only)
- Converted to proper case (first letter capitalized)
- 151,670 unique surnames

**Data Format:**
```
SMITH
JOHNSON
WILLIAMS
BROWN
JONES
...
```

**Extraction Command:**
```bash
# Download and extract surnames
curl -s "https://raw.githubusercontent.com/fivethirtyeight/data/master/most-common-name/surnames.csv" \
  | tail -n +2 \
  | cut -d',' -f1 \
  | awk '{print toupper(substr($0,1,1)) tolower(substr($0,2))}' \
  > last_names.txt
```

## Brand Names Sources

### 1. Interbrand Best Global Brands

**Source:** Interbrand
**URL:** https://interbrand.com/best-global-brands/
**License:** Educational use / Brand name compilation
**Terms Contributed:** ~100 brands
**Access Date:** 2025-12-11

**Description:**
Interbrand's annual ranking of the world's most valuable brands, based on financial performance, role of brand, and brand strength. Includes major technology companies, consumer brands, and industrial corporations.

**Processing:**
- Manually extracted brand names from annual ranking
- Verified official capitalization from brand style guides
- Prioritized brands with non-standard capitalization

### 2. Brand Finance Global 500

**Source:** Brand Finance
**URL:** https://brandirectory.com/
**License:** Educational use / Brand name compilation
**Terms Contributed:** ~80 brands
**Access Date:** 2025-12-11

**Description:**
Brand Finance's annual valuation of the world's 500 most valuable brands, covering technology, retail, automotive, financial services, and more.

**Processing:**
- Cross-referenced with Interbrand list
- Added additional brands not in Interbrand ranking
- Verified official capitalization

### 3. Official Brand Style Guides

**Source:** Individual company style guides and press materials
**License:** Educational use
**Terms Contributed:** Capitalization verification

**Description:**
For brands with special capitalization (lowercase letters, camelCase, etc.), official style guides were consulted to ensure correct representation:

- **Apple:** iOS, iPad, iPhone, iPod, iTunes, macOS, tvOS, watchOS, visionOS
- **eBay:** Always lowercase "e" followed by capital "B"
- **GitHub/GitLab:** Capital G, lowercase rest, capital second word
- **LinkedIn:** Capital L, capital I
- **PayPal:** Capital P, capital P
- **YouTube:** Capital Y, capital T

## Combined Statistics

| Source | Type | Terms | License |
|--------|------|-------|---------|
| SSA Baby Names | Person Names | ~100,364 | Public Domain |
| Popular Names by Country | Person Names | ~1,395 | CC0 |
| US Census Surnames | Last Names | ~151,670 | Public Domain |
| Interbrand | Brand Names | ~100 | Educational |
| Brand Finance | Brand Names | ~80 | Educational |
| Fortune 500 + Forbes 2000 | Brand Names | ~2,200 | Public Dataset |
| **Total (deduplicated)** | **All** | **~254,864** | **Mixed** |

## License Summary

### Person Names (First Names)
- **US SSA Data:** Public Domain (US Government work, 17 U.S.C. § 105)
- **Popular Names by Country:** CC0 1.0 Universal (Public Domain Dedication)

Both sources allow unrestricted use, modification, and distribution.

### Last Names (Surnames)
- **US Census Bureau:** Public Domain (US Government work, 17 U.S.C. § 105)

### Brand Names
- **Brand names themselves:** Individual trademark holders
- **This compilation:** Educational/informational use under fair use doctrine
- Names are used for spelling recognition, not commercial endorsement

## Extraction Commands

### SSA Baby Names (via GitHub)

```bash
# Download full allnames.txt (sorted by popularity, ~100k names)
curl -s "https://raw.githubusercontent.com/hackerb9/ssa-baby-names/master/allnames.txt" \
  > ssa_all_names.txt
```

### Popular Names by Country

```bash
# Clone or download from GitHub
git clone https://github.com/sigpwned/popular-names-by-country-dataset
# Extract forenames from CSV files
```

### Merging and Deduplication

```bash
# Combine sources and deduplicate (case-insensitive)
cat ssa_all_names.txt international_names.txt \
  | tr -d '\r' \
  | sed 's/[[:space:]]*$//' \
  | grep -v '^$' \
  | sort \
  | uniq -i \
  > person_names.txt
```

## Update Schedule

- **SSA Baby Names:** Annual (data released May each year)
- **Popular Names by Country:** As needed (stable dataset)
- **Brand Names:** Annual review (new major brands, rebranding)

**Last Updated:** 2025-12-11
**Next Scheduled Update:** 2026-05-01 (after SSA 2025 release)

## References

1. Social Security Administration. "Popular Baby Names." https://www.ssa.gov/oact/babynames/
2. hackerb9. "SSA Baby Names." GitHub. https://github.com/hackerb9/ssa-baby-names
3. sigpwned. "Popular Names by Country Dataset." GitHub. https://github.com/sigpwned/popular-names-by-country-dataset
4. FiveThirtyEight. "Most Common Name." GitHub. https://github.com/fivethirtyeight/data/tree/master/most-common-name
5. US Census Bureau. "Genealogy Data: Frequently Occurring Surnames." https://www.census.gov/topics/population/genealogy/data/2000_surnames.html
6. Interbrand. "Best Global Brands." https://interbrand.com/best-global-brands/
7. Brand Finance. "Global 500." https://brandirectory.com/
8. cmusam. "Fortune 500." GitHub. https://github.com/cmusam/fortune500
9. vincentarelbundock. "Rdatasets (Forbes 2000)." GitHub. https://github.com/vincentarelbundock/Rdatasets
