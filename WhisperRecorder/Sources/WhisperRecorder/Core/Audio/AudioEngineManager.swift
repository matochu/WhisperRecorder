import SwiftUI
import AVFoundation
import AVFAudio
import AppKit
import Foundation

// MARK: - Audio Engine Manager

class AudioEngineManager: ObservableObject {
    
    // Audio engine components
    private var _audioEngine: AVAudioEngine?
    private var _inputNode: AVAudioInputNode?
    private var audioBuffer: [Float] = []
    private var recordingTimer: Timer?
    private var isRequestingMicPermission = false
    
    // Configuration
    private let sampleRate: Double = 16000.0
    private let channelCount: Int = 1
    private let maxBufferSize: Int = 16000 * 60 * 5  // 5 minutes
    
    // State
    @Published private(set) var isRecording = false
    @Published private(set) var recordingDurationSeconds: Int = 0
    @Published var statusDescription: String = "Ready"
    
    // Dependencies
    private let systemAudioManager = SystemAudioManager.shared
    
    // Callbacks
    var onStatusUpdate: (() -> Void)?
    var onAudioDataReady: (([Float]) -> Void)?
    
    // MARK: - Public Interface
    
    func toggleRecording() {
        logInfo(.audio, "Toggle recording called")
        
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    func startRecording() {
        logInfo(.audio, "Starting recording")

        // Check microphone permission status for macOS
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            logInfo(.audio, "Microphone permission granted")
            self.actuallyStartRecording()
        case .denied:
            logInfo(.audio, "Microphone permission denied")
            DispatchQueue.main.async {
                self.showPermissionAlert()
                self.statusDescription = "Mic permission denied"
                self.onStatusUpdate?()
            }
            return
        case .notDetermined:
            guard !isRequestingMicPermission else {
                logInfo(.audio, "Microphone permission request already in progress.")
                return
            }
            logInfo(.audio, "Microphone permission undetermined, requesting...")
            isRequestingMicPermission = true
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isRequestingMicPermission = false
                    if granted {
                        logInfo(.audio, "Microphone permission granted after request")
                        self?.actuallyStartRecording()
                    } else {
                        logInfo(.audio, "Microphone permission denied after request")
                        self?.showPermissionAlert()
                        self?.statusDescription = "Mic permission denied"
                        self?.onStatusUpdate?()
                    }
                }
            }
            return
        case .restricted:
            logInfo(.audio, "Microphone permission restricted")
            DispatchQueue.main.async {
                self.showPermissionAlert()
                self.statusDescription = "Mic permission restricted"
                self.onStatusUpdate?()
            }
            return
        @unknown default:
            logInfo(.audio, "Unknown microphone permission status")
            DispatchQueue.main.async {
                self.showRecordingErrorAlert()
                self.statusDescription = "Mic permission error"
                self.onStatusUpdate?()
            }
            return
        }
    }
    
    func stopRecording(shouldProcess: Bool = true) {
        logInfo(.audio, "Stopping recording (shouldProcess: \(shouldProcess))")
        
        // Stop the audio engine and remove tap
        getAudioEngine()?.stop()
        getInputNode()?.removeTap(onBus: 0)
        isRecording = false

        // Invalidate the recording timer
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Restore system audio after stopping recording
        systemAudioManager.unmuteSystemAudio()

        statusDescription = "Ready"
        logInfo(.audio, "Recording stopped. Buffer size: \(audioBuffer.count) samples")
        onStatusUpdate?()

        // Send audio data if available and processing is requested
        if !audioBuffer.isEmpty && shouldProcess {
            logInfo(.audio, "Sending \(audioBuffer.count) PCM samples for processing")
            onAudioDataReady?(audioBuffer)
        } else if !audioBuffer.isEmpty {
            logInfo(.audio, "Audio data available (\(audioBuffer.count) samples) but processing skipped")
        } else {
            logInfo(.audio, "No audio data recorded")
        }
    }
    
    func getRecordingDuration() -> Int {
        return recordingDurationSeconds
    }
    
    func isCurrentlyRecording() -> Bool {
        return isRecording
    }
    
    // MARK: - Private Implementation
    
    private func getAudioEngine() -> AVAudioEngine? {
        if _audioEngine == nil {
            logDebug(.audio, "Lazily initializing AVAudioEngine")
            _audioEngine = AVAudioEngine()
        }
        return _audioEngine
    }

    private func getInputNode() -> AVAudioInputNode? {
        if _inputNode == nil {
            guard let engine = getAudioEngine() else {
                logError(.audio, "Cannot initialize inputNode without audioEngine")
                return nil
            }
            logDebug(.audio, "Lazily initializing AVAudioInputNode")
            _inputNode = engine.inputNode
            if _inputNode == nil {
                logError(.audio, "Failed to get input node from audio engine during lazy init.")
            }
        }
        return _inputNode
    }
    
    private func actuallyStartRecording() {
        logInfo(.audio, "Actually starting recording")
        
        // Reset audio buffer
        audioBuffer = []
        recordingDurationSeconds = 0

        // Mute system audio before starting recording
        systemAudioManager.muteSystemAudio()

        // Set up timer to update recording duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.recordingDurationSeconds += 1
        }

        do {
            guard let audioEngine = getAudioEngine() else {
                logError(.audio, "Audio engine not initialized (lazy init failed)")
                return
            }

            // If the audio engine is already running, stop it first
            if audioEngine.isRunning {
                logInfo(.audio, "Audio engine already running, stopping it first")
                audioEngine.stop()
            }

            // Remove any existing taps
            logInfo(.audio, "Removing existing tap")
            getInputNode()?.removeTap(onBus: 0)

            // Set up the audio tap
            logInfo(.audio, "Setting up audio tap")
            setupAudioTap()

            // Prepare and start the audio engine
            logInfo(.audio, "Starting audio engine")
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            statusDescription = "Recording..."
            logInfo(.audio, "Recording started successfully")
            onStatusUpdate?()
        } catch {
            logError(.audio, "Failed to start audio engine: \(error)")
            // If recording failed, restore system audio
            systemAudioManager.unmuteSystemAudio()
            showRecordingErrorAlert(error: error)
        }
    }
    
    private func setupAudioTap() {
        guard let inputNode = getInputNode() else {
            logError(.audio, "Failed to get input node for setupAudioTap")
            return
        }

        // Get the native format from the input hardware
        let nativeFormat = inputNode.inputFormat(forBus: 0)
        logDebug(.audio, "Native audio format: \(nativeFormat)")

        // Create a format for the converter output that matches what whisper.cpp expects
        let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false)

        guard let whisperFormat = whisperFormat else {
            logError(.audio, "Failed to create whisper audio format")
            return
        }

        logDebug(.audio, "Whisper audio format: \(whisperFormat)")

        // Install tap using the native hardware format
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) { [weak self] buffer, time in
            guard let self = self, self.isRecording else { return }
            
            // Create a converter to Whisper's format if needed
            if nativeFormat.sampleRate != self.sampleRate {
                // Create a new AVAudioConverter to convert the sample rate
                guard let converter = AVAudioConverter(from: nativeFormat, to: whisperFormat) else {
                    logError(.audio, "Failed to create audio converter")
                    return
                }

                // Calculate the new frame count based on the ratio of sample rates
                let ratio = Double(whisperFormat.sampleRate) / Double(nativeFormat.sampleRate)
                let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: whisperFormat, frameCapacity: frameCount) else {
                    logError(.audio, "Failed to create output buffer for conversion")
                    return
                }

                // Perform the conversion
                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }

                converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

                if let error = error {
                    logError(.audio, "Error converting audio: \(error)")
                    return
                }

                // Process the converted buffer
                if let channelData = convertedBuffer.floatChannelData, convertedBuffer.frameLength > 0 {
                    let channelDataValue = channelData.pointee
                    let frames = convertedBuffer.frameLength

                    // Append the converted audio data to our buffer
                    var samples = [Float](repeating: 0, count: Int(frames))
                    for i in 0..<Int(frames) {
                        samples[i] = channelDataValue[i]
                    }
                    
                    self.audioBuffer.append(contentsOf: samples)

                    // Check if buffer exceeds maximum size and trim if needed
                    if self.audioBuffer.count > self.maxBufferSize {
                        logInfo(.audio, "Audio buffer exceeding maximum size (\(self.maxBufferSize) samples), trimming oldest data")
                        self.audioBuffer = Array(self.audioBuffer.suffix(self.maxBufferSize))
                    }

                    // Periodically log buffer size to avoid too many log entries
                    if self.audioBuffer.count % 16000 == 0 {  // Log roughly every second
                        logInfo(.audio, "Audio buffer size: \(self.audioBuffer.count) samples (\(self.audioBuffer.count / 16000) seconds)")
                    }
                }
            } else {
                // No conversion needed, process directly
                if let channelData = buffer.floatChannelData, buffer.frameLength > 0 {
                    let channelDataValue = channelData.pointee
                    let frames = buffer.frameLength

                    // Append the audio data to our buffer
                    var samples = [Float](repeating: 0, count: Int(frames))
                    for i in 0..<Int(frames) {
                        samples[i] = channelDataValue[i]
                    }

                    self.audioBuffer.append(contentsOf: samples)

                    // Check if buffer exceeds maximum size and trim if needed
                    if self.audioBuffer.count > self.maxBufferSize {
                        logInfo(.audio, "Audio buffer exceeding maximum size (\(self.maxBufferSize) samples), trimming oldest data")
                        self.audioBuffer = Array(self.audioBuffer.suffix(self.maxBufferSize))
                    }

                    // Periodically log buffer size
                    if self.audioBuffer.count % 16000 == 0 {
                        logInfo(.audio, "Audio buffer size: \(self.audioBuffer.count) samples (\(self.audioBuffer.count / 16000) seconds)")
                    }
                }
            }
        }
    }
    
    private func showPermissionAlert() {
        logInfo(.audio, "Showing microphone permission alert")
        let alert = NSAlert()
        alert.messageText = "Microphone Access Required"
        alert.informativeText = "WhisperRecorder needs access to your microphone to transcribe audio. Please grant access in System Preferences > Security & Privacy > Privacy > Microphone."
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    private func showRecordingErrorAlert(error: Error? = nil) {
        logError(.audio, "Showing recording error alert: \(error?.localizedDescription ?? "unknown error")")
        let alert = NSAlert()
        alert.messageText = "Recording Error"
        if let error = error {
            alert.informativeText = "Failed to start recording: \(error.localizedDescription)"
        } else {
            alert.informativeText = "Failed to start recording. Please check your microphone settings."
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
} 