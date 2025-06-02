import Foundation

// MARK: - LLM Provider Support

enum LLMProvider: String, CaseIterable {
    case gemini = "gemini"
    case openai = "openai" 
    case claude = "claude"
    case ollama = "ollama"
    
    var displayName: String {
        switch self {
        case .gemini: return "Google Gemini"
        case .openai: return "OpenAI GPT"
        case .claude: return "Anthropic Claude"
        case .ollama: return "Ollama (Local)"
        }
    }
    
    var icon: String {
        switch self {
        case .gemini: return "🤖"
        case .openai: return "🧠"
        case .claude: return "🎯"
        case .ollama: return "🏠"
        }
    }
    
    var requiresApiKey: Bool {
        switch self {
        case .gemini, .openai, .claude: return true
        case .ollama: return false
        }
    }
    
    var availableModels: [String] {
        switch self {
        case .gemini:
            return [
                "gemini-2.0-flash",
                "gemini-1.5-pro",
                "gemini-1.5-flash",
                "gemini-1.0-pro"
            ]
        case .openai:
            return [
                "gpt-4o",
                "gpt-4o-mini",
                "gpt-4-turbo",
                "gpt-4",
                "gpt-3.5-turbo"
            ]
        case .claude:
            return [
                "claude-3-5-sonnet-20241022",
                "claude-3-5-haiku-20241022",
                "claude-3-opus-20240229",
                "claude-3-sonnet-20240229",
                "claude-3-haiku-20240307"
            ]
        case .ollama:
            return [
                "llama3.2",
                "llama3.1",
                "mistral",
                "codellama",
                "deepseek-coder"
            ]
        }
    }
    
    var defaultModel: String {
        switch self {
        case .gemini: return "gemini-2.0-flash"
        case .openai: return "gpt-4o-mini"
        case .claude: return "claude-3-5-haiku-20241022"
        case .ollama: return "llama3.2"
        }
    }
    
    var apiURL: String {
        switch self {
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/models"
        case .openai:
            return "https://api.openai.com/v1/chat/completions"
        case .claude:
            return "https://api.anthropic.com/v1/messages"
        case .ollama:
            return "http://localhost:11434/api/generate"
        }
    }
}

// MARK: - LLM Manager

class LLMManager: ObservableObject {
    static let shared = LLMManager()
    
    // Current provider and API keys
    @Published var currentProvider: LLMProvider = .gemini
    @Published var currentModel: String = ""
    private var apiKeys: [LLMProvider: String] = [:]
    
    // Error handling
    @Published var lastError: String = ""
    @Published var lastErrorTime: Date = Date()
    @Published var hasError: Bool = false
    
    // Last request for retry functionality
    private var lastRequest: (() -> Void)?
    
    private init() {
        logInfo(.llm, "LLMManager initializing...")
        loadAllApiKeys()
        loadCurrentProvider()
        loadCurrentModel()
        loadLastError()
    }
    
    // MARK: - Provider Management
    
    func setCurrentProvider(_ provider: LLMProvider) {
        currentProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: "currentLLMProvider")
        
        // Set default model for the new provider if none is set
        if currentModel.isEmpty || !provider.availableModels.contains(currentModel) {
            setCurrentModel(provider.defaultModel)
        }
        
        logInfo(.llm, "✅ Current provider set to: \(provider.displayName)")
        objectWillChange.send()
    }
    
    func getAllProviders() -> [LLMProvider] {
        return LLMProvider.allCases
    }
    
    func getProvidersWithKeys() -> [LLMProvider] {
        return apiKeys.keys.sorted { $0.displayName < $1.displayName }
    }
    
    // MARK: - Model Management
    
    func setCurrentModel(_ model: String) {
        currentModel = model
        UserDefaults.standard.set(model, forKey: "currentLLMModel_\(currentProvider.rawValue)")
        logInfo(.llm, "✅ Current model set to: \(model) for \(currentProvider.displayName)")
        objectWillChange.send()
    }
    
    func getAvailableModels() -> [String] {
        return currentProvider.availableModels
    }
    
    func getCurrentModelDisplayName() -> String {
        if currentModel.isEmpty {
            return currentProvider.defaultModel
        }
        return currentModel
    }
    
    private func loadCurrentModel() {
        let savedModel = UserDefaults.standard.string(forKey: "currentLLMModel_\(currentProvider.rawValue)")
        currentModel = savedModel ?? currentProvider.defaultModel
        logInfo(.llm, "📱 Loaded current model: \(currentModel) for \(currentProvider.displayName)")
    }
    
    // MARK: - API Key Management
    
    func saveApiKey(_ key: String, for provider: LLMProvider) {
        apiKeys[provider] = key
        UserDefaults.standard.set(key, forKey: "apiKey_\(provider.rawValue)")
        logInfo(.llm, "✅ \(provider.displayName) API key saved")
        
        // Also save to file for backward compatibility (Gemini)
        if provider == .gemini {
            saveGeminiKeyToFile(key)
        }
    }
    
    func hasApiKey(for provider: LLMProvider? = nil) -> Bool {
        let targetProvider = provider ?? currentProvider
        return apiKeys[targetProvider] != nil && !apiKeys[targetProvider]!.isEmpty
    }
    
    func getApiKey(for provider: LLMProvider? = nil) -> String? {
        let targetProvider = provider ?? currentProvider
        return apiKeys[targetProvider]
    }
    
    func deleteApiKey(for provider: LLMProvider) {
        apiKeys.removeValue(forKey: provider)
        UserDefaults.standard.removeObject(forKey: "apiKey_\(provider.rawValue)")
        logInfo(.llm, "🗑️ \(provider.displayName) API key deleted")
        
        // Also delete from file for Gemini backward compatibility
        if provider == .gemini {
            deleteGeminiKeyFromFile()
        }
    }
    
    func getMaskedApiKey(for provider: LLMProvider? = nil) -> String {
        let targetProvider = provider ?? currentProvider
        guard let key = apiKeys[targetProvider], !key.isEmpty else { return "" }

        let visibleChars = 4
        let maskedLength = max(0, key.count - visibleChars)
        return String(repeating: "•", count: maskedLength) + String(key.suffix(visibleChars))
    }
    
    // MARK: - API URL Generation
    
    func getApiURL(for provider: LLMProvider? = nil) -> String {
        let targetProvider = provider ?? currentProvider
        let selectedModel = currentModel.isEmpty ? targetProvider.defaultModel : currentModel
        
        switch targetProvider {
        case .gemini:
            guard let apiKey = apiKeys[.gemini] else {
                return "\(targetProvider.apiURL)/\(selectedModel):generateContent"
            }
            return "\(targetProvider.apiURL)/\(selectedModel):generateContent?key=\(apiKey)"
        default:
            return targetProvider.apiURL
        }
    }
    
    // MARK: - Generic API Call Method
    
    func callAPI(
        prompt: String,
        provider: LLMProvider? = nil,
        completion: @escaping (String?) -> Void
    ) {
        let targetProvider = provider ?? currentProvider
        
        logDebug(.llm, "🚀 Starting API call to \(targetProvider.displayName)")
        logDebug(.llm, "📤 Request prompt (\(prompt.count) chars): \(prompt)")
        
        // Store this request for potential retry
        lastRequest = { [weak self] in
            self?.callAPI(prompt: prompt, provider: provider, completion: completion)
        }
        
        // Check API key requirement
        if targetProvider.requiresApiKey && !hasApiKey(for: targetProvider) {
            let errorMsg = "No API key available for \(targetProvider.displayName)"
            logWarning(.llm, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }
        
        switch targetProvider {
        case .gemini:
            callGeminiAPI(prompt: prompt, completion: completion)
        case .openai:
            callOpenAIAPI(prompt: prompt, completion: completion)
        case .claude:
            callClaudeAPI(prompt: prompt, completion: completion)
        case .ollama:
            callOllamaAPI(prompt: prompt, completion: completion)
        }
    }
    
    // MARK: - Provider-Specific API Implementations
    
    private func callGeminiAPI(prompt: String, completion: @escaping (String?) -> Void) {
        logInfo(.network, "🌐 Starting Gemini API call")
        
        guard let url = URL(string: getApiURL(for: .gemini)) else {
            let errorMsg = "Invalid Gemini API URL"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
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
        } catch {
            let errorMsg = "Failed to serialize Gemini request body: \(error.localizedDescription)"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }

        executeAPIRequest(request) { data in
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let candidates = jsonObject["candidates"] as? [[String: Any]],
                   let firstCandidate = candidates.first,
                   let content = firstCandidate["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let firstPart = parts.first,
                   let text = firstPart["text"] as? String {
                    
                    let cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    logDebug(.llm, "📥 Gemini API response (\(cleanedText.count) chars): \(cleanedText)")
                    completion(cleanedText)
                } else {
                    let errorMsg = "Failed to parse Gemini response structure"
                    logError(.network, "❌ \(errorMsg)")
                    logDebug(.llm, "📥 Raw Gemini response: \(String(data: data, encoding: .utf8) ?? "nil")")
                    self.setError(errorMsg)
                    completion(nil)
                }
            } catch {
                let errorMsg = "Gemini JSON parsing error: \(error.localizedDescription)"
                logError(.network, "❌ \(errorMsg)")
                logDebug(.llm, "📥 Raw Gemini response: \(String(data: data, encoding: .utf8) ?? "nil")")
                self.setError(errorMsg)
                completion(nil)
            }
        }
    }
    
    private func callOpenAIAPI(prompt: String, completion: @escaping (String?) -> Void) {
        logInfo(.network, "🌐 Starting OpenAI API call")
        
        guard let url = URL(string: getApiURL(for: .openai)) else {
            let errorMsg = "Invalid OpenAI API URL"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }
        
        guard let apiKey = apiKeys[.openai] else {
            let errorMsg = "No OpenAI API key available"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let selectedModel = currentModel.isEmpty ? currentProvider.defaultModel : currentModel
        let requestBody: [String: Any] = [
            "model": selectedModel,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ],
            "max_tokens": 4000
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
        } catch {
            let errorMsg = "Failed to serialize OpenAI request body: \(error.localizedDescription)"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }

        executeAPIRequest(request) { data in
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = jsonObject["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    completion(content.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let errorMsg = "Failed to parse OpenAI response structure"
                    logError(.network, "❌ \(errorMsg)")
                    self.setError(errorMsg)
                    completion(nil)
                }
            } catch {
                let errorMsg = "OpenAI JSON parsing error: \(error.localizedDescription)"
                logError(.network, "❌ \(errorMsg)")
                self.setError(errorMsg)
                completion(nil)
            }
        }
    }
    
    private func callClaudeAPI(prompt: String, completion: @escaping (String?) -> Void) {
        logInfo(.network, "🌐 Starting Claude API call")
        
        guard let url = URL(string: getApiURL(for: .claude)) else {
            let errorMsg = "Invalid Claude API URL"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }
        
        guard let apiKey = apiKeys[.claude] else {
            let errorMsg = "No Claude API key available"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let selectedModel = currentModel.isEmpty ? currentProvider.defaultModel : currentModel
        let requestBody: [String: Any] = [
            "model": selectedModel,
            "max_tokens": 4000,
            "messages": [
                [
                    "role": "user",
                    "content": prompt
                ]
            ]
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
        } catch {
            let errorMsg = "Failed to serialize Claude request body: \(error.localizedDescription)"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }

        executeAPIRequest(request) { data in
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let content = jsonObject["content"] as? [[String: Any]],
                   let firstContent = content.first,
                   let text = firstContent["text"] as? String {
                    
                    completion(text.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let errorMsg = "Failed to parse Claude response structure"
                    logError(.network, "❌ \(errorMsg)")
                    self.setError(errorMsg)
                    completion(nil)
                }
            } catch {
                let errorMsg = "Claude JSON parsing error: \(error.localizedDescription)"
                logError(.network, "❌ \(errorMsg)")
                self.setError(errorMsg)
                completion(nil)
            }
        }
    }
    
    private func callOllamaAPI(prompt: String, completion: @escaping (String?) -> Void) {
        logInfo(.network, "🌐 Starting Ollama API call")
        
        guard let url = URL(string: getApiURL(for: .ollama)) else {
            let errorMsg = "Invalid Ollama API URL"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let selectedModel = currentModel.isEmpty ? currentProvider.defaultModel : currentModel
        let requestBody: [String: Any] = [
            "model": selectedModel,
            "prompt": prompt,
            "stream": false
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
            request.httpBody = jsonData
        } catch {
            let errorMsg = "Failed to serialize Ollama request body: \(error.localizedDescription)"
            logError(.network, "❌ \(errorMsg)")
            setError(errorMsg)
            completion(nil)
            return
        }

        executeAPIRequest(request) { data in
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let response = jsonObject["response"] as? String {
                    
                    completion(response.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let errorMsg = "Failed to parse Ollama response structure"
                    logError(.network, "❌ \(errorMsg)")
                    self.setError(errorMsg)
                    completion(nil)
                }
            } catch {
                let errorMsg = "Ollama JSON parsing error: \(error.localizedDescription)"
                logError(.network, "❌ \(errorMsg)")
                self.setError(errorMsg)
                completion(nil)
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func executeAPIRequest(_ request: URLRequest, completion: @escaping (Data) -> Void) {
        startTiming("api_request")

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let requestTime = endTiming("api_request")

            if let error = error {
                let errorMsg = "Network error: \(error.localizedDescription)"
                logError(.network, "❌ \(errorMsg)")
                logInfo(.performance, "Failed API request took \(String(format: "%.3f", requestTime ?? 0))s")
                self.setError(errorMsg)
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                let errorMsg = "Invalid response type"
                logError(.network, "❌ \(errorMsg)")
                self.setError(errorMsg)
                return
            }

            logInfo(.network, "📡 Received HTTP response: \(httpResponse.statusCode)")
            logInfo(.performance, "API request completed in \(String(format: "%.3f", requestTime ?? 0))s")

            guard let data = data else {
                let errorMsg = "No data received from API"
                logError(.network, "❌ \(errorMsg)")
                self.setError(errorMsg)
                return
            }

            if httpResponse.statusCode != 200 {
                var errorMsg = "API returned error status: \(httpResponse.statusCode)"
                
                // Try to parse error response for more details
                if let errorString = String(data: data, encoding: .utf8) {
                    logError(.network, "Error response: \(errorString)")
                    
                    // Try to extract meaningful error message from response
                    if let jsonData = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let error = jsonData["error"] as? [String: Any],
                           let message = error["message"] as? String {
                            errorMsg = message
                        } else if let message = jsonData["message"] as? String {
                            errorMsg = message
                        }
                    }
                }
                
                logError(.network, "❌ \(errorMsg)")
                self.setError(errorMsg)
                return
            }

            // Clear any previous errors on successful response
            if self.hasError {
                self.clearError()
            }

            completion(data)
        }

        task.resume()
    }
    
    // MARK: - Legacy Support and File Management
    
    private func loadAllApiKeys() {
        logDebug(.llm, "Loading API keys for all providers...")
        
        // Load from environment variables
        loadFromEnvironment()
        
        // Load from .env files
        loadFromFiles()
        
        // Load from UserDefaults (saved keys)
        loadFromUserDefaults()
    }
    
    private func loadFromEnvironment() {
        let envKeys: [LLMProvider: String] = [
            .gemini: "GEMINI_API_KEY",
            .openai: "OPENAI_API_KEY", 
            .claude: "CLAUDE_API_KEY"
        ]
        
        for (provider, envVar) in envKeys {
            if let key = ProcessInfo.processInfo.environment[envVar], !key.isEmpty {
                apiKeys[provider] = key
                logInfo(.llm, "✅ Loaded \(provider.displayName) API key from environment")
            }
        }
    }
    
    private func loadFromFiles() {
        let fileManager = FileManager.default
        let possibleLocations: [String] = [
            Bundle.main.resourcePath.map { path in
                URL(fileURLWithPath: path).appendingPathComponent(".env").path
            },
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".env").path,
            URL(fileURLWithPath: fileManager.currentDirectoryPath).appendingPathComponent(".env").path,
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/WhisperRecorder/.env").path,
        ].compactMap { $0 }

        for location in possibleLocations {
            if fileManager.fileExists(atPath: location) {
                loadApiKeysFromFile(at: location)
            }
        }
    }
    
    private func loadFromUserDefaults() {
        for provider in LLMProvider.allCases {
            if let key = UserDefaults.standard.string(forKey: "apiKey_\(provider.rawValue)"), !key.isEmpty {
                apiKeys[provider] = key
                logInfo(.llm, "✅ Loaded \(provider.displayName) API key from UserDefaults")
            }
        }
    }
    
    private func loadCurrentProvider() {
        if let providerRaw = UserDefaults.standard.string(forKey: "currentLLMProvider"),
           let provider = LLMProvider(rawValue: providerRaw) {
            currentProvider = provider
            logInfo(.llm, "✅ Loaded current provider: \(provider.displayName)")
        } else {
            // Default to first provider that has an API key, or Gemini
            currentProvider = apiKeys.keys.first ?? .gemini
            logInfo(.llm, "Using default provider: \(currentProvider.displayName)")
        }
    }
    
    private func loadApiKeysFromFile(at path: String) {
        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            let lines = content.split(separator: "\n")

            let keyMappings: [String: LLMProvider] = [
                "GEMINI_API_KEY": .gemini,
                "OPENAI_API_KEY": .openai,
                "CLAUDE_API_KEY": .claude
            ]
            
            for line in lines {
                for (envVar, provider) in keyMappings {
                    if line.starts(with: "\(envVar)=") {
                        let key = line.dropFirst("\(envVar)=".count).trimmingCharacters(
                            in: .whitespacesAndNewlines)
                        if !key.isEmpty && key != "your_api_key_here" {
                            apiKeys[provider] = key
                            logInfo(.llm, "✅ Loaded \(provider.displayName) key from \(path)")
                        }
                    }
                }
            }
        } catch {
            logError(.llm, "Error reading .env file at \(path): \(error)")
        }
    }
    
    private func saveGeminiKeyToFile(_ key: String) {
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
    
    private func deleteGeminiKeyFromFile() {
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
    
    // MARK: - Legacy Compatibility Methods
    
    func saveApiKey(_ key: String) {
        // Legacy method - saves to current provider
        apiKeys[currentProvider] = key
        UserDefaults.standard.set(key, forKey: "apiKey_\(currentProvider.rawValue)")
        logInfo(.llm, "✅ \(currentProvider.displayName) API key saved")
        
        // Also save to file for backward compatibility (Gemini)
        if currentProvider == .gemini {
            saveGeminiKeyToFile(key)
        }
    }

    func hasApiKey() -> Bool {
        return apiKeys[currentProvider] != nil && !apiKeys[currentProvider]!.isEmpty
    }

    func getButtonTitle() -> String {
        return (apiKeys[currentProvider] != nil && !apiKeys[currentProvider]!.isEmpty) ? "Delete Token" : "Save Token"
    }

    func deleteApiKey() {
        apiKeys.removeValue(forKey: currentProvider)
        UserDefaults.standard.removeObject(forKey: "apiKey_\(currentProvider.rawValue)")
        logInfo(.llm, "🗑️ \(currentProvider.displayName) API key deleted")
        
        // Also delete from file for Gemini backward compatibility
        if currentProvider == .gemini {
            deleteGeminiKeyFromFile()
        }
    }

    func getMaskedApiKey() -> String {
        guard let key = apiKeys[currentProvider], !key.isEmpty else { return "" }

        let visibleChars = 4
        let maskedLength = max(0, key.count - visibleChars)
        return String(repeating: "•", count: maskedLength) + String(key.suffix(visibleChars))
    }

    // MARK: - Text Processing Methods
    
    func processText(prompt: String, completion: @escaping (String?) -> Void) {
        callAPI(prompt: prompt, completion: completion)
    }
    
    // MARK: - Error Management
    
    func setError(_ error: String) {
        DispatchQueue.main.async {
            self.lastError = error
            self.lastErrorTime = Date()
            self.hasError = true
            
            // Save to UserDefaults for persistence
            UserDefaults.standard.set(error, forKey: "lastLLMError")
            UserDefaults.standard.set(self.lastErrorTime, forKey: "lastLLMErrorTime")
            
            logError(.llm, "LLM Error: \(error)")
            
            // Show toast notification for immediate feedback (Method A)
            ToastManager.shared.showToast(message: "LLM Error", preview: error)
        }
    }
    
    func clearError() {
        DispatchQueue.main.async {
            self.hasError = false
            self.lastError = ""
            UserDefaults.standard.removeObject(forKey: "lastLLMError")
            UserDefaults.standard.removeObject(forKey: "lastLLMErrorTime")
        }
    }
    
    func retryLastRequest() {
        guard let lastRequest = lastRequest else {
            logWarning(.llm, "No last request to retry")
            return
        }
        
        logInfo(.llm, "🔄 Retrying last LLM request")
        clearError() // Clear previous error
        lastRequest() // Execute the stored request
    }
    
    func getLastErrorSummary() -> String {
        if !hasError || lastError.isEmpty {
            return ""
        }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let timeAgo = formatter.localizedString(for: lastErrorTime, relativeTo: Date())
        
        return "\(lastError) (\(timeAgo))"
    }
    
    private func loadLastError() {
        if let error = UserDefaults.standard.string(forKey: "lastLLMError"),
           let errorTime = UserDefaults.standard.object(forKey: "lastLLMErrorTime") as? Date {
            lastError = error
            lastErrorTime = errorTime
            hasError = true
            logInfo(.llm, "Loaded last error: \(error)")
        }
    }
    
    // MARK: - Custom Prompt Processing
    
    func processWithCustomPrompt(_ prompt: String, completion: @escaping (String?) -> Void) {
        logInfo(.llm, "🤖 Processing custom prompt")
        logDebug(.llm, "Custom prompt: \\(prompt.count) characters")
        
        guard hasApiKey() else {
            logWarning(.llm, "❌ No API key available for custom prompt processing")
            completion(nil)
            return
        }
        
        // Direct API call without style or translation processing
        callAPI(prompt: prompt) { result in
            if let processedText = result {
                logInfo(.llm, "✅ Custom prompt processed successfully")
                logDebug(.llm, "Result: \\(processedText.count) characters")
                completion(processedText)
            } else {
                logError(.llm, "❌ Custom prompt processing failed")
                completion(nil)
            }
        }
    }
} 