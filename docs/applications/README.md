# Application-Specific Documentation

This folder contains detailed documentation for applications that require special handling in TextWarden.

## Contents

| Application | Description |
|-------------|-------------|
| [SLACK.md](SLACK.md) | Quill Delta format, Chromium Pickle, format-preserving replacement, positioning strategy |

## Adding New Documentation

When adding special handling for a new application:

1. Create `<APP_NAME>.md` in this folder
2. Document the app-specific format/protocol
3. Explain any special parsing or replacement logic
4. Add a link in the table above
5. Update the reference in [ARCHITECTURE.md](../../ARCHITECTURE.md)
