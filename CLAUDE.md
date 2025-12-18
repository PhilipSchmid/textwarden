# TextWarden Development Guidelines

## Architecture

**See [ARCHITECTURE.md](ARCHITECTURE.md) for detailed architecture documentation, design patterns, dependency injection, and coding principles.** Always consult ARCHITECTURE.md when making structural changes or adding new components.

- **Swift**: macOS app with SwiftUI, menu bar interface, Accessibility API integration
- **Rust**: GrammarEngine library via FFI (swift-bridge), handles grammar analysis via Harper
- **Apple Intelligence**: Style suggestions via Foundation Models framework (macOS 26+)
- **Build**: `make build` (Rust first, then Xcode)

## Swift Guidelines

### Logging
Use `Logger` (os.log-based), never `print()`:
```swift
Logger.info("Message", category: Logger.permissions)
Logger.debug("Details", category: Logger.ui)
Logger.error("Failed", category: Logger.analysis)
```

Categories: `permissions`, `ui`, `analysis`, `general`, `performance`, `accessibility`
Levels: `trace` (high-frequency) → `debug` → `info` → `warning` → `error` → `critical`

### Safety & Error Handling
- No force unwraps (`!`) on AXValue or external data
- Use `guard let` / `if let` for optionals
- Handle all error cases explicitly

**Error Handling Patterns:**
```swift
// Array access - use .first, .last, or indices.contains()
guard let first = array.first else { return }
guard array.indices.contains(index) else { return }

// String indices - use limitedBy: parameter
guard let endIdx = str.index(str.startIndex, offsetBy: offset, limitedBy: str.endIndex) else { return }

// AXValue types - use safe helper functions (AccessibilityBridge)
guard let frame = AccessibilityBridge.getElementFrame(element) else { return }

// Optional chaining for nullable properties
element?.attribute(forKey: key)
```

**Logging Errors:**
- Log at appropriate level before returning nil/early
- Include context: what failed and any relevant identifiers
```swift
Logger.warning("Failed to get bounds for element: \(elementRole)", category: Logger.accessibility)
```

### Thread Safety
- UI updates on main thread: `DispatchQueue.main.async`
- Never block main thread with sync operations
- Use `@MainActor` for SwiftUI state

## Rust Guidelines

### Error Handling
- Use `Result<T, E>` for fallible operations
- Propagate errors with `?`, don't panic in library code
- Log errors before returning them

### FFI
- Keep FFI boundary minimal and simple
- Use `swift_bridge` types for cross-language communication
- Validate all inputs from Swift side

## Code Quality

- Comments should explain "why", not "what"
- Remove dead code, don't comment it out
- Keep functions focused and small
- Prefer editing existing files over creating new ones
- **Check `Sources/Utilities/` before implementing common operations** (TextIndexConverter, CoordinateMapper, etc.)
- No backward compatibility required - this is a new product, focus on first release

## Design

- Follow macOS 26 (Tahoe) design principles from Apple
- Use native SwiftUI components where possible
- Respect system appearance and accessibility settings

## Git Workflow

- Only commit after user validates and explicitly requests it
- **Always run `make ci-check` and fix all findings before committing**
- Always sign-off git commits, but not with Claude Code. Also don't mention co-authored by any AI.

### Conventional Commits

Use [Conventional Commits](https://www.conventionalcommits.org/) format for all commit messages:

```
<type>: <description>

[optional body]

Signed-off-by: ...
```

**Types:**
- `feat`: New feature or functionality
- `fix`: Bug fix
- `docs`: Documentation only changes
- `refactor`: Code change that neither fixes a bug nor adds a feature
- `perf`: Performance improvement
- `test`: Adding or correcting tests
- `chore`: Maintenance tasks, dependencies, build changes
- `ci`: CI/CD configuration changes

**Guidelines:**
- Subject line: imperative mood, no period, ≤50 chars (e.g., "Add Outlook support")
- Body: wrap at 72 chars, explain "why" not "what"
- Keep commits atomic - one logical change per commit

**Examples:**
```
feat: Add Microsoft Outlook support with visual underlines
fix: Correct underline positioning in Slack
refactor: Extract positioning logic into strategy pattern
docs: Update README with new app support
chore: Update Harper to v0.15.0
``` 

## Testing

```bash
make build          # Full build only
make run            # Build AND restart the app (use this for testing!)
make test           # Run tests
cargo test          # Rust tests only
```
