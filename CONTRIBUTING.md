# Contributing to TextWarden

TextWarden is a Swift and Rust macOS grammar checker. Contributions are welcome, especially focused fixes for Accessibility behavior, app compatibility, grammar quality, and tests.

## Prerequisites

- macOS 26 for the complete Swift test suite
- Xcode 26 or later with Command Line Tools
- Rust 1.95 or later through [rustup](https://rustup.rs/)
- Intel and Apple Silicon Rust targets
- Homebrew
- SwiftFormat, SwiftLint, and Pandoc
- Node.js and Python 3 for the browser extension and developer-tool tests

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
6. Follow the [commit message](#commit-messages) and [signing requirements](#commit-sign-off-and-signatures) for every commit, including documentation and review fixes. Push your branch and open a pull request targeting `PhilipSchmid/textwarden:main`.

Useful commands:

| Command | Purpose |
| --- | --- |
| `make run` | Build, install to `/Applications`, and launch |
| `make test` | Run Rust, Swift, developer-tool, and browser extension tests |
| `make ci-check` | Run the pre-commit format, lint, test, and build checks |
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
5. Add regression tests under `Tests/Unit/`. Rebuild with `make run` and test in the host app.

   - Type the same misspelling twice, with an emoji before the second occurrence. Correct the second word and undo the edit. Check both underline positions and the resulting text.
   - Scroll a long document, move focus away and back, and clear the draft. Check that only visible text has underlines and that the empty editor has none. Exercise rich text, multiple windows, and external displays where relevant. See the [live testing guide](docs/testing/README.md).

6. Update both columns in the [Supported Apps table](README.md#supported-apps). Use `Full` when the feature works throughout the app’s normal writing surface. Reserve narrower labels and footnotes for user-visible limitations.
7. Add a Markdown guide under `docs/applications/` and link it from the [integration index](docs/applications/README.md). Include the bundle ID, host app and macOS versions tested, editor, known limits, and a short fixture with steps and expected results.

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

## Commit sign-off and signatures

Every PR commit must pass two independent checks. Use both flags in the same command.

```bash
git commit -s -S -m "fix: Correct underline positioning in Slack"
```

- **`-s` adds your DCO sign-off.** Git generates one `Signed-off-by` trailer from your configured name and email. For commits you author, use the same identity for the author and the sign-off. A GitHub-provided noreply email works. By signing off you attest to the [Developer Certificate of Origin](https://developercertificate.org/).
- **`-S` cryptographically signs the commit.** Configure an SSH, GPG, or S/MIME signing key that GitHub can verify. Check the signature on each commit in the PR’s **Commits** tab. [Configure Git’s signing key](https://docs.github.com/en/authentication/managing-commit-signature-verification/telling-git-about-your-signing-key)

Use `-s` as the sole way to add your sign-off. Omit `Co-Authored-By` trailers, including ones inserted by an AI assistant. Disable automatic co-author attribution in your commit tool and keep manual trailers out of commit messages. To see exactly what the tool wrote, run `git log -1 --format=%B`.

### Repair a commit on your PR branch

First bring your local PR branch up to date with its remote so you have any commits a maintainer added during review. If the latest commit is yours, amend it after configuring your Git identity and signing key. The editor lets you remove unwanted trailers and keep your Git-generated sign-off.

```bash
git commit --amend -s -S
```

For an earlier commit, start `git rebase -i -S upstream/main` (use `origin/main` in a direct upstream clone). Mark your affected commit as `edit`, run the amend command above, then `git rebase --continue`. The rebase’s `-S` also signs the later commits it replays. Preserve their authors and existing DCO sign-offs.

Review the rewritten messages with `git log --format=full upstream/main..HEAD`, using the same base as above. Coordinate with anyone sharing the branch, then use `git push --force-with-lease` on your PR branch. Check both **DCO** and **Commit signatures** on the new head.

## Pull Requests

- Keep the pull request focused and describe the user-visible result.
- Link the issue when one exists.
- Include manual test context for app-specific behavior.
- Make sure `make ci-check` passes.
- Review the trailers and verified signature on every commit. Wait for the required checks before merging. Maintainers use rebase merge to keep history linear.

GitHub may ask a maintainer to approve the build and test runs for a first-time
fork contributor. This also applies to the signature check.

The commit check verifies the original PR commits. GitHub's rebase merge creates
new commits on `main` and those new commits lose the original signatures.
[GitHub's rebase and merge behavior](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/about-merge-methods-on-github#rebasing-and-merging-your-commits)

### Required checks on main

The `main` ruleset requires both the **DCO** check from the DCO App and the **Commit signatures** workflow check. GitHub also requires sign-off for web commits. The DCO App skips bots and merge commits by default. [DCO App configuration](https://github.com/dcoapp/app)

The read-only **Commit signatures** job checks every original PR commit through GitHub’s verification API. Review
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
