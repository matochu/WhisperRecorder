import SwiftUI
import AppKit

// MARK: - Toast Window
class ToastWindow: NSWindow {
    private var toastView: NSHostingView<ToastView>!
    
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 50),  // Wider for 450px content + padding
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
            isContextual: ToastManager.shared.isContextual,
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
            isContextual: ToastManager.shared.isContextual,
            isShowing: toastBinding
        )
    }
    
    func showToastAtPosition(_ position: NSPoint) {
        // Update content first
        updateToastContent()
        
        // Calculate dynamic height based on text length
        let textLength = ToastManager.shared.preview.count
        let estimatedLines = max(1, (textLength / 75) + 1) // Roughly 75 chars per line (more for wider window)
        let dynamicHeight = min(200, max(50, estimatedLines * 20 + 20)) // 20px per line + padding
        
        // Convert screen coordinates for positioning
        let screenFrame = NSScreen.main?.frame ?? NSRect.zero
        let windowSize = NSSize(width: 470, height: CGFloat(dynamicHeight))  // Updated width
        
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