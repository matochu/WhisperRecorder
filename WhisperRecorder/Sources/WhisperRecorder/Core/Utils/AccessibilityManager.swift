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
    
    // MARK: - Selected Text Capture
    
    func getSelectedText() -> String? {
        // Check if we have accessibility permissions first
        guard checkAccessibilityPermissions() else {
            logWarning(.system, "❌ Cannot read selected text - no accessibility permissions")
            return nil
        }
        
        logDebug(.system, "🔍 Attempting to read selected text from active application")
        
        // Get the frontmost application
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication else {
            logWarning(.system, "❌ No frontmost application found")
            return nil
        }
        
        logDebug(.system, "🎯 Frontmost app: \(frontmostApp.localizedName ?? "Unknown")")
        
        // Create AXUIElement for the application
        let appElement = AXUIElementCreateApplication(frontmostApp.processIdentifier)
        
        // Try to get the focused element
        var focusedElement: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        
        if focusedResult != .success {
            logDebug(.system, "📝 No focused element found, trying alternative methods")
            return tryAlternativeTextCapture(appElement: appElement)
        }
        
        guard let focused = focusedElement else {
            logDebug(.system, "📝 Focused element is nil")
            return tryAlternativeTextCapture(appElement: appElement)
        }
        
        // Try to get selected text from focused element
        if let selectedText = getSelectedTextFromElement(focused as! AXUIElement) {
            logInfo(.system, "✅ Successfully read selected text: \(selectedText.count) characters")
            return selectedText
        }
        
        // Fallback: try alternative methods
        return tryAlternativeTextCapture(appElement: appElement)
    }
    
    private func getSelectedTextFromElement(_ element: AXUIElement) -> String? {
        // Try to get selected text attribute
        var selectedTextValue: CFTypeRef?
        let selectedTextResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextValue)
        
        if selectedTextResult == .success, let selectedText = selectedTextValue as? String, !selectedText.isEmpty {
            logDebug(.system, "✅ Found selected text via kAXSelectedTextAttribute: \(selectedText.count) chars")
            return selectedText
        }
        
        // Try to get selected text range and extract text
        if let textFromRange = getTextFromSelectedRange(element) {
            return textFromRange
        }
        
        logDebug(.system, "📝 No selected text found in element")
        return nil
    }
    
    private func getTextFromSelectedRange(_ element: AXUIElement) -> String? {
        // Get selected text range
        var selectedRangeValue: CFTypeRef?
        let rangeResult = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue)
        
        guard rangeResult == .success, let rangeValue = selectedRangeValue else {
            return nil
        }
        
        // Get the entire text value
        var textValue: CFTypeRef?
        let textResult = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &textValue)
        
        guard textResult == .success, let fullText = textValue as? String else {
            return nil
        }
        
        // Try to extract range information
        if CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) {
                let location = range.location
                let length = range.length
                
                // Validate range
                guard location >= 0, length > 0, location + length <= fullText.count else {
                    return nil
                }
                
                // Extract selected text using range
                let startIndex = fullText.index(fullText.startIndex, offsetBy: location)
                let endIndex = fullText.index(startIndex, offsetBy: length)
                let selectedText = String(fullText[startIndex..<endIndex])
                
                logDebug(.system, "✅ Extracted text from range (\(location), \(length)): \(selectedText.count) chars")
                return selectedText
            }
        }
        
        return nil
    }
    
    private func tryAlternativeTextCapture(appElement: AXUIElement) -> String? {
        logDebug(.system, "🔄 Trying alternative text capture methods")
        
        // Method 1: Try to find text fields with selections
        if let textFromFields = findSelectedTextInTextFields(appElement) {
            return textFromFields
        }
        
        // Method 2: Try web content (for browsers)
        if let textFromWeb = findSelectedTextInWebContent(appElement) {
            return textFromWeb
        }
        
        logDebug(.system, "📝 No selected text found via alternative methods")
        return nil
    }
    
    private func findSelectedTextInTextFields(_ appElement: AXUIElement) -> String? {
        // Get all text fields in the application
        var children: CFTypeRef?
        let childrenResult = AXUIElementCopyAttributeValue(appElement, kAXChildrenAttribute as CFString, &children)
        
        guard childrenResult == .success, let childrenArray = children as? [AXUIElement] else {
            return nil
        }
        
        // Recursively search for text fields with selections
        return searchElementsForSelectedText(childrenArray)
    }
    
    private func searchElementsForSelectedText(_ elements: [AXUIElement]) -> String? {
        for element in elements {
            // Check if this element has selected text
            if let selectedText = getSelectedTextFromElement(element), !selectedText.isEmpty {
                return selectedText
            }
            
            // Recursively check children
            var children: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children)
            
            if childrenResult == .success, let childrenArray = children as? [AXUIElement] {
                if let foundText = searchElementsForSelectedText(childrenArray) {
                    return foundText
                }
            }
        }
        
        return nil
    }
    
    private func findSelectedTextInWebContent(_ appElement: AXUIElement) -> String? {
        // For web browsers, try to find web areas with selections
        var role: CFTypeRef?
        let roleResult = AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &role)
        
        if roleResult == .success, let roleString = role as? String, roleString.contains("Web") {
            logDebug(.system, "🌐 Detected web content, trying web-specific extraction")
            
            // Try to get selected text from web areas
            return getSelectedTextFromWebArea(appElement)
        }
        
        return nil
    }
    
    private func getSelectedTextFromWebArea(_ element: AXUIElement) -> String? {
        // Web content often uses different attributes for selected text
        // Try common web accessibility attributes
        let webTextAttributes = [
            kAXSelectedTextAttribute,
            kAXValueAttribute,
            "AXSelectedTextMarkerRange" // Safari-specific
        ]
        
        for attribute in webTextAttributes {
            var value: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
            
            if result == .success, let textValue = value as? String, !textValue.isEmpty {
                logDebug(.system, "✅ Found web selected text via \(attribute): \(textValue.count) chars")
                return textValue
            }
        }
        
        return nil
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