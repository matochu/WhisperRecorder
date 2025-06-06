import AVFoundation
import CoreAudio
import Foundation

class SystemAudioManager: ObservableObject {
    static let shared = SystemAudioManager()

    private var previousVolume: Float = 0.0
    private var wasSystemMuted: Bool = false
    private var audioDeviceID: AudioDeviceID = kAudioObjectUnknown

    private init() {
        setupAudioDevice()
    }

    private func setupAudioDevice() {
        // Get the default output device
        var deviceID: AudioDeviceID = kAudioObjectUnknown
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )

        if status == noErr {
            audioDeviceID = deviceID
            logInfo(.audio, "SystemAudioManager: Found default output device ID: \(deviceID)")
        } else {
            logError(.audio, "SystemAudioManager: Failed to get default output device, error: \(status)")
        }
    }

    func muteSystemAudio() {
        guard audioDeviceID != kAudioObjectUnknown else {
            logError(.audio, "SystemAudioManager: No audio device available for muting")
            return
        }

        // Store the current volume and mute state for restoration
        previousVolume = getCurrentVolume()
        wasSystemMuted = isSystemMuted()

        logInfo(.audio,
            "SystemAudioManager: Storing current volume: \(previousVolume), muted: \(wasSystemMuted)"
        )

        // Mute the system audio with timeout protection
        DispatchQueue.global(qos: .userInitiated).async {
            let timeoutSeconds: TimeInterval = 2.0
            let group = DispatchGroup()
            group.enter()
            
            var success = false
            DispatchQueue.global(qos: .utility).async {
                success = self.setSystemMuted(true)
                group.leave()
            }
            
            let result = group.wait(timeout: .now() + timeoutSeconds)
            
            DispatchQueue.main.async {
                if result == .timedOut {
                    logError(.audio, "SystemAudioManager: Mute operation timed out after \(timeoutSeconds)s")
                } else if success {
                    logInfo(.audio, "SystemAudioManager: System audio muted for recording")
                } else {
                    logError(.audio, "SystemAudioManager: Failed to mute system audio")
                }
            }
        }
    }

    func unmuteSystemAudio() {
        guard audioDeviceID != kAudioObjectUnknown else {
            logError(.audio, "SystemAudioManager: No audio device available for unmuting")
            return
        }

        logInfo(.audio,
            "SystemAudioManager: Restoring volume: \(previousVolume), was muted: \(wasSystemMuted)"
        )

        // Restore the system audio with timeout protection
        DispatchQueue.global(qos: .userInitiated).async {
            let timeoutSeconds: TimeInterval = 2.0
            let group = DispatchGroup()
            group.enter()
            
            var success = false
            DispatchQueue.global(qos: .utility).async {
                // Restore the original mute state
                if !self.wasSystemMuted {
                    success = self.setSystemMuted(false)
                }
                
                // Restore the original volume
                if success || self.wasSystemMuted {
                    self.setVolume(self.previousVolume)
        }
                group.leave()
            }
            
            let result = group.wait(timeout: .now() + timeoutSeconds)
            
            DispatchQueue.main.async {
                if result == .timedOut {
                    logError(.audio, "SystemAudioManager: Unmute operation timed out after \(timeoutSeconds)s")
                } else {
                    logInfo(.audio, "SystemAudioManager: System audio restored after recording")
                }
            }
        }
    }

    private func getCurrentVolume() -> Float {
        var volume: Float = 0.0
        var dataSize = UInt32(MemoryLayout<Float>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            audioDeviceID,
            &address,
            0,
            nil,
            &dataSize,
            &volume
        )

        if status == noErr {
            return volume
        } else {
            logError(.audio, "SystemAudioManager: Failed to get current volume, error: \(status)")
            return 0.0
        }
    }

    private func setVolume(_ volume: Float) {
        var volumeValue = volume
        let dataSize = UInt32(MemoryLayout<Float>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            audioDeviceID,
            &address,
            0,
            nil,
            dataSize,
            &volumeValue
        )

        if status != noErr {
            logError(.audio, "SystemAudioManager: Failed to set volume, error: \(status)")
        }
    }

    private func isSystemMuted() -> Bool {
        var muted: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            audioDeviceID,
            &address,
            0,
            nil,
            &dataSize,
            &muted
        )

        if status == noErr {
            return muted != 0
        } else {
            logError(.audio, "SystemAudioManager: Failed to get mute state, error: \(status)")
            return false
        }
    }

    private func setSystemMuted(_ muted: Bool) -> Bool {
        var mutedValue: UInt32 = muted ? 1 : 0
        let dataSize = UInt32(MemoryLayout<UInt32>.size)

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectSetPropertyData(
            audioDeviceID,
            &address,
            0,
            nil,
            dataSize,
            &mutedValue
        )

        if status != noErr {
            logError(.audio, "SystemAudioManager: Failed to set mute state, error: \(status)")
            return false
        }
        return true
    }

    // Emergency restore function - called on app termination
    func emergencyRestoreAudio() {
        logWarning(.audio, "SystemAudioManager: Emergency audio restore called")
        
        // Attempt to restore to a safe state
        if !wasSystemMuted {
            logInfo(.audio, "SystemAudioManager: Emergency restore - unmuting system audio")
            _ = setSystemMuted(false)
            if previousVolume > 0 {
                setVolume(previousVolume)
            }
        }
    }
    
    // Alias for emergencyRestoreAudio for backwards compatibility
    func emergencyRestore() {
        emergencyRestoreAudio()
    }
}
