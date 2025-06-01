import SwiftUI
import KeyboardShortcuts

// MARK: - Configuration Card
struct ConfigurationCard: View {
    @Binding var selectedWritingStyleIndex: Int
    @Binding var selectedLanguageCode: String
    @Binding var inputText: String
    @State private var settingsType: SettingsType? = nil
    @State private var selectedModelIndex = 0
    @State private var modelRefreshTrigger = false
    @ObservedObject private var toastManager = ToastManager.shared
    @ObservedObject private var audioRecorder = AudioRecorder.shared
    @ObservedObject private var writingStyleManager = WritingStyleManager.shared
    @ObservedObject private var llmManager = LLMManager.shared
    
    // Settings panel types
    enum SettingsType {
        case models
        case api
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Main Configuration (no header)
            configRow(
                icon: "📝",
                label: "Style",
                content: AnyView(
                    Picker("", selection: $selectedWritingStyleIndex) {
                        ForEach(0..<WritingStyle.styles.count, id: \.self) { index in
                            let style = WritingStyle.styles[index]
                            Text(style.name)
                                .tag(index)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(minWidth: 100)
                    .disabled(!WritingStyleManager.shared.hasApiKey()) // Disable AI features without token
                )
            )
            
            configRow(
                icon: "🌍",
                label: "Target",
                content: AnyView(
                    Picker("", selection: $selectedLanguageCode) {
                        ForEach(
                            Array(WritingStyleManager.supportedLanguages.sorted(by: { $0.key < $1.key })),
                            id: \.key
                        ) { code, name in
                            Text(name).tag(code)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(minWidth: 100)
                    .disabled(!WritingStyleManager.shared.hasApiKey()) // Disable AI features without token
                )
            )
            
            // Model info with clickable selector
            configRow(
                icon: "🤖",
                label: "Model",
                content: AnyView(
                    HStack(spacing: 4) {
                        Button(action: {
                            settingsType = settingsType == .models ? nil : .models
                        }) {
                            HStack(spacing: 4) {
                                Text(modelStatusText)
                                    .font(.system(size: 12))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        Button(action: {
                            settingsType = settingsType == .models ? nil : .models
                        }) {
                            Image(systemName: "gear")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                )
            )
            
            // API Status (clickable to configure)
            configRow(
                icon: "🔑",
                label: "LLM",
                content: AnyView(
                    HStack(spacing: 4) {
                        Button(action: {
                            settingsType = settingsType == .api ? nil : .api
                        }) {
                            HStack(spacing: 4) {
                                let hasKey = llmManager.hasApiKey()
                                Text(hasKey ? llmManager.getCurrentModelDisplayName() : "Not Connected")
                                    .font(.system(size: 12))
                                    .foregroundColor(llmManager.hasError ? .red : (hasKey ? .green : .red))
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(llmManager.hasError ? llmManager.getLastErrorSummary() : "")
                        
                        Button(action: {
                            settingsType = settingsType == .api ? nil : .api
                        }) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                )
            )

            // Toast settings
            configRow(
                icon: "💬",
                label: "Toasts",
                content: AnyView(
                    HStack(spacing: 4) {
                        Button(action: {
                            toastManager.toastsEnabled.toggle()
                        }) {
                            HStack(spacing: 4) {
                                Text(toastManager.toastsEnabled ? "Enabled" : "Disabled")
                                    .font(.system(size: 12))
                                    .foregroundColor(toastManager.toastsEnabled ? .green : .orange)
                                
                                Image(systemName: (toastManager.toastsEnabled ? "checkmark.circle" : "xmark.circle" ))
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                )
            )
            
            // Auto-paste permissions status
            configRow(
                icon: "📋",
                label: "Auto-Paste",
                content: AnyView(
                    HStack(spacing: 4) {
                        Button(action: {
                            if audioRecorder.accessibilityPermissionsStatus {
                                // Toggle auto-paste if permissions are granted
                                AudioRecorder.shared.autoPasteEnabled.toggle()
                            } else {
                                // Request permissions if not granted
                                AudioRecorder.shared.requestAccessibilityPermissions()
                            }
                            // Refresh status after action
                            AudioRecorder.shared.updateAccessibilityPermissionStatus()
                        }) {
                            HStack(spacing: 4) {
                                let hasPermissions = audioRecorder.accessibilityPermissionsStatus
                                let isEnabled = AudioRecorder.shared.autoPasteEnabled
                                
                                if hasPermissions && isEnabled {
                                    Text("Enabled")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                } else if hasPermissions && !isEnabled {
                                    Text("Disabled")
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                } else {
                                    Text("No Permissions")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                }
                                
                                Image(systemName: hasPermissions ? (isEnabled ? "checkmark.circle" : "xmark.circle") : "lock.shield")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(autoPasteTooltip)
                        
                        // Manual permissions check button - only show when permissions not granted
                        if !audioRecorder.accessibilityPermissionsStatus {
                            Button(action: {
                                AudioRecorder.shared.updateAccessibilityPermissionStatus()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .help("Manually check permissions status")
                        }
                    }
                )
            )
            
            // Universal settings panel
            if let settingsType = settingsType {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(alignment: .top, spacing: 8) {
                    settingsPanel(for: settingsType)
                    
                    // Close button - fixed position at top right
                    Button(action: {
                        self.settingsType = nil
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .frame(width: 16, height: 16) // Fixed size
                }
            }
        }
        .cardStyle()
        .onAppear {
            // Set correct model index when view appears
            updateSelectedModelIndex()
            
            // Load saved language preference
            let savedLanguageCode = UserDefaults.standard.string(forKey: "selectedLanguageCode") ?? WritingStyleManager.shared.currentTargetLanguage
            selectedLanguageCode = savedLanguageCode
            WritingStyleManager.shared.setTargetLanguage(savedLanguageCode)
        }
        .onChange(of: WhisperWrapper.shared.currentModel.id) { _ in
            // Update when current model changes
            updateSelectedModelIndex()
        }
        .onChange(of: selectedLanguageCode) { newValue in
            WritingStyleManager.shared.setTargetLanguage(newValue)
            // Save to UserDefaults
            UserDefaults.standard.set(newValue, forKey: "selectedLanguageCode")
            logDebug(.ui, "💾 Saved target language: \(WritingStyleManager.supportedLanguages[newValue] ?? newValue)")
        }
    }
    
    private func configRow(icon: String, label: String, content: AnyView) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(icon)
                    .font(.system(size: 13))
                Text(label)
                    .font(.system(size: 12))
                    .frame(minWidth: 60, alignment: .leading)
            }
            
            Spacer()
            
            content
        }
    }
    
    private var modelStatusText: String {
        let currentModel = WhisperWrapper.shared.currentModel
        if WhisperWrapper.shared.isDownloading {
            return "Downloading..."
        } else if WhisperWrapper.shared.isModelLoaded() {
            return "\(currentModel.displayName)"
        } else {
            return "\(currentModel.displayName)"
        }
    }
    
    private var autoPasteTooltip: String {
        let hasPermissions = audioRecorder.accessibilityPermissionsStatus
        let isEnabled = AudioRecorder.shared.autoPasteEnabled
        
        if !hasPermissions {
            return "Click to request accessibility permissions for auto-paste functionality"
        } else if isEnabled {
            return "Auto-paste is enabled - transcribed text will be automatically pasted to active text fields"
        } else {
            return "Auto-paste is disabled - click to enable automatic pasting"
        }
    }
    
    @ViewBuilder
    private func settingsPanel(for type: SettingsType) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch type {
            case .models:
                modelSettingsView
            case .api:
                apiSettingsView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 4)
    }
    
    private var modelSettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Management")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            Picker("", selection: $selectedModelIndex) {
                ForEach(0..<WhisperWrapper.availableModels.count, id: \.self) { index in
                    let model = WhisperWrapper.availableModels[index]
                    Text(modelDisplayText(for: model))
                        .tag(index)
                }
            }
            .pickerStyle(MenuPickerStyle())
            .labelsHidden()
            
            if WhisperWrapper.shared.isDownloading {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Downloading: \(Int(WhisperWrapper.shared.downloadProgress * 100))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    ProgressView(value: WhisperWrapper.shared.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                        .frame(height: 4)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Apply") {
                        let selectedModel = WhisperWrapper.availableModels[selectedModelIndex]
                        WhisperWrapper.shared.switchModel(to: selectedModel) { success in
                            if !success {
                                WhisperWrapper.shared.downloadCurrentModel { _ in
                                    modelRefreshTrigger.toggle()
                                }
                            }
                            settingsType = nil
                        }
                    }
                    .disabled(WhisperWrapper.shared.isDownloading)
                    .font(.system(size: 11))
                    
                    if selectedModelIndex < WhisperWrapper.availableModels.count {
                        let selectedModel = WhisperWrapper.availableModels[selectedModelIndex]
                        if WhisperWrapper.shared.isModelDownloaded(selectedModel) && selectedModel.id != WhisperWrapper.shared.currentModel.id {
                            Button("Delete") {
                                WhisperWrapper.shared.deleteModel(selectedModel) { success in
                                    if success {
                                        modelRefreshTrigger.toggle()
                                    }
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                        }
                    }
                    
                    Button("Cancel") {
                        settingsType = nil
                    }
                    .font(.system(size: 11))
                }
            }
        }
        .onChange(of: modelRefreshTrigger) { _ in
            // Trigger view refresh
        }
    }
    
    private var apiSettingsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LLM Provider Configuration")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            // Provider Selection
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Provider:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Picker("Provider", selection: Binding(
                    get: { llmManager.currentProvider },
                    set: { llmManager.setCurrentProvider($0) }
                )) {
                    ForEach(llmManager.getAllProviders(), id: \.self) { provider in
                        HStack {
                            Text("\(provider.icon) \(provider.displayName)")
                            Spacer()
                            if llmManager.hasApiKey(for: provider) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            }
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .labelsHidden()
            }
            
            let currentProvider = llmManager.currentProvider
            let hasKey = llmManager.hasApiKey(for: currentProvider)
            
            // Model Selection for Current Provider
            if hasKey || !currentProvider.requiresApiKey {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Model Selection:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Picker("Model", selection: Binding(
                        get: { 
                            let currentModel = llmManager.getCurrentModelDisplayName()
                            return currentModel.isEmpty ? currentProvider.defaultModel : currentModel
                        },
                        set: { llmManager.setCurrentModel($0) }
                    )) {
                        ForEach(currentProvider.availableModels, id: \.self) { model in
                            Text(model)
                                .tag(model)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                    .disabled(!hasKey && currentProvider.requiresApiKey)
                    
                    Text("Current: \(llmManager.getCurrentModelDisplayName())")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            // API Key Management for Current Provider
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("\(currentProvider.icon) \(currentProvider.displayName)")
                        .font(.system(size: 11, weight: .medium))
                    
                    Spacer()
                    
                    if hasKey {
                        Text("✅ Connected")
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                    } else {
                        Text("❌ No Token")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
                
                if currentProvider.requiresApiKey {
                    if hasKey {
                        HStack {
                            Text("Token: \(llmManager.getMaskedApiKey(for: currentProvider))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            Spacer()
                            
                            Button("Change") {
                                llmManager.deleteApiKey(for: currentProvider)
                                inputText = ""
                            }
                            .font(.system(size: 11))
                            .foregroundColor(.blue)
                            .buttonStyle(PlainButtonStyle())
                        }
                    } else {
                        HStack {
                            TextField("Enter \(currentProvider.displayName) API Token", text: $inputText)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(size: 11))
                            
                            Button("Save") {
                                if !inputText.isEmpty {
                                    llmManager.saveApiKey(inputText, for: currentProvider)
                                    inputText = ""
                                }
                            }
                            .disabled(inputText.isEmpty)
                            .font(.system(size: 11))
                        }
                    }
                } else {
                    Text("This provider runs locally and doesn't require an API token")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .italic()
                }
                
                // Provider-specific info
                switch currentProvider {
                case .gemini:
                    Text("Get your API key from Google AI Studio (ai.google.dev)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                case .openai:
                    Text("Get your API key from OpenAI Platform (platform.openai.com)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                case .claude:
                    Text("Get your API key from Anthropic Console (console.anthropic.com)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                case .ollama:
                    Text("Make sure Ollama is running locally on port 11434")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                if !hasKey && currentProvider.requiresApiKey {
                    Text("⚠️ AI features disabled without API token")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
                }
            }
            
            // Summary of all providers
            if llmManager.getProvidersWithKeys().count > 1 {
                Divider()
                    .padding(.vertical, 2)
                
                Text("Available Providers:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                ForEach(llmManager.getProvidersWithKeys(), id: \.self) { provider in
                    HStack {
                        Text("\(provider.icon) \(provider.displayName)")
                            .font(.system(size: 10))
                        
                        Spacer()
                        
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 10))
                    }
                }
            }
        }
    }
    
    private func modelDisplayText(for model: WhisperModel) -> String {
        var text = "\(model.displayName) (\(model.size))"
        
        // Add status indicator based on actual file check
        if WhisperWrapper.shared.isModelDownloaded(model) {
            if model.id == WhisperWrapper.shared.currentModel.id {
                text = "✅ \(text) - Active"
            } else {
                text = "📦 \(text) - Downloaded"
            }
        } else {
            text = "📥 \(text) - Not Downloaded"
        }
        
        // Add language indicators
        if model.language.contains("Multilingual") {
            text += " 🌍"
        } else {
            text += " 🇺🇸" // For English-only models
        }
        
        return text
    }
    
    private func isModelDownloaded(_ model: WhisperModel) -> Bool {
        return WhisperWrapper.shared.isModelDownloaded(model)
    }
    
    private func updateSelectedModelIndex() {
        // Find the index of the current model in availableModels
        if let index = WhisperWrapper.availableModels.firstIndex(where: { $0.id == WhisperWrapper.shared.currentModel.id }) {
            selectedModelIndex = index
        } else {
            selectedModelIndex = 0  // Fallback to first model if current not found
        }
    }
} 