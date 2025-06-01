import SwiftUI

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