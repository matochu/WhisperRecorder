import SwiftUI

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