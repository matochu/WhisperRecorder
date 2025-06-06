#!/bin/bash

# WhisperRecorder Version Management Script

CURRENT_VERSION=$(cat VERSION 2>/dev/null || echo "1.0.0")

show_help() {
    echo "WhisperRecorder Version Manager"
    echo ""
    echo "Usage: $0 [command] [version]"
    echo ""
    echo "Commands:"
    echo "  current           Show current version"
    echo "  set <version>     Set specific version (e.g., 1.2.3)"
    echo "  bump major        Bump major version (1.0.0 → 2.0.0)"
    echo "  bump minor        Bump minor version (1.0.0 → 1.1.0)"  
    echo "  bump patch        Bump patch version (1.0.0 → 1.0.1)"
    echo "  tag               Create git tag for current version"
    echo "  tag-release       Create git tag and push (trigger GitHub workflow)"
    echo "  release           Local release (build, package, changelog, commit)"
    echo "  publish <type>    Full workflow (bump, build, changelog, GitHub release)"
    echo ""
    echo "Local workflow:"
    echo "  release           Build current version, update changelog, commit"
    echo ""
    echo "GitHub workflow:"
    echo "  publish major     Bump major → build → changelog → GitHub release"
    echo "  publish minor     Bump minor → build → changelog → GitHub release"
    echo "  publish patch     Bump patch → build → changelog → GitHub release"
    echo ""
    echo "Current version: $CURRENT_VERSION"
}

bump_version() {
    local type=$1
    local major minor patch
    
    IFS='.' read -r major minor patch <<< "$CURRENT_VERSION"
    
    case $type in
        major)
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            ;;
        patch)
            patch=$((patch + 1))
            ;;
        *)
            echo "❌ Invalid bump type: $type"
            exit 1
            ;;
    esac
    
    local new_version="$major.$minor.$patch"
    echo "$new_version" > VERSION
    echo "✅ Version bumped: $CURRENT_VERSION → $new_version"
}

set_version() {
    local version=$1
    
    # Validate version format
    if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "❌ Invalid version format. Use semver (e.g., 1.2.3)"
        exit 1
    fi
    
    echo "$version" > VERSION
    echo "✅ Version set to: $version"
}

create_tag() {
    local version=$(cat VERSION)
    local tag="v$version"
    
    echo "🏷️  Creating git tag: $tag"
    
    if git tag -l | grep -q "^$tag$"; then
        echo "❌ Tag $tag already exists"
        exit 1
    fi
    
    git tag -a "$tag" -m "WhisperRecorder v$version"
    echo "✅ Created tag: $tag"
}

update_changelog() {
    local version=$1
    local date=$(date +%Y-%m-%d)
    
    if [ ! -f "../CHANGELOG.md" ]; then
        echo "⚠️  CHANGELOG.md not found, skipping changelog update"
        return 0
    fi
    
    echo "📝 Updating CHANGELOG.md..."
    
    # Replace [Unreleased] with the new version
    sed -i.bak "s/## \[Unreleased\]/## [$version] - $date/" "../CHANGELOG.md"
    
    # Add new Unreleased section at the top using temp file approach
    echo "## [Unreleased]" > temp_section.md
    echo "" >> temp_section.md
    echo "### Added" >> temp_section.md
    echo "" >> temp_section.md
    echo "### Fixed" >> temp_section.md
    echo "" >> temp_section.md
    echo "### Changed" >> temp_section.md
    echo "" >> temp_section.md
    
    # Insert new unreleased section
    head -n $(grep -n "## \[$version\]" "../CHANGELOG.md" | cut -d: -f1 | head -1) "../CHANGELOG.md" > temp_changelog.md
    head -n -1 temp_changelog.md > temp_changelog2.md
    cat temp_section.md >> temp_changelog2.md
    tail -n +$(grep -n "## \[$version\]" "../CHANGELOG.md" | cut -d: -f1 | head -1) "../CHANGELOG.md" >> temp_changelog2.md
    mv temp_changelog2.md "../CHANGELOG.md"
    
    rm temp_section.md temp_changelog.md 2>/dev/null || true
    rm "../CHANGELOG.md.bak" 2>/dev/null || true
    
    echo "✅ CHANGELOG.md updated"
}

generate_release_notes() {
    local version=$1
    
    echo "📋 Generating release notes..."
    
    # Start release notes
    echo "# WhisperRecorder v$version" > release_notes.md
    echo "" >> release_notes.md
    
    # Extract changes from CHANGELOG.md if it exists
    if [ -f "../CHANGELOG.md" ]; then
        echo "## What's New" >> release_notes.md
        echo "" >> release_notes.md
        
        # Extract content for this version
        if grep -q "## \[$version\]" "../CHANGELOG.md"; then
            echo "### Changes in this release:" >> release_notes.md
            # Extract content between this version and next version section
            sed -n "/## \[$version\]/,/## \[/p" "../CHANGELOG.md" | sed '$d' | tail -n +2 >> release_notes.md
        else
            echo "### Recent changes:" >> release_notes.md
            # Fallback to git commits since last tag
            LAST_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
            if [ -n "$LAST_TAG" ]; then
                git log --pretty=format:"- %s" $LAST_TAG..HEAD >> release_notes.md
            else
                echo "- Initial release" >> release_notes.md
            fi
        fi
    else
        # Fallback to git commits
        echo "## Changes" >> release_notes.md
        echo "" >> release_notes.md
        LAST_TAG=$(git describe --tags --abbrev=0 HEAD^ 2>/dev/null || echo "")
        if [ -n "$LAST_TAG" ]; then
            echo "### Changes since $LAST_TAG:" >> release_notes.md
            git log --pretty=format:"- %s" $LAST_TAG..HEAD >> release_notes.md
        else
            echo "- Initial release" >> release_notes.md
        fi
    fi

    echo "" >> release_notes.md
    echo "## 🔓 Important Security Notice" >> release_notes.md
    echo "" >> release_notes.md
    echo "**If you see \"WhisperRecorder is damaged and can't be opened\":**" >> release_notes.md
    echo "" >> release_notes.md
    echo "This happens because the app is not code-signed with Apple Developer ID. Choose one solution:" >> release_notes.md
    echo "" >> release_notes.md
    echo "**Option 1 - Terminal command:**" >> release_notes.md
    echo "\`\`\`bash" >> release_notes.md
    echo "xattr -d com.apple.quarantine /Applications/WhisperRecorder.app" >> release_notes.md
    echo "\`\`\`" >> release_notes.md
    echo "" >> release_notes.md
    echo "**Option 2 - Right-click method:**" >> release_notes.md
    echo "- Right-click WhisperRecorder.app → \"Open\"" >> release_notes.md
    echo "- Click \"Open\" in the security dialog" >> release_notes.md
    echo "" >> release_notes.md
    echo "**Option 3 - System Preferences:**" >> release_notes.md
    echo "- System Preferences → Security & Privacy → General" >> release_notes.md
    echo "- Click \"Open Anyway\" next to WhisperRecorder message" >> release_notes.md
    echo "" >> release_notes.md
    echo "## 📦 Installation" >> release_notes.md
    echo "" >> release_notes.md
    echo "1. Download \`WhisperRecorder-v$version-macOS-arm64.zip\`" >> release_notes.md
    echo "2. Unzip and move \`WhisperRecorder.app\` to Applications folder" >> release_notes.md
    echo "3. **If blocked by macOS:** Use one of the methods above ☝️" >> release_notes.md
    echo "" >> release_notes.md
    echo "## Requirements" >> release_notes.md
    echo "" >> release_notes.md
    echo "- macOS 12.0+ (Monterey or later)" >> release_notes.md
    echo "- Apple Silicon (M1/M2/M3) Mac" >> release_notes.md
    echo "- Microphone access permission" >> release_notes.md
    echo "" >> release_notes.md
    echo "## Features" >> release_notes.md
    echo "" >> release_notes.md
    echo "- 🎙️ Real-time voice recording and transcription" >> release_notes.md
    echo "- 🤖 AI-powered text enhancement with multiple providers" >> release_notes.md
    echo "- 📋 Auto-paste to active applications" >> release_notes.md
    echo "- 💬 Smart toast notifications" >> release_notes.md
    echo "- ⚡ Offline Whisper AI models" >> release_notes.md
    echo "- 🌍 Multiple target languages" >> release_notes.md
    
    echo "✅ Release notes generated: release_notes.md"
}

create_github_release() {
    local version=$1
    local tag="v$version"
    local zip_file="WhisperRecorder-v$version-macOS-arm64.zip"
    
    # Check if GitHub CLI is installed
    if ! command -v gh &> /dev/null; then
        echo "❌ GitHub CLI (gh) not found. Install with: brew install gh"
        echo "   Or upload manually: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/releases/new"
        return 1
    fi
    
    # Check if authenticated
    if ! gh auth status &> /dev/null; then
        echo "❌ Not authenticated with GitHub. Run: gh auth login"
        return 1
    fi
    
    # Check if ZIP file exists
    if [ ! -f "$zip_file" ]; then
        echo "❌ Release ZIP not found: $zip_file"
        return 1
    fi
    
    echo "🚀 Creating GitHub release..."
    
    # Create release with ZIP attachment
    gh release create "$tag" "$zip_file" \
        --title "WhisperRecorder $version" \
        --notes-file release_notes.md \
        --latest
    
    if [ $? -eq 0 ]; then
        echo "✅ GitHub release created successfully!"
        echo "🌐 View: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/releases/latest"
    else
        echo "❌ Failed to create GitHub release"
        return 1
    fi
}

local_release() {
    local current_version=$(cat VERSION)
    
    echo "🔨 Starting local release workflow"
    echo "================================="
    echo "🔵 Current version: $current_version"
    
    # Check if working directory is clean
    if ! git diff-index --quiet HEAD --; then
        echo "❌ Working directory not clean. Commit changes first."
        exit 1
    fi
    
    # Step 1: Build app
    echo ""
    echo "🔨 Step 1/5: Building WhisperRecorder..."
    if ! ./whisper build; then
        echo "❌ Build failed"
        exit 1
    fi
    
    # Step 2: Create release package
    echo ""
    echo "📦 Step 2/5: Creating release package..."
    if ! echo "" | ./whisper release; then
        echo "❌ Release package creation failed"
        exit 1
    fi
    
    # Step 3: Rename ZIP with version
    echo ""
    echo "📝 Step 3/5: Renaming release package..."
    local zip_file="WhisperRecorder-v$current_version-macOS-arm64.zip"
    if [ -f "WhisperRecorder.zip" ]; then
        mv "WhisperRecorder.zip" "$zip_file"
        echo "✅ Created: $zip_file"
    else
        echo "❌ WhisperRecorder.zip not found"
        exit 1
    fi
    
    # Step 4: Update CHANGELOG
    echo ""
    echo "📝 Step 4/5: Updating CHANGELOG.md..."
    update_changelog "$current_version"
    
    # Step 5: Commit changes
    echo ""
    echo "💾 Step 5/5: Committing changes..."
    
    git add VERSION ../CHANGELOG.md
    git commit -m "Local release v$current_version

- Built and packaged WhisperRecorder.app
- Updated CHANGELOG.md with release date
- Created release package: $zip_file"
    
    echo ""
    echo "✅ Local release completed!"
    echo "=========================="
    echo "🔵 Version: $current_version"
    echo "📦 Package: $zip_file"
    echo "📝 CHANGELOG.md updated"
    echo ""
    echo "💡 Next steps:"
    echo "  • Test the release: open WhisperRecorder.app"
    echo "  • For GitHub release: ./whisper version publish <type>"
    echo "  • Manual upload: GitHub → Releases → New release"
}

github_publish_workflow() {
    local bump_type=$1
    local start_version=$CURRENT_VERSION
    
    echo "🚀 Starting GitHub publish workflow: $bump_type"
    echo "============================================="
    echo "🔵 Current version: $start_version"
    
    # Check if working directory is clean
    if ! git diff-index --quiet HEAD --; then
        echo "❌ Working directory not clean. Commit changes first."
        exit 1
    fi
    
    # Step 1: Bump version
    echo ""
    echo "📈 Step 1/7: Bumping version ($bump_type)..."
    bump_version "$bump_type"
    local new_version=$(cat VERSION)
    
    # Step 2: Build app
    echo ""
    echo "🔨 Step 2/7: Building WhisperRecorder..."
    if ! ./whisper build; then
        echo "❌ Build failed"
        exit 1
    fi
    
    # Step 3: Create release package
    echo ""
    echo "📦 Step 3/7: Creating release package..."
    if ! echo "" | ./whisper release; then
        echo "❌ Release package creation failed"
        exit 1
    fi
    
    # Step 4: Rename ZIP with version
    echo ""
    echo "📝 Step 4/7: Renaming release package..."
    local zip_file="WhisperRecorder-v$new_version-macOS-arm64.zip"
    if [ -f "WhisperRecorder.zip" ]; then
        mv "WhisperRecorder.zip" "$zip_file"
        echo "✅ Created: $zip_file"
    else
        echo "❌ WhisperRecorder.zip not found"
        exit 1
    fi
    
    # Step 5: Update CHANGELOG
    echo ""
    echo "📝 Step 5/7: Updating CHANGELOG.md..."
    update_changelog "$new_version"
    
    # Step 6: Generate release notes
    echo ""
    echo "📋 Step 6/7: Generating release notes..."
    generate_release_notes "$new_version"
    
    # Step 7: Commit and create GitHub release
    echo ""
    echo "🏷️  Step 7/7: Committing and creating GitHub release..."
    
    # Commit changes
    git add VERSION ../CHANGELOG.md
    git commit -m "Release v$new_version

- Bump version: $start_version → $new_version
- Update CHANGELOG.md with release date
- Created release package: $zip_file"
    
    # Create tag
    create_tag
    
    # Push changes and tag
    git push origin HEAD
    git push origin "v$new_version"
    
    # Create GitHub release
    create_github_release "$new_version"
    
    # Cleanup
    rm -f release_notes.md
    
    echo ""
    echo "🎉 GitHub publish workflow completed!"
    echo "=================================="
    echo "🔵 Version: $start_version → $new_version"
    echo "📦 Package: $zip_file"
    echo "🏷️  Tag: v$new_version"
    echo "📝 CHANGELOG.md updated"
    echo "🌐 GitHub: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/releases/latest"
}

simple_tag_release() {
    local version=$(cat VERSION)
    local tag="v$version"
    
    # Check if working directory is clean
    if ! git diff-index --quiet HEAD --; then
        echo "❌ Working directory not clean. Commit changes first."
        exit 1
    fi
    
    echo "🚀 Creating tag release for v$version..."
    
    # Create tag
    create_tag
    
    # Push tag to trigger GitHub release
    echo "📤 Pushing tag to GitHub..."
    git push origin "$tag"
    
    echo "✅ Tag release v$version triggered!"
    echo "🌐 Check: https://github.com/$(git config --get remote.origin.url | sed 's/.*github.com[:/]\([^.]*\).*/\1/')/actions"
}

case ${1:-help} in
    current)
        echo "Current version: $CURRENT_VERSION"
        ;;
    set)
        if [ -z "$2" ]; then
            echo "❌ Please specify version to set"
            exit 1
        fi
        set_version "$2"
        ;;
    bump)
        if [ -z "$2" ]; then
            echo "❌ Please specify bump type: major, minor, or patch"
            exit 1
        fi
        bump_version "$2"
        ;;
    tag)
        create_tag
        ;;
    tag-release)
        simple_tag_release
        ;;
    release)
        # Local release workflow
        local_release
        ;;
    publish)
        if [ -z "$2" ]; then
            echo "❌ Please specify bump type for GitHub publish"
            echo "Usage: ./whisper version publish <major|minor|patch>"
            exit 1
        else
            # GitHub publish workflow with bump type
            case "$2" in
                major|minor|patch)
                    github_publish_workflow "$2"
                    ;;
                *)
                    echo "❌ Invalid bump type: $2"
                    echo "Valid types: major, minor, patch"
                    exit 1
                    ;;
            esac
        fi
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        echo "❌ Unknown command: $1"
        show_help
        exit 1
        ;;
esac 