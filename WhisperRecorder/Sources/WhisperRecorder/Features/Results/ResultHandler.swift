import SwiftUI
import Foundation

// MARK: - Result Handler

class ResultHandler {
    
    // Dependencies - will be injected
    private var contextualProcessor: ContextualWorkflowProcessor
    private var historyManager: HistoryManager
    
    // Callbacks
    var onStatusUpdate: (() -> Void)?
    var onTranscriptionComplete: ((String) -> Void)?
    var onProcessedTextReady: ((String) -> Void)?
    var onCopyToClipboard: ((String) -> Void)?
    
    init(contextualProcessor: ContextualWorkflowProcessor, historyManager: HistoryManager) {
        self.contextualProcessor = contextualProcessor
        self.historyManager = historyManager
    }
    
    // MARK: - Public Interface
    
    func handleProcessingResult(_ reformattedText: String?, originalText: String, processingType: String) {
        // Handle timeout case
        if processingType == "timeout_fallback" {
            handleTimeoutFallback(originalText: originalText)
            return
        }
        
        let totalTime = endTiming("llm_processing")
        logInfo(.performance, "🏁 Total pipeline time: \(String(format: "%.3f", totalTime ?? 0))s")
        
        DispatchQueue.main.async {
            // Always reset status and contextual state
            defer {
                self.resetProcessingState()
                self.playCompletionSound()
            }
            
            if let processedText = reformattedText {
                self.handleSuccessfulProcessing(
                    processedText: processedText,
                    originalText: originalText,
                    processingType: processingType,
                    totalTime: totalTime
                )
            } else {
                self.handleFailedProcessing(
                    originalText: originalText,
                    processingType: processingType
                )
            }
        }
    }
    
    func handleWhisperOnlyResult(transcription: String, totalTime: TimeInterval?) {
        // Add to history (no processing)
        historyManager.addToHistory(
            originalText: transcription,
            processedText: nil,
            processingType: "whisper_only"
        )
        
        logInfo(.performance, "🏁 Total pipeline time: \(String(format: "%.3f", totalTime ?? 0))s (Whisper only)")

        // Copy to clipboard and complete
        DispatchQueue.main.async {
            self.onCopyToClipboard?(transcription)
            self.resetProcessingState()
            logInfo(.audio, "✅ Transcription pipeline complete (no processing needed)")
            self.playCompletionSound()
        }
    }
    
    // MARK: - Private Methods
    
    private func handleTimeoutFallback(originalText: String) {
        logWarning(.audio, "🚨 Processing timeout - forcefully resetting to Ready state")
        DispatchQueue.main.async {
            self.resetProcessingState()
            
            // Use original transcription as fallback
            self.onTranscriptionComplete?(originalText)
            self.onProcessedTextReady?(originalText)
            self.onCopyToClipboard?(originalText)
        }
    }
    
    private func handleSuccessfulProcessing(processedText: String, originalText: String, processingType: String, totalTime: TimeInterval?) {
        logInfo(.audio, "✅ \(processingType) processing completed in \(String(format: "%.3f", totalTime ?? 0))s")
        logInfo(.performance, "🏁 Total pipeline time: \(String(format: "%.3f", totalTime ?? 0))s")
        
        // Store results
        onTranscriptionComplete?(processedText)
        onProcessedTextReady?(processedText)
        
        // Add to history
        historyManager.addToHistory(
            originalText: originalText,
            processedText: processedText,
            processingType: processingType
        )
        
        // Copy result to clipboard using copyToClipboard for auto-paste functionality
        onCopyToClipboard?(processedText)
        
        // Show success toast
        let message = contextualProcessor.isInContextualWorkflow ? "Contextual response generated" : "Processing complete"
        ToastManager.shared.showToast(
            message: message,
            preview: processedText, 
            type: .normal
        )
        
        logInfo(.audio, "✅ \(processingType) workflow complete - response copied to clipboard")
    }
    
    private func handleFailedProcessing(originalText: String, processingType: String) {
        logError(.audio, "❌ \(processingType) processing failed")
        
        // Fallback to original transcription
        onTranscriptionComplete?(originalText)
        onProcessedTextReady?(originalText)
        
        // Add to history (failed processing)
        historyManager.addToHistory(
            originalText: originalText,
            processedText: nil,
            processingType: "failed_\(processingType)"
        )
        
        onCopyToClipboard?(originalText)
        
        ToastManager.shared.showToast(
            message: "Processing failed - using voice text", 
            preview: originalText,
            type: .error
        )
    }
    
    private func resetProcessingState() {
        // Clean contextual state
        let _ = contextualProcessor.isInContextualWorkflow
        contextualProcessor.cleanupContextualState()
        
        // Trigger status update
        onStatusUpdate?()
    }
    
    private func playCompletionSound() {
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
} 