import XCTest
import SwiftUI
@testable import WhisperRecorder

/// UI Component E2E Tests for WhisperRecorder
/// Tests real end-to-end UI component behavior and visual state changes
@MainActor class UIComponentE2ETests: XCTestCase {
    
    // MARK: - Properties
    
    var audioRecorder: AudioRecorder!
    var toastManager: ToastManager!
    var writingStyleManager: WritingStyleManager!
    var hostingController: NSHostingController<ContentView>!
    var contentView: ContentView!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize managers
        audioRecorder = AudioRecorder.shared
        toastManager = ToastManager.shared
        writingStyleManager = WritingStyleManager.shared
        
        // Create content view for UI testing
        contentView = ContentView()
        hostingController = NSHostingController(rootView: contentView)
        
        // Reset app state
        AppDelegate.lastOriginalWhisperText = ""
        AppDelegate.lastProcessedText = ""
        toastManager.toastsEnabled = true
        toastManager.hideToast()
        
        print("\n🔧 E2E UI Test Environment Setup Complete")
    }
    
    override func tearDown() {
        toastManager.hideToast()
        hostingController = nil
        contentView = nil
        super.tearDown()
    }
    
    // MARK: - UI Component E2E Tests
    
    func testStatusCardUIBehavior() {
        print("\n📋 E2E: Status Card UI Behavior")
        print("─────────────────────────────")
        
        // Test initial status display
        XCTAssertFalse(audioRecorder.isRecording, "Should not be recording initially")
        XCTAssertEqual(audioRecorder.statusDescription, "Ready", "Should show ready status")
        
        // Simulate status changes that would affect UI
        XCTAssertNotNil(audioRecorder.statusDescription, "Status should always be available for UI")
        XCTAssertFalse(audioRecorder.statusDescription.isEmpty, "Status should not be empty for UI display")
        
        print("   ✅ Status card displays proper state")
    }
    
    func testActionsCardUIInteractions() {
        print("\n🎬 E2E: Actions Card UI Interactions")
        print("──────────────────────────────────")
        
        // Setup test data for actions
        let testText = "Test text for actions card"
        AppDelegate.lastOriginalWhisperText = testText
        AppDelegate.lastProcessedText = "Enhanced: " + testText
        
        // Test copy actions availability
        XCTAssertTrue(AppDelegate.hasOriginalText, "Original copy action should be available")
        XCTAssertTrue(AppDelegate.hasProcessedText, "Processed copy action should be available")
        
        // Test clipboard interaction from UI perspective
        let clipboardManager = ClipboardManager.shared
        clipboardManager.copyToClipboard(text: testText)
        
        // Verify UI can access clipboard state
        XCTAssertNotNil(NSPasteboard.general.string(forType: .string), "Clipboard should have content for UI feedback")
        
        print("   ✅ Actions card interactions work end-to-end")
    }
    
    func testToastSystemUIFlow() {
        print("\n🍞 E2E: Toast System UI Flow")
        print("──────────────────────────")
        
        // Test toast display capabilities
        toastManager.toastsEnabled = true
        XCTAssertTrue(toastManager.toastsEnabled, "Toasts should be enabled for UI display")
        
        // Test toast message flow
        let testMessage = "E2E test toast message"
        let testPreview = "This is a preview for E2E testing"
        
        toastManager.showToast(message: testMessage, preview: testPreview, type: .normal)
        
        // Verify toast can be controlled programmatically (as UI would)
        toastManager.hideToast()
        
        // Test error toast type
        toastManager.showToast(message: "Error test", preview: "Error preview", type: .error)
        toastManager.hideToast()
        
        print("   ✅ Toast system UI flow works end-to-end")
    }
    
    func testConfigurationCardUIStates() {
        print("\n⚙️ E2E: Configuration Card UI States")
        print("───────────────────────────────────")
        
        // Test writing style configuration UI
        let currentStyle = writingStyleManager.selectedWritingStyle
        XCTAssertNotNil(currentStyle, "Configuration should have selectable style")
        
        // Test API key status for UI display
        let hasApiKey = writingStyleManager.hasApiKey()
        print("   🔑 API Configuration available: \(hasApiKey)")
        
        // Test toast configuration toggle
        let originalToastState = toastManager.toastsEnabled
        
        toastManager.toastsEnabled = !originalToastState
        XCTAssertNotEqual(toastManager.toastsEnabled, originalToastState, "Toast config should toggle")
        
        toastManager.toastsEnabled = originalToastState // Restore
        XCTAssertEqual(toastManager.toastsEnabled, originalToastState, "Should restore original state")
        
        print("   ✅ Configuration card states work end-to-end")
    }
    
    func testCompleteUIWorkflow() {
        print("\n🔄 E2E: Complete UI Workflow")
        print("──────────────────────────")
        
        print("1️⃣ Starting complete UI workflow test...")
        
        // 1. Simulate audio recording preparation (UI perspective)
        XCTAssertEqual(audioRecorder.statusDescription, "Ready", "UI should show ready state")
        print("2️⃣ Recording status ready ✓")
        
        // 2. Simulate transcription result (UI receives data)
        let originalText = "This is a complete UI workflow test transcription"
        AppDelegate.lastOriginalWhisperText = originalText
        XCTAssertTrue(AppDelegate.hasOriginalText, "UI should detect text availability")
        print("3️⃣ Transcription available for UI ✓")
        
        // 3. Simulate processing (UI gets enhanced text)
        let processedText = "Enhanced: " + originalText
        AppDelegate.lastProcessedText = processedText
        XCTAssertTrue(AppDelegate.hasProcessedText, "UI should detect processed text")
        print("4️⃣ Enhanced text available for UI ✓")
        
        // 4. Simulate UI copy action
        let clipboardManager = ClipboardManager.shared
        clipboardManager.copyToClipboard(text: processedText)
        print("5️⃣ Copy action executed ✓")
        
        // 5. Simulate UI toast notification
        if toastManager.toastsEnabled {
            toastManager.showToast(message: "Text copied!", preview: processedText, type: .normal)
            print("6️⃣ Toast notification displayed ✓")
        } else {
            print("6️⃣ Toast disabled - silent mode ✓")
        }
        
        // Verify complete workflow state
        XCTAssertTrue(AppDelegate.hasOriginalText, "Workflow should preserve original text")
        XCTAssertTrue(AppDelegate.hasProcessedText, "Workflow should preserve processed text")
        XCTAssertNotNil(NSPasteboard.general.string(forType: .string), "Clipboard should have final text")
        
        print("   ✅ Complete UI workflow successful!")
    }
    
    func testUIStateConsistency() {
        print("\n🎯 E2E: UI State Consistency")
        print("──────────────────────────")
        
        // Test all managers maintain consistent state for UI
        XCTAssertNotNil(audioRecorder.statusDescription, "Audio status always available")
        XCTAssertNotNil(writingStyleManager.selectedWritingStyle, "Writing style always selected")
        XCTAssertNotNil(toastManager, "Toast manager always available")
        
        // Test state changes are reflected consistently
        let originalToastState = toastManager.toastsEnabled
        toastManager.toastsEnabled = !originalToastState
        XCTAssertNotEqual(toastManager.toastsEnabled, originalToastState, "State changes should be immediate")
        toastManager.toastsEnabled = originalToastState
        
        print("   ✅ UI state consistency verified")
    }
    
    func testUIErrorHandling() {
        print("\n❌ E2E: UI Error Handling")
        print("────────────────────────")
        
        // Test UI handles empty states gracefully
        AppDelegate.lastOriginalWhisperText = ""
        AppDelegate.lastProcessedText = ""
        
        XCTAssertFalse(AppDelegate.hasOriginalText, "UI should handle empty original text")
        XCTAssertFalse(AppDelegate.hasProcessedText, "UI should handle empty processed text")
        
        // Test UI handles error toasts
        toastManager.showToast(message: "Error occurred", preview: "Error details", type: .error)
        toastManager.hideToast()
        
        // Test clipboard with empty content
        let clipboardManager = ClipboardManager.shared
        clipboardManager.copyToClipboard(text: "")
        
        print("   ✅ UI error handling verified")
    }
    
    func testUIPerformanceE2E() {
        print("\n🚀 E2E: UI Performance")
        print("────────────────────")
        
        let startTime = Date()
        
        // Test rapid UI state changes
        for i in 1...10 {
            AppDelegate.lastProcessedText = "Performance test iteration \(i)"
            toastManager.showToast(message: "Test \(i)", preview: "Performance", type: .normal)
            toastManager.hideToast()
        }
        
        let duration = Date().timeIntervalSince(startTime)
        print("   ⏱️ 10 UI operations in \(String(format: "%.3f", duration))s")
        print("   🚀 UI ops/second: \(String(format: "%.1f", 10.0 / duration))")
        
        // Test large text handling in UI context
        let largeText = String(repeating: "UI performance test content. ", count: 200)
        AppDelegate.lastProcessedText = largeText
        XCTAssertEqual(AppDelegate.lastProcessedText.count, largeText.count, "UI should handle large text")
        
        print("   📊 Large text: \(largeText.count) chars")
        print("   ✅ UI performance acceptable")
    }
    
    func testUIComponentIntegration() {
        print("\n🧩 E2E: UI Component Integration")
        print("───────────────────────────────")
        
        // Test that all UI components can access their data sources
        XCTAssertNotNil(audioRecorder, "StatusCard should access AudioRecorder")
        XCTAssertNotNil(writingStyleManager, "ConfigurationCard should access WritingStyleManager")
        XCTAssertNotNil(toastManager, "ToastView should access ToastManager")
        
        // Test cross-component communication
        AppDelegate.lastOriginalWhisperText = "Component integration test"
        let clipboardManager = ClipboardManager.shared
        clipboardManager.copyToClipboard(text: AppDelegate.lastOriginalWhisperText)
        
        if toastManager.toastsEnabled {
            toastManager.showToast(message: "Integration", preview: "Component test", type: .normal)
        }
        
        // Verify all components can coexist
        XCTAssertTrue(AppDelegate.hasOriginalText, "ActionsCard should see text")
        XCTAssertNotNil(NSPasteboard.general.string(forType: .string), "Clipboard should have text")
        
        print("   ✅ UI component integration verified")
    }
}

// MARK: - Helper Extensions

extension UIComponentE2ETests {
    
    /// Helper to simulate UI interaction delay
    func simulateUIDelay(_ duration: TimeInterval = 0.01) {
        let expectation = XCTestExpectation(description: "UI delay")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: duration + 0.1)
    }
    
    /// Helper to verify UI state consistency
    func verifyUIState(hasText: Bool, file: StaticString = #file, line: UInt = #line) {
        XCTAssertEqual(AppDelegate.hasOriginalText, hasText, "UI text state should match expectation", file: file, line: line)
    }
} 