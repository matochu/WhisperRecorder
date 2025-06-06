import SwiftUI

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