# Scripts Directory

This directory contains legacy scripts for reference and advanced usage. For normal use, the main `./whisper` script should be used instead.

## Legacy Scripts (Archived)

### Build Scripts

- `build.sh` - Original complex build script with architecture options
- `package_app.sh` - Complex packaging with signing and full features
- `package_app_simple.sh` - Simplified packaging without signing

### Run Scripts

- `run.sh` - Safe runner with process cleanup
- `run_whisper.sh` - Simple runner with library path
- `launch_properly.sh` - Launch through Finder for permissions

### Debug Scripts

- `debug-run.sh` - Interactive debug with terminal output
- `debug-lldb.sh` - Full LLDB debugging
- `emergency-cleanup.sh` - Emergency process cleanup

## Current Usage

**Use the main script instead:**

```bash
# Build the app
./whisper build

# Run the app
./whisper run

# Debug interactively
./whisper debug

# Debug with LLDB
./whisper lldb

# Emergency cleanup
./whisper cleanup

# See all options
./whisper help
```

## Migration Notes

The main `./whisper` script combines all functionality from these legacy scripts in a safe, unified interface:

- All process checking and cleanup is automatic
- Lockfiles prevent multiple instances
- No parallel jobs to avoid lipo conflicts
- Consistent error handling across all operations
- Simple, memorable commands

Legacy scripts are kept for reference but should not be used directly.
