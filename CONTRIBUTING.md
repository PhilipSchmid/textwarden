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

Fork the repository on GitHub before cloning. If you already have write access,
you can clone the upstream repository directly.

```bash
git clone https://github.com/YOUR-USERNAME/textwarden.git
cd textwarden
git remote add upstream https://github.com/PhilipSchmid/textwarden.git
make build
make test
open TextWarden.xcodeproj
```

`make build` compiles the Rust grammar engine for Intel and Apple Silicon, creates a universal static library, generates the Help Book from Markdown, and builds the Swift app. See [BUILD.md](BUILD.md) for individual targets and troubleshooting.

Harper is pinned to a [small security patch on top of 3.3.0](https://github.com/PhilipSchmid/harper/commit/def87ae5175e6887ec370ea547c5ea9e7a1c7881). It upgrades `zip` to a patched 9.x version, validates archive header consistency, and uses the same Burn inference components directly to remove unused vulnerable backends. Grammar rules and model data are unchanged. Return to an official Harper release once it includes these fixes and no longer resolves `zip` below 9.0.5; rerun the grammar tests, archive security regression, and CPU gate before changing the pin.

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

1. Fetch `upstream` and branch from `upstream/main`. Use `<type>/<short-description>`, such as `fix/outlook-positioning` or `feat/app-support`. Use `origin/main` if you cloned the upstream repository directly.
2. Make one focused change at a time.
3. Run `make run` after a code change so you test the installed app, not a stale build.
4. Test the affected host apps manually when Accessibility behavior changes.
5. Run `make ci-check` before committing. App/runtime and dependency changes also
   require the [local CPU gate](docs/CPU_PROFILING.md#local-regression-gate); use its
   full suite for analysis, AX, timers, overlays, and performance changes.
6. Push your branch and open a pull request targeting `PhilipSchmid/textwarden:main`.

Useful commands:

| Command | Purpose |
| --- | --- |
| `make run` | Build, install to `/Applications`, and launch |
| `make test` | Run Rust and selected Swift tests |
| `make ci-check` | Run all formatting, linting, testing, and build gates |
| `make reset-onboarding` | Show onboarding on the next launch |
| `make fmt` | Format Rust and Swift sources |
| `make lint` | Run Clippy and SwiftLint |

For performance investigations, see [CPU profiling](docs/CPU_PROFILING.md): native
counter captures, Instruments flame graphs, and repeatable Mail comparisons.

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

`AppRegistry` resolves application policy from the exact bundle IDs in [`ApplicationPolicy.defaults`](Sources/AppConfiguration/ApplicationPolicy.swift). Edit that single list to add a default exclusion. Terminal apps remain resumable; ignored utilities cannot be enabled by user overrides. Other unknown apps require safe-trial consent before TextWarden reads their text. `UserPreferences` stores the user's choices.

Before excluding an app, check the [exclusion policy](docs/APPLICATION_EXCLUSIONS.md). Review writing features before excluding an entire app; use a default pause when users should retain the option to enable it. Users can suggest additions from **Preferences → Applications → More → Suggest Default Exclusion…** or the [exclusion report form](https://github.com/PhilipSchmid/textwarden/issues/new?template=application_exclusion.yml).

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

Write an imperative subject of up to 50 characters with no period. Wrap any
commit body at 72 characters.

```text
fix: Correct underline positioning in Slack
```

Every commit on your pull request needs two things:

- **DCO sign-off.** Read the [Developer Certificate of Origin](https://developercertificate.org/), then add your attestation with `git commit -s`. Use the same email in your Git identity and the commit author. A GitHub-provided noreply email works.
- **Verified signature.** Configure Git to sign with an SSH, GPG or S/MIME key GitHub can verify, then use `git commit -S`. [Configure your signing key](https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key)

```bash
git commit -s -S -m "fix: Correct underline positioning in Slack"
```

Do not type a `Signed-off-by`, `Co-Authored-By`, or other trailer manually.

The **Commit signatures** job shows which commits GitHub could not verify.
To repair your latest commit after configuring your Git identity and signing key:

```bash
git commit --amend --no-edit -s -S
git push --force-with-lease
```

For earlier commits, use an interactive rebase to amend each affected commit
you authored. Sign every commit rewritten by the rebase. Push rewritten history
only on your contribution branch. If a commit still shows **Unverified**, open
its signature details on GitHub to see what failed.

## Pull Requests

- Keep the pull request focused and describe the user-visible result.
- Link the issue when one exists.
- Include manual test context for app-specific behavior.
- Make sure `make ci-check` passes.
- Review each commit's sign-off and wait for CI before merging. Maintainers use rebase merge to keep history linear.

GitHub may ask a maintainer to approve the build and test runs for a first-time
fork contributor. This also applies to the signature check.

The commit check verifies the original PR commits. GitHub's rebase merge creates
new commits on `main` and those new commits lose the original signatures.
[GitHub's rebase and merge behavior](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/about-merge-methods-on-github#rebasing-and-merging-your-commits)

### Maintainer setup

GitHub already requires sign-offs for commits made through its web interface.
For sign-offs on commits pushed from Git, the [DCO App](https://github.com/apps/dco)
can provide a separate required check from its own GitHub App identity.
Someone with repository admin access must install it first. It skips bots and
merge commits by default. [DCO App configuration](https://github.com/dcoapp/app)

The read-only **Commit signatures** job is contributor feedback. Review
changes to workflows and verify commit signatures in the PR's **Commits** tab
when a PR changes CI. GitHub's native [Require signed commits
rule](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#require-signed-commits)
is a separate branch control. Adopting it requires a merge strategy that leaves
verified signatures on `main`.

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
