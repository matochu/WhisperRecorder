# Troubleshooting WhisperRecorder

## 🛡️ Safe Debug Modes

### Debug Scripts (All Safe by Default)

All debug scripts now include automatic process cleanup and locks to prevent multiple instances:

1.  **`./debug-run.sh`** - Interactive debug with terminal output

    - ✅ Kills existing processes
    - ✅ Creates debug lock
    - ✅ All logs in terminal
    - 🛑 Press Ctrl+C to stop

2.  **`./debug-lldb.sh`** - Full debugger with LLDB
    - ✅ Kills existing processes
    - ✅ Creates debug lock
    - ✅ Starts LLDB with binary
    - 🔍 Full debugging capabilities

### Usage Examples

```bash
# Interactive terminal debug
./debug-run.sh
# All logs appear in terminal

# Full LLDB debugging
./debug-lldb.sh
# Then in LLDB: (lldb) run
```

## Process Hangs (UE State)

### Symptoms:

- The `WhisperRecorder.bin` process is not responding.
- `ps aux` shows the status `UE` (Uninterruptible Sleep + Traced).
- `kill -9` does not work.
- In the logs: repetition of `app read bytes, space = 131072`.

### Causes:

1.  **AVAudioEngine freeze** - blocking on `installTap` or `audioEngine.start()`.
2.  **Core Audio daemon issues** - `coreaudiod` is frozen or unavailable.
3.  **Audio device conflict** - another process has locked the microphone.
4.  **SystemAudioManager** - hang on `AudioObjectSetPropertyData`.

### Solutions:

#### 🚨 Emergency Unblocking:

```bash
# 1. Restart the Core Audio daemon
sudo killall coreaudiod

# 2. If that doesn't help, fully reset the audio subsystem
sudo launchctl bootout system /System/Library/LaunchDaemons/com.apple.audio.coreaudiod.plist
sudo launchctl load /System/Library/LaunchDaemons/com.apple.audio.coreaudiod.plist

# 3. Last resort - reboot the system
sudo reboot
```

#### 🔍 Diagnosis:

```bash
# Run the debug script
./debug-audio.sh

# Check for processes in UE state
ps aux | awk '$8 ~ /U/ && $8 ~ /E/ {print $2, $8, $11}'

# Check audio connections
lsof | grep -i audio
```

#### ⚡ Prevention:

1.  **Do not run from the terminal/Cursor** - this can cause permission issues.
2.  **Close other audio applications** before recording.
3.  **Grant accessibility permissions** correctly.
4.  **Use only one instance** of the program.

### New Protections (v2.1+):

- ✅ Timeout protection for the audio engine (5 seconds)
- ✅ Timeout protection for SystemAudioManager (2 seconds)
- ✅ Asynchronous audio buffer processing
- ✅ Buffer overflow protection
- ✅ Reduced logging frequency

### Contacts for Debug:

If the problem persists, please send:

1.  Output of `./debug-audio.sh`
2.  Console.app logs with the filter "WhisperRecorder"
3.  System information: `system_profiler SPAudioDataType`
