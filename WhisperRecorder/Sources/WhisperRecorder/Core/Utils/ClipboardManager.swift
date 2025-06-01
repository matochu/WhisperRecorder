import SwiftUI
import AppKit
import ApplicationServices
import Foundation

// MARK: - ClipboardManager

class ClipboardManager: ObservableObject {
    static let shared = ClipboardManager()
    
    @Published var autoPasteEnabled: Bool = true
    
    private init() {
        logInfo(.system, "ClipboardManager initializing")
    }
    
    // MARK: - Public Interface
    
    func copyToClipboard(text: String) {
        logInfo(.audio, "🔄 Starting clipboard sequence...")
        
        let originalText = AppDelegate.lastOriginalWhisperText
        let processedText = text
        
        logDebug(.audio, "Original text: \(originalText.isEmpty ? "empty" : "\(originalText.count) chars")")
        logDebug(.audio, "Processed text: \(processedText.isEmpty ? "empty" : "\(processedText.count) chars")")
        
        // If we have processing (translation/style), only copy the final result
        // Only copy both if processing failed and we're falling back to original
        let needsProcessing = AudioRecorder.shared.selectedWritingStyle.id != "default" || 
                             WritingStyleManager.shared.currentTargetLanguage != WritingStyleManager.shared.noTranslate
        
        if needsProcessing && !processedText.isEmpty && processedText != originalText {
            // We have successful processing - only copy the processed text
            logInfo(.audio, "📄 Using processed text only (translation/style applied)")
            copyTextToClipboard(processedText, label: "processed")
        } else if !originalText.isEmpty {
            // No processing or processing failed - copy original only
            logInfo(.audio, "📄 Using original text (no processing or fallback)")
            copyTextToClipboard(originalText, label: "original")
        } else {
            logWarning(.audio, "❌ No text available to copy")
        }
    }
    
    func copyOriginalText(_ text: String) {
        copyTextToClipboard(text, label: "original text")
        
        if autoPasteEnabled {
            autoPasteToActiveInput()
        }
    }
    
    func copyProcessedText(_ text: String) {
        copyTextToClipboard(text, label: "processed text")
        
        if autoPasteEnabled {
            autoPasteToActiveInput()
        }
    }
    
    // MARK: - Private Methods
    
    private func copyTextToClipboard(_ text: String, label: String) {
        logInfo(.audio, "📋 Copying \(label) text to clipboard: \"\(text.prefix(50))\(text.count > 50 ? "..." : "")\"")
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.setString(text, forType: .string)
        
        if success {
            logInfo(.audio, "✅ Successfully copied \(label) text (\(text.count) chars)")
            
            // Verify what's actually in clipboard
            if let clipboardContent = pasteboard.string(forType: .string) {
                logDebug(.audio, "📋 Clipboard verification: \(clipboardContent.count) chars, matches: \(clipboardContent == text)")
            }
            
            // Show toast with full text (no truncation)
            ToastManager.shared.showToast(message: "Copied to clipboard", preview: text)
            
            // Auto-paste to active input
            if autoPasteEnabled {
                autoPasteToActiveInput()
            } else {
                logDebug(.audio, "Auto-paste disabled by user")
            }
        } else {
            logError(.audio, "❌ Failed to copy \(label) text to clipboard")
        }
    }
    
    private func autoPasteToActiveInput() {
        // Check if accessibility permissions are enabled
        guard autoPasteEnabled else {
            logDebug(.audio, "Auto-paste disabled by user")
            return
        }
        
        // Check accessibility permissions - silently skip if no permissions
        if !AccessibilityManager.shared.checkAccessibilityPermissions() {
            logInfo(.audio, "❌ Auto-paste skipped - no accessibility permissions")
            return
        }
        
        // Set auto-paste in progress to prevent toast from closing
        ToastManager.shared.setAutoPasteInProgress(true)
        
        // Simply perform paste - try multiple methods with delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            logInfo(.audio, "🎯 Attempting auto-paste with multiple methods...")
            self.performPaste()
        }
    }
    
    private func performPaste() {
        // Method 1: Try NSApp sendAction (safest)
        logDebug(.audio, "Method 1: NSApp.sendAction")
        let result1 = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
        logDebug(.audio, "NSApp.sendAction result: \(result1)")
        
        // Method 2: Try CGEvent immediately
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            logDebug(.audio, "Method 2: CGEvent")
            self.sendPasteKeyEvent()
        }
        
        // Method 3: Try NSApp sendAction to first responder (SAFELY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            logDebug(.audio, "Method 3: Targeted sendAction")
            if let window = NSApp.keyWindow,
               let responder = window.firstResponder {
                logDebug(.audio, "Found responder: \(type(of: responder))")
                
                // SAFELY check if responder supports paste: selector
                if responder.responds(to: #selector(NSText.paste(_:))) {
                    logDebug(.audio, "Responder supports paste selector - sending action")
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: responder, from: nil)
                } else {
                    logDebug(.audio, "Responder does not support paste selector - skipping")
                }
            }
        }
        
        // Method 4: Try AppleScript approach
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            logDebug(.audio, "Method 4: AppleScript")
            self.applescriptPaste()
        }
        
        // Reset auto-paste flag after all methods complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            logDebug(.audio, "Auto-paste sequence completed, resetting flag")
            ToastManager.shared.setAutoPasteInProgress(false)
        }
    }
    
    private func sendPasteKeyEvent() {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Send Cmd+V with proper timing
        if let keyDownEvent = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true) {
            keyDownEvent.flags = .maskCommand
            keyDownEvent.post(tap: .cghidEventTap)
            
            // Small delay before key up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                if let keyUpEvent = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) {
                    keyUpEvent.flags = .maskCommand
                    keyUpEvent.post(tap: .cghidEventTap)
                    logDebug(.audio, "CGEvent paste sent")
                }
            }
        }
    }
    
    private func applescriptPaste() {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                logDebug(.audio, "AppleScript error: \(error)")
            } else {
                logDebug(.audio, "AppleScript paste executed")
            }
        }
    }
} 