# TextWarden Development Guidelines

## Architecture

- **Swift**: macOS app with SwiftUI, menu bar interface, Accessibility API integration
- **Rust**: GrammarEngine library via FFI (swift-bridge), handles text analysis and LLM inference
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

### Safety
- No force unwraps (`!`) on AXValue or external data
- Use `guard let` / `if let` for optionals
- Handle all error cases explicitly

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
- No backward compatibility required - this is a new product, focus on first release

## Design

- Follow macOS 26 (Tahoe) design principles from Apple
- Use native SwiftUI components where possible
- Respect system appearance and accessibility settings

## Git Workflow

- Only commit after user validates and explicitly requests it
- Use 50/72 rule: subject ≤50 chars, body wrapped at 72
- Write concise, descriptive commit messages
- Always sign-off git commits, but not with Claude Code. Also don't mention co-autored by any AI. 

## Testing

```bash
make build          # Full build
make test           # Run tests
cargo test          # Rust tests only
```
