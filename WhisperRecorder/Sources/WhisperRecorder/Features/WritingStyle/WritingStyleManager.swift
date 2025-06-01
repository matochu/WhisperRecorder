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
        logInfo(.llm, "🔄 Starting reformatText pipeline")
        logDebug(.llm, "Input text: \"\(text)\"")
        logDebug(.llm, "Selected style: \(style.name) (\(style.id))")
        logDebug(.llm, "Target language: \(WritingStyleManager.supportedLanguages[currentTargetLanguage] ?? currentTargetLanguage)")
        
        // Always start with applying the writing style if it's not default
        let applyStyle = { (inputText: String, next: @escaping (String?) -> Void) in
            if style.id == "default" {
                logDebug(.llm, "Default style selected - skipping style formatting")
                next(inputText)
            } else {
                logInfo(.llm, "🎨 Applying writing style: \(style.name)")
                self.reformatWithGeminiAPI(inputText, style: style) { formattedText in
                    if let formatted = formattedText {
                        logInfo(.llm, "✅ Style formatting completed")
                        logDebug(.llm, "Style-formatted text: \"\(formatted)\"")
                    } else {
                        logWarning(.llm, "⚠️ Style formatting failed, using original text")
                    }
                    next(formattedText ?? inputText)
                }
            }
        }

        // Then handle translation if needed
        applyStyle(text) { styledText in
            // Ensure we have valid text to translate, use original if style formatting failed
            logDebug(.llm, "Proceeding to translation phase with text: \"\(styledText ?? text)\"")
            self.translateIfNeeded(styledText ?? text) { finalResult in
                logInfo(.llm, "🏁 ReformatText pipeline complete")
                if let final = finalResult {
                    logDebug(.llm, "Final result: \"\(final)\"")
                } else {
                    logWarning(.llm, "Pipeline returned nil result")
                }
                completion(finalResult)
            }
        }
    }
    
    // Method to reformat text using Gemini API
    private func reformatWithGeminiAPI(_ text: String, style: WritingStyle, completion: @escaping (String?) -> Void) {
        guard llmManager.hasApiKey() else {
            logWarning(.llm, "❌ No Gemini API key available - returning original text")
            completion(text)  // Return original text instead of nil
            return
        }

        // Create prompt for the selected style
        let prompt = createPrompt(for: text, style: style)

        // Make API call to Gemini via LLMManager
        llmManager.callAPI(prompt: prompt) { result in
            if let formattedText = result {
                logInfo(.llm, "✅ Successfully reformatted text with style: \(style.id)")
                completion(formattedText)
            } else {
                logWarning(.llm, "❌ Failed to reformat text - returning original")
                completion(text)  // Return original text on failure
            }
        }
    }
    
    private func translateIfNeeded(_ text: String, completion: @escaping (String?) -> Void) {
        guard llmManager.hasApiKey() else {
            logWarning(.llm, "❌ No Gemini API key available - returning original text")
            completion(text)
            return
        }

        if currentTargetLanguage == noTranslate {
            logDebug(.llm, "No translation requested - using original text")
            completion(text)
            return
        }

        let sourceLanguage = "detected language" // Let Gemini auto-detect
        let targetLanguageName = WritingStyleManager.supportedLanguages[currentTargetLanguage] ?? currentTargetLanguage
        
        logInfo(.llm, "🌍 Starting translation from \(sourceLanguage) to \(targetLanguageName)")
        
        // Create detailed, context-aware translation prompt
        let prompt = createTranslationPrompt(for: text, from: sourceLanguage, to: targetLanguageName)

        llmManager.callAPI(prompt: prompt) { result in
            if let translatedText = result {
                logInfo(.llm, "✅ Successfully translated text")
                logDebug(.llm, "Translated from: \"\(text)\"")
                logDebug(.llm, "Translated to: \"\(translatedText)\"")
                completion(translatedText)
            } else {
                logWarning(.llm, "❌ Translation failed - returning original text")
                completion(text)
            }
        }
    }
    
    private func createTranslationPrompt(for text: String, from sourceLanguage: String, to targetLanguage: String) -> String {
        // Enhanced translation prompt following Gemini best practices
        let prompt = """
        You are a professional translator with expertise in natural, contextually accurate translations.
        
        TASK: Translate the provided text from \(sourceLanguage) to \(targetLanguage).
        
        CONTEXT: This text is from a voice recording that has been transcribed and may contain:
        - Informal spoken language
        - Technical terminology
        - Proper nouns (names, places, brands)
        - Colloquial expressions
        
        REQUIREMENTS:
        1. Translate naturally - preserve the meaning and tone, not word-for-word
        2. Keep proper nouns in their original form unless they have established translations
        3. Maintain the original formatting and structure
        4. Preserve any technical terms that are commonly used in the target language
        5. If the text contains multiple sentences, ensure natural flow between them
        6. Use contemporary, natural language that a native speaker would use
        
        FORMAT: Return only the translated text without any explanations, prefixes, or additional commentary.
        
        TEXT TO TRANSLATE:
        \(text)
        
        TRANSLATION:
        """
        
        logTrace(.llm, "Created enhanced translation prompt (\(prompt.count) characters)")
        return prompt
    }
    
    private func createPrompt(for text: String, style: WritingStyle) -> String {
        var prompt = ""
        
        // Add style-specific instructions
        switch style.id {
        case "vibe-coding":
            prompt = "Transform this transcribed voice note into clear, actionable instructions for coding tasks. Make it concise and technical:"
        case "coworker-chat":
            prompt = "Rewrite this voice note as a casual, friendly message for a coworker in Slack or Teams:"
        case "email":
            prompt = "Transform this voice note into a professional but friendly email format:"
        default:
            prompt = "Improve the clarity and readability of this text while maintaining its original meaning:"
        }
        
        prompt += "\n\n\(text)"
        
        return prompt
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
}
