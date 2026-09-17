# Building TextWarden

TextWarden combines a Swift macOS app with a Rust static library. The standard build creates a universal grammar engine for Intel and Apple Silicon, generates the Apple Help Book, then builds the app with Xcode.

## Prerequisites

- Xcode 26 or later, including the Command Line Tools
- Rust 1.95 or later, installed with [rustup](https://rustup.rs/)
- The `x86_64-apple-darwin` and `aarch64-apple-darwin` Rust targets
- [Pandoc](https://pandoc.org/) for the Help Book

The app's deployment target is macOS 14. Apple Intelligence code uses the macOS 26 SDK behind availability checks. Checks also run on macOS 14; newer APIs and their checks are availability-gated.

Install the tools and targets:

```bash
xcode-select --install
rustup update stable
rustup target add x86_64-apple-darwin aarch64-apple-darwin
brew install pandoc
```

SwiftFormat and SwiftLint are also required for the local CI checks:

```bash
brew install swiftformat swiftlint
```

Confirm the active toolchain:

```bash
xcodebuild -version
rustc --version
rustup target list --installed
pandoc --version
```

## Build from the Command Line

Run the repository's build target:

```bash
make build
```

This target performs two steps in order:

1. `Scripts/build-rust.sh` builds `GrammarEngine` for Intel and Apple Silicon, then combines both archives as `GrammarEngine/target/libgrammar_engine_universal.a`.
2. `make build-swift` builds the `TextWarden` scheme in Release configuration. Its Help Book phase regenerates and bundles `CONFIGURATION.md` and `TROUBLESHOOTING.md` with Pandoc on every build, including archives.

The first build also resolves Cargo and Swift Package Manager dependencies.

## Build and Run

To build the app, copy it to `/Applications`, stop an existing TextWarden process, and launch the new build:

```bash
make run
```

This command replaces `/Applications/TextWarden.app`. Use it only when that is the installation you intend to test.

Other useful targets:

| Command | Purpose |
| --- | --- |
| `make run-only` | Launch the existing app in `/Applications` without rebuilding |
| `make install` | Copy the latest Release build to `/Applications` |
| `make kill` | Stop TextWarden |
| `make status` | Show whether TextWarden is running |
| `make xcode` | Open `TextWarden.xcodeproj` |

## Browser Extension Preview

The app build includes the shared extension files, native messaging helper, and Safari app extension. Run `make run`, then use **Preferences → Browser → Install Extension** to load the preview manually. Chrome/Brave use Developer mode; Firefox/Zen use temporary add-ons. Safari development builds require an appropriate signing identity; unsigned builds additionally require Safari’s development setting for unsigned extensions. See the [extension guide](BrowserExtension/README.md).

`make test-browser` checks the browser runtime and packaging with Node.js and Python 3.

## Build in Xcode

Open `TextWarden.xcodeproj` and select the **TextWarden** scheme. The Xcode project builds the Rust library and regenerates the Help Book automatically. Pandoc must be installed before building:

```bash
open TextWarden.xcodeproj
```

Then press `⌘B` to build or `⌘R` to run.

## Tests and Checks

Run both the locked Rust test suite and the selected Swift unit and integration tests:

```bash
make test
```

Run the same formatting, linting, testing, and build gates used before a commit:

```bash
make ci-check
```

The seven local gates are Rust formatting, Clippy, SwiftFormat, SwiftLint, Rust tests, Swift tests, and a full build.

Targeted commands are also available:

```bash
make test-rust
make test-swift
make lint
make fmt
```

## Clean Builds

```bash
make clean          # Clean the Xcode build
make clean-derived  # Remove TextWarden DerivedData
make clean-all      # Clean Cargo, Xcode, and DerivedData outputs
```

`make clean-all` removes local build artifacts. It does not delete source files.

## Troubleshooting

### A Rust target is missing

```bash
rustup target add x86_64-apple-darwin aarch64-apple-darwin
```

### Cargo uses the wrong Rust installation

If both Homebrew Rust and rustup are installed, check which binaries your shell resolves:

```bash
which rustup
which rustc
rustup show active-toolchain
```

The build script prefers the active rustup toolchain. If Homebrew's `rust` package is shadowing it, remove that package or fix your `PATH`, then run `rustup update stable`.

### The universal Rust library is missing

Build it directly and inspect its architectures:

```bash
make build-rust
lipo -info GrammarEngine/target/libgrammar_engine_universal.a
```

The result should contain `x86_64` and `arm64`.

### Pandoc is missing

```bash
brew install pandoc
make help-book
```

### Accessibility permission does not update

Development builds can appear as a new app identity after signing or location changes. Remove stale TextWarden entries in **System Settings → Privacy & Security → Accessibility**, run the app again, and grant permission to the copy you are testing.

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [ARCHITECTURE.md](ARCHITECTURE.md) for the Swift, Rust, and Accessibility design.
