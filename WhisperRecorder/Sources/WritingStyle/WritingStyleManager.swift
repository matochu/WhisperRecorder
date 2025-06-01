    func enhanceText(_ text: String, completion: @escaping (String?) -> Void) {
        let needsStyleChange = selectedWritingStyle.id != "default"
        let needsTranslation = targetLanguage != nil && targetLanguage != noTranslate
        
        guard needsStyleChange || needsTranslation else {
            // Return original text if no style change and no translation needed
            completion(text)
            return
        }
        
        let prompt = buildPrompt(for: text, style: selectedWritingStyle)
        llmManager.processText(prompt: prompt, completion: completion)
    } 