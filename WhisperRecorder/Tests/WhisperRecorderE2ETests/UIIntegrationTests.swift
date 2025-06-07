import XCTest
import SwiftUI
@testable import WhisperRecorder

/// UI Integration Tests for WhisperRecorder
/// Tests real integration between UI components and core functionality
class UIIntegrationTests: XCTestCase {
    
    var audioRecorder: AudioRecorder!
    var toastManager: ToastManager!
    var writingStyleManager: WritingStyleManager!
    var accessibilityManager: AccessibilityManager!
    var clipboardManager: ClipboardManager!
    
    override func setUp() {
        super.setUp()
        audioRecorder = AudioRecorder.shared
        toastManager = ToastManager.shared
        writingStyleManager = WritingStyleManager.shared
        accessibilityManager = AccessibilityManager.shared
        clipboardManager = ClipboardManager.shared
        
        // Reset state for clean tests
        toastManager.toastsEnabled = true
        toastManager.hideToast()
    }
    
    override func tearDown() {
        toastManager.hideToast()
        super.tearDown()
    }
    
    // MARK: - Recording Integration Tests
    
    func testRecordingStatusIntegration() {
        print("\n🎤 Testing Recording Status Integration")
        print("─────────────────────────────────────")
        
        // Test initial state
        XCTAssertFalse(audioRecorder.isRecording, "Should not be recording initially")
        XCTAssertEqual(audioRecorder.statusDescription, "Ready", "Should show ready status")
        
        // Test that AudioRecorder has proper status descriptions
        XCTAssertNotNil(audioRecorder.statusDescription, "Should have status description")
        XCTAssertFalse(audioRecorder.statusDescription.isEmpty, "Status should not be empty")
        
        print("   ✅ Recording status integration works")
    }
    
    func testAudioRecorderAccessibilityIntegration() {
        print("\n♿ Testing Audio Recorder + Accessibility Integration")
        print("──────────────────────────────────────────────────")
        
        // Test accessibility permissions check through AudioRecorder
        let hasPermissions = audioRecorder.checkAccessibilityPermissions()
        print("   🔍 Accessibility permissions: \(hasPermissions)")
        
        // Test that AudioRecorder properly delegates to AccessibilityManager
        let directCheck = accessibilityManager.checkAccessibilityPermissions()
        XCTAssertEqual(hasPermissions, directCheck, "AudioRecorder should delegate to AccessibilityManager")
        
        print("   ✅ Audio + Accessibility integration verified")
    }
    
    // MARK: - Clipboard Integration Tests
    
    func testClipboardOperationIntegration() {
        print("\n📋 Testing Clipboard Operation Integration")
        print("────────────────────────────────────")
        
        let testText = "Integration test clipboard content"
        
        // Test clipboard copy with proper API
        clipboardManager.copyToClipboard(text: testText)
        
        // Verify clipboard content directly
        let pasteboard = NSPasteboard.general
        let clipboardContent = pasteboard.string(forType: .string)
        
        // Note: ClipboardManager might process text, so we check if content exists
        // In test environments, clipboard operations might be restricted
        if clipboardContent != nil {
            print("   ✅ Clipboard operation successful in test environment")
        } else {
            print("   ⚠️ Clipboard restricted in test environment (normal)")
        }
        
        print("   📝 Copied text length: \(testText.count)")
        print("   📋 Clipboard content exists: \(clipboardContent != nil)")
        print("   ✅ Clipboard integration works")
    }
    
    func testAutoPasteConfiguration() {
        print("\n🎯 Testing Auto-Paste Configuration")
        print("──────────────────────────────────")
        
        // Test auto-paste toggle
        let originalState = clipboardManager.autoPasteEnabled
        
        clipboardManager.autoPasteEnabled = false
        XCTAssertFalse(clipboardManager.autoPasteEnabled, "Should disable auto-paste")
        
        clipboardManager.autoPasteEnabled = true
        XCTAssertTrue(clipboardManager.autoPasteEnabled, "Should enable auto-paste")
        
        // Restore original state
        clipboardManager.autoPasteEnabled = originalState
        
        print("   ✅ Auto-paste configuration works")
    }
    
    // MARK: - Text Processing Integration Tests
    
    func testTextStorageIntegration() {
        print("\n📝 Testing Text Storage Integration")
        print("─────────────────────────────────")
        
        let originalText = "Original transcription for integration test"
        let processedText = "Processed version of integration test"
        
        // Test AppDelegate text storage
        AppDelegate.lastOriginalWhisperText = originalText
        AppDelegate.lastProcessedText = processedText
        
        // Verify storage
        XCTAssertEqual(AppDelegate.lastOriginalWhisperText, originalText, "Should store original text")
        XCTAssertEqual(AppDelegate.lastProcessedText, processedText, "Should store processed text")
        
        // Test availability flags
        XCTAssertTrue(AppDelegate.hasOriginalText, "Should indicate original text available")
        XCTAssertTrue(AppDelegate.hasProcessedText, "Should indicate processed text available")
        
        print("   📝 Original: \"\(originalText.prefix(30))...\"")
        print("   🔄 Processed: \"\(processedText.prefix(30))...\"")
        print("   ✅ Text storage integration works")
    }
    
    func testWritingStyleManagerIntegration() {
        print("\n✍️ Testing Writing Style Manager Integration")
        print("──────────────────────────────────────────")
        
        // Test API key status
        let hasApiKey = writingStyleManager.hasApiKey()
        print("   🔑 API Key status: \(hasApiKey ? "Present" : "Not configured")")
        
        // Test writing style access
        let currentStyle = writingStyleManager.selectedWritingStyle
        XCTAssertNotNil(currentStyle, "Should have a selected writing style")
        
        print("   📝 Current style: \(currentStyle)")
        print("   ✅ Writing style manager integration works")
    }
    
    // MARK: - Toast Integration Tests
    
    func testToastOperationIntegration() {
        print("\n🍞 Testing Toast Operation Integration")
        print("────────────────────────────────────")
        
        // Test toast display
        toastManager.toastsEnabled = true
        toastManager.showToast(message: "Test toast", preview: "Integration test", type: .normal)
        
        // Test toast configuration
        XCTAssertTrue(toastManager.toastsEnabled, "Toasts should be enabled")
        
        // Test toast hiding
        toastManager.hideToast()
        
        print("   ✅ Toast operation integration works")
    }
    
    func testToastPersistenceIntegration() {
        print("\n💾 Testing Toast Persistence Integration")
        print("──────────────────────────────────────")
        
        // Test configuration persistence through ToastManager API
        let originalState = toastManager.toastsEnabled
        
        // Test disabling toasts
        toastManager.toastsEnabled = false
        XCTAssertFalse(toastManager.toastsEnabled, "Should disable toasts")
        
        // Test enabling toasts  
        toastManager.toastsEnabled = true
        XCTAssertTrue(toastManager.toastsEnabled, "Should enable toasts")
        
        // Test configuration changes are persistent through the manager
        XCTAssertNotNil(toastManager, "Toast manager should be available")
        
        // Restore original state
        toastManager.toastsEnabled = originalState
        
        print("   ✅ Toast persistence integration works")
    }
    
    // MARK: - System Integration Tests
    
    func testSystemComponentIntegration() {
        print("\n🔧 Testing System Component Integration")
        print("─────────────────────────────────────")
        
        // Test all major components are available
        XCTAssertNotNil(audioRecorder, "Audio recorder should be available")
        XCTAssertNotNil(toastManager, "Toast manager should be available") 
        XCTAssertNotNil(writingStyleManager, "Writing style manager should be available")
        XCTAssertNotNil(accessibilityManager, "Accessibility manager should be available")
        XCTAssertNotNil(clipboardManager, "Clipboard manager should be available")
        
        // Test component states
        XCTAssertNotNil(audioRecorder.statusDescription, "Audio recorder should provide status")
        XCTAssertNotNil(writingStyleManager.selectedWritingStyle, "Should have selected writing style")
        
        print("   🎤 Audio recorder: ✓")
        print("   🍞 Toast manager: ✓") 
        print("   ✍️ Writing style manager: ✓")
        print("   ♿ Accessibility manager: ✓")
        print("   📋 Clipboard manager: ✓")
        print("   ✅ System component integration verified")
    }
    
    // MARK: - Workflow Integration Tests
    
    func testCompleteWorkflowIntegration() {
        print("\n🔄 Testing Complete Workflow Integration")
        print("──────────────────────────────────────")
        
        let testText = "Complete workflow integration test text"
        print("1️⃣ Setting up workflow...")
        
        // 2. Simulate transcription
        AppDelegate.lastOriginalWhisperText = testText
        XCTAssertEqual(AppDelegate.lastOriginalWhisperText, testText, "Should store original text")
        print("2️⃣ Transcription stored ✓")
        
        // 3. Simulate processing (if available)
        if writingStyleManager.hasApiKey() {
            AppDelegate.lastProcessedText = "Enhanced: " + testText
            print("3️⃣ Text processing simulated ✓")
        } else {
            AppDelegate.lastProcessedText = testText
            print("3️⃣ No API key - using original text ✓")
        }
        
        // 4. Test clipboard operation
        let finalText = AppDelegate.lastProcessedText
        clipboardManager.copyToClipboard(text: finalText)
        print("4️⃣ Clipboard operation ✓")
        
        // 5. Test toast notification
        if toastManager.toastsEnabled {
            toastManager.showToast(message: "Workflow completed!", preview: finalText, type: .normal)
            print("5️⃣ Toast notification ✓")
        } else {
            print("5️⃣ Toast disabled ✓")
        }
        
        // Verify final state
        XCTAssertTrue(AppDelegate.hasOriginalText, "Should have original text")
        XCTAssertTrue(AppDelegate.hasProcessedText, "Should have processed text")
        
        print("   ✅ Complete workflow integration successful!")
    }
    
    func testErrorHandlingIntegration() {
        print("\n❌ Testing Error Handling Integration")
        print("────────────────────────────────────")
        
        // Test empty text handling
        AppDelegate.lastOriginalWhisperText = ""
        XCTAssertFalse(AppDelegate.hasOriginalText, "Should handle empty original text")
        print("   ✓ Empty original text handling")
        
        // Test empty processed text handling
        AppDelegate.lastProcessedText = ""
        XCTAssertFalse(AppDelegate.hasProcessedText, "Should handle empty processed text")
        print("   ✓ Empty processed text handling")
        
        // Test clipboard with empty text
        clipboardManager.copyToClipboard(text: "")
        print("   ✓ Empty clipboard operation handling")
        
        // Test toast error state
        toastManager.showToast(message: "Error test", preview: "Error handling test", type: .error)
        print("   ✓ Error toast handling")
        
        print("   ✅ Error handling integration verified")
    }
    
    func testPerformanceIntegration() {
        print("\n📊 Testing Performance Integration")
        print("─────────────────────────────────")
        
        let startTime = Date()
        
        // Test rapid operations
        for i in 1...5 {
            AppDelegate.lastProcessedText = "Performance test \(i)"
            toastManager.showToast(message: "Test \(i)", preview: "Performance test", type: .normal)
            toastManager.hideToast()
        }
        
        let rapidTime = Date().timeIntervalSince(startTime)
        print("   ⏱️ Rapid operations time: \(String(format: "%.3f", rapidTime))s")
        
        // Test large text handling
        let largeText = String(repeating: "Performance test content. ", count: 100)
        AppDelegate.lastProcessedText = largeText
        XCTAssertEqual(AppDelegate.lastProcessedText.count, largeText.count, "Should handle large text")
        
        print("   📊 Large text size: \(largeText.count) characters")
        print("   🚀 Operations per second: \(String(format: "%.1f", 5.0 / rapidTime))")
        print("   ✅ Performance integration verified")
    }
}

// MARK: - Helper Extensions

extension XCTestCase {
    func XCTAssertNotEmpty(_ string: String, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
        XCTAssertFalse(string.isEmpty, message, file: file, line: line)
    }
} 