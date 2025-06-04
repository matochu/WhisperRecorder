# WhisperRecorder Release Guide

This guide explains how to create releases for WhisperRecorder using the automated GitHub workflow system.

## 🚀 Release Methods

WhisperRecorder supports **3 ways** to create releases:

### Method 1: Automatic Release (Recommended)

```bash
# Update version and create release in one command
./whisper version release
```

This will:

1. Create a git tag (e.g., `v1.4.0`)
2. Push the tag to GitHub
3. Automatically trigger the GitHub Action
4. Build and package the app
5. Create a GitHub release with assets

### Method 2: Step-by-Step

```bash
# 1. Set new version
./whisper version set 1.4.0

# 2. Commit changes
git add .
git commit -m "Release v1.4.0"

# 3. Create and push tag
./whisper version tag
git push origin v1.4.0
```

### Method 3: Manual GitHub Workflow

1. Go to **https://github.com/your-repo/actions**
2. Select **"WhisperRecorder Release"** workflow
3. Click **"Run workflow"**
4. Choose version bump type:
   - **patch** → 1.4.0 → 1.4.1
   - **minor** → 1.4.0 → 1.5.0
   - **major** → 1.4.0 → 2.0.0
5. Click **"Run workflow"**

## 🌿 Feature Branch Releases

For testing and preview releases from feature branches:

```bash
# From feature branch (e.g., feat/ui-improvements)
# 1. Go to GitHub Actions
# 2. Run workflow with "Create pre-release" checked
# 3. This creates: v1.4.1-feat-ui-improvements
# 4. Marked as "pre-release" on GitHub
```

## 📝 Release Notes Generation

Release notes are automatically generated from **CHANGELOG.md**:

### CHANGELOG.md Structure

```markdown
## [Unreleased]

### Added

- New feature description
- Another feature

### Fixed

- Bug fix description

### Changed

- Change description

## [1.3.1] - Previous Release

...
```

### How It Works

1. **From main branch**: Uses `[Unreleased]` section from CHANGELOG.md
2. **From feature branch**: Creates pre-release with branch-specific notes
3. **After release**: Automatically updates CHANGELOG.md (main branch only)

## ⚙️ GitHub Workflow Features

The automated workflow includes:

### Smart Versioning

- **Dropdown selection** instead of manual version entry
- **Semantic versioning** (patch/minor/major)
- **Feature branch support** with pre-release tags

### Build Process

- **Safe build environment** with process monitoring
- **Automatic artifact creation**: `WhisperRecorder-v1.4.0-macOS-arm64.zip`
- **Asset upload** to GitHub Releases

### Release Management

- **CHANGELOG integration** for professional release notes
- **Pre-release support** for feature branches
- **Automatic tagging** and version management

## 🔧 Version Management Commands

```bash
# Show current version
./whisper version

# Set specific version
./whisper version set 1.4.0

# Bump version
./whisper version bump patch   # 1.4.0 → 1.4.1
./whisper version bump minor   # 1.4.0 → 1.5.0
./whisper version bump major   # 1.4.0 → 2.0.0

# Create git tag
./whisper version tag

# Full release (tag + GitHub trigger)
./whisper version release
```

## 📋 Release Checklist

### Before Release

- [ ] All features tested and working
- [ ] Update CHANGELOG.md `[Unreleased]` section
- [ ] Commit all changes to your branch
- [ ] Verify build passes: `./whisper build`

### Release Process

- [ ] Choose release method (automatic/manual/GitHub)
- [ ] Select version bump type (patch/minor/major)
- [ ] Monitor GitHub Action progress
- [ ] Verify release assets are created
- [ ] Test downloaded release package

### After Release

- [ ] Verify release notes are correct
- [ ] Test installation on clean system
- [ ] Update project documentation if needed
- [ ] Announce release to users

## 🎯 Examples

### Patch Release (Bug Fixes)

```bash
# Current: v1.4.0 → New: v1.4.1
./whisper version bump patch
./whisper version release
```

### Minor Release (New Features)

```bash
# Current: v1.4.0 → New: v1.5.0
./whisper version bump minor
./whisper version release
```

### Major Release (Breaking Changes)

```bash
# Current: v1.4.0 → New: v2.0.0
./whisper version bump major
./whisper version release
```

### Feature Branch Preview

```bash
# From feat/new-ui branch
# GitHub Actions → Run workflow → Check "pre-release"
# Result: v1.4.1-feat-new-ui (marked as pre-release)
```

## ⚠️ Important Notes

1. **Main Branch Releases**: Full releases should be done from `main` branch
2. **Feature Branch Releases**: Automatically marked as pre-release
3. **CHANGELOG Updates**: Only happen on main branch releases
4. **Version Synchronization**: VERSION file is the single source of truth
5. **Asset Naming**: Follows pattern `WhisperRecorder-v{version}-macOS-arm64.zip`

## 🔍 Troubleshooting

### Workflow Fails

- Check GitHub Actions logs
- Verify permissions are correct
- Ensure no hanging processes on runner

### Wrong Version

- Use `./whisper version set X.Y.Z` to fix
- Create new release with correct version

### Missing Release Notes

- Update CHANGELOG.md `[Unreleased]` section
- Re-run the workflow

---

**For more information**, see the main [README.md](README.md) and [whisper script](whisper) documentation.
