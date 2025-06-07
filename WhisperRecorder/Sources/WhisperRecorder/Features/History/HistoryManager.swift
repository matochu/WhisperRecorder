import SwiftUI
import Foundation

// MARK: - History Manager

class HistoryManager {
    
    // Dependencies - will be injected
    private var selectedWritingStyle: WritingStyle
    private var audioEngineManager: AudioEngineManager
    
    init(writingStyle: WritingStyle, audioEngineManager: AudioEngineManager) {
        self.selectedWritingStyle = writingStyle
        self.audioEngineManager = audioEngineManager
    }
    
    // MARK: - Public Interface
    
    func updateWritingStyle(_ style: WritingStyle) {
        selectedWritingStyle = style
    }
    
    func addToHistory(originalText: String, processedText: String?, processingType: String) {
        // Get recording duration
        let duration = audioEngineManager.getRecordingDuration() > 0 ? TimeInterval(audioEngineManager.getRecordingDuration()) : nil
        
        // Get current speaker information
        let speakerCount: Int?
        if let timeline = SpeakerDiarizationEngine.shared.lastDiarizationResult {
            speakerCount = timeline.speakerCount > 1 ? timeline.speakerCount : nil
        } else {
            speakerCount = nil
        }
        
        // Get current style and language
        let writingStyle = selectedWritingStyle.name
        let currentLanguage = WritingStyleManager.shared.currentTargetLanguage
        let languageName = WritingStyleManager.supportedLanguages[currentLanguage]
        
        // Generate LLM format if processed text is available
        let llmFormatted: String?
        if let processed = processedText {
            // Try to get timeline for LLM formatting
            let timeline = SpeakerDiarizationEngine.shared.lastDiarizationResult
            llmFormatted = WhisperWrapper.shared.formatForLLM(humanReadableText: processed, timeline: timeline)
        } else {
            llmFormatted = nil
        }
        
        // Add to persistent history
        TranscriptionHistoryManager.shared.addTranscription(
            originalText: originalText,
            processedText: processedText,
            llmFormattedText: llmFormatted,
            duration: duration,
            speakerCount: speakerCount,
            writingStyle: writingStyle,
            language: languageName
        )
        
        logInfo(.storage, "Added to history: \(processingType), duration=\(duration?.description ?? "nil")s, speakers=\(speakerCount?.description ?? "nil")")
    }
} 