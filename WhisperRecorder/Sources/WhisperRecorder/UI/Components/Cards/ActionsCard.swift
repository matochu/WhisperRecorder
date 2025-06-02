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
            HStack(spacing: 16) {
                Button(action: {
                    // Open keyboard shortcuts preferences
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "gear")
                            .font(.system(size: 10))

                        KeyboardShortcuts.Recorder(for: .toggleRecording)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(height: 24) // Fixed height to prevent stretching
                .frame(maxWidth: 140) // Limit entire button width
                
                // Contextual processing shortcut
                Button(action: {
                    // Open keyboard shortcuts preferences
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Shortcuts") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text.below.ecg")
                            .font(.system(size: 10))
                        KeyboardShortcuts.Recorder(for: .contextualProcessing)
                            .font(.system(size: 11))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
                    .background(Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(height: 24) // Fixed height to prevent stretching
                .frame(maxWidth: 140) // Limit entire button width
            }
            .frame(height: 32) // Fixed height for the entire row
            .frame(maxWidth: .infinity) // Center the HStack content
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
} 