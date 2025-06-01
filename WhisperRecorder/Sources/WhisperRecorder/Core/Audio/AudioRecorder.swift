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
    private var isRequestingMicPermission = false  // Add this line

    // Writing style selection
    @Published var selectedWritingStyle: WritingStyle = WritingStyle.styles[0]  // Default style
    @Published private(set) var isReformattingWithGemini = false
    @Published var autoPasteEnabled: Bool = true  // Add auto-paste control

    // Status update callback
    var onStatusUpdate: (() -> Void)?

    // Accessibility permissions status - reactive property
    @Published var accessibilityPermissionsStatus: Bool = false

    // Timer for periodic permission checks
    private var permissionCheckTimer: Timer?

    // Backward compatibility
    var hasAccessibilityPermissions: Bool {
        return accessibilityPermissionsStatus
    }

    // Check if app was launched from terminal/cursor
    private var isLaunchedFromTerminal: Bool {
        // Check if parent process is terminal-like
        let parentPID = getppid()
        if let parentName = getProcessName(for: parentPID) {
            let terminalProcesses = ["Terminal", "iTerm", "cursor", "zsh", "bash", "fish"]
            return terminalProcesses.contains { parentName.lowercased().contains($0.lowercased()) }
        }
        return false
    }

    private func getProcessName(for pid: pid_t) -> String? {
        var name = [CChar](repeating: 0, count: 4096) // Use fixed size instead of PROC_PIDPATHINFO_MAXSIZE
        if proc_pidpath(pid, &name, 4096) > 0 {
            return String(cString: name).components(separatedBy: "/").last
        }
        return nil
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

        // NOTE: AVAudioEngine and inputNode are NOT initialized here anymore.
        // They will be lazily initialized by their respective getter methods.

        // Set up permission monitoring
        logInfo(.system, "Setting up permission monitoring...")
        setupPermissionMonitoring()
        logInfo(.audio, "AudioRecorder initialization completed")
    }

    deinit {
        // Clean up observers and timers
        NotificationCenter.default.removeObserver(self)
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }

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

            // Step 2: Check if we need reformatting or translation
            let currentTargetLang = WritingStyleManager.shared.currentTargetLanguage
            let noTranslateValue = WritingStyleManager.shared.noTranslate
            
            logDebug(.llm, "Current settings check:")
            logDebug(.llm, "  - Writing style: \(self.selectedWritingStyle.name) (\(self.selectedWritingStyle.id))")
            logDebug(.llm, "  - Target language: \(currentTargetLang)")
            logDebug(.llm, "  - No-translate value: \(noTranslateValue)")
            logDebug(.llm, "  - Needs style formatting: \(self.selectedWritingStyle.id != "default")")
            logDebug(.llm, "  - Needs translation: \(currentTargetLang != noTranslateValue)")
            
            let needsProcessing = self.selectedWritingStyle.id != "default" || 
                                 currentTargetLang != noTranslateValue
            
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
                }
                return
            }

            // Step 3: Gemini Processing (reformatting and/or translation)
            DispatchQueue.main.async {
                self.statusDescription = "Processing..."
                self.isReformattingWithGemini = true
                self.onStatusUpdate?()
            }

            logInfo(.audio, "🤖 Starting Gemini processing (style: \(self.selectedWritingStyle.name), translation: \(WritingStyleManager.shared.currentTargetLanguage))...")
            logInfo(.llm, "Selected writing style: \(self.selectedWritingStyle.name) (\(self.selectedWritingStyle.id))")
            logInfo(.llm, "Target language: \(WritingStyleManager.supportedLanguages[WritingStyleManager.shared.currentTargetLanguage] ?? WritingStyleManager.shared.currentTargetLanguage)")
            logInfo(.llm, "Input text for processing: \"\(transcription)\"")
            
            startTiming("gemini_processing")

            WritingStyleManager.shared.reformatText(
                transcription, withStyle: self.selectedWritingStyle
            ) { reformattedText in
                let geminiTime = endTiming("gemini_processing")
                let totalTime = endTiming("transcription_pipeline")
                
                DispatchQueue.main.async {
                    if let reformattedText = reformattedText {
                        logInfo(.llm, "✅ Gemini processing completed in \(String(format: "%.3f", geminiTime ?? 0))s")
                        logInfo(.llm, "📝 Reformatted output: \"\(reformattedText)\"")
                        logInfo(.performance, "🏁 Total pipeline time: \(String(format: "%.3f", totalTime ?? 0))s (Whisper: \(String(format: "%.3f", whisperTime ?? 0))s + Gemini: \(String(format: "%.3f", geminiTime ?? 0))s)")
                        
                        self.lastTranscription = reformattedText
                        
                        // Store the processed text
                        AppDelegate.lastProcessedText = reformattedText
                        logDebug(.storage, "Stored processed text: \(reformattedText.count) characters")
                        
                        self.copyToClipboard(text: reformattedText)
                        
                        logInfo(.audio, "✅ Full transcription pipeline complete with processing")
                    } else {
                        // If processing failed, use original transcription
                        logWarning(.llm, "❌ Gemini processing failed, falling back to original transcription")
                        logInfo(.performance, "🏁 Pipeline completed with fallback - total time: \(String(format: "%.3f", totalTime ?? 0))s")
                        
                        self.lastTranscription = transcription
                        
                        // Store original as processed text since processing failed
                        AppDelegate.lastProcessedText = transcription
                        logDebug(.storage, "Stored processed text (fallback to original): \(transcription.count) characters")
                        
                        self.copyToClipboard(text: transcription)
                        
                        logInfo(.audio, "✅ Transcription pipeline complete (fallback to original)")
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
        logInfo(.audio, "🔄 Starting clipboard sequence...")
        
        let originalText = AppDelegate.lastOriginalWhisperText
        let processedText = text
        
        logDebug(.audio, "Original text: \(originalText.isEmpty ? "empty" : "\(originalText.count) chars")")
        logDebug(.audio, "Processed text: \(processedText.isEmpty ? "empty" : "\(processedText.count) chars")")
        
        // If we have processing (translation/style), only copy the final result
        // Only copy both if processing failed and we're falling back to original
        let needsProcessing = self.selectedWritingStyle.id != "default" || 
                             WritingStyleManager.shared.currentTargetLanguage != WritingStyleManager.shared.noTranslate
        
        if needsProcessing && !processedText.isEmpty && processedText != originalText {
            // We have successful processing - only copy the processed text
            logInfo(.audio, "📄 Using processed text only (translation/style applied)")
            self.copyTextToClipboard(processedText, label: "processed")
        } else if !originalText.isEmpty {
            // No processing or processing failed - copy original only
            logInfo(.audio, "📄 Using original text (no processing or fallback)")
            self.copyTextToClipboard(originalText, label: "original")
        } else {
            logWarning(.audio, "❌ No text available to copy")
        }
    }
    
    private func copyTextToClipboard(_ text: String, label: String) {
        logInfo(.audio, "📋 Copying \(label) text to clipboard: \"\(text.prefix(50))\(text.count > 50 ? "..." : "")\"")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        
        if success {
            logInfo(.audio, "✅ Successfully copied \(label) text (\(text.count) chars)")
            
            // Verify what's actually in clipboard
            if let clipboardContent = pasteboard.string(forType: .string) {
                logDebug(.audio, "📋 Clipboard verification: \(clipboardContent.count) chars, matches: \(clipboardContent == text)")
            }
            
            // Auto-paste to active input
            if self.autoPasteEnabled {
                self.autoPasteToActiveInput()
            } else {
                logDebug(.audio, "Auto-paste disabled by user")
            }
        } else {
            logError(.audio, "❌ Failed to copy \(label) text to clipboard")
        }
    }
    
    private func autoPasteToActiveInput() {
        // Check if accessibility permissions are enabled
        guard self.autoPasteEnabled else {
            logDebug(.audio, "Auto-paste disabled by user")
            return
        }
        
        // Check accessibility permissions - silently skip if no permissions
        if !AXIsProcessTrusted() {
            logInfo(.audio, "❌ Auto-paste skipped - no accessibility permissions")
            return
        }
        
        // Simply perform paste - try multiple methods with delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            logInfo(.audio, "🎯 Attempting auto-paste with multiple methods...")
            self.performPaste()
        }
    }
    
    private func performPaste() {
        // Method 1: Try NSApp sendAction
        logDebug(.audio, "Method 1: NSApp.sendAction")
        let result1 = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        logDebug(.audio, "NSApp.sendAction result: \(result1)")
        
        // Method 2: Try CGEvent immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            logDebug(.audio, "Method 2: CGEvent")
            self.sendPasteKeyEvent()
        }
        
        // Method 3: Try NSApp sendAction to first responder specifically
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            logDebug(.audio, "Method 3: Targeted sendAction")
            if let window = NSApp.keyWindow,
               let responder = window.firstResponder {
                logDebug(.audio, "Sending paste to responder: \(type(of: responder))")
                NSApp.sendAction(#selector(NSText.paste(_:)), to: responder, from: nil)
            }
        }
        
        // Method 4: Try AppleScript approach
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            logDebug(.audio, "Method 4: AppleScript")
            self.applescriptPaste()
        }
    }
    
    private func sendPasteKeyEvent() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Send Cmd+V with proper timing
        if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) {
            keyDownEvent.flags = .maskCommand
            keyDownEvent.post(tap: .cghidEventTap)
            
            // Small delay before key up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
                    keyUpEvent.flags = .maskCommand
                    keyUpEvent.post(tap: .cghidEventTap)
                    logDebug(.audio, "CGEvent paste sent")
                }
            }
        }
    }
    
    private func applescriptPaste() {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                logDebug(.audio, "AppleScript error: \(error)")
            } else {
                logDebug(.audio, "AppleScript paste executed")
            }
        }
    }

    // MARK: - Accessibility Permissions
    
    func checkAccessibilityPermissions() -> Bool {
        logInfo(.system, "Checking accessibility permissions...")
        
        // Check WITHOUT showing system prompt
        let accessibilityEnabled = AXIsProcessTrusted()
        
        if accessibilityEnabled {
            logInfo(.system, "✅ Accessibility permissions granted")
        } else {
            logWarning(.system, "❌ Accessibility permissions not granted")
        }
        
        return accessibilityEnabled
    }
    
    func requestAccessibilityPermissions() {
        logInfo(.system, "Requesting accessibility permissions...")
        
        // Check if launched from terminal - for terminal launches, open System Preferences directly
        if isLaunchedFromTerminal {
            logWarning(.system, "⚠️ App launched from terminal/cursor - opening System Preferences directly")
            openAccessibilityPreferences()
            return
        }
        
        // For Finder launches: try to show system dialog
        logInfo(.system, "📱 App launched from Finder - attempting to show system permissions dialog")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if accessibilityEnabled {
            logInfo(.system, "✅ Accessibility permissions already granted")
        } else {
            logInfo(.system, "📝 System permissions dialog should appear for Finder launch")
            // Don't add fallback for Finder launches - let the system dialog do its work
        }
    }
    
    private func openAccessibilityPreferences() {
        logInfo(.system, "Opening System Preferences > Privacy & Security > Accessibility")
        
        // URL to open System Preferences to Accessibility section
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        
        NSWorkspace.shared.open(prefPaneURL, configuration: NSWorkspace.OpenConfiguration()) { (app, error) in
            if let error = error {
                logError(.system, "❌ Failed to open Accessibility preferences: \(error)")
                
                // Fallback: open general Security & Privacy
                let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
                NSWorkspace.shared.open(fallbackURL, configuration: NSWorkspace.OpenConfiguration()) { (_, fallbackError) in
                    if let fallbackError = fallbackError {
                        logError(.system, "❌ Failed to open Security & Privacy preferences: \(fallbackError)")
                    } else {
                        logInfo(.system, "✅ Opened Security & Privacy preferences (general)")
                    }
                }
            } else {
                logInfo(.system, "✅ Successfully opened Accessibility preferences")
            }
        }
    }

    private func setupPermissionMonitoring() {
        logInfo(.system, "Setting up permission monitoring...")
        
        // Initial status check
        updateAccessibilityPermissionStatus()
        
        // Monitor app focus changes only
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            logDebug(.system, "App became active - checking permissions")
            self?.updateAccessibilityPermissionStatus()
        }
        
        // Remove periodic timer - only manual checks now
    }
    
    func updateAccessibilityPermissionStatus() {
        let newStatus = AXIsProcessTrusted()
        let processName = ProcessInfo.processInfo.processName
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        
        logDebug(.system, "🔍 Permission check: AXIsProcessTrusted() = \(newStatus)")
        logDebug(.system, "🔍 Process name: \(processName)")
        logDebug(.system, "🔍 Bundle ID: \(bundleId)")
        logDebug(.system, "🔍 Current status: \(accessibilityPermissionsStatus)")
        
        if newStatus != accessibilityPermissionsStatus {
            logInfo(.system, "♻️ Accessibility permission status changed: \(accessibilityPermissionsStatus) → \(newStatus)")
            DispatchQueue.main.async {
                self.accessibilityPermissionsStatus = newStatus
                self.onStatusUpdate?()
            }
        } else {
            // Update without logging for routine checks, but force update UI anyway
            DispatchQueue.main.async {
                self.accessibilityPermissionsStatus = newStatus
            }
        }
    }
}
