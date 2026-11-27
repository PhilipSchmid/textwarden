# Working on TextWarden

## Before editing

- Branch from the latest upstream `main` using `<type>/<short-description>`. All changes go through a pull request targeting `main`. See the [development workflow](CONTRIBUTING.md#development-workflow).
- Read [ARCHITECTURE.md](ARCHITECTURE.md) before changing module boundaries, Accessibility strategies, or app behavior. For a host integration, follow [Adding or Fixing App Support](CONTRIBUTING.md#adding-or-fixing-app-support).
- Capture the baseline before editing runtime code or dependencies. Use the [CPU regression guide](docs/CPU_PROFILING.md#local-regression-gate) for the baseline and candidate.

## Implementation

- Target macOS 14. Guard macOS 26 features with availability checks. Prefer native SwiftUI controls that respect accessibility and system appearance.
- Keep UI state on the main actor and blocking work off the main thread. Reuse the Accessibility bridges, text-index converters, and coordinate helpers. Validate underline bounds and verify the source text before applying a correction. See the [design rules](ARCHITECTURE.md#design-rules).
- Use `Logger` for Swift app logging. Prefer identifiers, lengths, and ranges to user text. Safely unwrap Accessibility values, validate FFI inputs, and propagate Rust errors with `Result`. Add compatibility shims only for an existing file format, setting, or supported workflow. See [code style](CONTRIBUTING.md#code-style) and [logging and privacy](CONTRIBUTING.md#logging-and-privacy).

## Test and submit

- Use `make test` for automated tests and `make run` after app code changes to test the installed build. For Accessibility changes, exercise the affected host apps using the [live testing guide](docs/testing/README.md). See [BUILD.md](BUILD.md) for setup.
- Before committing, run `make ci-check` and fix failures. Runtime and dependency changes also need the CPU smoke gate. Use the full suite for analysis, Accessibility, timers, overlays, or performance changes. Record both revisions and results, and report inconclusive measurements. Documentation-only changes are exempt from the CPU gate.
- Commit after the user validates the change and requests a commit. Use a [Conventional Commit subject](CONTRIBUTING.md#commit-messages) and `git commit -s -S` for every commit. Let Git generate the DCO sign-off. Omit `Co-Authored-By`, AI attribution, and manual trailers. See [Commit sign-off and signatures](CONTRIBUTING.md#commit-sign-off-and-signatures).
- Follow the [pull request guidelines](CONTRIBUTING.md#pull-requests). Maintainers rebase-merge approved PRs. For release work, use the [maintainer release procedure](CONTRIBUTING.md#releases).
