import SwiftUI
import Foundation

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var isDarkMode: Bool = false
    @Published var autoStartRecording: Bool = false
    @Published var selectedLanguage: String = "auto"
    
    private init() {
        // Load settings from UserDefaults
        loadSettings()
    }
    
    private func loadSettings() {
        isDarkMode = UserDefaults.standard.bool(forKey: "isDarkMode")
        autoStartRecording = UserDefaults.standard.bool(forKey: "autoStartRecording")
        selectedLanguage = UserDefaults.standard.string(forKey: "selectedLanguage") ?? "auto"
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(isDarkMode, forKey: "isDarkMode")
        UserDefaults.standard.set(autoStartRecording, forKey: "autoStartRecording")
        UserDefaults.standard.set(selectedLanguage, forKey: "selectedLanguage")
    }
    
    func updateDarkMode(_ enabled: Bool) {
        isDarkMode = enabled
        saveSettings()
    }
    
    func updateAutoStart(_ enabled: Bool) {
        autoStartRecording = enabled
        saveSettings()
    }
    
    func updateLanguage(_ language: String) {
        selectedLanguage = language
        saveSettings()
    }
} 