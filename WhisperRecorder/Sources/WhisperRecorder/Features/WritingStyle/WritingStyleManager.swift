import Foundation

struct WritingStyle {
    let id: String
    let name: String
    let description: String

    static let styles: [WritingStyle] = [
        WritingStyle(
            id: "default", name: "Default",
            description: "Original transcription without modification"),
        WritingStyle(
            id: "free", name: "Free Flow",
            description: "Process voice commands with context awareness"),
        WritingStyle(
            id: "vibe-coding", name: "Vibe Coding",
            description: "For instructing AI on coding tasks"),
        WritingStyle(
            id: "coworker-chat", name: "Co-worker Chat",
            description: "For Slack/Teams communication"),
        WritingStyle(
            id: "email", name: "Email",
            description: "Balanced style for email communication"),
    ]
}

class WritingStyleManager: ObservableObject {
    static let shared = WritingStyleManager()
    
    // LLM functionality is delegated to LLMManager
    private let llmManager = LLMManager.shared
    
    private var targetLanguage: String?
    public var noTranslate = "aa_no-translate"
    
    @Published var selectedWritingStyle: WritingStyle = WritingStyle.styles[0]
    
    static let supportedLanguages = [
        "aa_no-translate": "No Translation",
        "ar": "Arabic",
        "zh": "Chinese",
        "nl": "Dutch",
        "en": "English",
        "fr": "French",
        "de": "German",
        "hi": "Hindi",
        "id": "Indonesian",
        "it": "Italian",
        "ja": "Japanese",
        "ko": "Korean",
        "pl": "Polish",
        "pt": "Portuguese",
        "es": "Spanish",
        "sw": "Swahili",
        "th": "Thai",
        "tr": "Turkish",
        "uk": "Ukrainian",
        "vi": "Vietnamese",
    ]

    private init() {
        logInfo(.llm, "WritingStyleManager initializing...")
    }
    
    // MARK: - Writing Style Management
    
    func setWritingStyle(_ style: WritingStyle) {
        selectedWritingStyle = style
        logInfo(.llm, "✅ Writing style set to: \(style.name)")
    }
    
    // MARK: - LLM Delegation Methods (for compatibility)
    
    func saveApiKey(_ key: String) {
        llmManager.saveApiKey(key)
    }

    func hasApiKey() -> Bool {
        return llmManager.hasApiKey()
    }

    func getButtonTitle() -> String {
        return llmManager.getButtonTitle()
    }

    func deleteApiKey() {
        llmManager.deleteApiKey()
    }

    func getMaskedApiKey() -> String {
        return llmManager.getMaskedApiKey()
    }
    
    // MARK: - Text Processing via LLM
    
    func enhanceText(_ text: String, completion: @escaping (String?) -> Void) {
        let needsStyleChange = selectedWritingStyle.id != "default"
        let needsTranslation = targetLanguage != nil && targetLanguage != noTranslate
        
        guard needsStyleChange || needsTranslation else {
            // Return original text if no style change and no translation needed
            completion(text)
            return
        }
        
        let prompt = createPrompt(for: text, style: selectedWritingStyle)
        llmManager.processText(prompt: prompt, completion: completion)
    }
    
    // MARK: - Legacy Method Compatibility - RESTORED WORKING VERSION
    
    func reformatText(_ text: String, withStyle style: WritingStyle, completion: @escaping (String?) -> Void) {
        logDebug(.llm, "🔄 reformatText called with style: \(style.id), target language: \(currentTargetLanguage)")
        
        // Check if any processing is actually needed
        let needsStyleChange = style.id != "default"
        let needsTranslation = currentTargetLanguage != noTranslate
        
        if !needsStyleChange && !needsTranslation {
            logDebug(.llm, "📝 No processing needed - returning original text")
            completion(text)
            return
        }
        
        // Create prompt that includes both style and translation requirements
        let prompt = createPrompt(for: text, style: style)
        
        logDebug(.llm, "📤 Sending to LLM API:")
        logDebug(.llm, "   Style: \(style.name) (\(style.id))")
        logDebug(.llm, "   Target language: \(WritingStyleManager.supportedLanguages[currentTargetLanguage] ?? currentTargetLanguage)")
        logDebug(.llm, "   Prompt: \(prompt)")
        
        // Call LLM API with the prepared prompt
        llmManager.callAPI(prompt: prompt) { result in
            if let formattedText = result {
                logInfo(.llm, "✅ Successfully processed text with style: \(style.id)")
                logDebug(.llm, "📥 LLM Response: \(formattedText)")
                completion(formattedText)
            } else {
                logWarning(.llm, "❌ Failed to process text - returning original")
                completion(text)  // Return original text on failure
            }
        }
    }
    
    // MARK: - Context-Enhanced Text Processing
    
    func reformatTextWithContext(_ text: String, withStyle style: WritingStyle, context: String, completion: @escaping (String?) -> Void) {
        // Create enhanced prompt that includes context + existing style/translation logic
        let contextualPrompt = createContextualPrompt(text: text, style: style, context: context)
        llmManager.processWithCustomPrompt(contextualPrompt, completion: completion)
    }
    
    // MARK: - Custom Prompt Processing
    
    func processWithCustomPrompt(_ prompt: String, completion: @escaping (String?) -> Void) {
        llmManager.processWithCustomPrompt(prompt, completion: completion)
    }
    
    // MARK: - Language Settings
    
    var currentTargetLanguage: String {
        return targetLanguage ?? noTranslate
    }
    
    func setTargetLanguage(_ language: String?) {
        targetLanguage = language
        logInfo(.llm, "Target language set to: \(language ?? "auto-detect")")
    }
    
    func getTargetLanguage() -> String? {
        return targetLanguage
    }
    
    // MARK: - Legacy Methods for Backward Compatibility
    
    private func createPrompt(for text: String, style: WritingStyle) -> String {
        var prompt = ""
        
        // Add style-specific instructions
        switch style.id {
        case "free":
            prompt = "You are a smart assistant that processes voice commands and responds. Analyze the voice input and provide a relevant response (no pleasantries):"
        case "vibe-coding":
            prompt = "Transform this transcribed voice note into clear, actionable instructions for coding tasks. Make it concise and technical:"
        case "coworker-chat":
            prompt = "Rewrite this voice note as a casual, friendly message for a coworker in Slack or Teams:"
        case "email":
            prompt = "Transform this voice note into a professional but friendly email format:"
        case "default":
            prompt = "Improve the clarity and readability of this text while maintaining its original meaning:"
        default:
            prompt = "Improve the clarity and readability of this text while maintaining its original meaning:"
        }
        
        // ALWAYS add language instruction (for all styles)
        if currentTargetLanguage != noTranslate {
            let langName = WritingStyleManager.supportedLanguages[currentTargetLanguage] ?? currentTargetLanguage
            prompt += " Respond in \(langName)."
        } else {
            prompt += " Respond in the same language as the user input."
        }
        
        prompt += "\n\n\(text)"
        
        return prompt
    }
    
    private func createContextualPrompt(text: String, style: WritingStyle, context: String) -> String {
        var prompt = "You are helping to create a response based on context and user input.\n\n"
        
        // Add context with markdown boundaries for clear separation
        prompt += """
---
## CONTEXT (from clipboard):
```
\(context)
```
---

"""
        
        // Add style-specific instructions that incorporate context
        switch style.id {
        case "free":
            prompt += """
Based on the context above, answer the user's question or request directly and concisely.

INSTRUCTIONS:
- Give direct, specific answers
- Use the context to provide accurate information
- No explanations unless asked
- No extra text or pleasantries
- Just the answer or response to what was asked

Answer directly:
"""
        case "vibe-coding":
            prompt += "Based on the context above, transform this voice note into clear, actionable coding instructions that address the context:"
        case "coworker-chat":
            prompt += "Based on the context above, create a casual, friendly response for a coworker in Slack or Teams:"
        case "email":
            prompt += "Based on the context above, create a professional but friendly email response:"
        default:
            prompt += "Based on the context above, create an appropriate response. Consider the context and provide a relevant, well-formatted reply:"
        }
        
        prompt += "\n\n**USER INPUT (from voice transcription):**\n\(text)\n\n"
        
        // ALWAYS add language instruction (consistent with createPrompt)
        let currentTargetLang = currentTargetLanguage
        if currentTargetLang != noTranslate {
            let langName = WritingStyleManager.supportedLanguages[currentTargetLang] ?? currentTargetLang
            prompt += "Respond in \(langName).\n\n"
        } else {
            prompt += "Respond in the same language as the user input.\n\n"
        }
        
        prompt += "Response:"
        
        return prompt
    }
}
