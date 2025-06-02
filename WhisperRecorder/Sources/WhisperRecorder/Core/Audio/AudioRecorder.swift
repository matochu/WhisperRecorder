import SwiftUI
import AVFoundation
import AVFAudio
import KeyboardShortcuts
import AppKit
import ApplicationServices
import Foundation

class AudioRecorder: ObservableObject {
    static let shared = AudioRecorder()

    // Audio engine components
    private var _audioEngine: AVAudioEngine?  // Renamed
    private var _inputNode: AVAudioInputNode?  // Renamed
    private var audioBuffer: [Float] = []
    private var isRecording = false
    private let whisperWrapper = WhisperWrapper.shared

    // System audio management
    private let systemAudioManager = SystemAudioManager.shared

    // Managers for extracted functionality
    private let accessibilityManager = AccessibilityManager.shared
    private let clipboardManager = ClipboardManager.shared

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
    private var recordingTimer: Timer?
    private var isRequestingMicPermission = false

    // Writing style selection
    @Published var selectedWritingStyle: WritingStyle = WritingStyle.styles[0]  // Default style
    @Published private(set) var isReformattingWithGemini = false
    
    // Storage for contextual workflow
    private var contextualClipboardContent: String = ""
    private var isContextualWorkflow: Bool = false

    // Status update callback
    var onStatusUpdate: (() -> Void)?

    // Delegation to managers
    var accessibilityPermissionsStatus: Bool { accessibilityManager.accessibilityPermissionsStatus }
    var hasAccessibilityPermissions: Bool { accessibilityManager.hasAccessibilityPermissions }
    var autoPasteEnabled: Bool { 
        get { clipboardManager.autoPasteEnabled }
        set { clipboardManager.autoPasteEnabled = newValue }
    }

    var hasModel: Bool {
        return whisperWrapper.isModelLoaded()
    }

    private init() {
        logInfo(.audio, "AudioRecorder initializing")

        // Check Application Support directory for the app
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperRecorder")
        logDebug(.storage, "Application Support directory: \(appSupport.path)")
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            do {
                try FileManager.default.createDirectory(
                    at: appSupport, withIntermediateDirectories: true)
                logInfo(.storage, "Created Application Support directory")
            } catch {
                logError(.storage, "Failed to create Application Support directory: \(error)")
            }
        }

        // Set up delegation to managers
        accessibilityManager.onStatusUpdate = { [weak self] in
            self?.onStatusUpdate?()
        }

        logInfo(.audio, "AudioRecorder initialization completed")
    }

    deinit {
        // Clean up observers and timers
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Accessibility Permissions (Delegated)
    
    func checkAccessibilityPermissions() -> Bool {
        return accessibilityManager.checkAccessibilityPermissions()
    }
    
    func requestAccessibilityPermissions() {
        accessibilityManager.requestAccessibilityPermissions()
    }
    
    func updateAccessibilityPermissionStatus() {
        accessibilityManager.updateAccessibilityPermissionStatus()
    }

    // MARK: - Clipboard Operations (Delegated)
    
    private func copyToClipboard(text: String) {
        clipboardManager.copyToClipboard(text: text)
    }

    // MARK: - Audio Engine Management

    // Getter for audioEngine - initializes on first access
    private func getAudioEngine() -> AVAudioEngine? {
        if _audioEngine == nil {
            logDebug(.audio, "Lazily initializing AVAudioEngine")
            _audioEngine = AVAudioEngine()
        }
        return _audioEngine
    }

    // Getter for inputNode - initializes on first access
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

    private func setupAudioTap() {
        guard let inputNode = getInputNode() else {  // Changed to use getter
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
        // Will resample in the callback to 16kHz for Whisper
        logDebug(.audio, "Installing audio tap")
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) {
            [weak self] buffer, time in
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

                guard
                    let convertedBuffer = AVAudioPCMBuffer(
                        pcmFormat: whisperFormat, frameCapacity: frameCount)
                else {
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
                        logInfo(.audio,
                            "Audio buffer exceeding maximum size (\(self.maxBufferSize) samples), trimming oldest data"
                        )
                        self.audioBuffer = Array(self.audioBuffer.suffix(self.maxBufferSize))
                    }

                    // Periodically log buffer size to avoid too many log entries
                    if self.audioBuffer.count % 16000 == 0 {  // Log roughly every second
                        logInfo(.audio,
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
                        logInfo(.audio,
                            "Audio buffer exceeding maximum size (\(self.maxBufferSize) samples), trimming oldest data"
                        )
                        self.audioBuffer = Array(self.audioBuffer.suffix(self.maxBufferSize))
                    }

                    // Periodically log buffer size
                    if self.audioBuffer.count % 16000 == 0 {
                        logInfo(.audio,
                            "Audio buffer size: \(self.audioBuffer.count) samples (\(self.audioBuffer.count / 16000) seconds)"
                        )
                    }
                }
            }
        }
    }

    private func showPermissionAlert() {
        logInfo(.audio, "Showing microphone permission alert")
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
        logInfo(.audio, "Toggle recording called")

        // Check if model is available first
        if !whisperWrapper.isModelLoaded() {
            logInfo(.audio, "Cannot record: no whisper model loaded")
            lastTranscription = "Please download a Whisper model first"
            statusDescription = "No model available"
            onStatusUpdate?()

            // Show notification if available
            // Notifications removed - requires Apple Developer certificate
            
            return
        }
        
        // SMART SHORTCUT HANDLING: If we're in contextual workflow mode and recording,
        // the toggle shortcut should stop the contextual recording properly
        if isContextualWorkflow && isRecording {
            logInfo(.audio, "🎯 Contextual workflow active - stopping contextual recording via toggle shortcut")
            stopRecording()
            return
        }
        
        // SMART SHORTCUT HANDLING: If we're in contextual workflow but not recording yet,
        // ignore the toggle shortcut to avoid conflicts
        if isContextualWorkflow {
            logInfo(.audio, "🎯 Contextual workflow active - ignoring toggle shortcut (not recording)")
            return
        }

        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        logInfo(.audio, "Starting recording")

        // Check microphone permission status for macOS
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            logInfo(.audio, "Microphone permission granted")
            // Proceed with recording
            self.actuallyStartRecording()
        case .denied:
            logInfo(.audio, "Microphone permission denied")
            // Show an alert to the user
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
                    self?.isRequestingMicPermission = false  // Reset flag here
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
        case .restricted:  // macOS specific case
            logInfo(.audio, "Microphone permission restricted")
            // Show an alert to the user, similar to denied
            DispatchQueue.main.async {
                self.showPermissionAlert()  // Or a more specific alert for restricted access
                self.statusDescription = "Mic permission restricted"
                self.onStatusUpdate?()
            }
            return
        @unknown default:
            logInfo(.audio, "Unknown microphone permission status")
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
        logInfo(.audio, "Actually starting recording")
        
        // Hide any existing toast when starting new recording
        ToastManager.shared.hideToastForNewRecording()
        
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
            getInputNode()?.removeTap(onBus: 0)  // Changed to use getter

            // Set up the audio tap
            logInfo(.audio, "Setting up audio tap")  // Changed comment
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

    private func showRecordingErrorAlert(error: Error? = nil) {
        logError(.audio, "Showing recording error alert: \(error?.localizedDescription ?? "unknown error")")
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
        logInfo(.audio, "Stopping recording")
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
        logInfo(.audio, "Recording stopped. Buffer size: \(audioBuffer.count) samples")
        onStatusUpdate?()

        // Process the audio buffer
        if !audioBuffer.isEmpty {
            logInfo(.audio, "Transcribing \(audioBuffer.count) PCM samples directly")
            transcribeAudioBuffer()
        } else {
            logInfo(.audio, "No audio data recorded")
        }
    }

    private func transcribeAudioBuffer() {
        logInfo(.audio, "Starting transcription pipeline")
        logDebug(.audio, "Audio buffer contains \(audioBuffer.count) samples")
        
        startTiming("transcription_pipeline")
        isTranscribing = true
        statusDescription = "Transcribing..."
        onStatusUpdate?()

        // Use a background thread for transcription
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Verify that the buffer is not empty
            guard !self.audioBuffer.isEmpty else {
                logError(.audio, "❌ Error: Audio buffer is empty")
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.statusDescription = "Ready"
                    self.lastTranscription = "Error: No audio recorded"
                    self.onStatusUpdate?()
                }
                return
            }
            
            // Add buffer validation to prevent GGML crashes
            let bufferSize = self.audioBuffer.count
            let maxSafeSize = 16000 * 300 // 5 minutes at 16kHz
            let minSafeSize = 8000 // 0.5 seconds at 16kHz
            
            guard bufferSize >= minSafeSize else {
                logError(.audio, "❌ Audio buffer too small: \(bufferSize) samples (min: \(minSafeSize))")
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.statusDescription = "Ready"
                    self.lastTranscription = "Error: Recording too short"
                    self.onStatusUpdate?()
                }
                return
            }
            
            if bufferSize > maxSafeSize {
                logWarning(.audio, "⚠️ Large audio buffer: \(bufferSize) samples, trimming to last \(maxSafeSize)")
                self.audioBuffer = Array(self.audioBuffer.suffix(maxSafeSize))
            }
            
            logDebug(.audio, "✅ Audio buffer validated: \(self.audioBuffer.count) samples")

            // Step 1: Whisper Transcription
            logInfo(.audio, "🎤 Starting Whisper transcription...")
            logDebug(.audio, "Sending \(self.audioBuffer.count) samples to Whisper for transcription")
            
            startTiming("whisper_transcription")
            let transcription = self.whisperWrapper.transcribePCM(audioData: self.audioBuffer)
            let whisperTime = endTiming("whisper_transcription")
            
            logInfo(.audio, "✅ Whisper transcription completed in \(String(format: "%.3f", whisperTime ?? 0))s")
            logInfo(.audio, "📝 Raw Whisper output: \"\(transcription)\"")
            logDebug(.audio, "Raw transcription length: \(transcription.count) characters")

            // Store the original Whisper transcription
            AppDelegate.lastOriginalWhisperText = transcription
            logDebug(.storage, "Stored original Whisper text: \(transcription.count) characters")

            // Step 2: Check if we need reformatting or translation (normal workflow)
            let currentTargetLang = WritingStyleManager.shared.currentTargetLanguage
            let noTranslateValue = WritingStyleManager.shared.noTranslate
            
            logDebug(.llm, "Current settings check:")
            logDebug(.llm, "  - Writing style: \(self.selectedWritingStyle.name) (\(self.selectedWritingStyle.id))")
            logDebug(.llm, "  - Target language: \(currentTargetLang)")
            logDebug(.llm, "  - No-translate value: \(noTranslateValue)")
            logDebug(.llm, "  - Needs style formatting: \(self.selectedWritingStyle.id != "default")")
            logDebug(.llm, "  - Needs translation: \(currentTargetLang != noTranslateValue)")
            logDebug(.llm, "  - Has contextual content: \(self.isContextualWorkflow)")
            
            let needsProcessing = self.selectedWritingStyle.id != "default" || 
                                 currentTargetLang != noTranslateValue ||
                                 self.isContextualWorkflow
            
            if !needsProcessing {
                logInfo(.audio, "📋 Using default style and no translation - no reformatting needed")
                self.lastTranscription = transcription
                
                // Store as processed text even though it's the same as original
                AppDelegate.lastProcessedText = transcription
                logDebug(.storage, "Stored processed text (same as original): \(transcription.count) characters")
                
                let totalTime = endTiming("transcription_pipeline")
                logInfo(.performance, "🏁 Total pipeline time: \(String(format: "%.3f", totalTime ?? 0))s (Whisper only)")

                // Copy to clipboard
                DispatchQueue.main.async {
                    self.copyToClipboard(text: transcription)
                    
                    self.isTranscribing = false
                    self.statusDescription = "Ready"
                    self.onStatusUpdate?()
                    logInfo(.audio, "✅ Transcription pipeline complete (no processing needed)")
                    
                    // Play completion sound with logging
                    logDebug(.audio, "🔊 Playing completion sound")
                    
                    if let sound = NSSound(named: "Tink") {
                        sound.volume = 1.2
                        sound.play()
                        logDebug(.audio, "✅ Tink sound played")
                    } else {
                        NSSound.beep()
                        logDebug(.audio, "🔔 System beep played")
                    }
                }
                return
            }

            // Step 3: LLM Processing (reformatting, translation, and/or contextual processing)
            DispatchQueue.main.async {
                if self.isContextualWorkflow {
                    self.statusDescription = "Processing with context..."
                } else {
                    self.statusDescription = "Processing..."
                }
                self.isReformattingWithGemini = true
                self.onStatusUpdate?()
            }

            let processingType = self.isContextualWorkflow ? "contextual" : "style/translation"
            logInfo(.audio, "🤖 Starting \(processingType) processing...")
            logInfo(.llm, "Selected writing style: \(self.selectedWritingStyle.name) (\(self.selectedWritingStyle.id))")
            logInfo(.llm, "Target language: \(WritingStyleManager.supportedLanguages[WritingStyleManager.shared.currentTargetLanguage] ?? WritingStyleManager.shared.currentTargetLanguage)")
            logInfo(.llm, "Input text for processing: \"\(transcription)\"")
            
            if self.isContextualWorkflow {
                logInfo(.llm, "Contextual content: \"\(self.contextualClipboardContent)\"")
            }
            
            startTiming("llm_processing")

            // Pass context to existing reformatText method if available
            if self.isContextualWorkflow {
                WritingStyleManager.shared.reformatTextWithContext(
                    transcription, 
                    withStyle: self.selectedWritingStyle,
                    context: self.contextualClipboardContent
                ) { reformattedText in
                    self.handleProcessingResult(reformattedText, originalText: transcription, processingType: "contextual")
                }
            } else {
                WritingStyleManager.shared.reformatText(
                    transcription, withStyle: self.selectedWritingStyle
                ) { reformattedText in
                    self.handleProcessingResult(reformattedText, originalText: transcription, processingType: "style/translation")
                }
            }
            
            // Safety fallback: If callback never gets called, reset state after 30 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                if self.isTranscribing || self.isReformattingWithGemini {
                    logWarning(.audio, "🚨 Processing timeout - forcefully resetting to Ready state")
                    self.isTranscribing = false
                    self.isReformattingWithGemini = false
                    self.statusDescription = "Ready"
                    self.isContextualWorkflow = false
                    self.contextualClipboardContent = ""
                    self.onStatusUpdate?()
                    
                    // Use original transcription as fallback
                    if self.lastTranscription == nil || self.lastTranscription?.isEmpty == true {
                        self.lastTranscription = transcription
                        AppDelegate.lastProcessedText = transcription
                        self.copyToClipboard(text: transcription)
                    }
                }
            }
        }
    }

    // MARK: - Contextual Processing with Clipboard Content
    
    func processWithClipboardContext() {
        logInfo(.audio, "🔄 Contextual processing workflow triggered")
        
        // If already in contextual workflow, ignore repeated calls
        if isContextualWorkflow {
            logInfo(.audio, "🔄 Contextual workflow already active - ignoring repeated call")
            return
        }
        
        // Check if already recording - if so, stop current recording first
        if isRecording {
            logInfo(.audio, "📴 Stopping current recording for contextual processing")
            stopRecording()
            // Wait a moment for recording to stop properly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startContextualWorkflow()
            }
            return
        }
        
        startContextualWorkflow()
    }
    
    private func startContextualWorkflow() {
        logInfo(.audio, "🎯 Starting contextual workflow...")
        
        // First, try to get selected text from active application
        if let selectedText = accessibilityManager.getSelectedText(), !selectedText.isEmpty {
            logInfo(.audio, "✅ Using selected text as context: \(selectedText.count) characters")
            contextualClipboardContent = selectedText
            
            ToastManager.shared.showToast(
                message: "Using selected text as context. Speak your response now...",
                preview: String(selectedText.prefix(100)) + (selectedText.count > 100 ? "..." : "")
            )
        } else {
            // Fallback: get content from clipboard
            logInfo(.audio, "📋 No selected text found, falling back to clipboard content")
            let clipboard = NSPasteboard.general
            if let clipboardContent = clipboard.string(forType: .string), !clipboardContent.isEmpty {
                contextualClipboardContent = clipboardContent
                logInfo(.audio, "✅ Using clipboard content as context: \(clipboardContent.count) characters")
                
                ToastManager.shared.showToast(
                    message: "Using clipboard content as context. Speak your response now...",
                    preview: String(clipboardContent.prefix(100)) + (clipboardContent.count > 100 ? "..." : "")
                )
            } else {
                logWarning(.audio, "❌ No context available (no selected text or clipboard content)")
                ToastManager.shared.showToast(
                    message: "No context available. Speaking voice-only...",
                    preview: ""
                )
                contextualClipboardContent = ""
            }
        }
        
        // Set contextual workflow flag
        isContextualWorkflow = true
        
        // Start voice recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.startRecording()
        }
    }
    
    private func handleProcessingResult(_ reformattedText: String?, originalText: String, processingType: String) {
        let totalTime = endTiming("llm_processing")
        logInfo(.performance, "🏁 Total pipeline time: \(String(format: "%.3f", totalTime ?? 0))s")
        
        DispatchQueue.main.async {
            // Always reset status and contextual state
            defer {
                self.isTranscribing = false
                self.isReformattingWithGemini = false
                self.statusDescription = "Ready"
                
                // Clean contextual state
                let wasContextual = self.isContextualWorkflow
                self.isContextualWorkflow = false
                self.contextualClipboardContent = ""
                
                if wasContextual {
                    logInfo(.audio, "🧹 Contextual workflow state cleaned up")
                }
                
                self.onStatusUpdate?()
                
                // Play completion sound with logging
                logDebug(.audio, "🔊 Playing completion sound")
                
                if let sound = NSSound(named: "Tink") {
                    sound.volume = 1.2
                    sound.play()
                    logDebug(.audio, "✅ Tink sound played")
                } else {
                    NSSound.beep()
                    logDebug(.audio, "🔔 System beep played")
                }
            }
            
            if let processedText = reformattedText {
                logInfo(.audio, "✅ \(processingType) processing completed in \(String(format: "%.3f", totalTime ?? 0))s")
                logInfo(.performance, "🏁 Total pipeline time: \(String(format: "%.3f", totalTime ?? 0))s")
                
                self.lastTranscription = processedText
                AppDelegate.lastProcessedText = processedText
                
                // Copy result to clipboard using copyToClipboard for auto-paste functionality
                self.copyToClipboard(text: processedText)
                
                // Show success toast
                ToastManager.shared.showToast(
                    message: self.isContextualWorkflow ? "Contextual response generated" : "Processing complete",
                    preview: processedText
                )
                
                logInfo(.audio, "✅ \(processingType) workflow complete - response copied to clipboard")
            } else {
                logError(.audio, "❌ \(processingType) processing failed")
                
                // Fallback to original transcription
                self.lastTranscription = originalText
                AppDelegate.lastProcessedText = originalText
                self.copyToClipboard(text: originalText)
                
                ToastManager.shared.showToast(
                    message: "Processing failed - using voice text", 
                    preview: originalText
                )
            }
        }
    }
}
