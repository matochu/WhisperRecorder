import SwiftUI
import KeyboardShortcuts

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
        
        // NO SOUND for manual copy operations - sound only plays on transcription completion
        // NSSound(named: "Tink")?.play() // REMOVED
        
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