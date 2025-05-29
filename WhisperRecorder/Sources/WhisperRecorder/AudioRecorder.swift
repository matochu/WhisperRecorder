import AVFoundation
import AppKit
import Foundation
import UserNotifications

class AudioRecorder: NSObject, ObservableObject {
    static let shared = AudioRecorder()

    // Audio engine components
    private var _audioEngine: AVAudioEngine?  // Renamed
    private var _inputNode: AVAudioInputNode?  // Renamed
    private var audioBuffer: [Float] = []
    private var isRecording = false
    private let whisperWrapper = WhisperWrapper.shared

    // System audio management
    private let systemAudioManager = SystemAudioManager.shared

    // Sample rate and channel count should match what whisper.cpp expects
    private let sampleRate: Double = 16000.0
    private let channelCount: Int = 1

    // Maximum buffer size in samples (approximately 5 minutes at 16kHz)
    private let maxBufferSize: Int = 16000 * 60 * 5

    // Status information
    @Published private(set) var isTranscribing = false
    @Published private(set) var lastTranscription: String?
    @Published var statusDescription: String = "Ready"
    @Published private(set) var recordingDurationSeconds: Int = 0
    private var notificationsAvailable = false
    private var recordingTimer: Timer?
    private var isRequestingMicPermission = false  // Add this line

    // Writing style selection
    @Published var selectedWritingStyle: WritingStyle = WritingStyle.styles[0]  // Default style
    @Published private(set) var isReformattingWithGemini = false

    // Status update callback
    var onStatusUpdate: (() -> Void)?

    var hasModel: Bool {
        return whisperWrapper.isModelLoaded()
    }

    private override init() {
        super.init()
        writeLog("AudioRecorder initializing")

        // Check Application Support directory for the app
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperRecorder")
        writeLog("Application Support directory: \(appSupport.path)")
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            do {
                try FileManager.default.createDirectory(
                    at: appSupport, withIntermediateDirectories: true)
                writeLog("Created Application Support directory")
            } catch {
                writeLog("Failed to create Application Support directory: \(error)")
            }
        }

        // NOTE: AVAudioEngine and inputNode are NOT initialized here anymore.
        // They will be lazily initialized by their respective getter methods.

        // Check if notifications are available
        if Bundle.main.bundleIdentifier != nil {
            writeLog("Requesting notification permissions")
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
                granted, error in
                if let error = error {
                    writeLog("Error requesting notification permission: \(error)")
                } else if granted {
                    writeLog("Notification permission granted")
                    self.notificationsAvailable = true
                } else {
                    writeLog("Notification permission denied")
                }
            }
        } else {
            writeLog("Running without bundle identifier, notifications disabled")
        }

        // Register for model download progress updates
        whisperWrapper.onDownloadProgressUpdate = { [weak self] in
            DispatchQueue.main.async {
                if self?.whisperWrapper.isDownloading == true {
                    self?.statusDescription =
                        "Downloading model: \(Int(self?.whisperWrapper.downloadProgress ?? 0 * 100))%"
                } else {
                    self?.statusDescription = "Ready"
                }
                self?.onStatusUpdate?()
            }
        }
    }

    // Getter for audioEngine - initializes on first access
    private func getAudioEngine() -> AVAudioEngine? {
        if _audioEngine == nil {
            writeLog("Lazily initializing AVAudioEngine")
            _audioEngine = AVAudioEngine()
        }
        return _audioEngine
    }

    // Getter for inputNode - initializes on first access
    private func getInputNode() -> AVAudioInputNode? {
        if _inputNode == nil {
            guard let engine = getAudioEngine() else {
                writeLog("Cannot initialize inputNode without audioEngine")
                return nil
            }
            writeLog("Lazily initializing AVAudioInputNode")
            _inputNode = engine.inputNode
            if _inputNode == nil {
                writeLog("Failed to get input node from audio engine during lazy init.")
            }
        }
        return _inputNode
    }

    private func setupAudioTap() {
        guard let inputNode = getInputNode() else {  // Changed to use getter
            writeLog("Failed to get input node for setupAudioTap")
            return
        }

        // Get the native format from the input hardware
        let nativeFormat = inputNode.inputFormat(forBus: 0)
        writeLog("Native audio format: \(nativeFormat)")

        // Create a format for the converter output that matches what whisper.cpp expects
        let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false)

        guard let whisperFormat = whisperFormat else {
            writeLog("Failed to create whisper audio format")
            return
        }

        writeLog("Whisper audio format: \(whisperFormat)")

        // Install tap using the native hardware format
        // Will resample in the callback to 16kHz for Whisper
        writeLog("Installing audio tap")
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) {
            [weak self] buffer, time in
            guard let self = self, self.isRecording else { return }

            // Create a converter to Whisper's format if needed
            if nativeFormat.sampleRate != self.sampleRate {
                // Create a new AVAudioConverter to convert the sample rate
                guard let converter = AVAudioConverter(from: nativeFormat, to: whisperFormat) else {
                    writeLog("Failed to create audio converter")
                    return
                }

                // Calculate the new frame count based on the ratio of sample rates
                let ratio = Double(whisperFormat.sampleRate) / Double(nativeFormat.sampleRate)
                let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

                guard
                    let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: whisperFormat, frameCapacity: frameCount)
                else {
                    writeLog("Failed to create output buffer for conversion")
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
                    writeLog("Error converting audio: \(error)")
                    return
                }

                // Process the converted buffer
                if let channelData = convertedBuffer.floatChannelData,
                    convertedBuffer.frameLength > 0
                {
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
                        writeLog(
                            "Audio buffer exceeding maximum size (\(self.maxBufferSize) samples), trimming oldest data"
                        )
                        self.audioBuffer = Array(self.audioBuffer.suffix(self.maxBufferSize))
                    }

                    // Periodically log buffer size to avoid too many log entries
                    if self.audioBuffer.count % 16000 == 0 {  // Log roughly every second
                        writeLog(
                            "Audio buffer size: \(self.audioBuffer.count) samples (\(self.audioBuffer.count / 16000) seconds)"
                        )
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
                        writeLog(
                            "Audio buffer exceeding maximum size (\(self.maxBufferSize) samples), trimming oldest data"
                        )
                        self.audioBuffer = Array(self.audioBuffer.suffix(self.maxBufferSize))
                    }

                    // Periodically log buffer size
                    if self.audioBuffer.count % 16000 == 0 {
                        writeLog(
                            "Audio buffer size: \(self.audioBuffer.count) samples (\(self.audioBuffer.count / 16000) seconds)"
                        )
                    }
                }
            }
        }
    }

    private func showPermissionAlert() {
        writeLog("Showing microphone permission alert")
        let alert = NSAlert()
        alert.messageText = "Microphone Access Required"
        alert.informativeText =
            "WhisperRecorder needs access to your microphone to transcribe audio. Please grant access in System Preferences > Security & Privacy > Privacy > Microphone."
        alert.addButton(withTitle: "Open System Preferences")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            ) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func toggleRecording() {
        writeLog("Toggle recording called")

        // Check if model is available first
        if !whisperWrapper.isModelLoaded() {
            writeLog("Cannot record: no whisper model loaded")
            lastTranscription = "Please download a Whisper model first"
            statusDescription = "No model available"
            onStatusUpdate?()

            // Show notification if available
            if notificationsAvailable {
                let content = UNMutableNotificationContent()
                content.title = "Model Required"
                content.body = "Please download a Whisper model to use recording."
                let request = UNNotificationRequest(
                    identifier: "modelMissing", content: content, trigger: nil)
                UNUserNotificationCenter.current().add(request)
            }
            return
        }

        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        writeLog("Starting recording")

        // Check microphone permission status for macOS
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            writeLog("Microphone permission granted")
            // Proceed with recording
            self.actuallyStartRecording()
        case .denied:
            writeLog("Microphone permission denied")
            // Show an alert to the user
            DispatchQueue.main.async {
                self.showPermissionAlert()
                self.statusDescription = "Mic permission denied"
                self.onStatusUpdate?()
            }
            return
        case .notDetermined:
            guard !isRequestingMicPermission else {
                writeLog("Microphone permission request already in progress.")
                return
            }
            writeLog("Microphone permission undetermined, requesting...")
            isRequestingMicPermission = true
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isRequestingMicPermission = false  // Reset flag here
                    if granted {
                        writeLog("Microphone permission granted after request")
                        self?.actuallyStartRecording()
                    } else {
                        writeLog("Microphone permission denied after request")
                        self?.showPermissionAlert()
                        self?.statusDescription = "Mic permission denied"
                        self?.onStatusUpdate?()
                    }
                }
            }
            return
        case .restricted:  // macOS specific case
            writeLog("Microphone permission restricted")
            // Show an alert to the user, similar to denied
            DispatchQueue.main.async {
                self.showPermissionAlert()  // Or a more specific alert for restricted access
                self.statusDescription = "Mic permission restricted"
                self.onStatusUpdate?()
            }
            return
        @unknown default:
            writeLog("Unknown microphone permission status")
            // Handle appropriately, perhaps by showing an error
            DispatchQueue.main.async {
                self.showRecordingErrorAlert()
                self.statusDescription = "Mic permission error"
                self.onStatusUpdate?()
            }
            return
        }
    }

    private func actuallyStartRecording() {
        writeLog("Actually starting recording")
        // Reset audio buffer
        audioBuffer = []
        recordingDurationSeconds = 0

        // Mute system audio before starting recording
        systemAudioManager.muteSystemAudio()

        // Set up timer to update recording duration
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) {
            [weak self] _ in
            guard let self = self else { return }
            self.recordingDurationSeconds += 1
            self.onStatusUpdate?()
        }

        do {
            guard let audioEngine = getAudioEngine() else {  // Changed to use getter
                writeLog("Audio engine not initialized (lazy init failed)")
                return
            }

            // If the audio engine is already running, stop it first
            if audioEngine.isRunning {
                writeLog("Audio engine already running, stopping it first")
                audioEngine.stop()
            }

            // Remove any existing taps
            writeLog("Removing existing tap")
            getInputNode()?.removeTap(onBus: 0)  // Changed to use getter

            // Set up the audio tap
            writeLog("Setting up audio tap")  // Changed comment
            setupAudioTap()

            // Prepare and start the audio engine
            writeLog("Starting audio engine")
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            statusDescription = "Recording..."
            writeLog("Recording started successfully")
            onStatusUpdate?()
        } catch {
            writeLog("Failed to start audio engine: \(error)")
            // If recording failed, restore system audio
            systemAudioManager.unmuteSystemAudio()
            showRecordingErrorAlert(error: error)
        }
    }

    private func showRecordingErrorAlert(error: Error? = nil) {
        writeLog("Showing recording error alert: \(error?.localizedDescription ?? "unknown error")")
        let alert = NSAlert()
        alert.messageText = "Recording Error"
        if let error = error {
            alert.informativeText = "Failed to start recording: \(error.localizedDescription)"
        } else {
            alert.informativeText =
                "Failed to start recording. Please check your microphone settings."
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func stopRecording() {
        writeLog("Stopping recording")
        // Stop the audio engine and remove tap
        getAudioEngine()?.stop()  // Changed to use getter
        getInputNode()?.removeTap(onBus: 0)  // Changed to use getter
        isRecording = false

        // Invalidate the recording timer
        recordingTimer?.invalidate()
        recordingTimer = nil

        // Restore system audio after stopping recording
        systemAudioManager.unmuteSystemAudio()

        statusDescription = "Ready"
        writeLog("Recording stopped. Buffer size: \(audioBuffer.count) samples")
        onStatusUpdate?()

        // Process the audio buffer
        if !audioBuffer.isEmpty {
            writeLog("Transcribing \(audioBuffer.count) PCM samples directly")
            transcribeAudioBuffer()
        } else {
            writeLog("No audio data recorded")
        }
    }

    private func transcribeAudioBuffer() {
        writeLog("Starting transcription")
        isTranscribing = true
        statusDescription = "Transcribing..."
        onStatusUpdate?()

        // Use a background thread for transcription
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Verify that the buffer is not empty
            guard !self.audioBuffer.isEmpty else {
                writeLog("Error: Audio buffer is empty")
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.statusDescription = "Ready"
                    self.lastTranscription = "Error: No audio recorded"
                    self.onStatusUpdate?()
                }
                return
            }

            // Process the audio buffer with whisper.cpp
            writeLog("Sending \(self.audioBuffer.count) samples to Whisper for transcription")
            let transcription = self.whisperWrapper.transcribePCM(audioData: self.audioBuffer)

            // If using default style, just use the transcription directly
            if self.selectedWritingStyle.id == "default" {
                self.lastTranscription = transcription
                writeLog(
                    "Using default style, transcription complete: \(transcription.prefix(100))...")

                // Copy to clipboard
                DispatchQueue.main.async {
                    self.copyToClipboard(text: transcription)
                    self.isTranscribing = false
                    self.statusDescription = "Ready"
                    self.onStatusUpdate?()
                    writeLog("Status updated after transcription")

                    // Show notification if available
                    if self.notificationsAvailable {
                        self.showNotification(
                            message: "Transcription copied to clipboard",
                            title: "Transcription Complete")
                    }
                }
                return
            }

            // If using a writing style, reformat with Gemini
            DispatchQueue.main.async {
                self.statusDescription = "Reformatting..."
                self.isReformattingWithGemini = true
                self.onStatusUpdate?()
            }

            writeLog("Reformatting with Gemini using style: \(self.selectedWritingStyle.name)")

            WritingStyleManager.shared.reformatText(
                transcription, withStyle: self.selectedWritingStyle
            ) { reformattedText in
                DispatchQueue.main.async {
                    if let reformattedText = reformattedText {
                        self.lastTranscription = reformattedText
                        writeLog("Reformatting complete: \(reformattedText.prefix(100))...")
                        self.copyToClipboard(text: reformattedText)
                        if self.notificationsAvailable {
                            self.showNotification(
                                message: "Reformatted text copied to clipboard",
                                title: "Reformatting Complete")
                        }
                    } else {
                        // If reformatting failed, use original transcription
                        writeLog("Reformatting failed, using original transcription")
                        self.lastTranscription = transcription
                        self.copyToClipboard(text: transcription)
                        if self.notificationsAvailable {
                            self.showNotification(
                                message: "Transcription copied to clipboard (reformatting failed)",
                                title: "Reformatting Failed")
                        }
                    }

                    self.isTranscribing = false
                    self.isReformattingWithGemini = false
                    self.statusDescription = "Ready"
                    self.onStatusUpdate?()
                }
            }
        }
    }

    private func copyToClipboard(text: String) {
        writeLog("Copying to clipboard: \(text.prefix(50))...")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    private func showNotification(message: String, title: String = "WhisperRecorder") {
        writeLog("Showing notification: \(message)")
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                writeLog("Error showing notification: \(error)")
            }
        }
    }
}
