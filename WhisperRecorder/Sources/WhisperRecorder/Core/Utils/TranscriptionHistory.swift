import Foundation
import SwiftUI

// MARK: - Transcription History Item
struct TranscriptionHistoryItem: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let originalText: String
    let processedText: String?
    let llmFormattedText: String?
    let duration: TimeInterval?
    let speakerCount: Int?
    let writingStyle: String?
    let language: String?
    
    init(
        originalText: String,
        processedText: String? = nil,
        llmFormattedText: String? = nil,
        duration: TimeInterval? = nil,
        speakerCount: Int? = nil,
        writingStyle: String? = nil,
        language: String? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.originalText = originalText
        self.processedText = processedText
        self.llmFormattedText = llmFormattedText
        self.duration = duration
        self.speakerCount = speakerCount
        self.writingStyle = writingStyle
        self.language = language
    }
    
    var hasProcessedText: Bool {
        return processedText != nil && !processedText!.isEmpty
    }
    
    var hasLLMText: Bool {
        return llmFormattedText != nil && !llmFormattedText!.isEmpty
    }
    
    var displayText: String {
        return hasProcessedText ? (processedText ?? originalText) : originalText
    }
    
    var preview: String {
        let text = displayText
        let maxLength = 100
        return text.count > maxLength ? String(text.prefix(maxLength)) + "..." : text
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
    
    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }
}

// MARK: - Transcription History Manager
class TranscriptionHistoryManager: ObservableObject {
    static let shared = TranscriptionHistoryManager()
    
    @Published var history: [TranscriptionHistoryItem] = []
    @Published var maxHistorySize: Int = 50 // Configurable limit
    
    private let userDefaults = UserDefaults.standard
    private let historyKey = "transcriptionHistory"
    
    private init() {
        loadHistory()
    }
    
    // MARK: - Public Methods
    
    func addTranscription(
        originalText: String,
        processedText: String? = nil,
        llmFormattedText: String? = nil,
        duration: TimeInterval? = nil,
        speakerCount: Int? = nil,
        writingStyle: String? = nil,
        language: String? = nil
    ) {
        guard !originalText.isEmpty else {
            logWarning(.storage, "Attempted to add empty transcription to history")
            return
        }
        
        let item = TranscriptionHistoryItem(
            originalText: originalText,
            processedText: processedText,
            llmFormattedText: llmFormattedText,
            duration: duration,
            speakerCount: speakerCount,
            writingStyle: writingStyle,
            language: language
        )
        
        DispatchQueue.main.async {
            self.history.insert(item, at: 0) // Add to beginning (newest first)
            
            // Limit history size
            if self.history.count > self.maxHistorySize {
                self.history = Array(self.history.prefix(self.maxHistorySize))
            }
            
            self.saveHistory()
            
            logInfo(.storage, "Added transcription to history: \(item.preview)")
        }
    }
    
    func removeItem(_ item: TranscriptionHistoryItem) {
        DispatchQueue.main.async {
            self.history.removeAll { $0.id == item.id }
            self.saveHistory()
            logInfo(.storage, "Removed transcription from history")
        }
    }
    
    func clearHistory() {
        DispatchQueue.main.async {
            self.history.removeAll()
            self.saveHistory()
            logInfo(.storage, "Cleared transcription history")
        }
    }
    
    func updateMaxHistorySize(_ newSize: Int) {
        maxHistorySize = max(1, min(newSize, 200)) // Between 1 and 200
        userDefaults.set(maxHistorySize, forKey: "maxHistorySize")
        
        // Trim current history if needed
        DispatchQueue.main.async {
            if self.history.count > self.maxHistorySize {
                self.history = Array(self.history.prefix(self.maxHistorySize))
                self.saveHistory()
            }
        }
    }
    
    // MARK: - Persistence
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(history)
            userDefaults.set(data, forKey: historyKey)
            logDebug(.storage, "Saved transcription history: \(history.count) items")
        } catch {
            logError(.storage, "Failed to save transcription history: \(error)")
        }
    }
    
    private func loadHistory() {
        // Load max history size
        let savedMaxSize = userDefaults.integer(forKey: "maxHistorySize")
        if savedMaxSize > 0 {
            maxHistorySize = savedMaxSize
        }
        
        // Load history items
        guard let data = userDefaults.data(forKey: historyKey) else {
            logInfo(.storage, "No transcription history found")
            return
        }
        
        do {
            let loadedHistory = try JSONDecoder().decode([TranscriptionHistoryItem].self, from: data)
            
            DispatchQueue.main.async {
                self.history = Array(loadedHistory.prefix(self.maxHistorySize))
                logInfo(.storage, "Loaded transcription history: \(self.history.count) items")
            }
        } catch {
            logError(.storage, "Failed to load transcription history: \(error)")
            // Clear corrupted data
            userDefaults.removeObject(forKey: historyKey)
        }
    }
    
    // MARK: - Utility Methods
    
    func getHistoryStats() -> (total: Int, withProcessing: Int, withSpeakers: Int) {
        let total = history.count
        let withProcessing = history.filter { $0.hasProcessedText }.count
        let withSpeakers = history.filter { ($0.speakerCount ?? 0) > 1 }.count
        
        return (total: total, withProcessing: withProcessing, withSpeakers: withSpeakers)
    }
    
    func searchHistory(_ query: String) -> [TranscriptionHistoryItem] {
        guard !query.isEmpty else { return history }
        
        let lowercaseQuery = query.lowercased()
        return history.filter { item in
            item.originalText.lowercased().contains(lowercaseQuery) ||
            (item.processedText?.lowercased().contains(lowercaseQuery) ?? false)
        }
    }
} 