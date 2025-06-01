import SwiftUI

// MARK: - Status Card
struct StatusCard: View {
    let audioRecorder: AudioRecorder
    let memoryUsage: UInt64
    
    var body: some View {
        VStack(spacing: 6) {
            // Main status line with Rec button
            HStack {
                // Only show recording timer when recording
                HStack(spacing: 4) {
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