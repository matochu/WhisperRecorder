import SwiftUI

struct NewPopoverView: View {
    let audioRecorder: AudioRecorder
    @State private var refreshTrigger = false
    @State private var memoryUsage: UInt64 = 0
    @State private var selectedWritingStyleIndex = 0
    @State private var inputText: String = ""
    @State private var selectedLanguageCode: String
    @StateObject private var popoverState = PopoverState()

    // Timer for updating memory usage
    let memoryTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

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
        .environmentObject(popoverState)
        .onAppear {
            setupInitialValues()
            popoverState.setVisible(true)
        }
        .onDisappear {
            popoverState.setVisible(false)
        }
        .onReceive(memoryTimer) { _ in
            memoryUsage = getMemoryUsage()
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
            .cardStyle(borderColor: .red, backgroundColor: Color(.controlBackgroundColor))
            
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
            logDebug(.ui, "Selected writing style: \(audioRecorder.selectedWritingStyle.name)")
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
        .cardStyle(borderColor: .orange, backgroundColor: Color(.controlBackgroundColor))
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
                    ForEach(0..<WhisperWrapper.availableModels.count, id: \.self) { index in
                        let model = WhisperWrapper.availableModels[index]
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
        .cardStyle(borderColor: .blue, backgroundColor: .white)
    }
    
    @State private var selectedModelIndex = 0
    
    private func setupInitialValues() {
        // Find current model index
        if let index = WhisperWrapper.availableModels.firstIndex(where: {
            $0.id == WhisperWrapper.shared.currentModel.id
        }) {
            selectedModelIndex = index
        }

        // Get current writing style index
        if let index = WritingStyle.styles.firstIndex(where: {
            $0.id == audioRecorder.selectedWritingStyle.id
        }) {
            selectedWritingStyleIndex = index
        }

        // Set up API token field
        if WritingStyleManager.shared.hasApiKey() {
            inputText = WritingStyleManager.shared.getMaskedApiKey()
        }

        // Initialize memory usage
        memoryUsage = getMemoryUsage()
    }
    
    private func useSelectedModel() {
        let selectedModel = WhisperWrapper.availableModels[selectedModelIndex]
        WhisperWrapper.shared.switchModel(to: selectedModel) { success in
            if !success {
                // Model not found, need to download
                WhisperWrapper.shared.downloadCurrentModel { _ in
                    refreshTrigger.toggle()
                }
            }
        }
    }
    
    private func downloadSelectedModel() {
        let selectedModel = WhisperWrapper.availableModels[selectedModelIndex]
        WhisperWrapper.shared.switchModel(to: selectedModel) { _ in
            WhisperWrapper.shared.downloadCurrentModel { _ in
                refreshTrigger.toggle()
            }
        }
    }
} 