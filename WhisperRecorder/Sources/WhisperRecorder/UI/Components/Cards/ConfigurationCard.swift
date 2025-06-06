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
    
    // Cached model lists for performance
    @State private var cachedWhisperModels: [WhisperModel] = []
    @State private var cachedDownloadedModels: [WhisperModel] = []
    @State private var cachedLLMProviders: [LLMProvider] = []
    @State private var cachedCurrentLLMModels: [String] = []
    @State private var lastCacheUpdate = Date()
    
    // Add state tracking for operation status to avoid frequent logging
    @State private var lastOperationStatus = ""
    @State private var lastOperationStatusChange = Date()
    
    // Check if recording or processing is active (block all configuration during these operations)
    private var isActiveOperation: Bool {
        let status = audioRecorder.statusDescription
        return status == "Recording..." || status == "Processing..."
    }
    
    // Function to handle status logging (called from onChange)
    private func handleStatusChange() {
        let status = audioRecorder.statusDescription
        let isActive = isActiveOperation
        
        // Only log on actual status changes
        if status != lastOperationStatus {
            let now = Date()
            // Throttle logging to at most once per second to avoid spam
            if now.timeIntervalSince(lastOperationStatusChange) >= 1.0 {
                if isActive {
                    logDebug(.ui, "🔒 ConfigurationCard: UI blocked, status changed to '\(status)'")
                } else if lastOperationStatus != "" && lastOperationStatus != status {
                    logDebug(.ui, "🔓 ConfigurationCard: UI unblocked, status changed to '\(status)'")
                }
                lastOperationStatus = status
                lastOperationStatusChange = now
            }
        }
    }
    
    @ObservedObject private var toastManager = ToastManager.shared
    @ObservedObject private var audioRecorder = AudioRecorder.shared
    @ObservedObject private var writingStyleManager = WritingStyleManager.shared
    @ObservedObject private var llmManager = LLMManager.shared
    @ObservedObject private var clipboardManager = ClipboardManager.shared // Add ClipboardManager for auto-paste reactivity
    
    // Add state tracking for UI debugging
    @State private var lastMenuInteraction = Date()
    @State private var uiStateDebug = "normal"
    
    // Settings panel types
    enum SettingsType {
        case models
        case api
    }
    
    // MARK: - Cache Management
    private func updateModelCache() {
        // Only update cache if more than 5 seconds passed (avoid too frequent updates)
        let now = Date()
        if now.timeIntervalSince(lastCacheUpdate) < 5.0 && !cachedWhisperModels.isEmpty {
            return
        }
        
        // Cache Whisper models
        cachedWhisperModels = WhisperWrapper.availableModels
        cachedDownloadedModels = cachedWhisperModels.filter { WhisperWrapper.shared.isModelDownloaded($0) }
        
        // Cache LLM providers and models
        cachedLLMProviders = llmManager.getAllProviders()
        cachedCurrentLLMModels = llmManager.currentProvider.availableModels
        
        lastCacheUpdate = now
    }
    
    private func refreshModelCache() {
        // Force cache refresh
        lastCacheUpdate = Date.distantPast
        updateModelCache()
    }
    
    var body: some View {
        ZStack {
            VStack(spacing: 8) {
                // Main Configuration (no header)
                configRow(
                    icon: "📝",
                    label: "Style",
                    content: AnyView(
                        Menu {
                            ForEach(0..<WritingStyle.styles.count, id: \.self) { index in
                                let style = WritingStyle.styles[index]
                                Button(style.name) {
                                    logDebug(.ui, "🎯 Style menu: Selected '\(style.name)' (index \(index))")
                                    lastMenuInteraction = Date()
                                    uiStateDebug = "style_selected"
                                    selectedWritingStyleIndex = index
                                    
                                    // Force UI update after menu interaction
                                    DispatchQueue.main.async {
                                        uiStateDebug = "normal"
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(WritingStyle.styles[selectedWritingStyleIndex].name)
                                    .font(.system(size: 12))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(minWidth: 120, alignment: .trailing)
                        .disabled(!WritingStyleManager.shared.hasApiKey() || isActiveOperation) // Block during active operations
                        .onTapGesture {
                            logDebug(.ui, "🎯 Style menu: Tapped to open")
                            lastMenuInteraction = Date()
                            uiStateDebug = "style_menu_opening"
                        }
                    )
                )
                
                configRow(
                    icon: "🌍",
                    label: "Target",
                    content: AnyView(
                        Menu {
                            ForEach(
                                Array(WritingStyleManager.supportedLanguages.sorted(by: { $0.key < $1.key })),
                                id: \.key
                            ) { code, name in
                                Button(name) {
                                    logDebug(.ui, "🌍 Target menu: Selected '\(name)' (code \(code))")
                                    lastMenuInteraction = Date()
                                    uiStateDebug = "target_selected"
                                    selectedLanguageCode = code
                                    
                                    // Force UI update after menu interaction
                                    DispatchQueue.main.async {
                                        uiStateDebug = "normal"
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(WritingStyleManager.supportedLanguages[selectedLanguageCode] ?? selectedLanguageCode)
                                    .font(.system(size: 12))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(.primary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .frame(minWidth: 120, alignment: .trailing)
                        .disabled(!WritingStyleManager.shared.hasApiKey() || isActiveOperation) // Block during active operations
                        .onTapGesture {
                            logDebug(.ui, "🌍 Target menu: Tapped to open")
                            lastMenuInteraction = Date()
                            uiStateDebug = "target_menu_opening"
                        }
                    )
                )
                
                // Model info with direct model selector
                configRow(
                    icon: "🤖",
                    label: "Model",
                    content: AnyView(
                        HStack(spacing: 4) {
                            Menu {
                                ForEach(cachedDownloadedModels, id: \.id) { model in
                                    Button(model.displayName) {
                                        WhisperWrapper.shared.switchModel(to: model) { success in
                                            if !success {
                                                // Handle error if needed
                                            }
                                        }
                                    }
                                }
                            } label: {
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
                            .frame(minWidth: 120, alignment: .trailing)
                            .disabled(isActiveOperation) // Block during active operations
                            
                            Button(action: {
                                if !isActiveOperation {
                                    settingsType = settingsType == .models ? nil : .models
                                }
                            }) {
                                Image(systemName: "gear")
                                    .font(.system(size: 10))
                                    .foregroundColor(isActiveOperation ? .secondary.opacity(0.5) : .secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isActiveOperation)
                            .help(isActiveOperation ? "Settings blocked during recording/processing" : "Configure models")
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
                                if !isActiveOperation {
                                    settingsType = settingsType == .api ? nil : .api
                                }
                            }) {
                                HStack(spacing: 4) {
                                    let hasKey = llmManager.hasApiKey()
                                    Text(hasKey ? llmManager.getCurrentModelDisplayName() : "Not Connected")
                                        .font(.system(size: 12))
                                        .foregroundColor(llmManager.hasError ? .red : (hasKey ? .green : .red))
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .frame(minWidth: 120, alignment: .trailing)
                            .help(llmManager.hasError ? llmManager.getLastErrorSummary() : "")
                            
                            // Only show retry button when there's an error
                            if llmManager.hasError {
                                Button(action: {
                                    llmManager.retryLastRequest()
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10))
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Retry last LLM request")
                            }
                            
                            Button(action: {
                                if !isActiveOperation {
                                    settingsType = settingsType == .api ? nil : .api
                                }
                            }) {
                                Image(systemName: "gear")
                                    .font(.system(size: 10))
                                    .foregroundColor(isActiveOperation ? .secondary.opacity(0.5) : .secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(isActiveOperation)
                            .help(isActiveOperation ? "Settings blocked during recording/processing" : "Configure LLM API")
                        }
                    )
                )

                // Toast settings - also block during active operations
                configRow(
                    icon: "💬",
                    label: "Toasts",
                    content: AnyView(
                        HStack(spacing: 4) {
                            Button(action: {
                                if !isActiveOperation {
                                    toastManager.toastsEnabled.toggle()
                                }
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
                            .frame(minWidth: 120, alignment: .trailing)
                            .disabled(isActiveOperation) // Block during active operations
                        }
                    )
                )
                
                // Auto-paste permissions status - also block during active operations
                configRow(
                    icon: "📋",
                    label: "Auto-Paste",
                    content: AnyView(
                        HStack(spacing: 4) {
                            Button(action: {
                                if !isActiveOperation {
                                    let hasPermissions = audioRecorder.accessibilityPermissionsStatus
                                    
                                    if hasPermissions {
                                        // Toggle auto-paste if permissions are granted
                                        clipboardManager.autoPasteEnabled.toggle()
                                        logDebug(.ui, "🔄 Auto-paste toggled to: \(clipboardManager.autoPasteEnabled)")
                                    } else {
                                        // Request permissions if not granted
                                        logDebug(.ui, "🔐 Requesting accessibility permissions")
                                        AudioRecorder.shared.requestAccessibilityPermissions()
                                    }
                                    // Refresh status after action
                                    AudioRecorder.shared.updateAccessibilityPermissionStatus()
                                }
                            }) {
                                HStack(spacing: 4) {
                                    let hasPermissions = audioRecorder.accessibilityPermissionsStatus
                                    let isEnabled = clipboardManager.autoPasteEnabled
                                    
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
                            .frame(minWidth: 120, alignment: .trailing)
                            .help(autoPasteTooltip)
                            .disabled(isActiveOperation) // Block during active operations
                            
                            // Manual permissions check button - only show when permissions not granted
                            if !audioRecorder.accessibilityPermissionsStatus {
                                Button(action: {
                                    if !isActiveOperation {
                                        AudioRecorder.shared.updateAccessibilityPermissionStatus()
                                    }
                                }) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Manually check permissions status")
                                .disabled(isActiveOperation) // Block during active operations
                            }
                        }
                    )
                )
                
                // Universal settings panel - only allow if not active operation
                if let settingsType = settingsType, !isActiveOperation {
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
        }
        .opacity(isActiveOperation ? 0.6 : 1.0) // Dim entire card during active operations
        .cardStyle()
        .onAppear {
            // Set correct model index when view appears
            updateModelCache()
            updateSelectedModelIndex()
            
            // Load saved language preference
            let savedLanguageCode = UserDefaults.standard.string(forKey: "selectedLanguageCode") ?? WritingStyleManager.shared.currentTargetLanguage
            selectedLanguageCode = savedLanguageCode
            WritingStyleManager.shared.setTargetLanguage(savedLanguageCode)
        }
        .onChange(of: audioRecorder.statusDescription) { _ in
            handleStatusChange()
        }
        .onChange(of: WhisperWrapper.shared.currentModel.id) { _ in
            // Update when current model changes - but only if not active operation to avoid conflicts
            if !isActiveOperation {
                updateModelCache()
                updateSelectedModelIndex()
            }
        }
        .onChange(of: selectedLanguageCode) { newValue in
            WritingStyleManager.shared.setTargetLanguage(newValue)
            // Save to UserDefaults
            UserDefaults.standard.set(newValue, forKey: "selectedLanguageCode")
            logDebug(.ui, "💾 Saved target language: \(WritingStyleManager.supportedLanguages[newValue] ?? newValue)")
        }
        .onChange(of: modelRefreshTrigger) { _ in
            // Trigger cache refresh when models change
            refreshModelCache()
        }
        .onChange(of: audioRecorder.statusDescription) { newStatus in
            // Auto-close settings panels when active operations start
            if isActiveOperation && settingsType != nil {
                settingsType = nil
                logDebug(.ui, "🔒 Auto-closed settings panel during active operation: \(newStatus)")
            }
        }
        .onReceive(Timer.publish(every: 2.0, on: .main, in: .common).autoconnect()) { _ in
            // Monitor UI state for debugging
            let timeSinceLastInteraction = Date().timeIntervalSince(lastMenuInteraction)
            
            if uiStateDebug != "normal" && timeSinceLastInteraction > 5.0 {
                logWarning(.ui, "🚨 UI potentially stuck: state='\(uiStateDebug)', \(timeSinceLastInteraction)s since last interaction")
                // Force reset
                DispatchQueue.main.async {
                    uiStateDebug = "force_reset"
                    // Try to force SwiftUI re-evaluation
                    settingsType = nil
                }
            }
            
            // Log current UI state every 10 seconds if not normal
            if Int(timeSinceLastInteraction) % 10 == 0 && uiStateDebug != "normal" {
                let settingsDescription = settingsType == .models ? "models" : settingsType == .api ? "api" : "none"
                logDebug(.ui, "📊 UI state check: '\(uiStateDebug)', isActive=\(isActiveOperation), settings=\(settingsDescription)")
            }
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
        let isEnabled = clipboardManager.autoPasteEnabled
        
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
            
            Menu {
                ForEach(0..<cachedWhisperModels.count, id: \.self) { index in
                    let model = cachedWhisperModels[index]
                    Button(modelDisplayText(for: model)) {
                        selectedModelIndex = index
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    if selectedModelIndex < cachedWhisperModels.count {
                        Text(modelDisplayText(for: cachedWhisperModels[selectedModelIndex]))
                            .font(.system(size: 11))
                    } else {
                        Text("Select Model")
                            .font(.system(size: 11))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .foregroundColor(.primary)
            }
            .buttonStyle(PlainButtonStyle())
            
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
                        let selectedModel = cachedWhisperModels[selectedModelIndex]
                        WhisperWrapper.shared.switchModel(to: selectedModel) { success in
                            if !success {
                                WhisperWrapper.shared.downloadCurrentModel { _ in
                                    refreshModelCache()
                                }
                            }
                            settingsType = nil
                        }
                    }
                    .disabled(WhisperWrapper.shared.isDownloading)
                    .font(.system(size: 11))
                    
                    if selectedModelIndex < cachedWhisperModels.count {
                        let selectedModel = cachedWhisperModels[selectedModelIndex]
                        if WhisperWrapper.shared.isModelDownloaded(selectedModel) && selectedModel.id != WhisperWrapper.shared.currentModel.id {
                            Button("Delete") {
                                WhisperWrapper.shared.deleteModel(selectedModel) { success in
                                    if success {
                                        refreshModelCache()
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
                    set: { llmManager.setCurrentProvider($0); refreshModelCache() }
                )) {
                    ForEach(cachedLLMProviders, id: \.self) { provider in
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
                        ForEach(cachedCurrentLLMModels, id: \.self) { model in
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
            if cachedLLMProviders.filter({ llmManager.hasApiKey(for: $0) }).count > 1 {
                Divider()
                    .padding(.vertical, 2)
                
                Text("Available Providers:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                
                ForEach(cachedLLMProviders.filter({ llmManager.hasApiKey(for: $0) }), id: \.self) { provider in
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
        if let index = cachedWhisperModels.firstIndex(where: { $0.id == WhisperWrapper.shared.currentModel.id }) {
            selectedModelIndex = index
        } else {
            selectedModelIndex = 0  // Fallback to first model if current not found
        }
    }
} 