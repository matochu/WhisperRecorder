import SwiftUI

// MARK: - History Card
struct HistoryCard: View {
    @ObservedObject private var historyManager = TranscriptionHistoryManager.shared
    @State private var isExpanded = false
    @State private var searchText = ""
    @State private var selectedItem: TranscriptionHistoryItem?
    @State private var showingClearConfirmation = false
    
    var onToggle: ((Bool) -> Void)? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            historyHeader
            
            if isExpanded {
                let _ = logInfo(.ui, "📜 History expanded: \(historyManager.history.count) items in manager")
                
                if historyManager.history.isEmpty {
                    emptyHistoryView
                } else {
                    historyControls
                    historyList
                }
            }
        }
        .cardStyle()
        .alert("Clear History", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                historyManager.clearHistory()
            }
        } message: {
            Text("Are you sure you want to clear all transcription history? This action cannot be undone.")
        }
    }
    
    private var historyHeader: some View {
        HStack {
            HStack(spacing: 6) {
                Text("📜")
                    .font(.system(size: 14))
                Text("History")
                    .font(.system(size: 12, weight: .medium))
                
                if !historyManager.history.isEmpty {
                    let stats = historyManager.getHistoryStats()
                    Text("(\(stats.total))")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    if stats.withProcessing > 0 {
                        Text("🔄\(stats.withProcessing)")
                            .font(.system(size: 10))
                            .foregroundColor(.blue)
                    }
                    
                    if stats.withSpeakers > 0 {
                        Text("👥\(stats.withSpeakers)")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                    onToggle?(isExpanded)
                }
            }) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    private var emptyHistoryView: some View {
        VStack(spacing: 4) {
            Text("No transcriptions yet")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            Text("Your transcription history will appear here")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
    
    private var historyControls: some View {
        VStack(spacing: 6) {
            // Search bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .font(.system(size: 11))
                
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Stats and controls
            HStack {
                let stats = historyManager.getHistoryStats()
                Text("\(stats.total) total • \(stats.withProcessing) processed • \(stats.withSpeakers) with speakers")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Clear All") {
                    showingClearConfirmation = true
                }
                .font(.system(size: 10))
                .foregroundColor(.red)
                .buttonStyle(PlainButtonStyle())
            }
        }
    }
    
    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                let filteredHistory = searchText.isEmpty ? historyManager.history : historyManager.searchHistory(searchText)
                
                // Debug: Log history count
                let _ = logInfo(.ui, "📜 History display: \(filteredHistory.count) items (total: \(historyManager.history.count))")
                
                ForEach(filteredHistory) { item in
                    HistoryItemView(
                        item: item,
                        isSelected: selectedItem?.id == item.id,
                        onSelect: {
                            selectedItem = selectedItem?.id == item.id ? nil : item
                        },
                        onCopy: { copyType in
                            copyHistoryItem(item, type: copyType)
                        },
                        onDelete: {
                            historyManager.removeItem(item)
                        }
                    )
                }
                
                if filteredHistory.isEmpty && !searchText.isEmpty {
                    Text("No results found")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else if filteredHistory.isEmpty && searchText.isEmpty && !historyManager.history.isEmpty {
                    Text("All items filtered out")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.bottom, 4)
        }
        .frame(minHeight: 100, maxHeight: 400)
    }
    
    private func copyHistoryItem(_ item: TranscriptionHistoryItem, type: HistoryItemCopyType) {
        let textToCopy: String
        let description: String
        
        switch type {
        case .original:
            textToCopy = item.originalText
            description = "original text"
        case .processed:
            textToCopy = item.processedText ?? item.originalText
            description = "processed text"
        case .llm:
            textToCopy = item.llmFormattedText ?? item.originalText
            description = "LLM format"
        case .display:
            textToCopy = item.displayText
            description = "text"
        }
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        
        // Show toast notification
        ToastManager.shared.showToast(
            message: "Copied \(description) from history",
            preview: String(textToCopy.prefix(50)),
            type: .normal
        )
        
        logInfo(.storage, "Copied \(description) from history: \(textToCopy.count) characters")
    }
}

// MARK: - History Item View
struct HistoryItemView: View {
    let item: TranscriptionHistoryItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onCopy: (HistoryItemCopyType) -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.formattedDate)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.primary)
                        
                        if let speakerCount = item.speakerCount, speakerCount > 1 {
                            Text("👥\(speakerCount)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        
                        if item.hasProcessedText {
                            Text("🔄")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                        }
                        
                        if let style = item.writingStyle, style != "default" {
                            Text("✍️")
                                .font(.system(size: 9))
                                .foregroundColor(.purple)
                        }
                    }
                    
                    Text(item.preview)
                        .font(.system(size: 11))
                        .foregroundColor(.primary)
                        .lineLimit(isSelected ? nil : 2)
                        .help(item.originalText.count > 100 ? item.originalText : "")
                }
                
                Spacer()
                
                Button(action: onSelect) {
                    Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            if isSelected {
                Divider()
                    .padding(.vertical, 2)
                
                // Action icons with tooltips
                HStack(spacing: 8) {
                    iconButton("doc.on.clipboard", "Copy display text", { onCopy(.display) })
                    
                    if item.hasProcessedText {
                        iconButton("arrow.triangle.2.circlepath", "Copy processed text", { onCopy(.processed) })
                    }
                    
                    iconButton("doc.text", "Copy original text", { onCopy(.original) })
                    
                    if item.hasLLMText {
                        iconButton("brain", "Copy LLM formatted text", { onCopy(.llm) })
                    }
                    
                    Spacer()
                    
                    iconButton("trash", "Delete this item", onDelete, color: .red)
                }
                
                // Metadata
                if let duration = item.duration {
                    Text("Duration: \(String(format: "%.1f", duration))s")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isSelected ? Color(.controlAccentColor).opacity(0.1) : Color.clear)
        .cornerRadius(4)
        .onTapGesture {
            onSelect()
        }
    }
    
    private func iconButton(_ systemName: String, _ tooltip: String, _ action: @escaping () -> Void, color: Color = .secondary) -> some View {
        IconButtonView(systemName: systemName, tooltip: tooltip, action: action, color: color)
    }
}

// MARK: - Icon Button with Hover Effect
struct IconButtonView: View {
    let systemName: String
    let tooltip: String
    let action: () -> Void
    let color: Color
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .foregroundColor(isHovered ? .primary : color)
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isHovered ? Color(.controlBackgroundColor) : Color.clear)
                        .animation(.easeInOut(duration: 0.15), value: isHovered)
                )
        }
        .buttonStyle(PlainButtonStyle())
        .help(tooltip)
        .onHover { hovering in
            isHovered = hovering
        }
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }
}

// MARK: - Supporting Types
enum HistoryItemCopyType {
    case original
    case processed
    case llm
    case display
} 