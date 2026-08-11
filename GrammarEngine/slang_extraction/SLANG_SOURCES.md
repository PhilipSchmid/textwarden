# Slang and Abbreviations Sources

This file records the stated sources behind TextWarden's internet abbreviation and Gen Z slang wordlists. The downloaded datasets and intermediate extraction files are not committed, so the coverage figures and processing steps below are provenance notes, not a reproducible manifest.

## Internet Abbreviations (`internet_abbreviations.txt`)

The committed wordlist header identifies the Kaggle Chat / Internet Slang dataset as its direct source. The other pages were recorded as references during curation.

### Recorded Sources

| Source | URL | Recorded coverage | Access record | License status in this repository |
|---|---|---:|---|---|
| Chat / Internet Slang, Abbreviations, Acronyms | https://www.kaggle.com/datasets/gowrishankarp/chat-slang-abbreviations-acronyms | 3,000+ entries | 2025-01-14 | Unknown; review the current Kaggle dataset terms before re-importing. |
| Messente, “Top 250+ Text Abbreviations” | https://messente.com/blog/text-abbreviations | 250+ examples | Accessed 2025-01-14 | No redistribution license recorded. |
| Preply, “Internet Abbreviations” | https://preply.com/en/blog/the-most-used-internet-abbreviations-for-texting-and-tweeting/ | 100+ examples | Accessed 2025-01-14 | No redistribution license recorded. |
| SimpleTexting, “Text Abbreviations” | https://simpletexting.com/blog/text-abbreviations/ | 50+ examples | Referenced 2025-01-14 | No redistribution license recorded. |
| EZ Texting, “Popular Text Abbreviations” | https://www.eztexting.com/resources/sms-resources/popular-text-abbreviations | 117 examples recorded | Reference only | No redistribution license recorded. |
| Mobile Text Alerts, “Texting Abbreviations” | https://mobile-text-alerts.com/articles/texting-abbreviations | 145+ examples recorded | Reference only | No redistribution license recorded. |
| ContentStudio, “Social Media Acronyms” | https://contentstudio.io/blog/social-media-acronyms | 210+ examples recorded | Reference only | No redistribution license recorded. |

The current output contains 3,211 entries, all case-insensitively unique.

## Gen Z Slang (`genz_slang.txt`)

### Recorded Sources

1. [MLBtrio/genz-slang-dataset on Hugging Face](https://huggingface.co/datasets/MLBtrio/genz-slang-dataset)
   - Recorded coverage: 1,779 terms with descriptions, examples, and context
   - Recorded format: CSV columns for slang, description, example, and context
   - Accessed: 2025-01-14
   - License status: public availability was recorded, but no explicit license was captured in this repository. Check the dataset card before re-importing.

2. [Gen Z Words and Phrases Dataset on Kaggle](https://www.kaggle.com/datasets/tawfiayeasmin/gen-z-words-and-phrases-dataset)
   - Recorded coverage: 500 terms, acronyms, and phrases
   - Recorded format: word or phrase, definition, example sentence, and popularity level
   - Accessed: 2025-01-14
   - License recorded at collection time: MIT

3. [Chat / Internet Slang, Abbreviations, Acronyms on Kaggle](https://www.kaggle.com/datasets/gowrishankarp/chat-slang-abbreviations-acronyms)
   - Recorded coverage: 3,000+ entries
   - Recorded formats: CSV, JSON, TXT, and PKL
   - Recorded source note: compiled from Urban Dictionary
   - Accessed: 2025-01-14
   - License status: unknown

4. [kaspercools/genz-dataset on GitHub](https://github.com/kaspercools/genz-dataset/blob/main/genz_slang.csv)
   - Recorded coverage: 146 terms with descriptions
   - Accessed: 2025-01-14
   - License status: no specific license was recorded. “Open source” is not enough to determine redistribution rights.

### Additional References

- [Sadman Hasib's Gen Z slang dataset on Kaggle](https://www.kaggle.com/datasets/sadmanhasib/gen-z-slang), recorded as Apache-2.0
- [SlangWise: 200 Internet Slang Words](https://slangwise.com/200-most-popular-internet-slangs-of-2025/), no license recorded
- [Gabb: Teen Slang Dictionary](https://gabb.com/blog/teen-slang/), no license recorded

The current output has 274 entries and 262 case-insensitive unique values. The loader lowercases every entry, so case-only variants become duplicate dictionary rows at runtime.

## Recorded Selection and Processing

The original notes described this selection policy:

- Include a term when it appeared in multiple independent sources, came from a curated dataset, or was judged common enough to prevent a noisy spelling alert.
- Prefer terms documented as current in 2024 or 2025.
- Normalize to one term per line and cross-check spelling across sources.

The repository does not contain the raw datasets or a script that proves those steps for the current outputs. It also does not fully satisfy the recorded deduplication step: `genz_slang.txt` contains 11 normalized values that appear more than once, accounting for 12 excess entries.

## Rights and Maintenance

This document preserves attribution; it does not grant rights to the source material. Common words and abbreviations may not themselves be copyrightable, but articles, dataset selection, descriptions, and compilations can carry separate rights. Before refreshing either list:

1. Check the current license or terms for every imported source.
2. Save the exact source snapshot or add a reproducible extraction script.
3. Record which source contributed each imported row when practical.
4. Remove case-insensitive duplicates, then verify counts from the output file.

Review the lists periodically for new terms, outdated spellings, and source changes.

Last source review: 2025-01-14. Counts verified: 2026-08-11.
