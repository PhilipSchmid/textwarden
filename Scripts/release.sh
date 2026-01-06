#!/bin/bash
# Release script for TextWarden
# Handles: archive, sign, DMG creation, appcast update, GitHub release

set -e
set -o pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Project settings
APP_NAME="TextWarden"
BUNDLE_ID="io.textwarden.TextWarden"
PROJECT="TextWarden.xcodeproj"
SCHEME="TextWarden"
GITHUB_REPO="PhilipSchmid/textwarden"

# Code signing settings
DEVELOPER_ID="Developer ID Application: Philip Schmid (KSW8RTNTKJ)"
ENTITLEMENTS="TextWarden.entitlements"
APPLE_ID="${APPLE_ID:-}"  # Set via environment or keychain
TEAM_ID="KSW8RTNTKJ"

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$PROJECT_ROOT/releases"
SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/TextWarden-*/SourcePackages/artifacts/sparkle/Sparkle/bin"

# Validate environment and dependencies
validate_environment() {
    echo -e "${BLUE}Validating environment...${NC}" >&2
    local errors=0

    # Check required commands
    local required_cmds=("xcodebuild" "codesign" "hdiutil" "git" "gh" "python3" "cargo" "rustc")
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${RED}Error: Required command '$cmd' not found${NC}" >&2
            errors=$((errors + 1))
        fi
    done

    # Check Xcode command line tools
    if ! xcode-select -p &>/dev/null; then
        echo -e "${RED}Error: Xcode command line tools not installed${NC}" >&2
        echo -e "  Run: xcode-select --install" >&2
        errors=$((errors + 1))
    fi

    # Check code signing identity
    if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "$TEAM_ID"; then
        echo -e "${RED}Error: Developer ID certificate not found in keychain${NC}" >&2
        echo -e "  Team ID: $TEAM_ID" >&2
        errors=$((errors + 1))
    fi

    # Check project files exist
    if [[ ! -f "$PROJECT_ROOT/$PROJECT/project.pbxproj" ]]; then
        echo -e "${RED}Error: Xcode project not found at $PROJECT_ROOT/$PROJECT${NC}" >&2
        errors=$((errors + 1))
    fi

    if [[ ! -f "$PROJECT_ROOT/$ENTITLEMENTS" ]]; then
        echo -e "${RED}Error: Entitlements file not found at $PROJECT_ROOT/$ENTITLEMENTS${NC}" >&2
        errors=$((errors + 1))
    fi

    if [[ ! -f "$PROJECT_ROOT/Info.plist" ]]; then
        echo -e "${RED}Error: Info.plist not found${NC}" >&2
        errors=$((errors + 1))
    fi

    # Check git status (warn if dirty)
    if [[ -n "$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null)" ]]; then
        echo -e "${YELLOW}Warning: Git working directory has uncommitted changes${NC}" >&2
    fi

    # Check gh CLI is authenticated
    if ! gh auth status &>/dev/null; then
        echo -e "${YELLOW}Warning: GitHub CLI not authenticated (gh release upload will fail)${NC}" >&2
    fi

    if [[ $errors -gt 0 ]]; then
        echo -e "${RED}Environment validation failed with $errors error(s)${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}Environment validated${NC}" >&2
}

# Find Sparkle tools
find_sparkle_tools() {
    local bin_path=$(ls -d $SPARKLE_BIN 2>/dev/null | head -1)
    if [[ -z "$bin_path" ]]; then
        echo -e "${RED}Error: Sparkle tools not found. Run 'make build' first.${NC}" >&2
        exit 1
    fi
    echo "$bin_path"
}

# Get version from Info.plist
get_version() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Info.plist"
}

# Get build number from Info.plist
get_build() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PROJECT_ROOT/Info.plist"
}

# Set version in Info.plist
set_version() {
    local version="$1"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$PROJECT_ROOT/Info.plist"
}

# Set build number in Info.plist
set_build() {
    local build="$1"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build" "$PROJECT_ROOT/Info.plist"
}

# Validate semantic versioning format
# Valid: 1.0.0, 0.2.0-alpha.1, 1.0.0-beta.2, 2.0.0-rc.1
# Invalid: v1.0.0, 1.0, 1.0.0-alpha, 1.0.0.0
validate_semver() {
    local version="$1"
    local semver_regex="^[0-9]+\.[0-9]+\.[0-9]+(-((alpha|beta|rc)\.[0-9]+))?$"

    if [[ ! "$version" =~ $semver_regex ]]; then
        echo -e "${RED}Error: Invalid semantic version: $version${NC}"
        echo ""
        echo "Valid formats:"
        echo "  Production:  X.Y.Z        (e.g., 1.0.0, 0.2.0)"
        echo "  Alpha:       X.Y.Z-alpha.N (e.g., 0.2.0-alpha.1)"
        echo "  Beta:        X.Y.Z-beta.N  (e.g., 0.2.0-beta.1)"
        echo "  RC:          X.Y.Z-rc.N    (e.g., 0.2.0-rc.1)"
        echo ""
        echo "Invalid:"
        echo "  - Leading 'v' (use 1.0.0, not v1.0.0)"
        echo "  - Missing patch (use 1.0.0, not 1.0)"
        echo "  - Pre-release without number (use -alpha.1, not -alpha)"
        exit 1
    fi
}

# Parse version type (alpha, beta, rc, release)
parse_version_type() {
    local version="$1"
    if [[ "$version" == *"-alpha."* ]]; then
        echo "alpha"
    elif [[ "$version" == *"-beta."* ]]; then
        echo "beta"
    elif [[ "$version" == *"-rc."* ]]; then
        echo "rc"
    else
        echo "release"
    fi
}

# Generate release notes from git commits
# Format: - commit message (short hash) by @author
# Links to GitHub commits for full context
# Note: Does NOT include "Full Changelog" link - that's added only for GitHub releases
generate_release_notes() {
    local from_tag="$1"
    local to_ref="${2:-HEAD}"

    echo "## What's Changed"
    echo ""

    # Get all commits since last tag (or since beginning if no tag)
    local log_range=""
    if [[ -n "$from_tag" ]] && git rev-parse "$from_tag" >/dev/null 2>&1; then
        log_range="$from_tag..$to_ref"
    else
        log_range="$to_ref"
    fi

    # Format: - Subject ([hash](url)) by @author
    # Look up actual GitHub username via API for each commit
    git log $log_range --no-merges --pretty=format:"%s|%h|%an" | \
        grep -v "^Merge" | \
        grep -v "^WIP" | \
        while IFS='|' read -r subject hash local_author; do
            # Look up actual GitHub username from commit via API
            # Falls back to local git author name if API fails (e.g., commit not pushed yet)
            local api_response
            api_response=$(gh api "repos/$GITHUB_REPO/commits/$hash" --jq '.author.login // .commit.author.name' 2>/dev/null)
            if [[ $? -eq 0 && -n "$api_response" && ! "$api_response" =~ ^\{.*\}$ ]]; then
                local github_author="$api_response"
            else
                local github_author="$local_author"
            fi
            echo "- $subject ([\`$hash\`](https://github.com/$GITHUB_REPO/commit/$hash)) by @$github_author"
        done
}

# Generate full changelog link for GitHub releases
# Note: Needs TWO blank lines before for proper markdown separation from list
generate_changelog_link() {
    local from_tag="$1"
    local to_ref="${2:-HEAD}"
    echo ""
    echo ""
    echo "**Full Changelog**: https://github.com/$GITHUB_REPO/compare/$from_tag...$to_ref"
}

# Build release archive
build_archive() {
    echo -e "${BLUE}Building release archive...${NC}" >&2

    # Clean build first
    echo -e "${BLUE}Cleaning previous build...${NC}" >&2
    xcodebuild clean -project "$PROJECT_ROOT/$PROJECT" -scheme "$SCHEME" -configuration Release >/dev/null 2>&1 || true

    # Build Rust in release mode (in subshell to isolate environment)
    echo -e "${BLUE}Building Rust grammar engine...${NC}" >&2
    (
        cd "$PROJECT_ROOT"
        # Ensure clean Rust environment
        export CARGO_TARGET_DIR="$PROJECT_ROOT/GrammarEngine/target"
        export MACOSX_DEPLOYMENT_TARGET="14.0"
        CONFIGURATION=Release ./Scripts/build-rust.sh
    ) >&2

    # Archive (signing handled by Xcode's automatic signing, re-signed during export)
    local archive_path="$RELEASE_DIR/$APP_NAME.xcarchive"
    echo -e "${BLUE}Creating Xcode archive...${NC}" >&2

    # Run xcodebuild in subshell with clean environment
    (
        cd "$PROJECT_ROOT"
        xcodebuild archive \
            -project "$PROJECT" \
            -scheme "$SCHEME" \
            -configuration Release \
            -archivePath "$archive_path" \
            2>&1 | grep -E "(error:|warning:|ARCHIVE SUCCEEDED|ARCHIVE FAILED)" || true
    ) >&2

    # Verify archive succeeded
    if [[ ! -d "$archive_path" ]]; then
        echo -e "${RED}Archive failed - check Xcode build settings${NC}" >&2
        exit 1
    fi

    # Verify the app exists in the archive
    if [[ ! -d "$archive_path/Products/Applications/$APP_NAME.app" ]]; then
        echo -e "${RED}Archive created but app bundle not found${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}Archive created${NC}" >&2
    echo "$archive_path"
}

# Export app from archive
export_app() {
    local archive_path="$1"
    local export_path="$RELEASE_DIR/export"

    echo -e "${BLUE}Exporting app...${NC}" >&2

    rm -rf "$export_path"
    mkdir -p "$export_path"

    # Copy from archive
    cp -R "$archive_path/Products/Applications/$APP_NAME.app" "$export_path/"

    # Re-sign with Developer ID and entitlements for distribution
    echo -e "${BLUE}Signing app with Developer ID...${NC}" >&2
    codesign --force --deep --timestamp --options=runtime \
        --sign "$DEVELOPER_ID" \
        --entitlements "$PROJECT_ROOT/$ENTITLEMENTS" \
        "$export_path/$APP_NAME.app"

    # Verify signature
    if ! codesign --verify --deep --strict "$export_path/$APP_NAME.app" 2>/dev/null; then
        echo -e "${RED}Code signing verification failed${NC}" >&2
        exit 1
    fi

    echo -e "${GREEN}App exported and signed${NC}" >&2
    echo "$export_path/$APP_NAME.app"
}

# Notarize the app
notarize_app() {
    local dmg_path="$1"

    echo -e "${BLUE}Notarizing app...${NC}"

    # Check for Apple ID credentials
    if [[ -z "$APPLE_ID" ]]; then
        echo -e "${YELLOW}APPLE_ID not set. Checking keychain for notarytool credentials...${NC}"
        # Try using stored keychain profile
        if ! xcrun notarytool history --keychain-profile "TextWarden" >/dev/null 2>&1; then
            echo -e "${YELLOW}No keychain profile found. Skipping notarization.${NC}"
            echo -e "${YELLOW}To enable notarization, run:${NC}"
            echo -e "  xcrun notarytool store-credentials \"TextWarden\" --apple-id YOUR_APPLE_ID --team-id $TEAM_ID"
            return 0
        fi
        local auth_args="--keychain-profile TextWarden"
    else
        local auth_args="--apple-id $APPLE_ID --team-id $TEAM_ID --password @keychain:AC_PASSWORD"
    fi

    # Submit for notarization
    echo -e "${BLUE}Submitting to Apple notary service...${NC}"
    local result
    result=$(xcrun notarytool submit "$dmg_path" $auth_args --wait 2>&1)

    if echo "$result" | grep -q "status: Accepted"; then
        echo -e "${GREEN}Notarization successful${NC}"

        # Staple the ticket to the DMG
        echo -e "${BLUE}Stapling notarization ticket...${NC}"
        xcrun stapler staple "$dmg_path"
        echo -e "${GREEN}Stapling complete${NC}"
    else
        echo -e "${RED}Notarization failed:${NC}"
        echo "$result"
        echo -e "${YELLOW}Continuing without notarization...${NC}"
    fi
}

# Create DMG
create_dmg() {
    local app_path="$1"
    local version="$2"
    local dmg_path="$RELEASE_DIR/$APP_NAME-$version-Universal.dmg"

    echo -e "${BLUE}Creating DMG...${NC}" >&2

    # Remove old DMG if exists
    rm -f "$dmg_path"

    # Create temporary DMG folder
    local dmg_temp="$RELEASE_DIR/dmg_temp"
    rm -rf "$dmg_temp"
    mkdir -p "$dmg_temp"

    # Copy app
    cp -R "$app_path" "$dmg_temp/"

    # Create symlink to Applications
    ln -s /Applications "$dmg_temp/Applications"

    # Create DMG
    hdiutil create -volname "$APP_NAME" \
        -srcfolder "$dmg_temp" \
        -ov -format UDZO \
        "$dmg_path" >/dev/null

    # Cleanup
    rm -rf "$dmg_temp"

    echo -e "${GREEN}DMG created: $dmg_path${NC}" >&2
    echo "$dmg_path"
}

# Sign update with Sparkle
sign_update() {
    local dmg_path="$1"
    local sparkle_bin="$2"

    echo -e "${BLUE}Signing update with Sparkle...${NC}" >&2

    # Don't suppress stderr - we need to see errors if keychain access fails
    local raw_signature
    raw_signature=$("$sparkle_bin/sign_update" "$dmg_path" 2>&1)
    local sign_exit_code=$?

    if [[ $sign_exit_code -ne 0 ]]; then
        echo -e "${RED}Failed to sign update (exit code $sign_exit_code):${NC}" >&2
        echo "$raw_signature" >&2
        echo "" >&2
        echo -e "${YELLOW}If keychain access failed, try:${NC}" >&2
        echo -e "  1. Run: security unlock-keychain ~/Library/Keychains/login.keychain-db" >&2
        echo -e "  2. Or: $sparkle_bin/generate_keys  (to check key access)" >&2
        exit 1
    fi

    if [[ -z "$raw_signature" ]]; then
        echo -e "${RED}Failed to sign update - empty output${NC}" >&2
        exit 1
    fi

    # Extract just the base64 signature from Sparkle's output
    # Format: sparkle:edSignature="<base64>" length="<size>"
    local signature
    if [[ "$raw_signature" =~ edSignature=\"([^\"]+)\" ]]; then
        signature="${BASH_REMATCH[1]}"
    else
        echo -e "${RED}Failed to parse signature from output:${NC}" >&2
        echo "$raw_signature" >&2
        exit 1
    fi

    # CRITICAL: Verify the signature is valid before continuing
    # This catches cases where keychain access silently failed
    echo -e "${BLUE}Verifying signature...${NC}" >&2
    if ! "$sparkle_bin/sign_update" --verify "$dmg_path" "$signature" >/dev/null 2>&1; then
        echo -e "${RED}SIGNATURE VERIFICATION FAILED!${NC}" >&2
        echo -e "The generated signature does not match the private key." >&2
        echo -e "This usually means keychain access is broken." >&2
        echo "" >&2
        echo -e "Try running: $sparkle_bin/generate_keys -p" >&2
        echo -e "If that fails, the keychain entry may need to be re-authorized." >&2
        exit 1
    fi

    echo -e "${GREEN}Update signed and verified ✓${NC}" >&2
    echo "$signature"
}

# Convert markdown release notes to HTML for Sparkle
# Handles: ## headers, - lists, **bold**, `code`, [links](url)
convert_markdown_to_html() {
    local markdown="$1"

    python3 << PYEOF
import re
import html

md = '''$markdown'''

# Split into lines for processing
lines = md.strip().split('\n')
html_lines = []
in_list = False

for line in lines:
    # Skip empty lines
    if not line.strip():
        if in_list:
            html_lines.append('</ul>')
            in_list = False
        continue

    # Headers
    if line.startswith('## '):
        if in_list:
            html_lines.append('</ul>')
            in_list = False
        text = html.escape(line[3:])
        html_lines.append(f'<h3>{text}</h3>')
        continue

    # List items
    if line.startswith('- '):
        if not in_list:
            html_lines.append('<ul>')
            in_list = True
        text = line[2:]
        # Convert markdown links [text](url) to HTML
        text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', text)
        # Convert inline code
        text = re.sub(r'\`([^\`]+)\`', r'<code>\1</code>', text)
        # Convert bold
        text = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', text)
        # Escape remaining HTML but preserve our tags
        # (links and code already converted, so we just escape plain text parts)
        html_lines.append(f'<li>{text}</li>')
        continue

    # Regular text (like Full Changelog line)
    if in_list:
        html_lines.append('</ul>')
        in_list = False
    text = line
    # Convert markdown links
    text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', text)
    text = re.sub(r'\*\*([^*]+)\*\*', r'<b>\1</b>', text)
    html_lines.append(f'<p>{text}</p>')

if in_list:
    html_lines.append('</ul>')

print('\n'.join(html_lines))
PYEOF
}

# Update appcast.xml
update_appcast() {
    local version="$1"
    local build="$2"
    local dmg_path="$3"
    local signature="$4"
    local release_notes="$5"
    local is_prerelease="$6"
    local version_type="$7"

    echo -e "${BLUE}Updating appcast.xml...${NC}"

    local dmg_size=$(stat -f%z "$dmg_path")
    local dmg_filename=$(basename "$dmg_path")
    local pub_date=$(date -R)
    local download_url="https://github.com/$GITHUB_REPO/releases/download/v$version/$dmg_filename"
    local appcast="$PROJECT_ROOT/appcast.xml"

    # Add channel element for pre-release versions
    local channel_element=""
    if [[ "$version_type" == "alpha" || "$version_type" == "beta" || "$version_type" == "rc" ]]; then
        channel_element="experimental"
        echo -e "${YELLOW}Adding to experimental channel${NC}"
    fi

    # Convert release notes markdown to HTML for Sparkle
    local html_notes=$(convert_markdown_to_html "$release_notes")

    # Use Python for reliable XML manipulation
    python3 << EOF
import xml.etree.ElementTree as ET
from datetime import datetime
import html

# Parse appcast
tree = ET.parse("$appcast")
root = tree.getroot()

# Define Sparkle namespace
ns = {'sparkle': 'http://www.andymatuschak.org/xml-namespaces/sparkle'}
ET.register_namespace('sparkle', 'http://www.andymatuschak.org/xml-namespaces/sparkle')
ET.register_namespace('', 'http://www.w3.org/2005/Atom')

# Find channel
channel = root.find('channel')
if channel is None:
    print("Error: No channel found in appcast")
    exit(1)

# Find insert position (after title, before first item)
insert_idx = 0
for i, child in enumerate(channel):
    if child.tag == 'title':
        insert_idx = i + 1
        break

# Create new item
item = ET.Element('item')

title = ET.SubElement(item, 'title')
title.text = "$version"

pubDate = ET.SubElement(item, 'pubDate')
pubDate.text = "$pub_date"

sparkle_version = ET.SubElement(item, '{http://www.andymatuschak.org/xml-namespaces/sparkle}version')
sparkle_version.text = "$build"

short_version = ET.SubElement(item, '{http://www.andymatuschak.org/xml-namespaces/sparkle}shortVersionString')
short_version.text = "$version"

min_sys = ET.SubElement(item, '{http://www.andymatuschak.org/xml-namespaces/sparkle}minimumSystemVersion')
min_sys.text = "14.0"

channel_elem_value = "$channel_element"
if channel_elem_value:
    sparkle_channel = ET.SubElement(item, '{http://www.andymatuschak.org/xml-namespaces/sparkle}channel')
    sparkle_channel.text = channel_elem_value

desc = ET.SubElement(item, 'description')
# Embed the HTML release notes
html_notes = '''$html_notes'''
desc.text = html_notes

enclosure = ET.SubElement(item, 'enclosure')
enclosure.set('url', "$download_url")
enclosure.set('length', "$dmg_size")
enclosure.set('type', 'application/octet-stream')
enclosure.set('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature', "$signature")

# Insert at position
channel.insert(insert_idx, item)

# Write with proper formatting
tree.write("$appcast", encoding='unicode', xml_declaration=True)

# Pretty print by re-reading and formatting
import xml.dom.minidom
with open("$appcast", 'r') as f:
    content = f.read()
dom = xml.dom.minidom.parseString(content)
pretty = dom.toprettyxml(indent="    ")
# Remove extra blank lines and fix declaration
lines = [l for l in pretty.split('\n') if l.strip()]
lines[0] = '<?xml version="1.0" encoding="UTF-8"?>'
with open("$appcast", 'w') as f:
    f.write('\n'.join(lines))

print("Appcast updated successfully")
EOF

    echo -e "${GREEN}Appcast updated${NC}"
}

# Create GitHub release
create_github_release() {
    local version="$1"
    local dmg_path="$2"
    local release_notes="$3"
    local is_prerelease="$4"

    echo -e "${BLUE}Creating GitHub release...${NC}"

    local prerelease_flag=""
    if [[ "$is_prerelease" == "true" ]]; then
        prerelease_flag="--prerelease"
    fi

    # Create release
    gh release create "v$version" \
        --title "v$version" \
        --notes "$release_notes" \
        $prerelease_flag \
        "$dmg_path"

    echo -e "${GREEN}GitHub release created: v$version${NC}"
}

# Main release function
do_release() {
    local version="$1"
    local skip_confirm="$2"

    # Validate environment first
    validate_environment

    if [[ -z "$version" ]]; then
        version=$(get_version)
        echo -e "${YELLOW}No version specified, using current: $version${NC}"
    fi

    # Validate semver before proceeding
    validate_semver "$version"

    local version_type=$(parse_version_type "$version")
    local is_prerelease="false"

    if [[ "$version_type" != "release" ]]; then
        is_prerelease="true"
    fi

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}TextWarden Release${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "  Version:     ${GREEN}$version${NC}"
    echo -e "  Type:        ${YELLOW}$version_type${NC}"
    echo -e "  Prerelease:  $is_prerelease"
    echo ""

    # For production releases, require explicit confirmation
    if [[ "$version_type" == "release" && "$skip_confirm" != "--yes" ]]; then
        echo -e "${RED}⚠️  This is a PRODUCTION release!${NC}"
        echo ""
        read -p "Type 'release' to confirm: " confirm
        if [[ "$confirm" != "release" ]]; then
            echo -e "${RED}Aborted${NC}"
            exit 1
        fi
        echo ""
    fi

    # Find Sparkle tools
    local sparkle_bin=$(find_sparkle_tools)

    # Create release directory
    mkdir -p "$RELEASE_DIR"

    # Get last tag for release notes
    local last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

    # Generate release notes (without changelog link - that's only for GitHub releases)
    echo -e "${BLUE}Generating release notes...${NC}"
    local release_notes=$(generate_release_notes "$last_tag")
    echo "$release_notes"
    # Show changelog link in console for reference (but don't include in Sparkle appcast)
    echo ""
    echo "**Full Changelog**: https://github.com/$GITHUB_REPO/compare/$last_tag...HEAD"
    echo ""

    # Update version in Info.plist
    set_version "$version"

    # Increment build number
    local current_build=$(get_build)
    local new_build=$((current_build + 1))
    set_build "$new_build"
    echo -e "Build number: $new_build"

    # Build
    local archive_path=$(build_archive)

    # Export
    local app_path=$(export_app "$archive_path")

    # Create DMG
    local dmg_path=$(create_dmg "$app_path" "$version")

    # Notarize the DMG FIRST (stapling modifies the DMG)
    notarize_app "$dmg_path"

    # Sign with Sparkle AFTER stapling (signature must be for final DMG)
    local signature=$(sign_update "$dmg_path" "$sparkle_bin")

    # Update appcast
    update_appcast "$version" "$new_build" "$dmg_path" "$signature" "$release_notes" "$is_prerelease" "$version_type"

    # Commit version changes
    echo -e "${BLUE}Committing version changes...${NC}"
    git add "$PROJECT_ROOT/Info.plist" "$PROJECT_ROOT/appcast.xml"
    git commit -m "Release v$version"

    # Create git tag
    git tag -a "v$version" -m "Release v$version"

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Release prepared: v$version${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "Next steps:"
    echo -e "  1. Review: git log -1 && git diff HEAD~1"
    echo -e "  2. Push:   git push && git push --tags"
    echo -e "  3. Upload: make release-upload VERSION=$version"
    echo ""
    echo -e "DMG location: $dmg_path"
}

# Upload release to GitHub
do_upload() {
    local version="$1"

    if [[ -z "$version" ]]; then
        version=$(get_version)
    fi

    local dmg_path="$RELEASE_DIR/$APP_NAME-$version-Universal.dmg"

    if [[ ! -f "$dmg_path" ]]; then
        echo -e "${RED}DMG not found: $dmg_path${NC}"
        echo -e "Run 'make release VERSION=$version' first"
        exit 1
    fi

    # Get the previous tag (excluding the one we're releasing) for release notes
    # This finds the most recent tag that isn't the current version
    local last_tag=$(git tag --sort=-creatordate | grep -v "^v$version$" | head -1)
    local release_notes=$(generate_release_notes "$last_tag" "v$version")
    # Add changelog link for GitHub releases (not included in Sparkle appcast)
    release_notes+=$(generate_changelog_link "$last_tag" "v$version")

    local version_type=$(parse_version_type "$version")
    local is_prerelease="false"
    if [[ "$version_type" != "release" ]]; then
        is_prerelease="true"
    fi

    create_github_release "$version" "$dmg_path" "$release_notes" "$is_prerelease"

    echo ""
    echo -e "${GREEN}Release uploaded!${NC}"
    echo -e "View at: https://github.com/$GITHUB_REPO/releases/tag/v$version"
}

# Show usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo ""
    echo "Commands:"
    echo "  release [VERSION]     Build and prepare release"
    echo "  upload [VERSION]      Upload prepared release to GitHub"
    echo "  notes [FROM_TAG] [TO_TAG]  Generate release notes (TO_TAG defaults to HEAD)"
    echo "  version               Show current version"
    echo ""
    echo "Examples:"
    echo "  $0 release 0.2.0-alpha.1"
    echo "  $0 release 0.2.0-beta.1"
    echo "  $0 release 0.2.0-rc.1"
    echo "  $0 release 0.2.0"
    echo "  $0 upload 0.2.0"
}

# Main
case "${1:-}" in
    release)
        do_release "$2" "$3"
        ;;
    upload)
        do_upload "$2"
        ;;
    notes)
        generate_release_notes "$2" "$3"
        ;;
    version)
        echo "$(get_version) (build $(get_build))"
        ;;
    *)
        usage
        ;;
esac
