import AVFoundation
import AppKit
import Foundation
import UserNotifications
import ApplicationServices

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
    
    // Auto-paste control with persistence
    @Published var autoPasteEnabled: Bool {
        didSet {
            print("🎯 [AUTO-PASTE] autoPasteEnabled changed: \(oldValue) → \(autoPasteEnabled)")
            UserDefaults.standard.set(autoPasteEnabled, forKey: "whisperAutoPasteEnabled")
            print("🎯 [AUTO-PASTE] Saved to UserDefaults successfully")
        }
    }

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

    override init() {
        // Initialize auto-paste setting from UserDefaults
        self.autoPasteEnabled = UserDefaults.standard.object(forKey: "whisperAutoPasteEnabled") as? Bool ?? true
        
        super.init()
        print("🎯 [INIT] AudioRecorder initializing")
        
        // TEST APP CATEGORY
        DebugManager.shared.log(.app, .info, "🔄 TEST AudioRecorder initialization")
        print("🎯 [INIT] Testing APP category in AudioRecorder...")

        // Check Application Support directory for the app
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WhisperRecorder")
        print("🎯 [INIT] Application Support directory: \(appSupport.path)")
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            do {
                try FileManager.default.createDirectory(
                    at: appSupport, withIntermediateDirectories: true)
                print("🎯 [INIT] Created Application Support directory")
            } catch {
                print("🎯 [INIT] Failed to create Application Support directory: \(error)")
            }
        }

        // NOTE: AVAudioEngine and inputNode are NOT initialized here anymore.
        // They will be lazily initialized by their respective getter methods.

        // Check if notifications are available
        if Bundle.main.bundleIdentifier != nil {
            print("🎯 [INIT] Requesting notification permissions")
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) {
                granted, error in
                if let error = error {
                    print("🎯 [INIT] Error requesting notification permission: \(error)")
                } else if granted {
                    print("🎯 [INIT] Notification permission granted")
                    self.notificationsAvailable = true
                } else {
                    print("🎯 [INIT] Notification permission denied")
                }
            }
        } else {
            print("🎯 [INIT] Running without bundle identifier, notifications disabled")
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
        
        // Set up permission monitoring
        print("🎯 [INIT] 🔄 [SETUP] Setting up permission monitoring...")
        setupPermissionMonitoring()
        print("✅ [INIT] setupPermissionMonitoring() completed")

        print("🎯 [AUTO-PASTE] AudioRecorder initialized - autoPasteEnabled: \(autoPasteEnabled)")
        print("✅ [INIT] AudioRecorder initialization completed")
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
            print("🎯 [INIT] Lazily initializing AVAudioEngine")
            _audioEngine = AVAudioEngine()
        }
        return _audioEngine
    }

    // Getter for inputNode - initializes on first access
    private func getInputNode() -> AVAudioInputNode? {
        if _inputNode == nil {
            guard let engine = getAudioEngine() else {
                print("🎯 [INIT] Cannot initialize inputNode without audioEngine")
                return nil
            }
            print("🎯 [INIT] Lazily initializing AVAudioInputNode")
            _inputNode = engine.inputNode
            if _inputNode == nil {
                print("🎯 [INIT] Failed to get input node from audio engine during lazy init.")
            }
        }
        return _inputNode
    }

    private func setupAudioTap() {
        guard let inputNode = getInputNode() else {  // Changed to use getter
            print("🎯 [INIT] Failed to get input node for setupAudioTap")
            return
        }

        // Get the native format from the input hardware
        let nativeFormat = inputNode.inputFormat(forBus: 0)
        print("🎯 [INIT] Native audio format: \(nativeFormat)")

        // Create a format for the converter output that matches what whisper.cpp expects
        let whisperFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false)

        guard let whisperFormat = whisperFormat else {
            print("🎯 [INIT] Failed to create whisper audio format")
            return
        }

        print("🎯 [INIT] Whisper audio format: \(whisperFormat)")

        // Install tap using the native hardware format
        // Will resample in the callback to 16kHz for Whisper
        print("🎯 [INIT] Installing audio tap")
        
        // Add timeout protection for audio tap
        let tapQueue = DispatchQueue(label: "audio.tap.queue", qos: .userInitiated)
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: nativeFormat) {
            [weak self] buffer, time in
            guard let self = self, self.isRecording else { return }
            
            // Protection: Skip processing if buffer seems corrupted or too large
            guard buffer.frameLength > 0 && buffer.frameLength < 65536 else {
                print("🎯 [INIT] Suspicious buffer size: \(buffer.frameLength), skipping")
                return
            }

            // Use dispatch to prevent blocking the audio thread
            tapQueue.async {
                self.processAudioBuffer(buffer: buffer, nativeFormat: nativeFormat, whisperFormat: whisperFormat)
            }
        }
    }
    
    private func processAudioBuffer(buffer: AVAudioPCMBuffer, nativeFormat: AVAudioFormat, whisperFormat: AVAudioFormat) {
        // Create a converter to Whisper's format if needed
        if nativeFormat.sampleRate != self.sampleRate {
            // Create a new AVAudioConverter to convert the sample rate
            guard let converter = AVAudioConverter(from: nativeFormat, to: whisperFormat) else {
                print("🎯 [INIT] Failed to create audio converter")
                return
            }

            // Calculate the new frame count based on the ratio of sample rates
            let ratio = Double(whisperFormat.sampleRate) / Double(nativeFormat.sampleRate)
            let frameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)

            guard
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: whisperFormat, frameCapacity: frameCount)
            else {
                print("🎯 [INIT] Failed to create output buffer for conversion")
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
                print("🎯 [INIT] Error converting audio: \(error)")
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
                
                // Use main queue to safely modify the buffer
                DispatchQueue.main.async {
                    self.appendToAudioBuffer(samples: samples)
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

                // Use main queue to safely modify the buffer
                DispatchQueue.main.async {
                    self.appendToAudioBuffer(samples: samples)
                }
            }
        }
    }
    
    private func appendToAudioBuffer(samples: [Float]) {
        // Protect against runaway buffer growth
        guard audioBuffer.count < maxBufferSize * 2 else {
            print("🎯 [INIT] Audio buffer critically oversized (\(audioBuffer.count)), stopping recording")
            stopRecording()
            return
        }
        
        audioBuffer.append(contentsOf: samples)

        // Check if buffer exceeds maximum size and trim if needed
        if self.audioBuffer.count > self.maxBufferSize {
            print("🎯 [INIT] Audio buffer exceeding maximum size (\(self.maxBufferSize) samples), trimming oldest data")
            self.audioBuffer = Array(self.audioBuffer.suffix(self.maxBufferSize))
        }

        // Reduce logging frequency to prevent log spam
        if self.audioBuffer.count % 160000 == 0 {  // Log every 10 seconds instead of every second
            print("🎯 [INIT] Audio buffer size: \(self.audioBuffer.count) samples (\(self.audioBuffer.count / 16000) seconds)")
        }
    }

    private func showPermissionAlert() {
        print("🎯 [INIT] Showing microphone permission alert")
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
        print("🎯 [INIT] Toggle recording called")

        // Check if model is available first
        if !whisperWrapper.isModelLoaded() {
            print("🎯 [INIT] Cannot record: no whisper model loaded")
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
        print("🎯 [INIT] Starting recording")

        // Check microphone permission status for macOS
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            print("🎯 [INIT] Microphone permission granted")
            // Proceed with recording
            self.actuallyStartRecording()
        case .denied:
            print("🎯 [INIT] Microphone permission denied")
            // Show an alert to the user
            DispatchQueue.main.async {
                self.showPermissionAlert()
                self.statusDescription = "Mic permission denied"
                self.onStatusUpdate?()
            }
            return
        case .notDetermined:
            guard !isRequestingMicPermission else {
                print("🎯 [INIT] Microphone permission request already in progress.")
                return
            }
            print("🎯 [INIT] Microphone permission undetermined, requesting...")
            isRequestingMicPermission = true
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.isRequestingMicPermission = false  // Reset flag here
                    if granted {
                        print("🎯 [INIT] Microphone permission granted after request")
                        self?.actuallyStartRecording()
                    } else {
                        print("🎯 [INIT] Microphone permission denied after request")
                        self?.showPermissionAlert()
                        self?.statusDescription = "Mic permission denied"
                        self?.onStatusUpdate?()
                    }
                }
            }
            return
        case .restricted:  // macOS specific case
            print("🎯 [INIT] Microphone permission restricted")
            // Show an alert to the user, similar to denied
            DispatchQueue.main.async {
                self.showPermissionAlert()  // Or a more specific alert for restricted access
                self.statusDescription = "Mic permission restricted"
                self.onStatusUpdate?()
            }
            return
        @unknown default:
            print("🎯 [INIT] Unknown microphone permission status")
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
        print("🎯 [INIT] Actually starting recording")
        
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

        // Use timeout protection for audio engine startup
        let timeoutSeconds: TimeInterval = 5.0
        let group = DispatchGroup()
        group.enter()
        
        var startupSuccess = false
        var startupError: Error?
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                guard let audioEngine = self.getAudioEngine() else {
                    throw NSError(domain: "AudioRecorder", code: 1, userInfo: [NSLocalizedDescriptionKey: "Audio engine not initialized (lazy init failed)"])
                }

                // If the audio engine is already running, stop it first
                if audioEngine.isRunning {
                    print("🎯 [INIT] Audio engine already running, stopping it first")
                    audioEngine.stop()
                }

                // Remove any existing taps
                print("🎯 [INIT] Removing existing tap")
                self.getInputNode()?.removeTap(onBus: 0)

                // Set up the audio tap
                print("🎯 [INIT] Setting up audio tap")
                self.setupAudioTap()

                // Prepare and start the audio engine
                print("🎯 [INIT] Starting audio engine")
                audioEngine.prepare()
                try audioEngine.start()
                
                startupSuccess = true
                group.leave()
            } catch {
                startupError = error
                group.leave()
            }
        }
        
        let result = group.wait(timeout: .now() + timeoutSeconds)
        
        DispatchQueue.main.async {
            if result == .timedOut {
                print("🎯 [INIT] Audio engine startup timed out after \(timeoutSeconds)s")
                // Clean up on timeout
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                self.systemAudioManager.unmuteSystemAudio()
                self.showRecordingErrorAlert(error: NSError(domain: "AudioRecorder", code: 2, userInfo: [NSLocalizedDescriptionKey: "Audio engine startup timed out"]))
            } else if startupSuccess {
                self.isRecording = true
                self.statusDescription = "Recording..."
                print("🎯 [INIT] Recording started successfully")
                self.onStatusUpdate?()
            } else {
                print("🎯 [INIT] Failed to start audio engine: \(startupError?.localizedDescription ?? "unknown error")")
                // If recording failed, restore system audio
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                self.systemAudioManager.unmuteSystemAudio()
                self.showRecordingErrorAlert(error: startupError)
            }
        }
    }

    private func showRecordingErrorAlert(error: Error? = nil) {
        print("🎯 [INIT] Showing recording error alert: \(error?.localizedDescription ?? "unknown error")")
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
        print("🎯 [INIT] Stopping recording")
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
        print("🎯 [INIT] Recording stopped. Buffer size: \(audioBuffer.count) samples")
        onStatusUpdate?()

        // Process the audio buffer
        if !audioBuffer.isEmpty {
            print("🎯 [INIT] Transcribing \(audioBuffer.count) PCM samples directly")
            transcribeAudioBuffer()
        } else {
            print("🎯 [INIT] No audio data recorded")
        }
    }

    private func transcribeAudioBuffer() {
        print("🎯 [INIT] Starting transcription pipeline")
        print("🎯 [INIT] Audio buffer contains \(audioBuffer.count) samples")
        
        startTiming("transcription_pipeline")
        isTranscribing = true
        statusDescription = "Transcribing..."
        onStatusUpdate?()

        // Use a background thread for transcription
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Verify that the buffer is not empty
            guard !self.audioBuffer.isEmpty else {
                print("🎯 [INIT] ❌ Error: Audio buffer is empty")
                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.statusDescription = "Ready"
                    self.lastTranscription = "Error: No audio recorded"
                    self.onStatusUpdate?()
                }
                return
            }

            // Step 1: Whisper Transcription
            print("🎯 [INIT] 🎤 Starting Whisper transcription...")
            print("🎯 [INIT] Sending \(self.audioBuffer.count) samples to Whisper for transcription")
            
            startTiming("whisper_transcription")
            let transcription = self.whisperWrapper.transcribePCM(audioData: self.audioBuffer)
            let whisperTime = endTiming("whisper_transcription")
            
            print("🎯 [INIT] ✅ Whisper transcription completed in \(String(format: "%.3f", whisperTime ?? 0))s")
            print("🎯 [INIT] 📝 Raw Whisper output: \"\(transcription)\"")
            print("🎯 [INIT] Raw transcription length: \(transcription.count) characters")

            // Store the original Whisper transcription
            AppDelegate.lastOriginalWhisperText = transcription
            print("🎯 [INIT] Stored original Whisper text: \(transcription.count) characters")

            // Step 2: Check if we need reformatting or translation
            let currentTargetLang = WritingStyleManager.shared.currentTargetLanguage
            let noTranslateValue = WritingStyleManager.shared.noTranslate
            
            print("🎯 [INIT] Current settings check:")
            print("🎯 [INIT]   - Writing style: \(self.selectedWritingStyle.name) (\(self.selectedWritingStyle.id))")
            print("🎯 [INIT]   - Target language: \(currentTargetLang)")
            print("🎯 [INIT]   - No-translate value: \(noTranslateValue)")
            print("🎯 [INIT]   - Needs style formatting: \(self.selectedWritingStyle.id != "default")")
            print("🎯 [INIT]   - Needs translation: \(currentTargetLang != noTranslateValue)")
            
            let needsProcessing = self.selectedWritingStyle.id != "default" || 
                                 currentTargetLang != noTranslateValue
            
            if !needsProcessing {
                print("🎯 [INIT] 📋 Using default style and no translation - no reformatting needed")
                self.lastTranscription = transcription
                
                // Store as processed text even though it's the same as original
                AppDelegate.lastProcessedText = transcription
                print("🎯 [INIT] Stored processed text (same as original): \(transcription.count) characters")
                
                let totalTime = endTiming("transcription_pipeline")
                print("🎯 [INIT] 🏁 Total pipeline time: \(String(format: "%.3f", totalTime ?? 0))s (Whisper only)")

                // Copy to clipboard
                DispatchQueue.main.async {
                    self.copyToClipboard(text: transcription)
                    self.isTranscribing = false
                    self.statusDescription = "Ready"
                    self.onStatusUpdate?()
                    print("🎯 [INIT] ✅ Transcription pipeline complete (no processing needed)")

                    // Show notification if available
                    if self.notificationsAvailable {
                        self.showNotification(
                            message: "Transcription copied to clipboard",
                            title: "Transcription Complete")
                    }
                }
                return
            }

            // Step 3: Gemini Processing (reformatting and/or translation)
            DispatchQueue.main.async {
                self.statusDescription = "Processing..."
                self.isReformattingWithGemini = true
                self.onStatusUpdate?()
            }

            print("🎯 [INIT] 🤖 Starting Gemini processing (style: \(self.selectedWritingStyle.name), translation: \(WritingStyleManager.shared.currentTargetLanguage))...")
            print("🎯 [INIT] Selected writing style: \(self.selectedWritingStyle.name) (\(self.selectedWritingStyle.id))")
            print("🎯 [INIT] Target language: \(WritingStyleManager.supportedLanguages[WritingStyleManager.shared.currentTargetLanguage] ?? WritingStyleManager.shared.currentTargetLanguage)")
            print("🎯 [INIT] Input text for processing: \"\(transcription)\"")
            
            startTiming("gemini_processing")

            WritingStyleManager.shared.reformatText(
                transcription, withStyle: self.selectedWritingStyle
            ) { reformattedText in
                let geminiTime = endTiming("gemini_processing")
                let totalTime = endTiming("transcription_pipeline")
                
                DispatchQueue.main.async {
                    if let reformattedText = reformattedText {
                        print("🎯 [INIT] ✅ Gemini processing completed in \(String(format: "%.3f", geminiTime ?? 0))s")
                        print("🎯 [INIT] 📝 Reformatted output: \"\(reformattedText)\"")
                        print("🎯 [INIT] 🏁 Total pipeline time: \(String(format: "%.3f", totalTime ?? 0))s (Whisper: \(String(format: "%.3f", whisperTime ?? 0))s + Gemini: \(String(format: "%.3f", geminiTime ?? 0))s)")
                        
                        self.lastTranscription = reformattedText
                        
                        // Store the processed text
                        AppDelegate.lastProcessedText = reformattedText
                        print("🎯 [INIT] Stored processed text: \(reformattedText.count) characters")
                        
                        self.copyToClipboard(text: reformattedText)
                        
                        if self.notificationsAvailable {
                            self.showNotification(
                                message: "Reformatted text copied to clipboard",
                                title: "Reformatting Complete")
                        }
                        
                        print("🎯 [INIT] ✅ Full transcription pipeline complete with processing")
                    } else {
                        // If processing failed, use original transcription
                        print("🎯 [INIT] ❌ Gemini processing failed, falling back to original transcription")
                        print("🎯 [INIT] �� Pipeline completed with fallback - total time: \(String(format: "%.3f", totalTime ?? 0))s")
                        
                        self.lastTranscription = transcription
                        
                        // Store original as processed text since processing failed
                        AppDelegate.lastProcessedText = transcription
                        print("🎯 [INIT] Stored processed text (fallback to original): \(transcription.count) characters")
                        
                        self.copyToClipboard(text: transcription)
                        
                        if self.notificationsAvailable {
                            self.showNotification(
                                message: "Transcription copied to clipboard (processing failed)",
                                title: "Processing Failed")
                        }
                        
                        print("🎯 [INIT] ✅ Transcription pipeline complete (fallback to original)")
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
        print("🎯 [INIT] 🔄 Starting clipboard sequence...")
        
        let originalText = AppDelegate.lastOriginalWhisperText
        let processedText = text
        
        print("🎯 [INIT] Original text: \(originalText.isEmpty ? "empty" : "\(originalText.count) chars")")
        print("🎯 [INIT] Processed text: \(processedText.isEmpty ? "empty" : "\(processedText.count) chars")")
        
        // If we have processing (translation/style), only copy the final result
        // Only copy both if processing failed and we're falling back to original
        let needsProcessing = self.selectedWritingStyle.id != "default" || 
                             WritingStyleManager.shared.currentTargetLanguage != WritingStyleManager.shared.noTranslate
        
        if needsProcessing && !processedText.isEmpty && processedText != originalText {
            // We have successful processing - only copy the processed text
            print("🎯 [INIT] 📄 Using processed text only (translation/style applied)")
            self.copyTextToClipboard(processedText, label: "processed")
        } else if !originalText.isEmpty {
            // No processing or processing failed - copy original only
            print("🎯 [INIT] 📄 Using original text (no processing or fallback)")
            self.copyTextToClipboard(originalText, label: "original")
        } else {
            print("🎯 [INIT] ❌ No text available to copy")
        }
    }
    
    private func copyTextToClipboard(_ text: String, label: String) {
        print("🎯 [INIT] 📋 Copying \(label) text to clipboard: \"\(text.prefix(50))\(text.count > 50 ? "..." : "")\"")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        
        if success {
            print("🎯 [INIT] ✅ Successfully copied \(label) text (\(text.count) chars)")
            
            // Verify what's actually in clipboard
            if let clipboardContent = pasteboard.string(forType: .string) {
                print("🎯 [INIT] 📋 Clipboard verification: \(clipboardContent.count) chars, matches: \(clipboardContent == text)")
            }
            
            // Show toast notification
            let toastMessage = label == "processed" ? "Text processed & copied" : "Text copied"
            ToastManager.shared.showToast(message: toastMessage, preview: text)
            
            // Play centralized completion sound when transcription process completes
            NSSound(named: "Tink")?.play()
            
            // Auto-paste to active input (with delay to let toast show)
            if self.autoPasteEnabled {
                // Add delay so toast can be seen before auto-paste triggers key events that hide it
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Prevent toast from hiding during auto-paste
                    ToastManager.shared.setAutoPasteInProgress(true)
                    
                    self.autoPasteToActiveInput()
                    
                    // Re-enable toast hiding after auto-paste completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        ToastManager.shared.setAutoPasteInProgress(false)
                    }
                }
            } else {
                print("🎯 [INIT] Auto-paste disabled by user")
            }
        } else {
            print("🎯 [INIT] ❌ Failed to copy \(label) text to clipboard")
        }
    }
    
    private func autoPasteToActiveInput() {
        // Check if accessibility permissions are enabled
        guard self.autoPasteEnabled else {
            print("🎯 [INIT] Auto-paste disabled by user")
            return
        }
        
        // Check accessibility permissions - silently skip if no permissions
        if !AXIsProcessTrusted() {
            print("🎯 [INIT] ❌ Auto-paste skipped - no accessibility permissions")
            return
        }
        
        // Simply perform paste - try multiple methods with delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🎯 [INIT] 🎯 Attempting auto-paste with multiple methods...")
            self.performPaste()
        }
    }
    
    private func performPaste() {
        // Method 1: Try NSApp sendAction (safer approach)
        print("🎯 [INIT] Method 1: NSApp.sendAction")
        let result1 = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        print("🎯 [INIT] NSApp.sendAction result: \(result1)")
        
        // Method 2: Try CGEvent after small delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🎯 [INIT] Method 2: CGEvent")
            self.sendPasteKeyEvent()
        }
        
        // Method 3: Try AppleScript approach (removed problematic targeted approach)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            print("🎯 [INIT] Method 3: AppleScript")
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
                    print("🎯 [INIT] CGEvent paste sent")
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
                print("🎯 [INIT] AppleScript error: \(error)")
            } else {
                print("🎯 [INIT] AppleScript paste executed")
            }
        }
    }

    private func showNotification(message: String, title: String = "WhisperRecorder") {
        print("🎯 [INIT] Showing notification: \(message)")
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("🎯 [INIT] Error showing notification: \(error)")
            }
        }
    }

    func requestAccessibilityPermissions() {
        print("🎯 [INIT] Checking accessibility permissions...")
        DebugManager.shared.log(.app, .info, "Checking accessibility permissions...")
        
        // Only check permissions without showing prompt
        let accessibilityEnabled = AXIsProcessTrusted()
        
        if accessibilityEnabled {
            print("🎯 [INIT] ✅ Accessibility permissions already granted")
            DebugManager.shared.log(.app, .info, "✅ Accessibility permissions already granted")
        } else {
            print("🎯 [INIT] ❌ Accessibility permissions not granted")
            DebugManager.shared.log(.app, .warning, "❌ Accessibility permissions not granted")
            print("🎯 [INIT] ℹ️  To enable: System Preferences → Security & Privacy → Privacy → Accessibility")
        }
        
        // Update status after check
        updateAccessibilityPermissionStatus()
    }
    
    // Separate method for UI button that shows system prompt
    func requestAccessibilityPermissionsWithPrompt() {
        print("🎯 [UI] User clicked permission button - showing system prompt")
        DebugManager.shared.log(.app, .info, "User clicked permission button - showing system prompt")
        
        // Show system prompt when user explicitly requests it
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if accessibilityEnabled {
            print("🎯 [UI] ✅ Accessibility permissions already granted")
            DebugManager.shared.log(.app, .info, "✅ Accessibility permissions granted via prompt")
        } else {
            print("🎯 [UI] ❌ System prompt shown - user needs to grant permissions")
            DebugManager.shared.log(.app, .warning, "❌ System prompt shown - user needs to grant permissions")
        }
        
        // Update status after request
        updateAccessibilityPermissionStatus()
    }
    
    private func setupPermissionMonitoring() {
        print("🎯 [INIT] 🔄 [SETUP] Setting up permission monitoring...")
        
        // SIMPLE: Just do one initial check, no monitoring
        let initialStatus = AXIsProcessTrusted()
        self.accessibilityPermissionsStatus = initialStatus
        print("🎯 [INIT] ✅ Initial permission status: \(initialStatus)")
        
        print("🎯 [INIT] ✅ [SETUP] Permission setup completed (no automatic monitoring)")
    }
    
    func updateAccessibilityPermissionStatus() {
        print("🔄 [PERMISSIONS] Manual permission check")
        DebugManager.shared.log(.app, .debug, "Manual accessibility permission check")
        
        let newStatus = AXIsProcessTrusted()
        print("🔍 [PERMISSIONS] AXIsProcessTrusted() = \(newStatus)")
        DebugManager.shared.log(.app, .info, "AXIsProcessTrusted() result: \(newStatus)")
        
        if newStatus != accessibilityPermissionsStatus {
            print("🔄 [PERMISSIONS] STATUS CHANGED: \(accessibilityPermissionsStatus) → \(newStatus)")
            DebugManager.shared.log(.app, .info, "Permission status changed: \(accessibilityPermissionsStatus) → \(newStatus)")
            DispatchQueue.main.async {
                self.accessibilityPermissionsStatus = newStatus
                self.objectWillChange.send()
            }
        } else {
            print("🔄 [PERMISSIONS] Status unchanged: \(accessibilityPermissionsStatus)")
            DebugManager.shared.log(.app, .debug, "Permission status unchanged: \(accessibilityPermissionsStatus)")
        }
    }
    
    private func getParentProcessInfo() -> String {
        let parentPID = getppid()
        if let parentName = getProcessName(for: parentPID) {
            return "\(parentName) (PID: \(parentPID))"
        }
        return "unknown (PID: \(parentPID))"
    }
    
    // Public method for manual permission checking (called by UI)
    func checkPermissionsStatus() {
        print("🔄 [MANUAL] Manual permission check requested")
        updateAccessibilityPermissionStatus()
            }
        }

