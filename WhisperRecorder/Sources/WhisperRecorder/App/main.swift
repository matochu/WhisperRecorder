import AVFoundation
import AppKit
import Combine
import Darwin
import Foundation
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let audioRecorder = AudioRecorder.shared
    var popover: NSPopover?
    var toastWindow: ToastWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        print("🐛 [MAIN] COMPILED IN DEBUG MODE!")
        #else
        print("🚀 [MAIN] COMPILED IN RELEASE MODE!")
        #endif
        
        // Initialize debug manager first
        _ = DebugManager.shared
        
        // TEST APP CATEGORY
        logInfo(.app, "🔄 TEST APP CATEGORY - checking if APP logs work")
        print("🎯 [MAIN] Testing APP category logging...")
        
        // Log startup information using new debug system
        logInfo(.system, "=====================================================")
        logInfo(.system, "WhisperRecorder starting")
        logInfo(.system, "Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
        logInfo(.system, "Resource path: \(Bundle.main.resourcePath ?? "unknown")")
        logInfo(.system, "Frameworks path: \(Bundle.main.privateFrameworksPath ?? "unknown")")
        logInfo(.system, "Running as app bundle: \(ProcessInfo.processInfo.environment["WHISPER_APP_BUNDLE"] != nil)")

        if let resourcesPath = ProcessInfo.processInfo.environment["WHISPER_RESOURCES_PATH"] {
            logInfo(.system, "Custom resources path: \(resourcesPath)")
        }

        if let libraryPath = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"] {
            logDebug(.system, "DYLD_LIBRARY_PATH: \(libraryPath)")
        }

        if let insertLibraries = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] {
            logDebug(.system, "DYLD_INSERT_LIBRARIES: \(insertLibraries)")
        }

        logInfo(.system, "Application did finish launching")

        // Check for updates
        logInfo(.system, "Checking for updates")
        AutoUpdater.shared.onUpdateStatusChanged = {
            DispatchQueue.main.async {
                if let popover = self.popover, popover.isShown {
                    popover.contentViewController = NSHostingController(
                        rootView: PopoverView(audioRecorder: self.audioRecorder))
                }
            }
        }
        AutoUpdater.shared.checkForUpdates()

        // Check bundle resources
        if let bundlePath = Bundle.main.resourcePath {
            logDebug(.system, "Bundle resource path: \(bundlePath)")
            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
                logDebug(.system, "Bundle resources: \(contents.joined(separator: ", "))")
            } else {
                logWarning(.system, "Failed to list bundle resources")
            }
        }

        // Check frameworks directory
        if let bundlePath = Bundle.main.privateFrameworksPath {
            logDebug(.system, "Bundle frameworks path: \(bundlePath)")
            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
                logDebug(.system, "Bundle frameworks: \(contents.joined(separator: ", "))")
            } else {
                logWarning(.system, "Failed to list bundle frameworks")
            }
        }

        // Set up default keyboard shortcut
        logInfo(.system, "Setting up keyboard shortcut")
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [self] in
            logDebug(.ui, "Keyboard shortcut triggered")
            audioRecorder.toggleRecording()
        }

        if KeyboardShortcuts.getShortcut(for: .toggleRecording) == nil {
            logInfo(.system, "Setting default keyboard shortcut")
            KeyboardShortcuts.setShortcut(
                .init(.r, modifiers: [.command, .shift]), for: .toggleRecording)
        }

        // Handle status updates
        logInfo(.ui, "Setting up status update handler")
        audioRecorder.onStatusUpdate = {
            self.updateMenuBar()
        }

        // Make app visible in dock for easier debugging
        logInfo(.system, "Setting activation policy to regular (visible in dock)")
        NSApp.setActivationPolicy(.regular)

        // Set up status item in the menu bar
        logInfo(.ui, "Setting up menu bar")
        setupMenuBar()
        
        // Initialize toast window
        logInfo(.ui, "Setting up toast window")
        setupToastWindow()
        
        logInfo(.system, "Application startup complete")

        let mainMenu = NSMenu()

        // Edit menu (for Paste)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)

        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(
            withTitle: "Paste", action: #selector(AppDelegate.paste(_:)), keyEquivalent: "v")

        // Set as app main menu
        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        logWarning(.system, "Application will terminate - performing emergency audio restore")
        SystemAudioManager.shared.emergencyRestore()
    }

    private func setupMenuBar() {
        logDebug(.ui, "Creating status item")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            logDebug(.ui, "Configuring status item button")
            button.image = createCompatibleImage(
                systemSymbol: "waveform.circle",
                accessibilityDescription: "WhisperRecorder")
            button.action = #selector(togglePopover(_:))
            button.target = self
        } else {
            logWarning(.ui, "Failed to get status item button")
        }

        // Create popover
        logDebug(.ui, "Creating popover")
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 340, height: 400)  // Updated size for card design
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: NewPopoverView(audioRecorder: audioRecorder))  // Use new card-based view
        logDebug(.ui, "Menu bar setup complete")
    }

    private func setupToastWindow() {
        toastWindow = ToastWindow()
        print("🎯 [MAIN] ToastWindow created: \(toastWindow != nil)")
        print("🎯 [MAIN] ToastWindow address: \(Unmanaged.passUnretained(toastWindow!).toOpaque())")
        
        // Observe ToastManager state changes
        let cancellable = ToastManager.shared.$isShowing
            .sink { [weak self] isShowing in
                print("🎯 [MAIN] === TOAST OBSERVER TRIGGERED ===")
                print("🎯 [MAIN] Toast isShowing changed to: \(isShowing)")
                print("🎯 [MAIN] ToastManager message: '\(ToastManager.shared.message)'")
                print("🎯 [MAIN] ToastManager position: \(ToastManager.shared.position)")
                print("🎯 [MAIN] ToastWindow exists: \(self?.toastWindow != nil)")
                print("🎯 [MAIN] Thread: \(Thread.isMainThread ? "Main" : "Background")")
                
                DispatchQueue.main.async {
                    print("🎯 [MAIN] In main queue - updating toast content")
                    self?.toastWindow?.updateToastContent()
                    
                    if isShowing {
                        print("🎯 [MAIN] About to show toast at position: \(ToastManager.shared.position)")
                        self?.toastWindow?.showToastAtPosition(ToastManager.shared.position)
                        print("🎯 [MAIN] showToastAtPosition called")
                    } else {
                        print("🎯 [MAIN] About to hide toast")
                        self?.toastWindow?.orderOut(nil)
                        print("🎯 [MAIN] orderOut called")
                    }
                    print("🎯 [MAIN] === OBSERVER COMPLETE ===")
                }
            }
        
        // Keep the cancellable (in a real app, you'd store this)
        objc_setAssociatedObject(self, "toastCancellable", cancellable, .OBJC_ASSOCIATION_RETAIN)
        print("🎯 [MAIN] Toast observer setup complete")
    }

    @objc func togglePopover(_ sender: AnyObject) {
        logDebug(.ui, "Toggle popover called")
        if let button = statusItem?.button {
            if popover?.isShown == true {
                popover?.performClose(sender)
            } else {
                popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
                popover?.contentViewController?.view.window?.makeKey()
            }
        }
    }

    private func updateMenuBar() {
        logDebug(.ui, "Updating menu bar")
        DispatchQueue.main.async {
            if let button = self.statusItem?.button {
                switch self.audioRecorder.statusDescription {
                case "Recording...":
                    button.image = createCompatibleImage(
                        systemSymbol: "waveform.circle.fill",
                        accessibilityDescription: "Recording")
                    if let image = button.image {
                        button.image?.isTemplate = false
                        button.image = image.tinted(with: .systemRed)
                    }
                case "Transcribing...":
                    button.image = createCompatibleImage(
                        systemSymbol: "waveform.circle.fill",
                        accessibilityDescription: "Transcribing")
                    if let image = button.image {
                        button.image?.isTemplate = false
                        button.image = image.tinted(with: .systemBlue)
                    }
                case "Reformatting...":
                    button.image = createCompatibleImage(
                        systemSymbol: "text.bubble.fill",
                        accessibilityDescription: "Reformatting")
                    if let image = button.image {
                        button.image?.isTemplate = false
                        button.image = image.tinted(with: .systemPurple)
                    }
                default:
                    button.image = createCompatibleImage(
                        systemSymbol: "waveform.circle",
                        accessibilityDescription: "WhisperRecorder")
                    button.image?.isTemplate = true
                }
            }

            // If popover is open, update it
            if let popover = self.popover, popover.isShown {
                popover.contentViewController = NSHostingController(
                    rootView: NewPopoverView(audioRecorder: self.audioRecorder))  // Use new card-based view
            }
        }
    }
}

// Helper view for SF Symbols compatibility
struct CompatibleSystemImage: View {
    let systemName: String
    let color: Color?

    init(_ systemName: String, color: Color? = nil) {
        self.systemName = systemName
        self.color = color
    }

    var body: some View {
        if #available(macOS 11.0, *) {  // Changed from 13.0 to 11.0 for broader compatibility
            Image(systemName: systemName)
                .foregroundColor(color)
        } else {
            // Use a simple circle as fallback for older macOS versions
            Circle()
                .foregroundColor(color)
                .frame(width: 16, height: 16)
        }
    }
}

struct PopoverView: View {
    let audioRecorder: AudioRecorder
    @State private var refreshTrigger = false
    @State private var isShowingModelSelector = false
    @State private var selectedModelIndex = 0
    @State private var isFirstRun = false
    @State private var memoryUsage: UInt64 = 0
    @State private var showingUpdateInfo = false
    @State private var selectedWritingStyleIndex = 0
    @State private var inputText: String = ""
    @State private var selectedLanguageCode: String

    // Timer for updating memory usage
    let memoryTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(audioRecorder: AudioRecorder) {
        self.audioRecorder = audioRecorder
        _selectedLanguageCode = State(initialValue: WritingStyleManager.shared.noTranslate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Whisper Recorder")
                .font(.headline)
                .padding(.bottom, 5)

            Divider()

            if WhisperWrapper.shared.needsModelDownload {
                firstRunView
            } else {
                mainView
            }
        }
        .padding()
        .frame(width: 300)
        .onAppear {
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

            // Check if this is first run with no model
            isFirstRun = WhisperWrapper.shared.needsModelDownload
            isShowingModelSelector = isFirstRun

            // Initialize memory usage
            memoryUsage = getMemoryUsage()
        }
        .onReceive(memoryTimer) { _ in
            memoryUsage = getMemoryUsage()
        }
    }

    private var firstRunView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No Whisper model found")
                .font(.headline)
                .foregroundColor(.red)

            Text("Please select and download a model to continue.")
                .font(.caption)
                .padding(.bottom, 5)

            modelSelectorView

            // Memory usage display
            Text("Memory: \(formatMemorySize(memoryUsage))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Status: \(audioRecorder.statusDescription)")
                .font(.caption)
                .padding(.bottom, 5)

            // Memory usage display
            Text("Memory: \(formatMemorySize(memoryUsage))")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.bottom, 5)

            // Update status display
            if AutoUpdater.shared.updateAvailable {
                HStack {
                    CompatibleSystemImage("arrow.down.circle.fill", color: .blue)
                    Text("Update available: v\(AutoUpdater.shared.latestVersion)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .padding(.bottom, 5)

                Button("Download & Install Update") {
                    AutoUpdater.shared.downloadAndInstallUpdate()
                }
                .disabled(AutoUpdater.shared.isDownloadingUpdate)
                .padding(.bottom, 5)

                if AutoUpdater.shared.isDownloadingUpdate {
                    VStack(alignment: .leading) {
                        Text("Downloading: \(Int(AutoUpdater.shared.downloadProgress * 100))%")
                            .font(.caption)

                        ProgressView(value: AutoUpdater.shared.downloadProgress)
                            .progressViewStyle(LinearProgressViewStyle())
                    }
                    .padding(.bottom, 5)
                }

                Divider()
            }

            if audioRecorder.statusDescription == "Recording..." {
                // Show recording duration
                Text("Recording time: \(formatDuration(audioRecorder.recordingDurationSeconds))")
                    .font(.caption)
                    .foregroundColor(
                        audioRecorder.recordingDurationSeconds > 120 ? .orange : .primary)

                if audioRecorder.recordingDurationSeconds > 120 {
                    Text("Long recordings (>2min) may be truncated")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.bottom, 5)
                }
            }

            if let lastTranscription = audioRecorder.lastTranscription, !lastTranscription.isEmpty {
                Divider()

                Button("Copy last transcription") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(lastTranscription, forType: .string)
                }
                .padding(.bottom, 5)
            }

            Divider()

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    TextField("Gemini API token", text: $inputText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .onAppear {
                            if WritingStyleManager.shared.hasApiKey() {
                                inputText = WritingStyleManager.shared.getMaskedApiKey()
                            }
                        }
                        .disabled(WritingStyleManager.shared.hasApiKey())

                    Button(WritingStyleManager.shared.getButtonTitle()) {
                        if WritingStyleManager.shared.hasApiKey() {
                            WritingStyleManager.shared.deleteApiKey()
                            inputText = ""  // Clear the field after deleting
                        } else if !inputText.isEmpty {
                            WritingStyleManager.shared.saveApiKey(inputText)
                            inputText = WritingStyleManager.shared.getMaskedApiKey()  // Show masked version
                        }
                    }
                    .disabled(!WritingStyleManager.shared.hasApiKey() && inputText.isEmpty)
                }
            }.padding(.bottom, 5)

            Divider()

            // Writing style selection
            VStack(alignment: .leading, spacing: 5) {
                Picker("Writing style", selection: $selectedWritingStyleIndex) {
                    ForEach(0..<WritingStyle.styles.count, id: \.self) { index in
                        let style = WritingStyle.styles[index]
                        Text("\(style.name) - \(style.description)")
                            .tag(index)
                    }
                }
                .pickerStyle(PopUpButtonPickerStyle())
                .onChange(of: selectedWritingStyleIndex) { newValue in
                    audioRecorder.selectedWritingStyle = WritingStyle.styles[newValue]
                    logDebug(.ui, "Selected writing style: \(audioRecorder.selectedWritingStyle.name)")
                }

                // Add language selection
                Picker("Translate to", selection: $selectedLanguageCode) {
                    ForEach(
                        Array(
                            WritingStyleManager.supportedLanguages.sorted(by: {
                                $0.key < $1.key
                            })), id: \.key
                    ) { code, name in
                        Text(name)
                            .tag(code)
                    }
                }
                .pickerStyle(PopUpButtonPickerStyle())
                .onChange(of: selectedLanguageCode) { newValue in
                    WritingStyleManager.shared.setTargetLanguage(newValue)
                    logDebug(.ui, "Selected target language: \(WritingStyleManager.supportedLanguages[newValue] ?? newValue)")
                }
            }
            .padding(.bottom, 5)

            Divider()

            // Model selection
            Button("Change Whisper Model") {
                isShowingModelSelector.toggle()
            }
            .padding(.vertical, 5)

            if isShowingModelSelector {
                modelSelectorView
            }

            Divider()

            HStack {
                Text("Shortcut:")
                KeyboardShortcuts.Recorder(for: .toggleRecording)
            }
            .padding(.vertical, 5)

            Divider()

            HStack {
                Button("Check for Updates") {
                    AutoUpdater.shared.checkForUpdates(force: true)
                }
                .padding(.vertical, 5)

                Spacer()

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .padding(.vertical, 5)
            }
        }
    }

    // Helper to format duration as MM:SS
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private var modelSelectorView: some View {
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
            .pickerStyle(PopUpButtonPickerStyle())
            .labelsHidden()

            if WhisperWrapper.shared.isDownloading {
                VStack(alignment: .leading) {
                    Text("Downloading: \(Int(WhisperWrapper.shared.downloadProgress * 100))%")
                        .font(.caption)

                    ProgressView(value: WhisperWrapper.shared.downloadProgress)
                        .progressViewStyle(LinearProgressViewStyle())
                }
            } else {
                HStack {
                    Button("Use Selected Model") {
                        let selectedModel = WhisperWrapper.availableModels[selectedModelIndex]
                        WhisperWrapper.shared.switchModel(to: selectedModel) { success in
                            if !success {
                                // Model not found, need to download
                                WhisperWrapper.shared.downloadCurrentModel { _ in
                                    // Refresh the view when download completes
                                    refreshTrigger.toggle()
                                }
                            }
                        }
                    }
                    .disabled(WhisperWrapper.shared.isDownloading)

                    Button("Download Model") {
                        let selectedModel = WhisperWrapper.availableModels[selectedModelIndex]
                        WhisperWrapper.shared.switchModel(to: selectedModel) { _ in
                            WhisperWrapper.shared.downloadCurrentModel { _ in
                                // Refresh the view when download completes
                                refreshTrigger.toggle()
                            }
                        }
                    }
                    .disabled(WhisperWrapper.shared.isDownloading)
                }
            }
        }
        .padding(.bottom, 5)
        .onChange(of: refreshTrigger) { _ in
            // This is just to trigger a view refresh
        }
    }
}

// Helper extension to tint NSImage
extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()

        color.set()

        let imageRect = NSRect(origin: .zero, size: image.size)
        imageRect.fill(using: .sourceAtop)

        image.unlockFocus()
        return image
    }
}

// Helper function to create compatible NSImage
func createCompatibleImage(systemSymbol: String, accessibilityDescription: String?) -> NSImage? {
    if #available(macOS 11.0, *) {  // Changed from 13.0 to 11.0
        return NSImage(
            systemSymbolName: systemSymbol, accessibilityDescription: accessibilityDescription)
    } else {
        // Fallback for older macOS versions - use template images
        let imageName: String
        switch systemSymbol {
        case "waveform.circle":
            imageName = "NSStatusAvailable"
        case "waveform.circle.fill":
            imageName = "NSStatusAvailable"
        case "text.bubble.fill":
            imageName = "NSStatusAvailable"
        default:
            imageName = "NSStatusAvailable"
        }
        let image = NSImage(named: imageName)
        image?.isTemplate = true
        image?.accessibilityDescription = accessibilityDescription
        return image
    }
}

extension AppDelegate {
    @objc func paste(_ sender: Any?) {
        if let window = NSApp.keyWindow,
            let responder = window.firstResponder as? NSText
        {
            responder.paste(sender)
        } else {
            // Removed NSSound.beep() - causes double sound during auto-paste
            // NSSound.beep()  // Optional: play a beep if no responder
        }
    }
}

// Main entry point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
