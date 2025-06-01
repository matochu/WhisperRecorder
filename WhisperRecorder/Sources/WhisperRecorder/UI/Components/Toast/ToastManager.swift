import SwiftUI
import AppKit

// MARK: - Toast Manager
class ToastManager: ObservableObject {
    @Published var isShowing = false
    @Published var message = ""
    @Published var preview = ""
    @Published var position = NSPoint.zero
    
    static let shared = ToastManager()
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var isAutoPasteInProgress = false  // Flag to prevent hiding during auto-paste
    
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
    
    func showToast(message: String, preview: String = "", at position: NSPoint? = nil) {
        // Check if toasts are enabled for visual display
        guard toastsEnabled else {
            return
        }
        
        // Get cursor position if not provided
        let toastPosition = position ?? NSEvent.mouseLocation
        
        DispatchQueue.main.async {
            // Show the full preview text (not truncated)
            self.message = ""  // Clear message - we don't want it
            self.preview = preview.trimmingCharacters(in: .whitespacesAndNewlines) // Show full text, just trim whitespace
            self.position = toastPosition
            
            self.isShowing = true
            
            // Set up key monitoring to hide on any key press - NO TIMER
            self.setupKeyMonitoring()
        }
    }
    
    private func setupKeyMonitoring() {
        // Remove existing monitor
        if let globalKeyMonitor = globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
        }
        if let localKeyMonitor = localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
        
        // Monitor for any key press to hide toast - use both local and global
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self = self else { return }
            if self.isAutoPasteInProgress {
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
            self.hideToast()
            return event  // Return the event to allow normal processing
        }
    }
    
    func hideToast() {
        DispatchQueue.main.async {
            self.isShowing = false
            
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