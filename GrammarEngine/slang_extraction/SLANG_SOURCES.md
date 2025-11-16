# Internet Slang Dictionary Sources

This document tracks the sources used to compile the slang dictionaries for gnau's grammar engine.

## Internet Abbreviations Dictionary (`internet_abbreviations.txt`)

### Primary Sources

1. **Messente Blog** - "Top 250+ Text Abbreviations, Acronyms and Short Form Words"
   - URL: https://messente.com/blog/text-abbreviations
   - Accessed: 2025-01-14
   - Coverage: 250+ text abbreviations including BTW, FYI, LOL, ASAP, etc.
   - License: Public educational content

2. **Preply Blog** - "100+ Coolest Internet Abbreviations of 2025"
   - URL: https://preply.com/en/blog/the-most-used-internet-abbreviations-for-texting-and-tweeting/
   - Accessed: 2025-01-14
   - Coverage: 100+ modern internet abbreviations
   - License: Public educational content

3. **SimpleTexting** - "50+ most common abbreviations for text in 2024"
   - URL: https://simpletexting.com/blog/text-abbreviations/
   - Referenced: 2025-01-14
   - Coverage: Common text abbreviations
   - License: Public educational content

### Additional References

- EZ Texting - "The 117 Most Popular Text Abbreviations"
  - URL: https://www.eztexting.com/resources/sms-resources/popular-text-abbreviations

- Mobile Text Alerts - "Top 145+ Texting Abbreviations with Examples [2024]"
  - URL: https://mobile-text-alerts.com/articles/texting-abbreviations

- Content Studio - "210+ popular social media acronyms and slang you should know"
  - URL: https://contentstudio.io/blog/social-media-acronyms

## Gen Z Slang Dictionary (`genz_slang.txt`)

### Primary Sources

1. **Hugging Face Dataset** - "MLBtrio/genz-slang-dataset"
   - URL: https://huggingface.co/datasets/MLBtrio/genz-slang-dataset
   - Accessed: 2025-01-14
   - Coverage: 1,779 Gen Z slang terms with descriptions, examples, and context
   - Format: CSV with columns: Slang, Description, Example, Context
   - License: Community dataset, publicly available
   - Sources: Compiled from Kaggle collections and GitHub repositories

2. **Kaggle Dataset** - "Gen Z words and Phrases Dataset" by Tawfia Yeasmin
   - URL: https://www.kaggle.com/datasets/tawfiayeasmin/gen-z-words-and-phrases-dataset
   - Accessed: 2025-01-14
   - Coverage: 500 Gen Z slang terms, acronyms, and phrases
   - Format: CSV with Word/Phrase, Definition, Example Sentence, Popularity/Trend Level
   - License: MIT License
   - Description: Language used in digital communication and social media

3. **Kaggle Dataset** - "Chat / Internet Slang | Abbreviations | Acronyms"
   - URL: https://www.kaggle.com/datasets/gowrishankarp/chat-slang-abbreviations-acronyms
   - Accessed: 2025-01-14
   - Coverage: 3,000+ chat slang abbreviations
   - Format: CSV, JSON, TXT, PKL (acronym | expansion)
   - Source: Urban Dictionary
   - License: Unknown

4. **GitHub Repository** - "kaspercools/genz-dataset"
   - URL: https://github.com/kaspercools/genz-dataset/blob/main/genz_slang.csv
   - Accessed: 2025-01-14
   - Coverage: 146 curated Gen Z slang terms
   - Format: CSV with keyword | description
   - License: Open source
   - Examples: NGL, TFW, Sus, Ghosting, Slay, etc.

### Additional References

- Kaggle Dataset - "gen z slang" by Sadman Hasib
  - URL: https://www.kaggle.com/datasets/sadmanhasib/gen-z-slang
  - License: Apache 2.0

- SlangWise - "List of 200 Most Popular Internet Slang Words of 2025"
  - URL: https://slangwise.com/200-most-popular-internet-slangs-of-2025/

- Gabb - "2025 Teen Slang Dictionary: Decode Gen Z Lingo"
  - URL: https://gabb.com/blog/teen-slang/

## Usage and Licensing

### For Internet Abbreviations Dictionary

The internet abbreviations are compiled from publicly available educational resources. These are standard, widely-used abbreviations that are part of common internet vernacular. The compilation is:
- For educational and functional purposes
- Based on publicly documented language usage
- Not subject to copyright (facts/common usage)

### For Gen Z Slang Dictionary

The Gen Z slang dictionary combines data from:
- MIT-licensed dataset (500 terms)
- Community datasets (publicly available)
- Open source GitHub repositories

This compilation is used under fair use for educational and functional purposes as a grammar checking reference.

## Methodology

### Selection Criteria

Terms were included if they met at least one of these criteria:
1. Appeared in multiple independent sources
2. Listed in curated datasets (MIT or open source licensed)
3. Documented in 2024-2025 as actively used
4. Common enough to warrant spell-check recognition

### Processing

1. **Deduplication**: Removed duplicate terms across sources
2. **Normalization**: Standardized format (one term per line)
3. **Validation**: Cross-referenced against multiple sources
4. **Coverage**: Ensured all case variations (lowercase, UPPERCASE, Capitalized)

## Updates

This dictionary should be periodically updated to reflect:
- New slang terms entering common usage
- Deprecated terms no longer in active use
- Changes in preferred spelling or capitalization

Last updated: 2025-01-14
