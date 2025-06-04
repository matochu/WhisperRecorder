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
    echo "  release           Create git tag and push for GitHub release"
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

create_release() {
    local version=$(cat VERSION)
    local tag="v$version"
    
    # Check if working directory is clean
    if ! git diff-index --quiet HEAD --; then
        echo "❌ Working directory not clean. Commit changes first."
        exit 1
    fi
    
    echo "🚀 Preparing release for v$version..."
    
    # Create tag
    create_tag
    
    # Push tag to trigger GitHub release
    echo "📤 Pushing tag to GitHub..."
    git push origin "$tag"
    
    echo "✅ Release v$version triggered!"
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
    release)
        create_release
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