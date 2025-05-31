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

        // Mute the system audio
        setSystemMuted(true)

        logInfo(.audio, "SystemAudioManager: System audio muted for recording")
    }

    func unmuteSystemAudio() {
        guard audioDeviceID != kAudioObjectUnknown else {
            logError(.audio, "SystemAudioManager: No audio device available for unmuting")
            return
        }

        // Restore the previous volume and mute state
        if !wasSystemMuted {
            setSystemMuted(false)
            if previousVolume > 0 {
                setVolume(previousVolume)
            }
        }

        logInfo(.audio,
            "SystemAudioManager: System audio restored to volume: \(previousVolume), muted: \(wasSystemMuted)"
        )
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

    private func setSystemMuted(_ muted: Bool) {
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
        }
    }

    // Emergency restore function - called on app termination
    func emergencyRestore() {
        if !wasSystemMuted {
            logInfo(.audio, "SystemAudioManager: Emergency restore - unmuting system audio")
            setSystemMuted(false)
            if previousVolume > 0 {
                setVolume(previousVolume)
            }
        }
    }
}
