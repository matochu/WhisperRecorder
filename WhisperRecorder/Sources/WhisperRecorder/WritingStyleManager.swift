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

    // Debug file path for detailed logging
    private let debugLogPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Application Support/WhisperRecorder/whisperrecorder_debug.log")

    private init() {
        createDebugLogDirectoryIfNeeded()
        writeDebugLog("WritingStyleManager initializing...")
        loadApiKey()
    }

    private func createDebugLogDirectoryIfNeeded() {
        let directory = debugLogPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func writeDebugLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logMessage = "[\(timestamp)] \(message)\n"

        // Write to file
        if let data = logMessage.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugLogPath.path) {
                if let fileHandle = try? FileHandle(forWritingTo: debugLogPath) {
                    fileHandle.seekToEndOfFile()
                    fileHandle.write(data)
                    fileHandle.closeFile()
                }
            } else {
                try? data.write(to: debugLogPath, options: .atomic)
            }
        }

        // Also write to standard app log
        writeLog(message)
    }

    private func loadApiKey() {
        writeDebugLog("Starting to load API key...")

        // Load from environment first
        if let key = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] {
            self.apiKey = key
            writeDebugLog("✅ Loaded Gemini API key from environment")
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

        writeDebugLog("Checking for .env file in the following locations:")

        for location in possibleLocations {
            writeDebugLog("  - Checking: \(location)")
            if fileManager.fileExists(atPath: location) {
                writeDebugLog("  ✓ Found .env file at: \(location)")
                if loadApiKeyFromFile(at: location) {
                    writeDebugLog("  ✅ Successfully loaded API key from \(location)")
                    return
                } else {
                    writeDebugLog("  ✗ Failed to load API key from \(location)")
                }
            }
        }

        writeDebugLog("❌ Could not locate .env file with valid Gemini API key in any location")
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

            writeDebugLog("No valid Gemini API key found in file at \(path)")
            return false
        } catch {
            writeDebugLog("Error reading .env file at \(path): \(error)")
            return false
        }
    }

    var currentTargetLanguage: String {
        return targetLanguage ?? noTranslate
    }

    func setTargetLanguage(_ code: String) {
        self.targetLanguage = code
        writeDebugLog("✅ Target language set to: \(code)")
    }

    private func translateIfNeeded(_ text: String, completion: @escaping (String?) -> Void) {
        let targetLang = currentTargetLanguage

        // Skip translation if target language is the same as system language
        if targetLang == noTranslate {
            completion(text)
            return
        }

        guard let apiKey = self.apiKey, !apiKey.isEmpty else {
            writeDebugLog("❌ No Gemini API key available - skipping translation")
            completion(text)
            return
        }

        let prompt = """
            Translate the following text into \(WritingStyleManager.supportedLanguages[targetLang] ?? targetLang).
            Maintain any formatting, tone, and style of the original text.
            Return the result as a JSON object with this schema: {"reformatted_text": "your translated text here"}
            Do not include any additional comments or explanations.

            Text to translate:
            \(text)
            """

        callGeminiAPI(prompt: prompt, apiKey: apiKey) { result in
            if let translatedText = result {
                // Try to parse the response as JSON first
                if let jsonData = translatedText.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                    let reformattedText = json["reformatted_text"] as? String
                {
                    self.writeDebugLog("✅ Successfully translated text to \(targetLang)")
                    completion(reformattedText)
                } else {
                    // If not JSON, use the raw text
                    self.writeDebugLog("✅ Successfully translated text to \(targetLang) (raw text)")
                    completion(translatedText)
                }
            } else {
                self.writeDebugLog("❌ Failed to translate text - returning original")
                completion(text)
            }
        }
    }

    func reformatText(
        _ text: String, withStyle style: WritingStyle, completion: @escaping (String?) -> Void
    ) {
        // Always start with applying the writing style if it's not default
        let applyStyle = { (inputText: String, next: @escaping (String?) -> Void) in
            if style.id == "default" {
                next(inputText)
            } else {
                self.reformatWithGeminiAPI(inputText, style: style) { formattedText in
                    next(formattedText ?? inputText)
                }
            }
        }

        // Then handle translation if needed
        applyStyle(text) { styledText in
            // Ensure we have valid text to translate, use original if style formatting failed
            self.translateIfNeeded(styledText ?? text, completion: completion)
        }
    }

    // Method to reformat text using Gemini API
    private func reformatWithGeminiAPI(
        _ text: String, style: WritingStyle, completion: @escaping (String?) -> Void
    ) {
        guard let apiKey = self.apiKey, !apiKey.isEmpty else {
            writeDebugLog("❌ No Gemini API key available - returning original text")
            completion(text)  // Return original text instead of nil
            return
        }

        // Create prompt for the selected style
        let prompt = createPrompt(for: text, style: style)

        // Make API call to Gemini
        callGeminiAPI(prompt: prompt, apiKey: apiKey) { result in
            if let formattedText = result {
                self.writeDebugLog("✅ Successfully reformatted text with style: \(style.id)")
                completion(formattedText)
            } else {
                self.writeDebugLog("❌ Failed to reformat text - returning original")
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
        let urlString =
            "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)"
        guard let url = URL(string: urlString) else {
            writeDebugLog("Invalid Gemini API URL")
            completion(nil)
            return
        }

        // Create request body with structured output configuration
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt]
                    ]
                ]
            ],
            "generationConfig": [
                "response_mime_type": "application/json"
            ],
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            writeDebugLog("Failed to serialize request body")
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        writeDebugLog("Calling Gemini API to reformat text with structured output...")

        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                self.writeDebugLog("Gemini API request error: \(error)")
                completion(nil)
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                self.writeDebugLog("Gemini API response status: \(httpResponse.statusCode)")
            }

            guard let data = data else {
                self.writeDebugLog("No data received from Gemini API")
                completion(nil)
                return
            }

            do {
                // Log the full response for debugging
                if let jsonString = String(data: data, encoding: .utf8) {
                    self.writeDebugLog("Gemini API response: \(jsonString)")
                }

                // Parse response based on the actual format from Gemini API
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let candidates = json["candidates"] as? [[String: Any]],
                    let firstCandidate = candidates.first,
                    let content = firstCandidate["content"] as? [String: Any]
                {
                    // For structured output, extract the actual JSON content
                    if let parts = content["parts"] as? [[String: Any]],
                        let firstPart = parts.first,
                        let inlineData = firstPart["inlineData"] as? [String: Any],
                        let mimeType = inlineData["mimeType"] as? String,
                        mimeType == "application/json",
                        let data = inlineData["data"] as? String,
                        let jsonData = Data(base64Encoded: data)
                    {
                        // Try to parse the base64-encoded JSON data
                        if let formattedJson = try? JSONSerialization.jsonObject(with: jsonData)
                            as? [String: Any],
                            let reformattedText = formattedJson["reformatted_text"] as? String
                        {
                            self.writeDebugLog(
                                "Successfully received reformatted text from structured output")
                            completion(reformattedText)
                            return
                        }
                    }

                    // Fallback to regular text format if structured format isn't found
                    if let parts = content["parts"] as? [[String: Any]],
                        let firstPart = parts.first,
                        let text = firstPart["text"] as? String
                    {
                        // Try to manually parse JSON if the response is a JSON string
                        if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                            do {
                                if let textData = text.data(using: .utf8),
                                    let jsonObj = try JSONSerialization.jsonObject(with: textData)
                                        as? [String: Any],
                                    let reformattedText = jsonObj["reformatted_text"] as? String
                                {
                                    self.writeDebugLog(
                                        "Successfully parsed JSON from text response")
                                    completion(reformattedText)
                                    return
                                }
                            } catch {
                                self.writeDebugLog("Error parsing JSON from text: \(error)")
                            }
                        }

                        // If we can't extract structured data, use the text directly
                        self.writeDebugLog("Using text response as fallback")
                        completion(text)
                        return
                    }
                }

                // If we get here, we couldn't parse the response
                self.writeDebugLog("Failed to parse Gemini API response structure")

                // Try to get error message
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let error = json["error"] as? [String: Any],
                    let message = error["message"] as? String
                {
                    self.writeDebugLog("Gemini API error: \(message)")
                } else {
                    self.writeDebugLog(
                        "Failed to parse Gemini API response: \(String(data: data, encoding: .utf8) ?? "unknown")"
                    )
                }
                completion(nil)
            } catch {
                self.writeDebugLog("Error parsing Gemini API response: \(error)")
                completion(nil)
            }
        }

        task.resume()
    }

    func saveApiKey(_ key: String) {
        self.apiKey = key
        writeDebugLog("✅ New Gemini API key saved")

        // Save to Application Support directory
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhisperRecorder")
        let keyFile = supportDir.appendingPathComponent(".env")

        do {
            try FileManager.default.createDirectory(
                at: supportDir, withIntermediateDirectories: true)
            try "GEMINI_API_KEY=\(key)".write(to: keyFile, atomically: true, encoding: .utf8)
            writeDebugLog("✅ API key saved to \(keyFile.path)")
        } catch {
            writeDebugLog("❌ Failed to save API key to file: \(error)")
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
        writeDebugLog("🗑️ Gemini API key deleted from memory")

        // Delete from Application Support directory
        let supportDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/WhisperRecorder")
        let keyFile = supportDir.appendingPathComponent(".env")

        do {
            try FileManager.default.removeItem(at: keyFile)
            writeDebugLog("✅ API key file deleted from \(keyFile.path)")
        } catch {
            writeDebugLog("❌ Failed to delete API key file: \(error)")
        }
    }

    func getMaskedApiKey() -> String {
        guard let key = apiKey, !key.isEmpty else { return "" }

        let visibleChars = 4
        let maskedLength = max(0, key.count - visibleChars)
        return String(repeating: "•", count: maskedLength) + String(key.suffix(visibleChars))
    }
}
