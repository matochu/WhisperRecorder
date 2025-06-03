import SwiftUI

struct PopoverView: View {
    let audioRecorder: AudioRecorder
    @State private var refreshTrigger = false
    @State private var memoryUsage: UInt64 = 0
    @State private var selectedWritingStyleIndex = 0
    @State private var inputText: String = ""
    @State private var selectedLanguageCode: String
    
    // Cached models for performance
    @State private var cachedWhisperModels: [WhisperModel] = []
    @State private var lastModelCacheUpdate = Date()
    @State private var memoryTimer: Timer?

    init(audioRecorder: AudioRecorder) {
        self.audioRecorder = audioRecorder
        _selectedLanguageCode = State(initialValue: WritingStyleManager.shared.noTranslate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if WhisperWrapper.shared.needsModelDownload {
                firstRunView
            } else {
                mainView
            }
        }
        .frame(width: 340)  // Increased from 300px as per design
        .onAppear {
            updateModelCache()
            setupInitialValues()
            // Calculate memory on appear and start timer
            memoryUsage = getMemoryUsage()
            startMemoryTimer()
        }
        .onDisappear {
            // Stop timer when popover closes
            stopMemoryTimer()
        }
    }

    private var firstRunView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status message
            VStack(spacing: 0) {
                HStack {
                    Text("⚠️")
                        .font(.system(size: 16))
                    Spacer()
                }
                .padding(.bottom, 8)
                
                Divider()
                    .padding(.bottom, 12)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("No Whisper model found")
                        .font(.headline)
                        .foregroundColor(.red)

                    Text("Please select and download a model to continue.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Memory: \(formatMemorySize(memoryUsage))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .cardStyle(borderColor: .red, backgroundColor: Color.clear)
            
            // Model selection placeholder
            modelSelectionCard
            
            // System card
            SystemCard()
        }
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Update notification if available
            if AutoUpdater.shared.updateAvailable {
                updateNotificationCard
            }
            
            // Main cards
            StatusCard(audioRecorder: audioRecorder, memoryUsage: memoryUsage)
            
            ActionsCard(audioRecorder: audioRecorder)
            
            ConfigurationCard( 
                selectedWritingStyleIndex: $selectedWritingStyleIndex,
                selectedLanguageCode: $selectedLanguageCode,
                inputText: $inputText
            )
            
            SystemCard()
        }
        .onChange(of: selectedWritingStyleIndex) { newValue in
            audioRecorder.selectedWritingStyle = WritingStyle.styles[newValue]
            
            // Save to UserDefaults to persist selection
            UserDefaults.standard.set(newValue, forKey: "selectedWritingStyleIndex")
        }
        .onChange(of: selectedLanguageCode) { newValue in
            WritingStyleManager.shared.setTargetLanguage(newValue)
            logDebug(.ui, "Selected target language: \(WritingStyleManager.supportedLanguages[newValue] ?? newValue)")
        }
    }
    
    private var updateNotificationCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("🔄")
                    .font(.system(size: 16))
                Spacer()
            }
            .padding(.bottom, 8)
            
            Divider()
                .padding(.bottom, 12)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    CompatibleSystemImage("arrow.down.circle.fill", color: .blue)
                    Text("Update available: v\(AutoUpdater.shared.latestVersion)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Button("Download & Install Update") {
                    AutoUpdater.shared.downloadAndInstallUpdate()
                }
                .disabled(AutoUpdater.shared.isDownloadingUpdate)

                if AutoUpdater.shared.isDownloadingUpdate {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Downloading: \(Int(AutoUpdater.shared.downloadProgress * 100))%")
                            .font(.caption)

                        ProgressView(value: AutoUpdater.shared.downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                }
            }
        }
        .cardStyle(borderColor: .orange, backgroundColor: Color.clear)
    }
    
    private var modelSelectionCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("🤖")
                    .font(.system(size: 16))
                Spacer()
            }
            .padding(.bottom, 8)
            
            Divider()
                .padding(.bottom, 12)
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Select Whisper Model:")
                    .font(.caption)
                    .bold()

                Picker("Model", selection: $selectedModelIndex) {
                    ForEach(0..<cachedWhisperModels.count, id: \.self) { index in
                        let model = cachedWhisperModels[index]
                        Text("\(model.displayName) (\(model.size)) - \(model.language)")
                            .tag(index)
                    }
                }
                .pickerStyle(MenuPickerStyle())

                if WhisperWrapper.shared.isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Downloading: \(Int(WhisperWrapper.shared.downloadProgress * 100))%")
                            .font(.caption)

                        ProgressView(value: WhisperWrapper.shared.downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                } else {
                    HStack {
                        Button("Use Selected Model") {
                            useSelectedModel()
                        }
                        .disabled(WhisperWrapper.shared.isDownloading)

                        Button("Download Model") {
                            downloadSelectedModel()
                        }
                        .disabled(WhisperWrapper.shared.isDownloading)
                    }
                }
            }
        }
        .cardStyle(borderColor: .blue, backgroundColor: Color.clear)
    }
    
    @State private var selectedModelIndex = 0
    
    private func setupInitialValues() {
        // Find current model index using cached models
        if let index = cachedWhisperModels.firstIndex(where: {
            $0.id == WhisperWrapper.shared.currentModel.id
        }) {
            selectedModelIndex = index
        } else {
            // Fallback: update cache and try again
            updateModelCache()
            if let index = cachedWhisperModels.firstIndex(where: {
                $0.id == WhisperWrapper.shared.currentModel.id
            }) {
                selectedModelIndex = index
            }
        }

        // Load writing style index from UserDefaults (instead of audioRecorder to avoid conflicts)
        let savedStyleIndex = UserDefaults.standard.integer(forKey: "selectedWritingStyleIndex")
        if savedStyleIndex < WritingStyle.styles.count {
            selectedWritingStyleIndex = savedStyleIndex
            audioRecorder.selectedWritingStyle = WritingStyle.styles[savedStyleIndex]
        } else {
            // Fallback to current audioRecorder value if no saved preference
            if let index = WritingStyle.styles.firstIndex(where: {
                $0.id == audioRecorder.selectedWritingStyle.id
            }) {
                selectedWritingStyleIndex = index
            }
        }

        // Set up API token field
        if WritingStyleManager.shared.hasApiKey() {
            inputText = WritingStyleManager.shared.getMaskedApiKey()
        }
        
        // Initialize memory usage
        memoryUsage = getMemoryUsage()
    }
    
    private func useSelectedModel() {
        guard selectedModelIndex < cachedWhisperModels.count else {
            logWarning(.ui, "Selected model index out of bounds")
            return
        }
        
        let selectedModel = cachedWhisperModels[selectedModelIndex]
        WhisperWrapper.shared.switchModel(to: selectedModel) { success in
            if !success {
                // Model not found, need to download
                WhisperWrapper.shared.downloadCurrentModel { _ in
                    refreshTrigger.toggle()
                    updateMemoryAfterModelChange()
                }
            } else {
                updateMemoryAfterModelChange()
            }
        }
    }
    
    private func downloadSelectedModel() {
        guard selectedModelIndex < cachedWhisperModels.count else {
            logWarning(.ui, "Selected model index out of bounds")
            return
        }
        
        let selectedModel = cachedWhisperModels[selectedModelIndex]
        WhisperWrapper.shared.switchModel(to: selectedModel) { _ in
            WhisperWrapper.shared.downloadCurrentModel { _ in
                refreshTrigger.toggle()
                updateMemoryAfterModelChange()
            }
        }
    }

    // MARK: - Model Cache Management
    private func updateModelCache() {
        // Only update if cache is old or empty
        let now = Date()
        if now.timeIntervalSince(lastModelCacheUpdate) < 5.0 && !cachedWhisperModels.isEmpty {
            return
        }
        
        cachedWhisperModels = WhisperWrapper.availableModels
        lastModelCacheUpdate = now
    }
    
    // MARK: - Memory Management
    private func startMemoryTimer() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            updateMemoryUsage()
        }
    }
    
    private func stopMemoryTimer() {
        memoryTimer?.invalidate()
        memoryTimer = nil
    }
    
    private func updateMemoryUsage() {
        let newMemory = getMemoryUsage()
        memoryUsage = newMemory
    }
    
    private func updateMemoryAfterModelChange() {
        // Wait a bit for model to load, then update memory
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            updateMemoryUsage()
        }
    }
} 