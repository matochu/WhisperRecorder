import SwiftUI
import KeyboardShortcuts

// MARK: - Actions Card
struct ActionsCard: View {
    let audioRecorder: AudioRecorder
    @State private var lastStatus: String = ""
    @State private var lastOriginalText: String = ""
    @State private var lastProcessedText: String = ""
    @ObservedObject private var speakerEngine = SpeakerDiarizationEngine.shared
    
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
        ToastManager.shared.showToast(message: toastMessage, preview: text, type: .normal)
    }
    
    // MARK: - Speaker-Specific Actions
    
    private func speakerCopyButton(speakerIndex: Int, speakerID: String, timeline: SpeakerTimeline) -> some View {
        let speakingTime = timeline.speakingTime(for: speakerID)
        let segmentCount = timeline.segments(for: speakerID).count
        
        return Button(action: {
            copySpeakerText(speakerIndex: speakerIndex, speakerID: speakerID, timeline: timeline)
        }) {
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Text("👤")
                        .font(.system(size: 10))
                    Text("S\(speakerIndex)")
                        .font(.system(size: 9, weight: .medium))
                }
                Text("\(String(format: "%.0f", speakingTime))s")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color(.controlAccentColor).opacity(0.7))
            .foregroundColor(.white)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(.separatorColor), lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .help("Speaker \(speakerIndex): \(String(format: "%.1f", speakingTime))s speaking time, \(segmentCount) segments")
    }
    
    private func copySpeakerText(speakerIndex: Int, speakerID: String, timeline: SpeakerTimeline) {
        // Extract text segments for this speaker
        // For now, we'll use a placeholder approach since we don't have segment-level transcription yet
        let segments = timeline.segments(for: speakerID)
        let speakingTime = timeline.speakingTime(for: speakerID)
        
        var speakerText = "👤 Speaker \(speakerIndex) (\(String(format: "%.1f", speakingTime))s total)\n\n"
        
        for (index, segment) in segments.enumerated() {
            let timestamp = String(format: "%.1f", segment.startTime)
            speakerText += "[\(timestamp)s] Segment \(index + 1) (\(String(format: "%.1f", segment.duration))s)\n"
        }
        
        // Add note about segment-level transcription
        speakerText += "\nNote: Segment-level transcription not yet implemented.\nThis shows speaker timeline information only."
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(speakerText, forType: .string)
        
        let toastMessage = "Copied Speaker \(speakerIndex) info"
        logInfo(.ui, "👤 [TOAST] Copied Speaker \(speakerIndex) text to clipboard")
        ToastManager.shared.showToast(message: toastMessage, preview: speakerText, type: .normal)
    }
    
    private func copySpeakerLabeledText() {
        guard let timeline = speakerEngine.lastDiarizationResult else {
            logWarning(.ui, "❌ No speaker timeline available")
            return
        }
        
        // Get the current processed or original text with speaker labels
        let baseText = AppDelegate.hasProcessedText ? AppDelegate.lastProcessedText : AppDelegate.lastOriginalWhisperText
        
        if baseText.isEmpty {
            logWarning(.ui, "❌ No text available to copy with speaker labels")
            return
        }
        
        // Create speaker-labeled version
        var labeledText = "🎤 Speaker Diarization Results\n"
        labeledText += "Detected \(timeline.speakerCount) speakers\n\n"
        
        // Add speaker summary
        for (index, speakerID) in timeline.uniqueSpeakers.enumerated() {
            let speakingTime = timeline.speakingTime(for: speakerID)
            let segmentCount = timeline.segments(for: speakerID).count
            labeledText += "👤 Speaker \(index + 1): \(String(format: "%.1f", speakingTime))s (\(segmentCount) segments)\n"
        }
        
        labeledText += "\n📝 Transcript:\n\(baseText)\n\n"
        
        // Add timeline information
        labeledText += "🕒 Speaker Timeline:\n"
        for segment in timeline.segments {
            let speakerIndex = timeline.uniqueSpeakers.firstIndex(of: segment.speakerID) ?? 0
            let timestamp = String(format: "%.1f", segment.startTime)
            let duration = String(format: "%.1f", segment.duration)
            labeledText += "[\(timestamp)s-\(String(format: "%.1f", segment.endTime))s] Speaker \(speakerIndex + 1) (\(duration)s)\n"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(labeledText, forType: .string)
        
        let toastMessage = "Copied transcript with speaker labels"
        logInfo(.ui, "👥 [TOAST] Copied speaker-labeled transcript to clipboard")
        ToastManager.shared.showToast(message: toastMessage, preview: labeledText, type: .normal)
    }
} 