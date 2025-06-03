import SwiftUI
import AppKit

// MARK: - Toast Types
enum ToastType {
    case normal      // Regular copy toasts (hide on key press)
    case contextual  // Recording status toasts (hide on recording end)
    case error       // Error toasts (auto-hide after 10 seconds + red border)
}

// MARK: - Toast Manager
class ToastManager: ObservableObject {
    @Published var isShowing = false
    @Published var message = ""
    @Published var preview = ""
    @Published var position = NSPoint.zero
    @Published var toastType: ToastType = .normal
    
    static let shared = ToastManager()
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var isAutoPasteInProgress = false  // Flag to prevent hiding during auto-paste
    private var errorTimer: Timer?  // Timer for auto-hiding error toasts
    
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
    
    func showToast(message: String, preview: String = "", at position: NSPoint? = nil, type: ToastType = .normal) {
        // Check if toasts are enabled for visual display
        guard toastsEnabled else {
            return
        }
        
        // Get cursor position if not provided
        let toastPosition = position ?? NSEvent.mouseLocation
        
        DispatchQueue.main.async {
            // Cancel any existing error timer
            self.errorTimer?.invalidate()
            self.errorTimer = nil
            
            // Show the full preview text (not truncated)
            self.message = ""  // Clear message - we don't want it
            self.preview = preview.trimmingCharacters(in: .whitespacesAndNewlines) // Show full text, just trim whitespace
            self.position = toastPosition
            self.toastType = type
            
            self.isShowing = true
            
            // Set up appropriate hiding behavior based on type
            switch type {
            case .error:
                // Error toasts auto-hide after 10 seconds
                self.errorTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                    self?.hideToast()
                }
            case .normal, .contextual:
                // Set up key monitoring to hide on any key press
                self.setupKeyMonitoring()
            }
        }
    }
    
    func showErrorToast(message: String, at position: NSPoint? = nil) {
        showToast(message: message, preview: message, at: position, type: .error)
    }
    
    private func setupKeyMonitoring() {
        // Remove existing monitor
        if let globalKeyMonitor = globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let localKeyMonitor = localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        
        // Monitor for any key press to hide toast
        // But don't hide contextual toasts on mouse clicks - they stay until recording ends
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            if self.isAutoPasteInProgress {
                return
            }
            // Don't hide contextual toasts on mouse clicks
            if self.toastType == .contextual && (event.type == .leftMouseDown || event.type == .rightMouseDown) {
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
            // Don't hide contextual toasts on mouse clicks
            if self.toastType == .contextual && (event.type == .leftMouseDown || event.type == .rightMouseDown) {
                return event
            }
            self.hideToast()
            return event  // Return the event to allow normal processing
        }
    }
    
    func hideToast() {
        DispatchQueue.main.async {
            self.isShowing = false
            self.toastType = .normal  // Reset toast type when hiding
            
            // Cancel error timer
            self.errorTimer?.invalidate()
            self.errorTimer = nil
            
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