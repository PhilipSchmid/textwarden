# Contributing to TextWarden

TextWarden is a Swift and Rust macOS grammar checker. Contributions are welcome, especially focused fixes for Accessibility behavior, app compatibility, grammar quality, and tests.

## Prerequisites

- macOS 26 for the complete Swift test suite
- Xcode 26 or later with Command Line Tools
- Rust 1.95 or later through [rustup](https://rustup.rs/)
- Intel and Apple Silicon Rust targets
- Homebrew
- SwiftFormat, SwiftLint, and Pandoc

The shipped app targets macOS 14. macOS 26 and Xcode 26 are required for developing and testing its Apple Foundation Models integration.

Install the command-line dependencies:

```bash
rustup update stable
rustup target add x86_64-apple-darwin aarch64-apple-darwin
brew install swiftformat swiftlint pandoc
```

Check the toolchain:

```bash
xcodebuild -version
rustc --version
rustup target list --installed
swiftformat --version
swiftlint --version
pandoc --version
```

## Set Up the Project

```bash
git clone https://github.com/PhilipSchmid/textwarden.git
cd textwarden
make build
make test
open TextWarden.xcodeproj
```

`make build` compiles the Rust grammar engine for Intel and Apple Silicon, creates a universal static library, generates the Help Book from Markdown, and builds the Swift app. See [BUILD.md](BUILD.md) for individual targets and troubleshooting.

## Repository Layout

```text
textwarden/
├── Sources/                # Swift app
│   ├── Accessibility/      # Focused-element monitoring and AX helpers
│   ├── App/                # Coordination, Foundation Models, updates, lifecycle
│   ├── AppConfiguration/   # Per-app strategies and behavior
│   ├── ContentParsers/     # Text extraction for supported editors
│   ├── Positioning/        # Character-bound and overlay positioning
│   ├── SketchPad/          # Built-in writing editor
│   ├── TextReplacement/    # Validated correction application
│   ├── UI/                 # SwiftUI and AppKit views
│   └── Utilities/          # Shared conversion and readability helpers
├── GrammarEngine/          # Rust library and Harper integration
├── Tests/                  # Swift unit, integration, contract, and performance tests
├── Scripts/                # Build, release, reset, and Help Book scripts
└── docs/                   # Internal and application-specific documentation
```

Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing module boundaries, dependency flow, app behavior, or Accessibility strategy selection.

## Development Workflow

Never commit directly to `main`.

1. Create a branch from the current `main` using `<type>/<short-description>`, such as `fix/outlook-positioning` or `feat/app-support`.
2. Make one focused change at a time.
3. Run `make run` after a code change so you test the installed app, not a stale build.
4. Test the affected host apps manually when Accessibility behavior changes.
5. Run `make ci-check` before committing.
6. Create a pull request targeting `main`.

Useful commands:

| Command | Purpose |
| --- | --- |
| `make run` | Build, install to `/Applications`, and launch |
| `make test` | Run Rust and selected Swift tests |
| `make ci-check` | Run all formatting, linting, testing, and build gates |
| `make reset-onboarding` | Show onboarding on the next launch |
| `make fmt` | Format Rust and Swift sources |
| `make lint` | Run Clippy and SwiftLint |

## Accessibility Permission

TextWarden needs Accessibility permission to inspect and update text in other apps. Enable the exact build you are testing under **System Settings → Privacy & Security → Accessibility**. A build at a different path or with a different signature may need permission again.

## Adding or Fixing App Support

Most app-specific behavior lives in three places:

- `Sources/AppConfiguration/AppRegistry.swift` selects parsers, positioning strategies, replacement methods, and feature flags.
- `Sources/AppConfiguration/AppBehaviorRegistry.swift` registers isolated overlay, timing, scrolling, coordinate, and text-index behavior.
- `Sources/ContentParsers/` handles editors whose exposed text needs app-specific parsing.

Unknown apps are profiled through Accessibility probes and cached in `~/Library/Application Support/TextWarden/strategy-profiles.json`. Profiles expire after seven days. Add explicit support when automatic detection cannot capture an app's quirks or when it needs dedicated parsing, replacement, or positioning.

When adding an app:

1. Find its bundle identifier in **Preferences → Applications**, with `osascript -e 'id of app "AppName"'`, or with `mdls -name kMDItemCFBundleIdentifier /Applications/AppName.app`.
2. Inspect the editor with Xcode's Accessibility Inspector. Check `AXValue`, selection attributes, range bounds, text-marker support, focus behavior, and what changes while typing or scrolling.
3. Add the narrowest configuration or behavior needed. Do not copy another app's quirks without confirming them.
4. Register any new `AppBehavior` and `AppConfiguration` explicitly.
5. Add regression tests under `Tests/Unit/` and an application note under `docs/applications/`.
6. Test typing, scrolling, focus changes, multiple windows, replacement, emoji, rich text, and external displays where relevant.

Terminal apps are the only fixed paused-by-default set in `UserPreferences`. Other unknown apps are paused when first discovered and can be enabled by the user; there is no separate hidden-app registry.

## Code Style

### Swift

- Use `Logger`, never `print()`.
- Do not force-unwrap Accessibility values or external data.
- Keep UI state on the main actor and move blocking work off the main thread.
- Check `Sources/Utilities/` before adding text-index, coordinate, or other shared helpers.
- Use named constants from `TimingConstants`, `GeometryConstants`, or `UIConstants` when the value is shared or behavior-defining.

### Rust

- Return `Result<T, E>` from fallible library code.
- Propagate errors instead of panicking across the library or FFI boundary.
- Keep the Swift bridge surface small and validate Swift inputs.
- Run `cargo fmt`, Clippy, and locked tests through `make ci-check`.

Comments should explain why a constraint or workaround exists. Delete dead code instead of commenting it out.

## Logging and Privacy

Writing may contain credentials, private messages, and customer data. Do not put user text in Info, Warning, Error, or Critical logs. Prefer lengths, ranges, identifiers, timing, and result counts.

```swift
// Avoid: exposes user text
Logger.debug("Processing: \(userText)", category: Logger.analysis)

// Prefer: records enough context without the text
Logger.debug("Processing \(userText.count) characters", category: Logger.analysis)
```

Use the existing categories: `general`, `permissions`, `analysis`, `accessibility`, `ffi`, `llm`, `ui`, `performance`, `errors`, `lifecycle`, and `rust`.

Debug and Trace logs may include text for targeted troubleshooting. Keep those cases deliberate and make the privacy consequence visible to the user.

## Commit Messages

Use [Conventional Commits](https://www.conventionalcommits.org/) with one of these types:

`feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `chore`, or `ci`.

Write an imperative subject with no period:

```text
fix: Correct underline positioning in Slack
```

Every commit must be cryptographically signed and include the Developer Certificate of Origin sign-off created by Git:

```bash
git commit -s -S -m "fix: Correct underline positioning in Slack"
```

Do not type a `Signed-off-by`, `Co-Authored-By`, or other trailer manually.

## Pull Requests

- Keep the pull request focused and describe the user-visible result.
- Link the issue when one exists.
- Include manual test context for app-specific behavior.
- Make sure `make ci-check` passes.
- Keep history linear; maintainers use rebase merge.

## Bug Reports and Feature Requests

Use the [bug report template](https://github.com/PhilipSchmid/textwarden/issues/new/choose) for defects. Include the TextWarden version, macOS version, host app, exact steps, expected behavior, actual behavior, and a diagnostic export when appropriate.

Use [GitHub Discussions](https://github.com/PhilipSchmid/textwarden/discussions) for feature requests and questions.

## Releases

Releases are maintainer-only because production builds require Developer ID signing, notarization credentials, and the Sparkle signing key. Releases still go through a pull request.

```bash
git switch -c release/vX.Y.Z main
make release VERSION=X.Y.Z
git push -u origin HEAD
git push --tags
gh pr create --title "Release vX.Y.Z" --body "Release vX.Y.Z"
```

After the release pull request is merged:

```bash
make release-upload VERSION=X.Y.Z
```

Versions follow Semantic Versioning, including `alpha`, `beta`, and `rc` prerelease identifiers.
