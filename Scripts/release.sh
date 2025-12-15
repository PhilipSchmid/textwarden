#!/bin/bash
# Release script for TextWarden
# Handles: archive, sign, DMG creation, appcast update, GitHub release

set -e

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

# Directories
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
RELEASE_DIR="$PROJECT_ROOT/releases"
SPARKLE_BIN="$HOME/Library/Developer/Xcode/DerivedData/TextWarden-*/SourcePackages/artifacts/sparkle/Sparkle/bin"

# Find Sparkle tools
find_sparkle_tools() {
    local bin_path=$(ls -d $SPARKLE_BIN 2>/dev/null | head -1)
    if [[ -z "$bin_path" ]]; then
        echo -e "${RED}Error: Sparkle tools not found. Run 'make build' first.${NC}"
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
    git log $log_range --no-merges --pretty=format:"%s|%h|%an" | \
        grep -v "^Merge" | \
        grep -v "^WIP" | \
        while IFS='|' read -r subject hash author; do
            # Convert author name to GitHub-style (lowercase, replace spaces)
            local github_author=$(echo "$author" | tr '[:upper:]' '[:lower:]' | tr ' ' '-')
            echo "- $subject ([\`$hash\`](https://github.com/$GITHUB_REPO/commit/$hash)) by @$github_author"
        done

    echo ""
    echo "**Full Changelog**: https://github.com/$GITHUB_REPO/compare/$from_tag...$to_ref"
}

# Build release archive
build_archive() {
    echo -e "${BLUE}Building release archive...${NC}"

    # Clean build
    xcodebuild clean -project "$PROJECT_ROOT/$PROJECT" -scheme "$SCHEME" -configuration Release >/dev/null 2>&1

    # Build Rust with LLM
    cd "$PROJECT_ROOT"
    FEATURES=llm ./Scripts/build-rust.sh

    # Archive
    local archive_path="$RELEASE_DIR/$APP_NAME.xcarchive"
    xcodebuild archive \
        -project "$PROJECT" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$archive_path" \
        CODE_SIGN_IDENTITY="-" \
        2>&1 | grep -E "(error:|warning:|ARCHIVE SUCCEEDED|ARCHIVE FAILED)" || true

    # Verify archive succeeded
    if [[ ! -d "$archive_path" ]]; then
        echo -e "${RED}Archive failed${NC}"
        exit 1
    fi

    echo -e "${GREEN}Archive created${NC}"
    echo "$archive_path"
}

# Export app from archive
export_app() {
    local archive_path="$1"
    local export_path="$RELEASE_DIR/export"

    echo -e "${BLUE}Exporting app...${NC}"

    rm -rf "$export_path"
    mkdir -p "$export_path"

    # For unsigned development builds, just copy from archive
    cp -R "$archive_path/Products/Applications/$APP_NAME.app" "$export_path/"

    echo -e "${GREEN}App exported${NC}"
    echo "$export_path/$APP_NAME.app"
}

# Create DMG
create_dmg() {
    local app_path="$1"
    local version="$2"
    local dmg_path="$RELEASE_DIR/$APP_NAME-$version.dmg"

    echo -e "${BLUE}Creating DMG...${NC}"

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

    echo -e "${GREEN}DMG created: $dmg_path${NC}"
    echo "$dmg_path"
}

# Sign update with Sparkle
sign_update() {
    local dmg_path="$1"
    local sparkle_bin="$2"

    echo -e "${BLUE}Signing update with Sparkle...${NC}"

    local signature=$("$sparkle_bin/sign_update" "$dmg_path" 2>/dev/null)

    if [[ -z "$signature" ]]; then
        echo -e "${RED}Failed to sign update${NC}"
        exit 1
    fi

    echo -e "${GREEN}Update signed${NC}"
    echo "$signature"
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

    # Escape release notes for XML
    local escaped_notes=$(echo "$release_notes" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g')

    # Add channel element for pre-release versions (alpha, beta, rc -> experimental channel)
    local channel_element=""
    if [[ "$version_type" == "alpha" || "$version_type" == "beta" || "$version_type" == "rc" ]]; then
        channel_element="
            <sparkle:channel>experimental</sparkle:channel>"
        echo -e "${YELLOW}Adding to experimental channel${NC}"
    fi

    # Create new item entry
    local item="        <item>
            <title>$version</title>
            <pubDate>$pub_date</pubDate>
            <sparkle:version>$build</sparkle:version>
            <sparkle:shortVersionString>$version</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>$channel_element
            <description><![CDATA[
$escaped_notes
            ]]></description>
            <enclosure url=\"$download_url\" length=\"$dmg_size\" type=\"application/octet-stream\" sparkle:edSignature=\"$signature\"/>
        </item>"

    # Insert after <channel> opening tag (before </channel>)
    local appcast="$PROJECT_ROOT/appcast.xml"

    # Read current appcast
    local current=$(cat "$appcast")

    # Check if there are existing items
    if grep -q "</item>" "$appcast"; then
        # Insert before first </item> (newest first)
        sed -i '' "/<channel>/,/<\/channel>/ {
            /<title>.*Releases<\/title>/a\\
$item
        }" "$appcast" 2>/dev/null || {
            # Fallback: insert after channel title
            local tmp=$(mktemp)
            awk -v item="$item" '
                /<title>.*Releases<\/title>/ { print; print item; next }
                { print }
            ' "$appcast" > "$tmp"
            mv "$tmp" "$appcast"
        }
    else
        # No existing items, add after channel opening
        sed -i '' "s|</channel>|$item\n    </channel>|" "$appcast"
    fi

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

    # Generate release notes
    echo -e "${BLUE}Generating release notes...${NC}"
    local release_notes=$(generate_release_notes "$last_tag")
    echo "$release_notes"
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

    # Sign with Sparkle
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

    local dmg_path="$RELEASE_DIR/$APP_NAME-$version.dmg"

    if [[ ! -f "$dmg_path" ]]; then
        echo -e "${RED}DMG not found: $dmg_path${NC}"
        echo -e "Run 'make release VERSION=$version' first"
        exit 1
    fi

    # Get last tag for release notes
    local last_tag=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")
    local release_notes=$(generate_release_notes "$last_tag" "v$version")

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
    echo "  notes [FROM_TAG]      Generate release notes"
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
        generate_release_notes "$2"
        ;;
    version)
        echo "$(get_version) (build $(get_build))"
        ;;
    *)
        usage
        ;;
esac
