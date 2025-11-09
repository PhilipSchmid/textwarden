# Gnau Setup Instructions

## Automated Setup Complete ✅

The following has been automatically configured:

- ✅ Directory structure created (`Sources/`, `Tests/`, `GrammarEngine/`, `Scripts/`)
- ✅ Rust Cargo project initialized with Harper and swift-bridge dependencies
- ✅ SwiftLint configuration (`.swiftlint.yml`)
- ✅ Clippy lints configured in `Cargo.toml`
- ✅ Universal binary build script (`Scripts/build-rust.sh`)
- ✅ Info.plist template created

## Manual Steps Required (Xcode Project Setup)

⚠️ **These steps require Xcode to be installed and must be done manually:**

### 1. Create Xcode Project (T001)

1. Open Xcode
2. File → New → Project
3. Select **macOS** → **App**
4. Configure:
   - **Product Name**: Gnau
   - **Team**: (Your development team)
   - **Organization Identifier**: com.gnau (or your preference)
   - **Bundle Identifier**: com.gnau.app
   - **Interface**: SwiftUI
   - **Language**: Swift
   - **Use Core Data**: NO
   - **Include Tests**: YES
5. Save in repository root as `Gnau.xcodeproj`

### 2. Configure Info.plist (T003)

1. In Xcode project navigator, select the Gnau target
2. Go to **Info** tab
3. Add custom iOS target properties:
   - **Application is agent (UIElement)**: YES (or set LSUIElement = 1)
   - **Minimum system version**: 13.0

Alternatively, replace the auto-generated `Info.plist` with the template at `./Info.plist`

### 3. Configure Build Phases (T009)

1. Select Gnau target → **Build Phases**
2. Click **+** → **New Run Script Phase**
3. Drag the new phase **above** "Compile Sources"
4. Name it: "Build Rust Grammar Engine"
5. Add script:
   ```bash
   ${PROJECT_DIR}/Scripts/build-rust.sh
   ```
6. Set **Output Files**:
   ```
   $(PROJECT_DIR)/GrammarEngine/target/libgrammar_engine_universal.a
   ```

### 4. Link Rust Library (T010)

#### Step A: Add Library Search Path

1. Select Gnau target → **Build Settings**
2. Search for "Library Search Paths"
3. Add: `$(PROJECT_DIR)/GrammarEngine/target`

#### Step B: Link Static Library

1. Select Gnau target → **General** tab
2. Scroll to **Frameworks, Libraries, and Embedded Content**
3. Click **+** → **Add Other...** → **Add Files...**
4. Navigate to `GrammarEngine/target/libgrammar_engine_universal.a`
5. **Important**: Set embedding to **Do Not Embed**

#### Step C: Configure Linker Flags

1. Select Gnau target → **Build Settings**
2. Search for "Other Linker Flags"
3. Add: `-lgrammar_engine_universal`

### 5. Configure Deployment Target

1. Select Gnau target → **Build Settings**
2. Search for "macOS Deployment Target"
3. Set to: **13.0** (macOS Ventura)

### 6. Verify Setup

1. Select Gnau scheme
2. Press **⌘B** (Cmd+B) to build
3. Expected: Build succeeds with Rust compilation logs visible
4. Expected: Universal binary created at `GrammarEngine/target/libgrammar_engine_universal.a`

---

## Next Steps After Manual Setup

Once the Xcode project is configured, you can proceed with:

1. **Phase 2: Foundational** - Implement Rust FFI layer (automated)
2. **Phase 3: User Story 1** - Real-time grammar detection (automated)
3. **Phase 4+**: Remaining user stories (automated)

---

## Troubleshooting

### "Library not found for -lgrammar_engine_universal"

**Solution**:
1. Ensure `Scripts/build-rust.sh` has been run successfully
2. Check that `GrammarEngine/target/libgrammar_engine_universal.a` exists
3. Verify Library Search Paths includes `$(PROJECT_DIR)/GrammarEngine/target`
4. Clean build folder: **Product** → **Clean Build Folder** (⇧⌘K)

### Rust targets not installed

**Solution**:
```bash
rustup target add x86_64-apple-darwin aarch64-apple-darwin
```

### swift-bridge generation errors

**Solution**: Ensure `Cargo.toml` has:
```toml
[dependencies]
swift-bridge = "1.0"
```

---

## Ready to Continue?

Once Xcode project setup is complete, run:

```bash
# Continue with automated implementation
/speckit.implement
```

The system will detect the Xcode project and proceed with Phase 2 (Foundational layer).
