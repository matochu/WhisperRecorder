import AVFoundation
import AppKit
import Darwin
import Foundation
import KeyboardShortcuts
import SwiftUI

// Function to get current memory usage
func getMemoryUsage() -> UInt64 {
    var taskInfo = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size) / 4
    let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }

    if result == KERN_SUCCESS {
        return taskInfo.phys_footprint
    }
    return 0
}

// Format bytes to human-readable format
func formatMemorySize(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useKB, .useMB]
    formatter.countStyle = .memory
    return formatter.string(fromByteCount: Int64(bytes))
}

// Add global log file path function
func getLogFilePath() -> URL {
    let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[
        0]

    // If running from app bundle, use the app's container directory
    if ProcessInfo.processInfo.environment["WHISPER_APP_BUNDLE"] != nil {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appSupportPath = applicationSupport.appendingPathComponent("WhisperRecorder")

        do {
            try FileManager.default.createDirectory(
                at: appSupportPath, withIntermediateDirectories: true)
            return appSupportPath.appendingPathComponent("whisperrecorder_debug.log")
        } catch {
            // Fall back to documents directory
            print("Failed to create app support directory: \(error)")
        }
    }

    return documentsDirectory.appendingPathComponent("whisperrecorder_debug.log")
}

// Add global log function
func writeLog(_ message: String) {
    let logFileURL = getLogFilePath()
    let formattedMessage = "[\(Date())] \(message)\n"

    if let data = formattedMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
                fileHandle.closeFile()
            }
        } else {
            try? data.write(to: logFileURL)
        }
    }

    // Also print to console
    print(message)
}

// Write startup information
writeLog("=====================================================")
writeLog("WhisperRecorder starting")
writeLog("Log file: \(getLogFilePath().path)")
writeLog("Bundle ID: \(Bundle.main.bundleIdentifier ?? "unknown")")
writeLog("Resource path: \(Bundle.main.resourcePath ?? "unknown")")
writeLog("Frameworks path: \(Bundle.main.privateFrameworksPath ?? "unknown")")
writeLog(
    "Running as app bundle: \(ProcessInfo.processInfo.environment["WHISPER_APP_BUNDLE"] != nil)")

if let resourcesPath = ProcessInfo.processInfo.environment["WHISPER_RESOURCES_PATH"] {
    writeLog("Custom resources path: \(resourcesPath)")
}

if let libraryPath = ProcessInfo.processInfo.environment["DYLD_LIBRARY_PATH"] {
    writeLog("DYLD_LIBRARY_PATH: \(libraryPath)")
}

if let insertLibraries = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] {
    writeLog("DYLD_INSERT_LIBRARIES: \(insertLibraries)")
}

extension KeyboardShortcuts.Name {
    static let toggleRecording = Self("toggleRecording")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    let audioRecorder = AudioRecorder.shared
    var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        writeLog("Application did finish launching")

        // Check for updates
        writeLog("Checking for updates")
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
            writeLog("Bundle resource path: \(bundlePath)")
            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
                writeLog("Bundle resources: \(contents.joined(separator: ", "))")
            } else {
                writeLog("Failed to list bundle resources")
            }
        }

        // Check frameworks directory
        if let bundlePath = Bundle.main.privateFrameworksPath {
            writeLog("Bundle frameworks path: \(bundlePath)")
            let fileManager = FileManager.default
            if let contents = try? fileManager.contentsOfDirectory(atPath: bundlePath) {
                writeLog("Bundle frameworks: \(contents.joined(separator: ", "))")
            } else {
                writeLog("Failed to list bundle frameworks")
            }
        }

        // Set up default keyboard shortcut
        writeLog("Setting up keyboard shortcut")
        KeyboardShortcuts.onKeyDown(for: .toggleRecording) { [self] in
            writeLog("Keyboard shortcut triggered")
            audioRecorder.toggleRecording()
        }

        if KeyboardShortcuts.getShortcut(for: .toggleRecording) == nil {
            writeLog("Setting default keyboard shortcut")
            KeyboardShortcuts.setShortcut(
                .init(.r, modifiers: [.command, .shift]), for: .toggleRecording)
        }

        // Handle status updates
        writeLog("Setting up status update handler")
        audioRecorder.onStatusUpdate = {
            self.updateMenuBar()
        }

        // Make app not appear in dock
        writeLog("Setting activation policy")
        // NSApp.setActivationPolicy(.accessory)
        writeLog("NOT setting accessory policy - app will appear in dock for debugging")

        // Set up status item in the menu bar
        writeLog("Setting up menu bar")
        setupMenuBar()
        writeLog("Application startup complete")

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
        writeLog("Application will terminate - performing emergency audio restore")
        SystemAudioManager.shared.emergencyRestore()
    }

    private func setupMenuBar() {
        writeLog("Creating status item")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            writeLog("Configuring status item button")
            button.image = createCompatibleImage(
                systemSymbol: "waveform.circle",
                accessibilityDescription: "WhisperRecorder")
            button.action = #selector(togglePopover(_:))
            button.target = self
        } else {
            writeLog("Failed to get status item button")
        }

        // Create popover
        writeLog("Creating popover")
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 300)
        popover?.behavior = .transient
        popover?.contentViewController = NSHostingController(
            rootView: PopoverView(audioRecorder: audioRecorder))
        writeLog("Menu bar setup complete")
    }

    @objc func togglePopover(_ sender: AnyObject) {
        writeLog("Toggle popover called")
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
        writeLog("Updating menu bar")
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
                    rootView: PopoverView(audioRecorder: self.audioRecorder))
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
                    writeLog("Selected writing style: \(audioRecorder.selectedWritingStyle.name)")
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
                    writeLog(
                        "Selected target language: \(WritingStyleManager.supportedLanguages[newValue] ?? newValue)"
                    )
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
            NSSound.beep()  // Optional: play a beep if no responder
        }
    }
}

// Main entry point
writeLog("Application starting")
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
writeLog("Running application main loop")
app.run()
