import SwiftUI
import AVFoundation
import AVFAudio
import KeyboardShortcuts
import AppKit
import ApplicationServices
import Foundation

class AudioRecorder: ObservableObject {
    static let shared = AudioRecorder()

    // Core managers
    private let whisperWrapper = WhisperWrapper.shared
    private let audioEngineManager = AudioEngineManager()

    // Extracted functionality managers
    private let accessibilityManager = AccessibilityManager.shared
    private let clipboardManager = ClipboardManager.shared

    // Status information
    @Published private(set) var isTranscribing = false
    @Published private(set) var lastTranscription: String?
    @Published var statusDescription: String = "Ready"

    // Writing style selection
    @Published var selectedWritingStyle: WritingStyle = WritingStyle.styles[0] {  // Default style
        didSet {
            llmProcessor.updateWritingStyle(selectedWritingStyle)
            historyManager.updateWritingStyle(selectedWritingStyle)
        }
    }
    @Published private(set) var isReformattingWithGemini = false
    
    // Contextual workflow processor
    private let contextualProcessor = ContextualWorkflowProcessor()
    
    // LLM processor
    private lazy var llmProcessor = LLMProcessor(writingStyle: selectedWritingStyle, contextualProcessor: contextualProcessor)
    
    // History manager
    private lazy var historyManager = HistoryManager(writingStyle: selectedWritingStyle, audioEngineManager: audioEngineManager)
    
    // Result handler
    private lazy var resultHandler = ResultHandler(contextualProcessor: contextualProcessor, historyManager: historyManager)

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

    var isInContextualWorkflow: Bool {
        return contextualProcessor.isInContextualWorkflow
    }
    
    var isRecording: Bool {
        return audioEngineManager.isCurrentlyRecording()
    }
    
    var recordingDurationSeconds: Int {
        return audioEngineManager.getRecordingDuration()
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
        
        // Set up contextual processor callbacks
        contextualProcessor.onStartRecording = { [weak self] in
            self?.audioEngineManager.startRecording()
        }
        
        contextualProcessor.onStopRecording = { [weak self] in
            self?.audioEngineManager.stopRecording()
        }
        
        // Set up audio engine manager callbacks
        audioEngineManager.onStatusUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.statusDescription = self?.audioEngineManager.statusDescription ?? "Ready"
                self?.onStatusUpdate?()
            }
        }
        
        audioEngineManager.onAudioDataReady = { [weak self] audioBuffer in
            DispatchQueue.main.async {
                self?.transcribeAudioBuffer(audioBuffer)
            }
        }
        
        // Set up LLM processor callbacks
        llmProcessor.onStatusUpdate = { [weak self] status in
            DispatchQueue.main.async {
                self?.statusDescription = status
                self?.isReformattingWithGemini = self?.llmProcessor.isProcessing ?? false
                self?.onStatusUpdate?()
            }
        }
        
        llmProcessor.onProcessingComplete = { [weak self] result, original, type in
            self?.resultHandler.handleProcessingResult(result, originalText: original, processingType: type)
        }
        
        // Set up result handler callbacks
        resultHandler.onStatusUpdate = { [weak self] in
            DispatchQueue.main.async {
                self?.isTranscribing = false
                self?.isReformattingWithGemini = false
                self?.statusDescription = "Ready"
                self?.onStatusUpdate?()
            }
        }
        
        resultHandler.onTranscriptionComplete = { [weak self] text in
            DispatchQueue.main.async {
                self?.lastTranscription = text
            }
        }
        
        resultHandler.onProcessedTextReady = { text in
            DispatchQueue.main.async {
                AppDelegate.lastProcessedText = text
            }
        }
        
        resultHandler.onCopyToClipboard = { [weak self] text in
            DispatchQueue.main.async {
                self?.copyToClipboard(text: text)
            }
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



    func toggleRecording() {
        logInfo(.audio, "Toggle recording called")

        // Check if model is available first
        if !whisperWrapper.isModelLoaded() {
            logInfo(.audio, "Cannot record: no whisper model loaded")
            lastTranscription = "Please download a Whisper model first"
            statusDescription = "No model available"
            onStatusUpdate?()
            return
        }
        
        // SMART SHORTCUT HANDLING: If we're in contextual workflow mode and recording,
        // the toggle shortcut should stop the contextual recording properly
        if contextualProcessor.isInContextualWorkflow && isRecording {
            logInfo(.audio, "🎯 Contextual workflow active - stopping contextual recording via toggle shortcut")
            audioEngineManager.stopRecording()
            return
        }
        
        // SMART SHORTCUT HANDLING: If we're in contextual workflow but not recording yet,
        // ignore the toggle shortcut to avoid conflicts
        if contextualProcessor.isInContextualWorkflow {
            logInfo(.audio, "🎯 Contextual workflow active - ignoring toggle shortcut (not recording)")
            return
        }

        audioEngineManager.toggleRecording()
    }





    private func transcribeAudioBuffer(_ audioBuffer: [Float]) {
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
            guard !audioBuffer.isEmpty else {
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
            let bufferSize = audioBuffer.count
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
            
            let validatedBuffer: [Float]
            if bufferSize > maxSafeSize {
                logWarning(.audio, "⚠️ Large audio buffer: \(bufferSize) samples, trimming to last \(maxSafeSize)")
                validatedBuffer = Array(audioBuffer.suffix(maxSafeSize))
            } else {
                validatedBuffer = audioBuffer
            }
            
            logDebug(.audio, "✅ Audio buffer validated: \(validatedBuffer.count) samples")

            // Step 1: Whisper Transcription
            logInfo(.audio, "🎤 Starting Whisper transcription...")
            logDebug(.audio, "Sending \(validatedBuffer.count) samples to Whisper for transcription")
            
            startTiming("whisper_transcription")
            let transcription = self.whisperWrapper.transcribePCM(audioData: validatedBuffer)
            let whisperTime = endTiming("whisper_transcription")
            
            logInfo(.audio, "✅ Whisper transcription completed in \(String(format: "%.3f", whisperTime ?? 0))s")
            logInfo(.audio, "📝 Raw Whisper output: \"\(transcription)\"")
            logDebug(.audio, "Raw transcription length: \(transcription.count) characters")

            // Store the original Whisper transcription
            AppDelegate.lastOriginalWhisperText = transcription
            logDebug(.storage, "Stored original Whisper text: \(transcription.count) characters")

            // Step 2: Check if we need LLM processing
            if !self.llmProcessor.needsProcessing() {
                logInfo(.audio, "📋 Using default style and no translation - no reformatting needed")
                self.lastTranscription = transcription
                
                // Store as processed text even though it's the same as original
                AppDelegate.lastProcessedText = transcription
                logDebug(.storage, "Stored processed text (same as original): \(transcription.count) characters")
                
                let totalTime = endTiming("transcription_pipeline")
                
                // Delegate to result handler
                self.resultHandler.handleWhisperOnlyResult(transcription: transcription, totalTime: totalTime)
                return
            }

            // Step 3: LLM Processing (delegated to LLMProcessor)
            self.llmProcessor.processText(transcription)
        }
    }

    // MARK: - Contextual Processing (Delegated)
    
    func processWithClipboardContext() {
        // Check if already recording - if so, stop current recording first
        if isRecording {
            logInfo(.audio, "📴 Stopping current recording for contextual processing (no transcription)")
            audioEngineManager.stopRecording(shouldProcess: false)  // Don't process the audio buffer
            // Wait a moment for recording to stop properly
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.contextualProcessor.processWithClipboardContext()
            }
            return
        }
        
        contextualProcessor.processWithClipboardContext()
    }
    
    // MARK: - Testing Support
    
    #if DEBUG
    /// Test helper to set lastTranscription for testing
    func setLastTranscriptionForTesting(_ text: String?) {
        lastTranscription = text
    }
    
    /// Test helper to set isTranscribing for testing
    func setIsTranscribingForTesting(_ value: Bool) {
        isTranscribing = value
    }
    
    /// Test helper to get system ready state
    var isSystemReadyForTesting: Bool {
        return !isTranscribing && statusDescription == "Ready"
    }
    #endif

}
