import SwiftUI
import KeyboardShortcuts

// MARK: - Toast View
struct ToastView: View {
    let message: String
    let preview: String
    @Binding var isShowing: Bool
    
    var body: some View {
        // Show the full copied text content with darker 8-bit + macOS style background
        Text(preview.isEmpty ? message : preview)
            .font(.system(size: 11, weight: .medium, design: .monospaced))  // Monospaced for 8-bit feel
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 300, alignment: .leading)  // Fixed width, left-aligned text
            .fixedSize(horizontal: false, vertical: true)  // Allow vertical expansion
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlColor).opacity(0.7))  // Less bright background
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(.tertiaryLabelColor).opacity(0.5), lineWidth: 1)  // Subtle border
                    )
            )
            .scaleEffect(isShowing ? 1.0 : 0.9)
            .opacity(isShowing ? 0.75 : 0.0)  // Reduced opacity from 0.92 to 0.75
            .animation(.easeInOut(duration: 0.15), value: isShowing)
    }
}

// MARK: - Toast Manager
class ToastManager: ObservableObject {
    @Published var isShowing = false
    @Published var message = ""
    @Published var preview = ""
    @Published var position = NSPoint.zero
    
    static let shared = ToastManager()
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var isAutoPasteInProgress = false  // Flag to prevent hiding during auto-paste
    
    // Settings - completely separate from auto-paste
    @Published var toastsEnabled: Bool {
        didSet {
            print("🎯 [TOAST SETTINGS] toastsEnabled changed: \(oldValue) → \(toastsEnabled)")
            UserDefaults.standard.set(toastsEnabled, forKey: "whisperToastsEnabled")
            print("🎯 [TOAST SETTINGS] Saved to UserDefaults successfully")
        }
    }
    
    private init() {
        // Load saved preference with proper fallback
        self.toastsEnabled = UserDefaults.standard.object(forKey: "whisperToastsEnabled") as? Bool ?? true
        print("🎯 [TOAST SETTINGS] ToastManager initialized - toastsEnabled: \(toastsEnabled)")
    }
    
    // Control auto-paste state
    func setAutoPasteInProgress(_ inProgress: Bool) {
        isAutoPasteInProgress = inProgress
    }
    
    // Hide toast when starting new recording
    func hideToastForNewRecording() {
        hideToast()
    }
    
    func showToast(message: String, preview: String = "", at position: NSPoint? = nil) {
        // Check if toasts are enabled for visual display
        guard toastsEnabled else {
            return
        }
        
        // Get cursor position if not provided
        let toastPosition = position ?? NSEvent.mouseLocation
        
        DispatchQueue.main.async {
            // Show the full preview text (not truncated)
            self.message = ""  // Clear message - we don't want it
            self.preview = preview.trimmingCharacters(in: .whitespacesAndNewlines) // Show full text, just trim whitespace
            self.position = toastPosition
            
            self.isShowing = true
            
            // Set up key monitoring to hide on any key press - NO TIMER
            self.setupKeyMonitoring()
        }
    }
    
    private func setupKeyMonitoring() {
        // Remove existing monitor
        if let globalKeyMonitor = globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let localKeyMonitor = localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        
        // Monitor for any key press to hide toast - use both local and global
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            if self.isAutoPasteInProgress {
                return
            }
            self.hideToast()
        }
        
        // Also add local monitor for key events within the app
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return event }
            if self.isAutoPasteInProgress {
                return event
            }
            self.hideToast()
            return event  // Return the event to allow normal processing
        }
    }
    
    func hideToast() {
        DispatchQueue.main.async {
            self.isShowing = false
            
            // Remove key monitor
            if let globalKeyMonitor = self.globalKeyMonitor {
                NSEvent.removeMonitor(globalKeyMonitor)
                self.globalKeyMonitor = nil
            }
            if let localKeyMonitor = self.localKeyMonitor {
                NSEvent.removeMonitor(localKeyMonitor)
                self.localKeyMonitor = nil
            }
        }
    }
}

// MARK: - Toast Window
class ToastWindow: NSWindow {
    private var toastView: NSHostingView<ToastView>!
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 50),  // Wider for 300px content + padding
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = NSColor.clear
        self.level = .statusBar  // Keep it visible but not too intrusive
        self.ignoresMouseEvents = true
        self.hasShadow = false
        
        setupToastView()
    }
    
    private func setupToastView() {
        let toastBinding = Binding<Bool>(
            get: { ToastManager.shared.isShowing },
            set: { _ in }
        )
        
        toastView = NSHostingView(rootView: ToastView(
            message: ToastManager.shared.message,
            preview: ToastManager.shared.preview,
            isShowing: toastBinding
        ))
        
        self.contentView = toastView
    }
    
    func updateToastContent() {
        let toastBinding = Binding<Bool>(
            get: { ToastManager.shared.isShowing },
            set: { _ in }
        )
        
        toastView.rootView = ToastView(
            message: ToastManager.shared.message,
            preview: ToastManager.shared.preview,
            isShowing: toastBinding
        )
    }
    
    func showToastAtPosition(_ position: NSPoint) {
        // Update content first
        updateToastContent()
        
        // Calculate dynamic height based on text length
        let textLength = ToastManager.shared.preview.count
        let estimatedLines = max(1, (textLength / 50) + 1) // Roughly 50 chars per line
        let dynamicHeight = min(200, max(50, estimatedLines * 20 + 20)) // 20px per line + padding
        
        // Convert screen coordinates for positioning
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowSize = NSSize(width: 320, height: CGFloat(dynamicHeight))
        
        // Position toast below and to the right of cursor
        let windowX = position.x + 20  // 20px to the right of cursor
        let windowY = position.y - CGFloat(dynamicHeight) - 10  // Below cursor with 10px gap
        
        // Keep toast on screen horizontally
        let finalX = max(10, min(windowX, screenFrame.maxX - windowSize.width - 10))
        let finalY = windowY
        
        let finalPosition = NSPoint(x: finalX, y: finalY)
        
        self.setFrameOrigin(finalPosition)
        self.setContentSize(windowSize)
        
        self.orderFront(nil)
    }
}

// MARK: - Text Storage State 
extension AppDelegate {
    static var lastOriginalWhisperText: String = ""
    static var lastProcessedText: String = ""
    
    static var hasOriginalText: Bool {
        return !lastOriginalWhisperText.isEmpty
    }
    
    static var hasProcessedText: Bool {
        return !lastProcessedText.isEmpty
    }
}

// MARK: - Model Status
enum ModelStatus {
    case ready
    case downloading(progress: Double)
    case notAvailable
    
    var displayText: String {
        switch self {
        case .ready: return "Ready"
        case .downloading(let progress): return "⏳ \(Int(progress * 100))%"
        case .notAvailable: return "📥 Download"
        }
    }
    
    var color: Color {
        switch self {
        case .ready: return .green
        case .downloading: return .blue
        case .notAvailable: return .orange
        }
    }
}

// MARK: - Card Base Style
struct CardStyle: ViewModifier {
    let borderColor: Color
    let backgroundColor: Color
    
    func body(content: Content) -> some View {
        content
            .padding(10)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(borderColor.opacity(0.3), lineWidth: 0.5)
            )
            .cornerRadius(6)
    }
}

extension View {
    func cardStyle(borderColor: Color = Color(.separatorColor), backgroundColor: Color = Color.clear) -> some View {
        self.modifier(CardStyle(borderColor: borderColor, backgroundColor: backgroundColor))
    }
}

// MARK: - Status Card
struct StatusCard: View {
    let audioRecorder: AudioRecorder
    let memoryUsage: UInt64
    
    var body: some View {
        VStack(spacing: 6) {
            // Main status line with Rec button
            HStack {
                // Only show recording timer when recording
                HStack(spacing: 8) {
                    if !recordingDuration.isEmpty {
                        Text(recordingDuration)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                    }
                }
                
                Spacer()
                
                // Recording button moved to right (styled like Process Again)
                Button(action: {
                    audioRecorder.toggleRecording()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: recButtonSystemIcon)
                            .font(.system(size: 10))
                        Text(recButtonText)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(recButtonBackgroundColor)
                    .foregroundColor(recButtonTextColor)
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(height: 24) // Fixed height like Process Again
            }
            
            // Secondary info lines  
            statusLine(
                left: "Memory: \(formatMemorySize(memoryUsage))",
                right: memoryDelta,
                isPrimary: false
            )
            
            statusLine(
                left: "Model: \(WhisperWrapper.shared.currentModel.displayName)",
                right: modelStatusText,
                isPrimary: false
            )
            
            statusLine(
                left: "Target: \(targetLanguage)",
                right: "Style: \(audioRecorder.selectedWritingStyle.name)",
                isPrimary: false
            )
        }
        .cardStyle(borderColor: Color(.separatorColor), backgroundColor: statusBackgroundColor)
    }
    
    private func statusLine(left: String, right: String, isPrimary: Bool) -> some View {
        HStack {
            Text(left)
                .font(isPrimary ? .system(size: 13, weight: .medium, design: .default) : .system(size: 11))
                .foregroundColor(isPrimary ? statusColor : .secondary)
            
            Spacer()
            
            Text(right)
                .font(isPrimary ? .system(size: 13, weight: .medium, design: .default) : .system(size: 11))
                .foregroundColor(isPrimary ? statusColor : .secondary)
        }
    }
    
    private var statusIcon: String {
        switch audioRecorder.statusDescription {
        case "Recording...": return "🔴"
        case "Transcribing...": return "🟡"
        case "Processing...": return "🔵"
        default: return "✅"
        }
    }
    
    private var statusText: String {
        return audioRecorder.statusDescription
    }
    
    private var statusColor: Color {
        switch audioRecorder.statusDescription {
        case "Recording...": return Color(.systemRed)
        case "Transcribing...": return Color(.systemOrange)
        case "Processing...": return Color(.systemBlue)
        default: return Color(.systemGreen)
        }
    }
    
    private var statusBackgroundColor: Color {
        return Color.clear
    }
    
    private var recordingDuration: String {
        if audioRecorder.statusDescription == "Recording..." {
            return formatDuration(audioRecorder.recordingDurationSeconds)
        }
        return ""
    }
    
    private var memoryDelta: String {
        return "+12MB"
    }
    
    private var targetLanguage: String {
        let code = WritingStyleManager.shared.currentTargetLanguage
        return WritingStyleManager.supportedLanguages[code] ?? "English"
    }
    
    private func formatDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
    
    private var modelStatusText: String {
        let currentModel = WhisperWrapper.shared.currentModel
        if WhisperWrapper.shared.isDownloading {
            return "Downloading..."
        } else if WhisperWrapper.shared.isModelLoaded() {
            return currentModel.displayName
        } else {
            return currentModel.displayName
        }
    }
    
    private var recButtonIcon: String {
        switch audioRecorder.statusDescription {
        case "Recording...": return "🔴"
        case "Transcribing...": return "🟡"
        case "Processing...": return "🔵"
        default: return "✅"
        }
    }
    
    private var recButtonText: String {
        switch audioRecorder.statusDescription {
        case "Recording...": return "Stop Recording"
        case "Transcribing...": return "Stop Transcription"
        case "Processing...": return "Stop Processing"
        default: return "Start Recording"
        }
    }
    
    private var recButtonTextColor: Color {
        switch audioRecorder.statusDescription {
        case "Recording...": return .white
        case "Transcribing...": return .white
        case "Processing...": return .white
        default: return .primary
        }
    }
    
    private var recButtonBackgroundColor: Color {
        switch audioRecorder.statusDescription {
        case "Recording...": return Color(.systemRed)
        case "Transcribing...": return Color(.systemOrange)
        case "Processing...": return Color(.systemBlue)
        default: return Color(.controlColor)
        }
    }
    
    private var recButtonSystemIcon: String {
        switch audioRecorder.statusDescription {
        case "Recording...": return "stop.circle.fill"
        case "Transcribing...": return "waveform.circle"
        case "Processing...": return "gearshape.circle"
        default: return "record.circle"
        }
    }
}

// MARK: - Actions Card
struct ActionsCard: View {
    let audioRecorder: AudioRecorder
    @State private var lastStatus: String = ""
    @State private var lastOriginalText: String = ""
    @State private var lastProcessedText: String = ""
    
    var body: some View {
        VStack(spacing: 8) {
            // Copy buttons side by side (no header)
            HStack(spacing: 6) {
                copyButton(
                    icon: "📋",
                    title: "Result",
                    textType: .processed,
                    isPrimary: true
                )
                
                copyButton(
                    icon: "📄",
                    title: "Original", 
                    textType: .original,
                    isPrimary: false
                )
            }
            
            // Shortcut display
            HStack {
                Button(action: {
                    // Open keyboard shortcuts preferences
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                            .foregroundColor(.secondary)
                            .font(.system(size: 10))
                        Text("Shortcut:")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        KeyboardShortcuts.Recorder(for: .toggleRecording)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(height: 24) // Fixed height to prevent stretching
                
                Spacer()
                
                // Process again button (smaller)
                Button(action: processAgain) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Process Again")
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(canProcessAgain ? Color(.controlColor) : Color(.controlColor).opacity(0.5))
                    .foregroundColor(canProcessAgain ? .primary : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(height: 24) // Fixed height to prevent stretching
                .disabled(!canProcessAgain)
                .help(processAgainTooltip)
            }
            .frame(height: 32) // Fixed height for the entire row
        }
        .cardStyle()
        .onChange(of: audioRecorder.statusDescription) { newStatus in
            // Refresh when recording status changes
            if lastStatus != newStatus {
                lastStatus = newStatus
                print("📱 Status changed to: \(newStatus)")
            }
        }
        .onChange(of: AppDelegate.lastOriginalWhisperText) { newText in
            // Refresh when original text changes
            if lastOriginalText != newText {
                lastOriginalText = newText
                print("📝 Original text updated: \(newText.isEmpty ? "empty" : "\(newText.count) chars")")
            }
        }
        .onChange(of: AppDelegate.lastProcessedText) { newText in
            // Refresh when processed text changes
            if lastProcessedText != newText {
                lastProcessedText = newText
                print("🔄 Processed text updated: \(newText.isEmpty ? "empty" : "\(newText.count) chars")")
            }
        }
        .onAppear {
            // Initialize state
            lastStatus = audioRecorder.statusDescription
            lastOriginalText = AppDelegate.lastOriginalWhisperText
            lastProcessedText = AppDelegate.lastProcessedText
        }
    }
    
    private enum TextType {
        case processed, original
    }
    
    private func copyButton(icon: String, title: String, textType: TextType, isPrimary: Bool) -> some View {
        let isAvailable = hasText(type: textType)
        let buttonText = isAvailable ? "Copy \(title)" : "No \(title)"
        
        return Button(action: {
            copyText(type: textType)
        }) {
            HStack(spacing: 6) {
                Text(icon)
                    .font(.system(size: 14))
                Text(buttonText)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isAvailable ? (isPrimary ? Color.blue : Color(.controlAccentColor).opacity(0.8)) : Color(.controlColor).opacity(0.5))
            .foregroundColor(isAvailable ? .white : .secondary)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!isAvailable)
        .help(tooltipText(type: textType)) // macOS tooltip with preview
    }
    
    private func tooltipText(type: TextType) -> String {
        switch type {
        case .processed:
            let text = AppDelegate.lastProcessedText
            if text.isEmpty {
                return "No processed text available"
            }
            let preview = String(text.prefix(100))
            return preview.count < text.count ? "\(preview)..." : preview
        case .original:
            let text = AppDelegate.lastOriginalWhisperText
            if text.isEmpty {
                return "No original text available"
            }
            let preview = String(text.prefix(100))
            return preview.count < text.count ? "\(preview)..." : preview
        }
    }
    
    private func hasText(type: TextType) -> Bool {
        let result: Bool
        switch type {
        case .processed: 
            result = AppDelegate.hasProcessedText
        case .original: 
            result = AppDelegate.hasOriginalText
        }
        return result
    }
    
    private func copyText(type: TextType) {
        let text: String
        let toastMessage: String
        
        switch type {
        case .processed:
            text = AppDelegate.lastProcessedText
            toastMessage = "Copied processed text"
            logInfo(.ui, "📋 [TOAST] Copied processed text to clipboard")
        case .original:
            text = AppDelegate.lastOriginalWhisperText
            toastMessage = "Copied original text"
            logInfo(.ui, "📄 [TOAST] Copied original Whisper text to clipboard")
        }
        
        guard !text.isEmpty else {
            logWarning(.ui, "❌ [TOAST] No text available to copy")
            return
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        // Play centralized sound for manual copy operations
        NSSound(named: "Tink")?.play()
        
        // Show toast with full text (no truncation)
        logInfo(.ui, "🎯 [TOAST] Showing toast: '\(toastMessage)' with full text: \(text.count) chars")
        ToastManager.shared.showToast(message: toastMessage, preview: text)
    }
    
    private func processAgain() {
        guard AppDelegate.hasOriginalText else {
            logWarning(.ui, "❌ No original text available to process again")
            return
        }
        
        logInfo(.ui, "🔄 Processing original text again")
        // Use the currently selected writing style or default
        let currentStyle = WritingStyle.styles.first { $0.id == "default" } ?? WritingStyle.styles[0]
        
        // Reprocess the original Whisper text through WritingStyleManager
        WritingStyleManager.shared.reformatText(AppDelegate.lastOriginalWhisperText, withStyle: currentStyle) { processedText in
            if let processed = processedText {
                AppDelegate.lastProcessedText = processed
                logInfo(.ui, "✅ Reprocessed text successfully")
                
                // Copy the new processed text to clipboard
                DispatchQueue.main.async {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(processed, forType: .string)
                    logInfo(.ui, "📋 Copied reprocessed text to clipboard")
                }
            } else {
                logError(.ui, "❌ Failed to reprocess text")
            }
        }
    }
    
    private var canProcessAgain: Bool {
        return AppDelegate.hasOriginalText && WritingStyleManager.shared.hasApiKey()
    }
    
    private var processAgainTooltip: String {
        if !WritingStyleManager.shared.hasApiKey() {
            return "Process Again requires API token to be set"
        } else if !AppDelegate.hasOriginalText {
            return "No original text available to process"
        } else {
            return "Process the original transcription again with current settings"
        }
    }
}

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
                label: "API",
                content: AnyView(
                    HStack(spacing: 4) {
                        Button(action: {
                            settingsType = settingsType == .api ? nil : .api
                        }) {
                            HStack(spacing: 4) {
                                Text(WritingStyleManager.shared.hasApiKey() ? "Connected" : "Not Set")
                                    .font(.system(size: 12))
                                    .foregroundColor(WritingStyleManager.shared.hasApiKey() ? .green : .orange)
                                
                                Image(systemName: "gear")
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
                            if AudioRecorder.shared.hasAccessibilityPermissions {
                                // Toggle auto-paste if permissions are granted
                                print("🎯 [UI] Auto-paste button clicked - current state: \(audioRecorder.autoPasteEnabled)")
                                audioRecorder.autoPasteEnabled.toggle()
                                print("🎯 [UI] Auto-paste button clicked - new state: \(audioRecorder.autoPasteEnabled)")
                            } else {
                                // Request permissions if not granted
                                print("🎯 [UI] No permissions detected - requesting accessibility permissions")
                                AudioRecorder.shared.requestAccessibilityPermissionsWithPrompt()
                            }
                        }) {
                            HStack(spacing: 4) {
                                let hasPermissions = AudioRecorder.shared.hasAccessibilityPermissions
                                let isEnabled = audioRecorder.autoPasteEnabled
                                
                                if !hasPermissions {
                                    Text("No Permissions")
                                        .font(.system(size: 12))
                                        .foregroundColor(.red)
                                } else if isEnabled {
                                    Text("Enabled")
                                        .font(.system(size: 12))
                                        .foregroundColor(.green)
                                } else {
                                    Text("Disabled")
                                        .font(.system(size: 12))
                                        .foregroundColor(.orange)
                                }
                                
                                Image(systemName: hasPermissions ? (isEnabled ? "checkmark.circle" : "pause.circle") : "gear")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .onAppear {
                                print("🎯 [UI] Auto-Paste button rendered:")
                                print("🎯 [UI]   - hasPermissions: \(AudioRecorder.shared.hasAccessibilityPermissions)")
                                print("🎯 [UI]   - isEnabled: \(audioRecorder.autoPasteEnabled)")
                                print("🎯 [UI]   - accessibilityPermissionsStatus: \(AudioRecorder.shared.accessibilityPermissionsStatus)")
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // Manual permissions check button
                        Button(action: {
                            // Manually recheck permissions
                            print("🔄 [UI] Manual permission check button clicked!")
                            print("🔄 [UI] Current state before check:")
                            print("🔄 [UI]   - hasAccessibilityPermissions: \(AudioRecorder.shared.hasAccessibilityPermissions)")
                            print("🔄 [UI]   - accessibilityPermissionsStatus: \(AudioRecorder.shared.accessibilityPermissionsStatus)")
                            AudioRecorder.shared.checkPermissionsStatus()
                            
                            // Check state after
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                print("🔄 [UI] State after manual check:")
                                print("🔄 [UI]   - hasAccessibilityPermissions: \(AudioRecorder.shared.hasAccessibilityPermissions)")
                                print("🔄 [UI]   - accessibilityPermissionsStatus: \(AudioRecorder.shared.accessibilityPermissionsStatus)")
                            }
                        }) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("Manually check permissions status")
                    }
                )
            )
            
            // Toast notifications control - completely separate setting
            configRow(
                icon: "💬",
                label: "Toasts",
                content: AnyView(
                    HStack(spacing: 4) {
                        Button(action: {
                            print("🎯 [UI] Toast button clicked - current state: \(toastManager.toastsEnabled)")
                            toastManager.toastsEnabled.toggle()
                            print("🎯 [UI] Toast button clicked - new state: \(toastManager.toastsEnabled)")
                            // NO TEST TOAST - just toggle the setting
                        }) {
                            HStack(spacing: 4) {
                                Text(toastManager.toastsEnabled ? "Enabled" : "Disabled")
                                    .font(.system(size: 12))
                                    .foregroundColor(toastManager.toastsEnabled ? .green : .orange)
                                
                                Image(systemName: toastManager.toastsEnabled ? "checkmark.circle" : "pause.circle")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help(toastManager.toastsEnabled ? "Toast notifications enabled - click to disable" : "Toast notifications disabled - click to enable")
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
            return currentModel.displayName
        } else {
            return currentModel.displayName
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
            Text("API Configuration")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 6) {
                if WritingStyleManager.shared.hasApiKey() {
                    HStack {
                        Text("Token: \(WritingStyleManager.shared.getMaskedApiKey())")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        Button("Change") {
                            WritingStyleManager.shared.deleteApiKey()
                            inputText = ""
                        }
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                        .buttonStyle(PlainButtonStyle())
                    }
                } else {
                    HStack {
                        TextField("Enter Gemini API Token", text: $inputText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.system(size: 11))
                        
                        Button("Save") {
                            if !inputText.isEmpty {
                                WritingStyleManager.shared.saveApiKey(inputText)
                                inputText = ""
                                settingsType = nil
                            }
                        }
                        .disabled(inputText.isEmpty)
                        .font(.system(size: 11))
                    }
                }
                
                Text("Required for AI text enhancement and translation features")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                    
                if !WritingStyleManager.shared.hasApiKey() {
                    Text("⚠️ AI features disabled without API token")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .padding(.top, 2)
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

// MARK: - System Card
struct SystemCard: View {
    var body: some View {
        HStack(spacing: 8) {
            systemButton(icon: "🔄", title: "Updates") {
                AutoUpdater.shared.checkForUpdates(force: true)
            }
            
            systemButton(icon: "🚪", title: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .cardStyle()
    }
    
    private func systemButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlColor))
            .foregroundColor(.primary)
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
} 
 