import SwiftUI

// MARK: - Toast View
struct ToastView: View {
    let message: String
    let preview: String
    let toastType: ToastType
    @Binding var isShowing: Bool
    
    var body: some View {
        // Show the full copied text content with darker 8-bit + macOS style background
        Text(preview.isEmpty ? message : preview)
            .font(.system(size: 11, weight: .medium, design: .monospaced))  // Monospaced for 8-bit feel
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(width: 450, alignment: .leading)  // Increased width from 300 to 450
            .fixedSize(horizontal: false, vertical: true)  // Allow vertical expansion
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(.controlColor).opacity(0.7))  // Less bright background
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                borderColor,
                                lineWidth: borderWidth
                            )
                    )
            )
            .scaleEffect(isShowing ? 1.0 : 0.9)
            .opacity(isShowing ? 0.75 : 0.0)  // Reduced opacity from 0.92 to 0.75
            .animation(.easeInOut(duration: 0.15), value: isShowing)
    }
    
    private var borderColor: Color {
        switch toastType {
        case .error:
            return Color(red: 0.5, green: 0.0, blue: 0.0)  // Dark red color
        case .contextual:
            return Color.red.opacity(0.3)  // Light red for contextual
        case .normal:
            return Color(.tertiaryLabelColor).opacity(0.5)  // Default border
        }
    }
    
    private var borderWidth: CGFloat {
        switch toastType {
        case .error:
            return 2.0  // Thicker border for errors
        case .contextual:
            return 1.5
        case .normal:
            return 1.0
        }
    }
} 