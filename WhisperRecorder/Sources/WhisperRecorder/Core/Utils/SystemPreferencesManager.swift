import Foundation
import AppKit

// MARK: - SystemPreferencesManager

class SystemPreferencesManager {
    static let shared = SystemPreferencesManager()
    
    private init() {}
    
    // MARK: - Public Interface
    
    func openAccessibilityPreferences() {
        logInfo(.system, "Opening System Preferences > Privacy & Security > Accessibility")
        
        // URL to open System Preferences to Accessibility section
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        
        NSWorkspace.shared.open(prefPaneURL, configuration: NSWorkspace.OpenConfiguration()) { (app, error) in
            if let error = error {
                logError(.system, "❌ Failed to open Accessibility preferences: \(error)")
                
                // Fallback: open general Security & Privacy
                let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
                NSWorkspace.shared.open(fallbackURL, configuration: NSWorkspace.OpenConfiguration()) { (_, fallbackError) in
                    if let fallbackError = fallbackError {
                        logError(.system, "❌ Failed to open Security & Privacy preferences: \(fallbackError)")
                    } else {
                        logInfo(.system, "✅ Opened Security & Privacy preferences (general)")
                    }
                }
            } else {
                logInfo(.system, "✅ Successfully opened Accessibility preferences")
            }
        }
    }
    
    func openGeneralSecurityPreferences() {
        logInfo(.system, "Opening System Preferences > Privacy & Security")
        
        let prefPaneURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")!
        
        NSWorkspace.shared.open(prefPaneURL, configuration: NSWorkspace.OpenConfiguration()) { (app, error) in
            if let error = error {
                logError(.system, "❌ Failed to open Security & Privacy preferences: \(error)")
            } else {
                logInfo(.system, "✅ Successfully opened Security & Privacy preferences")
            }
        }
    }
} 