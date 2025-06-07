import SwiftUI
import AVFoundation
import AppKit
import Foundation

// MARK: - Contextual Workflow Processor

class ContextualWorkflowProcessor: ObservableObject {
    
    // Storage for contextual workflow
    private(set) var contextualClipboardContent: String = ""
    private(set) var isContextualWorkflow: Bool = false
    
    // Dependencies
    private let accessibilityManager = AccessibilityManager.shared
    
    // Callbacks
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    
    // MARK: - Public Interface
    
    func processWithClipboardContext() {
        logInfo(.audio, "🔄 Contextual processing workflow triggered")
            
        // If already in contextual workflow, just stop recording (don't restart)
        if isContextualWorkflow {
            logInfo(.audio, "🛑 Contextual workflow already active - stopping recording only")
            onStopRecording?()
            return
        }
        
        startContextualWorkflow()
    }
    
    var isInContextualWorkflow: Bool {
        return isContextualWorkflow
    }
    
    func getContextualContent() -> String {
        return contextualClipboardContent
    }
    
    func hideContextualToast() {
        // Will be implemented when needed
    }
    
    func cleanupContextualState() {
        isContextualWorkflow = false
        contextualClipboardContent = ""
        logInfo(.audio, "🧹 Contextual workflow state cleaned up")
    }
    
    // MARK: - Private Implementation
    
    private func startContextualWorkflow() {
        logInfo(.audio, "🎯 Starting contextual workflow...")
        
        // First, try to get selected text from active application
        if let selectedText = accessibilityManager.getSelectedText(), !selectedText.isEmpty {
            logInfo(.audio, "✅ Using selected text as context: \(selectedText.count) characters")
            contextualClipboardContent = selectedText
            
            ToastManager.shared.showToast(
                message: "Context: Selected text",
                preview: String(selectedText.prefix(300)),  // Show more text
                type: .contextual
            )
        } else {
            // Fallback: get content from clipboard
            logInfo(.audio, "📋 No selected text found, falling back to clipboard content")
            let clipboard = NSPasteboard.general
            if let clipboardContent = clipboard.string(forType: .string), !clipboardContent.isEmpty {
                contextualClipboardContent = clipboardContent
                logInfo(.audio, "✅ Using clipboard content as context: \(clipboardContent.count) characters")
                
                ToastManager.shared.showToast(
                    message: "Context: Clipboard",
                    preview: String(clipboardContent.prefix(300)),  // Show more text
                    type: .contextual
                )
            } else {
                logWarning(.audio, "❌ No context available (no selected text or clipboard content)")
                ToastManager.shared.showToast(
                    message: "Voice only",
                    preview: "",
                    type: .normal  // No context, so no red border
                )
                contextualClipboardContent = ""
            }
        }
        
        // Set contextual workflow flag
        isContextualWorkflow = true
        
        // Start voice recording
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.onStartRecording?()
        }
    }
} 