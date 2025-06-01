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

class WritingStyleManager {
    static let shared = WritingStyleManager()
    private var apiKey: String?
    private var targetLanguage: String?
    public var noTranslate = "aa_no-translate"
    private var apiURL: String {
        guard let apiKey = self.apiKey else {
            return "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
        }
        return "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
    }

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
        loadApiKey()
    }

    private func loadApiKey() {
        logDebug(.llm, "Starting to load API key...")

        // Load from environment first
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
            self.apiKey = key
            logInfo(.llm, "✅ Loaded Gemini API key from environment")
            return
        }

        // Try to load from .env file
        let fileManager = FileManager.default

        // Check locations for .env file
        let possibleLocations: [String] = [
            // App bundle resources path
            Bundle.main.resourcePath.map { path in
                URL(fileURLWithPath: path).appendingPathComponent(".env").path
            },

            // User's home directory
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".env").path,

            // Current directory
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(".env")
                .path,

            // Support directory
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/WhisperRecorder/.env").path,
        ].compactMap { $0 }

        logDebug(.llm, "Checking for .env file in the following locations:")

        for location in possibleLocations {
            logTrace(.llm, "  - Checking: \(location)")
            if fileManager.fileExists(atPath: location) {
                logDebug(.llm, "  ✓ Found .env file at: \(location)")
                if loadApiKeyFromFile(at: location) {
                    logInfo(.llm, "  ✅ Successfully loaded API key from \(location)")
                    return
                } else {
                    logWarning(.llm, "  ✗ Failed to load API key from \(location)")
                }
            }
        }

        logWarning(.llm, "❌ Could not locate .env file with valid Gemini API key in any location")
    }

    private func loadApiKeyFromFile(at path: String) -> Bool {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let lines = content.split(separator: "\n")

            for line in lines {
                if line.starts(with: "GEMINI_API_KEY=") {
                    let key = line.dropFirst("GEMINI_API_KEY=".count).trimmingCharacters(
                        in: .whitespacesAndNewlines)
                    if !key.isEmpty && key != "your_api_key_here" {
                        self.apiKey = key
                        return true
                    }
                }
            }

            logWarning(.llm, "No valid Gemini API key found in file at \(path)")
            return false
        } catch {
            logError(.llm, "Error reading .env file at \(path): \(error)")
            return false
        }
    }

    var currentTargetLanguage: String {
        return targetLanguage ?? noTranslate
    }

    func setTargetLanguage(_ code: String) {
        self.targetLanguage = code
        logInfo(.llm, "✅ Target language set to: \(code)")
    }

    private func translateIfNeeded(_ text: String, completion: @escaping (String?) -> Void) {
        guard let apiKey = self.apiKey, !apiKey.isEmpty else {
            logWarning(.llm, "❌ No Gemini API key available - returning original text")
            completion(text)
            return
        }

        if currentTargetLanguage == "no_translate" {
            logDebug(.llm, "No translation requested - using original text")
            completion(text)
            return
        }

        let sourceLanguage = "detected language" // Let Gemini auto-detect
        let targetLanguageName = WritingStyleManager.supportedLanguages[currentTargetLanguage] ?? currentTargetLanguage
        
        logInfo(.llm, "🌍 Starting translation from \(sourceLanguage) to \(targetLanguageName)")
        
        // Create detailed, context-aware translation prompt
        let prompt = createTranslationPrompt(for: text, from: sourceLanguage, to: targetLanguageName)

        callGeminiAPI(prompt: prompt, apiKey: apiKey) { result in
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

    func reformatText(
        _ text: String, withStyle style: WritingStyle, completion: @escaping (String?) -> Void
    ) {
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
    private func reformatWithGeminiAPI(
        _ text: String, style: WritingStyle, completion: @escaping (String?) -> Void
    ) {
        guard let apiKey = self.apiKey, !apiKey.isEmpty else {
            logWarning(.llm, "❌ No Gemini API key available - returning original text")
            completion(text)  // Return original text instead of nil
            return
        }

        // Create prompt for the selected style
        let prompt = createPrompt(for: text, style: style)

        // Make API call to Gemini
        callGeminiAPI(prompt: prompt, apiKey: apiKey) { result in
            if let formattedText = result {
                logInfo(.llm, "✅ Successfully reformatted text with style: \(style.id)")
                completion(formattedText)
            } else {
                logWarning(.llm, "❌ Failed to reformat text - returning original")
                completion(text)  // Return original text on failure
            }
        }
    }

    private func createPrompt(for text: String, style: WritingStyle) -> String {
        var styleDescription = ""
        var schema = ""

        switch style.id {
        case "vibe-coding":
            styleDescription = """
                Transform the following text into a clear, concise prompt that would be suitable for instructing an AI assistant like Claude or GPT on a coding task. 
                The prompt should be directive, specific, and follow best practices for prompting AI for code generation or modification.
                Make it sound natural and conversational while still being precise about technical requirements.
                Format it appropriately with clear sections, as needed.
                """
            schema = """
                FormattedOutput = {"reformatted_text": str}
                Return: FormattedOutput
                """

        case "coworker-chat":
            styleDescription = """
                Rewrite the following text to be suitable for messaging a colleague on Slack or Microsoft Teams.
                The tone should be friendly and professional, but relaxed and conversational.
                Use appropriate casual language, brevity, and clarity that works well in a workplace chat context.
                Feel free to add appropriate emoji if it enhances the message.
                """
            schema = """
                FormattedOutput = {"reformatted_text": str}
                Return: FormattedOutput
                """

        case "email":
            styleDescription = """
                Reformat the following text into a well-structured email message.
                The tone should balance professionalism with approachability - not too formal, but also not too casual.
                Include appropriate email formatting elements (greeting, clear paragraphs, sign-off) as needed.
                Make it concise, respectful of the reader's time, while maintaining all key information.
                """
            schema = """
                FormattedOutput = {"reformatted_text": str}
                Return: FormattedOutput
                """

        default:
            styleDescription = "Rewrite the following text to improve clarity and readability."
            schema = """
                FormattedOutput = {"reformatted_text": str}
                Return: FormattedOutput
                """
        }

        return "\(styleDescription)\n\nOriginal text: \(text)\n\nUse this JSON schema: \(schema)"
    }

    private func callGeminiAPI(
        prompt: String, apiKey: String, completion: @escaping (String?) -> Void
    ) {
        logInfo(.network, "🌐 Starting Gemini API call")
        logDebug(.network, "API endpoint: \(self.apiURL)")
        logDebug(.network, "Prompt length: \(prompt.count) characters")
        logTrace(.network, "Full prompt: \"\(prompt)\"")
        
        guard let url = URL(string: self.apiURL) else {
            logError(.network, "❌ Invalid API URL: \(self.apiURL)")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ]
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
            
            logDebug(.network, "Request body size: \(jsonData.count) bytes")
            logTrace(.network, "Request body: \(String(data: jsonData, encoding: .utf8) ?? "Unable to convert to string")")
        } catch {
            logError(.network, "❌ Failed to serialize request body: \(error)")
            completion(nil)
            return
        }

        startTiming("api_request")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let requestTime = endTiming("api_request")

            if let error = error {
                logError(.network, "❌ Network error: \(error.localizedDescription)")
                logInfo(.performance, "Failed API request took \(String(format: "%.3f", requestTime ?? 0))s")
                completion(nil)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                logError(.network, "❌ Invalid response type")
                completion(nil)
                return
            }

            logInfo(.network, "📡 Received HTTP response: \(httpResponse.statusCode)")
            logInfo(.performance, "API request completed in \(String(format: "%.3f", requestTime ?? 0))s")

            guard let data = data else {
                logError(.network, "❌ No data received from API")
                completion(nil)
                return
            }

            logDebug(.network, "Response data size: \(data.count) bytes")

            if httpResponse.statusCode != 200 {
                logError(.network, "❌ API returned error status: \(httpResponse.statusCode)")
                if let errorString = String(data: data, encoding: .utf8) {
                    logError(.network, "Error response: \(errorString)")
                }
                completion(nil)
                            return
                        }

            // Parse the response
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    logTrace(.network, "Full API response: \(jsonObject)")
                    
                    if let candidates = jsonObject["candidates"] as? [[String: Any]],
                       let firstCandidate = candidates.first,
                       let content = firstCandidate["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                        let firstPart = parts.first,
                       let text = firstPart["text"] as? String {
                        
                        logInfo(.network, "✅ Successfully parsed API response")
                        logDebug(.network, "Response text length: \(text.count) characters")
                        logDebug(.network, "Response text: \"\(text)\"")
                        completion(text.trimmingCharacters(in: .whitespacesAndNewlines))
                    } else {
                        logError(.network, "❌ Failed to parse API response structure")
                        logDebug(.network, "Response structure didn't match expected format")
                        completion(nil)
                    }
                } else {
                    logError(.network, "❌ Failed to parse JSON response")
                    completion(nil)
                }
            } catch {
                logError(.network, "❌ JSON parsing error: \(error)")
                completion(nil)
            }
        }

        task.resume()
        logDebug(.network, "HTTP request sent, waiting for response...")
    }

    func saveApiKey(_ key: String) {
        self.apiKey = key
        logInfo(.llm, "✅ New Gemini API key saved")

        // Save to Application Support directory
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhisperRecorder")
        let keyFile = supportDir.appendingPathComponent(".env")

        do {
            try FileManager.default.createDirectory(
                at: supportDir, withIntermediateDirectories: true)
            try "GEMINI_API_KEY=\(key)".write(to: keyFile, atomically: true, encoding: .utf8)
            logInfo(.llm, "✅ API key saved to \(keyFile.path)")
        } catch {
            logWarning(.llm, "❌ Failed to save API key to file: \(error)")
        }
    }

    func hasApiKey() -> Bool {
        return apiKey != nil && !apiKey!.isEmpty
    }

    func getButtonTitle() -> String {
        return hasApiKey() ? "Delete Token" : "Save Token"
    }

    func deleteApiKey() {
        self.apiKey = nil
        logInfo(.llm, "🗑️ Gemini API key deleted from memory")

        // Delete from Application Support directory
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhisperRecorder")
        let keyFile = supportDir.appendingPathComponent(".env")

        do {
            try FileManager.default.removeItem(at: keyFile)
            logInfo(.llm, "✅ API key file deleted from \(keyFile.path)")
        } catch {
            logWarning(.llm, "❌ Failed to delete API key file: \(error)")
        }
    }

    func getMaskedApiKey() -> String {
        guard let key = apiKey, !key.isEmpty else { return "" }

        let visibleChars = 4
        let maskedLength = max(0, key.count - visibleChars)
        return String(repeating: "•", count: maskedLength) + String(key.suffix(visibleChars))
    }
}
