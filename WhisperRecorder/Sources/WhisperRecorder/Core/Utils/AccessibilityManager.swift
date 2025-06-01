import SwiftUI
import ApplicationServices
import AppKit
import Foundation

// MARK: - AccessibilityManager

class AccessibilityManager: ObservableObject {
    static let shared = AccessibilityManager()
    
    // Published property for accessibility permissions status
    @Published var accessibilityPermissionsStatus: Bool = false
    
    // Status update callback
    var onStatusUpdate: (() -> Void)?
    
    // Check if app was launched from terminal/cursor
    private var isLaunchedFromTerminal: Bool {
        // Check if parent process is terminal-like
        let parentPID = getppid()
        if let parentName = getProcessName(for: parentPID) {
            let terminalProcesses = ["Terminal", "iTerm", "cursor", "zsh", "bash", "fish"]
            return terminalProcesses.contains { parentName.lowercased().contains($0.lowercased()) }
        }
        return false
    }
    
    private func getProcessName(for pid: pid_t) -> String? {
        var name = [CChar](repeating: 0, count: 4096)
        if proc_pidpath(pid, &name, 4096) > 0 {
            return String(cString: name).components(separatedBy: "/").last
        }
        return nil
    }
    
    // Backward compatibility
    var hasAccessibilityPermissions: Bool {
        return accessibilityPermissionsStatus
    }
    
    private init() {
        logInfo(.system, "AccessibilityManager initializing")
        setupPermissionMonitoring()
        logInfo(.system, "AccessibilityManager initialization completed")
    }
    
    deinit {
        // Clean up observers
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Interface
    
    func checkAccessibilityPermissions() -> Bool {
        logInfo(.system, "Checking accessibility permissions...")
        
        // Check WITHOUT showing system prompt
        let accessibilityEnabled = AXIsProcessTrusted()
        
        if accessibilityEnabled {
            logInfo(.system, "✅ Accessibility permissions granted")
        } else {
            logWarning(.system, "❌ Accessibility permissions not granted")
        }
        
        return accessibilityEnabled
    }
    
    func requestAccessibilityPermissions() {
        logInfo(.system, "Requesting accessibility permissions...")
        
        // Check if launched from terminal - for terminal launches, open System Preferences directly
        if isLaunchedFromTerminal {
            logWarning(.system, "⚠️ App launched from terminal/cursor - opening System Preferences directly")
            SystemPreferencesManager.shared.openAccessibilityPreferences()
            return
        }
        
        // For Finder launches: try to show system dialog
        logInfo(.system, "📱 App launched from Finder - attempting to show system permissions dialog")
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        let accessibilityEnabled = AXIsProcessTrustedWithOptions(options as CFDictionary)
        
        if accessibilityEnabled {
            logInfo(.system, "✅ Accessibility permissions already granted")
        } else {
            logInfo(.system, "📝 System permissions dialog should appear for Finder launch")
            // Don't add fallback for Finder launches - let the system dialog do its work
        }
    }
    
    func updateAccessibilityPermissionStatus() {
        let newStatus = AXIsProcessTrusted()
        let processName = ProcessInfo.processInfo.processName
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        
        logDebug(.system, "🔍 Permission check: AXIsProcessTrusted() = \(newStatus)")
        logDebug(.system, "🔍 Process name: \(processName)")
        logDebug(.system, "🔍 Bundle ID: \(bundleId)")
        logDebug(.system, "🔍 Current status: \(accessibilityPermissionsStatus)")
        
        if newStatus != accessibilityPermissionsStatus {
            logInfo(.system, "♻️ Accessibility permission status changed: \(accessibilityPermissionsStatus) → \(newStatus)")
            DispatchQueue.main.async {
                self.accessibilityPermissionsStatus = newStatus
                self.onStatusUpdate?()
            }
        } else {
            // Update without logging for routine checks, but force update UI anyway
            DispatchQueue.main.async {
                self.accessibilityPermissionsStatus = newStatus
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupPermissionMonitoring() {
        logInfo(.system, "Setting up permission monitoring...")
        
        // Initial status check
        updateAccessibilityPermissionStatus()
        
        // Monitor app focus changes only
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            logDebug(.system, "App became active - checking permissions")
            self?.updateAccessibilityPermissionStatus()
        }
        
        // Remove periodic timer - only manual checks now
    }
} 