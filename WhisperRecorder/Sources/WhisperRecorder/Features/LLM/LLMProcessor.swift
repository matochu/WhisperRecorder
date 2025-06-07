import SwiftUI
import Foundation

// MARK: - LLM Processor

class LLMProcessor: ObservableObject {
    
    // Processing state
    @Published private(set) var isProcessing = false
    
    // Dependencies - will be injected from AudioRecorder
    private var selectedWritingStyle: WritingStyle
    private var contextualProcessor: ContextualWorkflowProcessor
    
    // Callbacks
    var onStatusUpdate: ((String) -> Void)?
    var onProcessingComplete: ((String?, String, String) -> Void)?  // (result, original, type)
    
    init(writingStyle: WritingStyle, contextualProcessor: ContextualWorkflowProcessor) {
        self.selectedWritingStyle = writingStyle
        self.contextualProcessor = contextualProcessor
    }
    
    // MARK: - Public Interface
    
    func updateWritingStyle(_ style: WritingStyle) {
        selectedWritingStyle = style
    }
    
    func needsProcessing() -> Bool {
        let currentTargetLang = WritingStyleManager.shared.currentTargetLanguage
        let noTranslateValue = WritingStyleManager.shared.noTranslate
        
        logDebug(.llm, "Current settings check:")
        logDebug(.llm, "  - Writing style: \(selectedWritingStyle.name) (\(selectedWritingStyle.id))")
        logDebug(.llm, "  - Target language: \(currentTargetLang)")
        logDebug(.llm, "  - No-translate value: \(noTranslateValue)")
        logDebug(.llm, "  - Needs style formatting: \(selectedWritingStyle.id != "default")")
        logDebug(.llm, "  - Needs translation: \(currentTargetLang != noTranslateValue)")
        logDebug(.llm, "  - Has contextual content: \(contextualProcessor.isInContextualWorkflow)")
        
        return selectedWritingStyle.id != "default" || 
               currentTargetLang != noTranslateValue ||
               contextualProcessor.isInContextualWorkflow
    }
    
    func processText(_ transcription: String) {
        logInfo(.audio, "🤖 Starting LLM processing pipeline...")
        
        // Update status
        isProcessing = true
        let processingType = contextualProcessor.isInContextualWorkflow ? "contextual" : "style/translation"
        
        DispatchQueue.main.async {
            if self.contextualProcessor.isInContextualWorkflow {
                self.onStatusUpdate?("Processing with context...")
            } else {
                self.onStatusUpdate?("Processing...")
            }
        }
        
        // Log processing details
        logInfo(.audio, "🤖 Starting \(processingType) processing...")
        logInfo(.llm, "Selected writing style: \(selectedWritingStyle.name) (\(selectedWritingStyle.id))")
        logInfo(.llm, "Target language: \(WritingStyleManager.supportedLanguages[WritingStyleManager.shared.currentTargetLanguage] ?? WritingStyleManager.shared.currentTargetLanguage)")
        logInfo(.llm, "Input text for processing: \"\(transcription)\"")
        
        if contextualProcessor.isInContextualWorkflow {
            let contextualContent = contextualProcessor.getContextualContent()
            logInfo(.llm, "Contextual content: \"\(contextualContent)\"")
        }
        
        startTiming("llm_processing")
        
        // Process based on type
        if contextualProcessor.isInContextualWorkflow {
            processWithContext(transcription, processingType: processingType)
        } else {
            processWithStyle(transcription, processingType: processingType)
        }
        
        // Safety fallback: timeout handling
        setupProcessingTimeout(originalText: transcription)
    }
    
    // MARK: - Private Implementation
    
    private func processWithContext(_ transcription: String, processingType: String) {
        let contextualContent = contextualProcessor.getContextualContent()
        WritingStyleManager.shared.reformatTextWithContext(
            transcription, 
            withStyle: selectedWritingStyle,
            context: contextualContent
        ) { [weak self] reformattedText in
            self?.handleProcessingResult(reformattedText, originalText: transcription, processingType: processingType)
        }
    }
    
    private func processWithStyle(_ transcription: String, processingType: String) {
        WritingStyleManager.shared.reformatText(
            transcription, withStyle: selectedWritingStyle
        ) { [weak self] reformattedText in
            self?.handleProcessingResult(reformattedText, originalText: transcription, processingType: processingType)
        }
    }
    
    private func handleProcessingResult(_ reformattedText: String?, originalText: String, processingType: String) {
        let totalTime = endTiming("llm_processing")
        logInfo(.performance, "🏁 LLM processing time: \(String(format: "%.3f", totalTime ?? 0))s")
        
        DispatchQueue.main.async {
            self.isProcessing = false
            self.onProcessingComplete?(reformattedText, originalText, processingType)
        }
    }
    
    private func setupProcessingTimeout(originalText: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self = self else { return }
            
            if self.isProcessing {
                logWarning(.audio, "🚨 LLM processing timeout - forcefully resetting")
                self.isProcessing = false
                
                // Return original text as fallback
                self.onProcessingComplete?(nil, originalText, "timeout_fallback")
            }
        }
    }
} 